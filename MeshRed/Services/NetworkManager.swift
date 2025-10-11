//
//  NetworkManager.swift
//  MeshRed
//
//  Created by Emilio Contreras on 28/09/25.
//

import Foundation
import MultipeerConnectivity
import Combine
import NearbyInteraction
import SystemConfiguration
import Network

class NetworkManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var connectedPeers: [MCPeerID] = []
    @Published var availablePeers: [MCPeerID] = []
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var isAdvertising: Bool = false
    @Published var isBrowsing: Bool = false
    @Published var relayingMessage: Bool = false
    @Published var pendingAcksCount: Int = 0
    @Published var connectionQuality: ConnectionQuality = .unknown
    @Published var networkStats: (attempts: Int, blocked: Int, active: Int) = (0, 0, 0)
    @Published var hasNetworkConfigurationIssue: Bool = false
    @Published var networkConfigurationMessage: String = ""

    // MARK: - Core Components
    private let serviceType = "meshred-chat"
    internal let localPeerID: MCPeerID = {
        let deviceName = ProcessInfo.processInfo.hostName
        // Use public name from UserDisplayNameManager
        let displayNameManager = UserDisplayNameManager.shared
        let publicName = displayNameManager.getCurrentPublicName(deviceName: deviceName)
        print("📡 [NetworkManager] Creating MCPeerID with public name: '\(publicName)'")
        return MCPeerID(displayName: publicName)
    }()
    internal var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    // MARK: - Message Store
    let messageStore = MessageStore()

    // MARK: - Family Group Manager
    let familyGroupManager = FamilyGroupManager()

    // MARK: - LinkFence Manager
    var linkfenceManager: LinkFenceManager?

    // MARK: - Connection Manager
    let connectionManager = ConnectionManager()

    // MARK: - Routing Table
    private(set) var routingTable: RoutingTable!

    // MARK: - Advanced Components
    private let messageQueue = MessageQueue()
    private let messageCache = MessageCache()
    private let ackManager = AckManager()
    internal let sessionManager = SessionManager()
    let healthMonitor = PeerHealthMonitor()
    private let connectionMutex = ConnectionMutex()

    // MARK: - Location Components
    let locationService = LocationService()
    let locationRequestManager = LocationRequestManager()
    let peerLocationTracker = PeerLocationTracker()
    var uwbSessionManager: LinkFinderSessionManager?

    // GPS Location Sharing for Navigation
    private var locationSharingTimer: Timer?
    private var peersInNavigation: Set<String> = []
    private let locationSharingInterval: TimeInterval = 5.0  // Broadcast every 5 seconds

    private var processingTimer: Timer?
    private let processingQueue = DispatchQueue(label: "com.meshred.processing", qos: .userInitiated)
    private var lastBrowseTime = Date.distantPast
    private var lastAdvertiseTime = Date.distantPast
    private let throttleInterval: TimeInterval = 1.0

    // Event deduplication
    private var peerEventTimes: [String: (found: Date?, lost: Date?)] = [:]
    private let eventDeduplicationWindow: TimeInterval = 10.0  // Increased from 3.0

    // LinkFinder retry management
    private var uwbRetryCount: [String: Int] = [:]
    private let maxUWBRetries = 3

    // Network monitoring (added for continuous network state tracking)
    private var networkPathMonitor: NWPathMonitor?

    // Network configuration
    private let config = NetworkConfig.shared

    // MARK: - Peer Connection State Management
    /// Tracks the connection state of each peer for intelligent disconnection management
    enum PeerConnectionState {
        case active              // Normal connection, can send/receive messages
        case pendingDisconnect   // User requested disconnect, waiting for alternative peer
    }

    /// Dictionary tracking connection state for each peer (by displayName)
    /// Thread-safe access via processingQueue barriers
    private var peerConnectionStates: [String: PeerConnectionState] = [:]

    // MARK: - Connection Status Enum
    enum ConnectionStatus {
        case disconnected
        case connecting
        case connected
    }

    override init() {
        // EXTREME DIAGNOSTIC MODE: Use .none encryption to completely bypass TLS
        // This removes ALL encryption and certificate exchange to isolate the problem
        // If connections succeed with .none → TLS handshake is the root cause
        // If connections still fail → Network transport layer issue (WiFi/Bluetooth)
        // ⚠️⚠️⚠️ SECURITY WARNING: This disables ALL encryption - ONLY for testing
        self.session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .none)
        print("🔓🔓🔓 [EXTREME DIAGNOSTIC MODE] Using .none encryption - NO TLS HANDSHAKE")
        print("⚠️⚠️⚠️ Security COMPLETELY DISABLED - ONLY for root cause diagnosis")
        print("📊 If this works → TLS is the problem | If this fails → Network transport issue")
        super.init()

        // Initialize routing table
        self.routingTable = RoutingTable(localPeerID: localPeerID.displayName)

        // Initialize linkfence manager
        self.linkfenceManager = LinkFenceManager(
            locationService: locationService,
            familyGroupManager: familyGroupManager
        )
        self.linkfenceManager?.setNetworkManager(self)

        session.delegate = self
        ackManager.delegate = self
        healthMonitor.delegate = self

        // Initialize LinkFinder if supported
        if #available(iOS 14.0, *) {
            let uwbManager = LinkFinderSessionManager()
            uwbManager.delegate = self
            self.uwbSessionManager = uwbManager
        }

        startServices()
        startProcessingTimer()
        startStatsUpdateTimer()
        startHealthCheck()
        startWaitingCheckTimer()
        startTopologyBroadcastTimer()

        // Setup notification observers for settings actions
        setupNotificationObservers()

        // DEVELOPMENT: Clear any blocked peers to allow Simulator-Device connections
        #if DEBUG
        connectionManager.clearAllBlocksForDevelopment()
        #endif

        print("🚀 NetworkManager: Initialized with peer ID: \(localPeerID.displayName)")
    }

    deinit {
        stopServices()
        processingTimer?.invalidate()
        statsUpdateTimer?.invalidate()
        waitingCheckTimer?.invalidate()
        locationSharingTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    private var statsUpdateTimer: Timer?

    private func startStatsUpdateTimer() {
        statsUpdateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateNetworkStats()
        }
    }

    private func updateNetworkStats() {
        let stats = sessionManager.getConnectionStats()
        DispatchQueue.main.async {
            self.networkStats = stats
        }
    }

    // MARK: - Public Methods

    func startServices() {
        // Validate network configuration before starting
        validateNetworkConfiguration()

        startAdvertising()
        startBrowsing()
        print("🔄 NetworkManager: Started advertising and browsing services")
    }

    func stopServices() {
        stopAdvertising()
        stopBrowsing()
        session.disconnect()
        print("⏹️ NetworkManager: Stopped all services and disconnected session")
    }

    // MARK: - Network Configuration Validation

    private func validateNetworkConfiguration() {
        let pathMonitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.meshred.network-monitor")

        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            let hasWiFi = path.usesInterfaceType(.wifi)
            let hasCellular = path.usesInterfaceType(.cellular)
            let isExpensive = path.isExpensive
            let isConstrained = path.isConstrained

            // Check if WiFi is available but connection is not established
            let isWiFiEnabledButNotConnected = hasWiFi && path.status != .satisfied

            DispatchQueue.main.async {
                if isWiFiEnabledButNotConnected {
                    // WiFi is ON but not connected to any network
                    self.hasNetworkConfigurationIssue = true
                    self.networkConfigurationMessage = "WiFi habilitado sin red conectada. Para mejor conectividad: (1) Conecta a una red WiFi, O (2) Desactiva WiFi para usar solo Bluetooth."

                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    print("⚠️ CONFIGURACIÓN DE RED PROBLEMÁTICA DETECTADA")
                    print("   WiFi: Habilitado pero NO conectado")
                    print("   Bluetooth: Probablemente habilitado")
                    print("   ")
                    print("   PROBLEMA:")
                    print("   MultipeerConnectivity intentará usar WiFi Direct/TCP")
                    print("   que fallará con timeout (Error Code 60)")
                    print("   ")
                    print("   SOLUCIÓN:")
                    print("   1. Conecta a una red WiFi, O")
                    print("   2. Desactiva WiFi completamente (Settings → WiFi → OFF)")
                    print("   ")
                    print("   Esto forzará el uso de Bluetooth puro que SÍ funciona.")
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                } else if !hasWiFi && path.status == .satisfied {
                    // Good: Bluetooth-only mode or cellular
                    self.hasNetworkConfigurationIssue = false
                    self.networkConfigurationMessage = ""
                    print("✅ Configuración de red: Bluetooth puro (WiFi desactivado) - Óptimo")
                } else if hasWiFi && path.status == .satisfied {
                    // Good: WiFi connected
                    self.hasNetworkConfigurationIssue = false
                    self.networkConfigurationMessage = ""
                    print("✅ Configuración de red: WiFi conectado + Bluetooth - Óptimo")
                }

                // Additional diagnostics
                print("📡 Estado de red:")
                print("   Path status: \(path.status)")
                print("   WiFi available: \(hasWiFi)")
                print("   Cellular available: \(hasCellular)")
                print("   Expensive: \(isExpensive)")
                print("   Constrained: \(isConstrained)")
            }

            // FIX: Keep monitor alive to detect network changes during runtime
            // Previously we cancelled after first check, missing network transitions
            // pathMonitor.cancel()  // ← REMOVED: Monitor stays active
        }

        pathMonitor.start(queue: queue)

        // Store monitor to keep it alive for continuous monitoring
        // This allows detecting WiFi connect/disconnect during app runtime
        self.networkPathMonitor = pathMonitor
        print("🔍 Network monitor started - will continuously monitor for changes")
    }

    // MARK: - Settings Actions

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClearAllConnections),
            name: NSNotification.Name("ClearAllConnections"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRestartNetworkServices),
            name: NSNotification.Name("RestartNetworkServices"),
            object: nil
        )
    }

    @objc private func handleClearAllConnections() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🧹 NetworkManager: Clearing all connections")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Disconnect all peers
        session.disconnect()

        // Clear all state
        DispatchQueue.main.async {
            self.connectedPeers.removeAll()
            self.availablePeers.removeAll()
        }

        // Clear routing table (individual routes, not the table itself)
        for peer in connectedPeers {
            routingTable.removePeer(peer.displayName)
        }

        // Clear LinkFinder sessions
        if #available(iOS 14.0, *) {
            uwbSessionManager?.stopAllSessions()
        }

        // Clear pending messages
        messageQueue.clear()

        // Clear location tracking
        peerLocationTracker.clearAllLocations()

        // Stop and restart services
        stopServices()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.startServices()
        }

        print("✅ NetworkManager: All connections cleared and services restarted")
    }

    @objc private func handleRestartNetworkServices() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔄 NetworkManager: Restarting network services")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Stop services
        stopAdvertising()
        stopBrowsing()

        // Wait a moment then restart
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startAdvertising()
            self?.startBrowsing()
            print("✅ NetworkManager: Services restarted successfully")
        }
    }

    // MARK: - Recovery and Error Handling

    private var serviceRestartTimer: Timer?
    private var lastServiceRestart = Date.distantPast
    private var consecutiveFailures = 0
    private var failedConnectionAttempts: [String: Int] = [:]  // Track failed attempts per peer
    private var lastPeerDiscoveryTime = Date()  // Track when we last discovered a peer
    private var waitingForInvitationFrom: [String: Date] = [:]  // Track when we started waiting for invitation
    private var waitingCheckTimer: Timer?  // Timer to check for stuck waiting states

    func restartServicesIfNeeded() {
        let now = Date()
        // Increase minimum interval between restarts to 15 seconds to prevent disruptions
        let minimumRestartInterval = 15.0
        guard now.timeIntervalSince(lastServiceRestart) >= minimumRestartInterval else {
            let timeRemaining = minimumRestartInterval - now.timeIntervalSince(lastServiceRestart)
            print("⚠️ Skipping service restart - too soon (wait \(Int(timeRemaining))s)")
            return
        }

        lastServiceRestart = now

        print("🔧 NetworkManager: Restarting services to recover from errors...")

        // Stop everything cleanly
        stopServices()

        // Clear stale state and reset failure counters
        DispatchQueue.main.async { [weak self] in
            self?.availablePeers.removeAll()
            self?.connectionMutex.releaseAllLocks()
            self?.failedConnectionAttempts.removeAll()  // Reset failure tracking
            self?.waitingForInvitationFrom.removeAll()  // Clear waiting status
        }

        // Create a new session to clear any DTLS/SSL errors
        // EXTREME DIAGNOSTIC: Using .none to completely bypass TLS
        self.session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .none)
        print("🔓🔓🔓 [RESTART-DIAGNOSTIC] Using .none encryption - NO TLS HANDSHAKE")
        self.session.delegate = self

        // Restart almost immediately for faster recovery
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startServices()
            self?.consecutiveFailures = 0
            print("✅ Services restarted successfully with fresh session")
        }
    }

    private func handleConnectionFailure(with peerID: MCPeerID) {
        consecutiveFailures += 1

        // Track failures per peer
        let peerKey = peerID.displayName
        failedConnectionAttempts[peerKey] = (failedConnectionAttempts[peerKey] ?? 0) + 1

        print("⚠️ Connection failure #\(failedConnectionAttempts[peerKey] ?? 1) for \(peerKey)")

        if consecutiveFailures >= 5 {
            print("⚠️ Multiple connection failures detected (5+). Initiating recovery...")
            restartServicesIfNeeded()
            failedConnectionAttempts.removeAll()  // Reset after restart
        } else {
            // Try to reconnect after a delay using exponential backoff
            // Backoff: 2s, 4s, 8s, 16s (capped at 16s)
            let baseDelay: TimeInterval = 2.0
            let exponentialDelay = baseDelay * pow(2.0, Double(min(consecutiveFailures - 1, 3)))
            let delay = min(exponentialDelay, 16.0)

            print("⏳ Will retry connection to \(peerKey) in \(Int(delay))s (attempt #\(failedConnectionAttempts[peerKey] ?? 1))")

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }

                if self.availablePeers.contains(peerID) &&
                   !self.connectedPeers.contains(peerID) &&
                   self.sessionManager.shouldAttemptConnection(to: peerID) {
                    print("🔄 Retrying connection to \(peerID.displayName) after failure")
                    self.connectToPeer(peerID)  // Use proper connection method with SessionManager tracking
                }
            }
        }
    }

    private func startHealthCheck() {
        // Check network health every 30 seconds to avoid interfering with connections
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            let now = Date()

            // Send health pings to all connected peers
            for peer in self.connectedPeers {
                if let pingData = self.healthMonitor.createPingData(for: peer) {
                    do {
                        try self.safeSend(pingData, toPeers: [peer], with: .reliable, context: "healthPing")
                    } catch {
                        print("❌ Failed to send ping to \(peer.displayName): \(error.localizedDescription)")
                    }
                }
            }

            // Check if we've been disconnected
            if self.connectedPeers.isEmpty {
                if self.availablePeers.isEmpty {
                    // No peers at all - wait longer before restarting (20 seconds)
                    if now.timeIntervalSince(self.lastServiceRestart) > 20.0 {
                        print("⚠️ No peers found for 20 seconds. Auto-restarting...")
                        self.restartServicesIfNeeded()
                    }
                } else {
                    // Have available peers but can't connect - wait much longer before restarting
                    self.consecutiveFailures += 1
                    if self.consecutiveFailures >= 6 {  // Restart after 6 failures (3 minutes with 30s timer)
                        print("⚠️ Multiple connection failures. Auto-restarting...")
                        self.restartServicesIfNeeded()
                    }
                }
            } else {
                // We have connections - reset failure counter
                self.consecutiveFailures = 0
            }

            // Force restart if we haven't seen any peers for a longer period
            if self.connectedPeers.isEmpty && self.availablePeers.isEmpty {
                if now.timeIntervalSince(self.lastPeerDiscoveryTime) > 30.0 {
                    print("🔄 No peers in 30s. Force restarting...")
                    self.restartServicesIfNeeded()
                }
            }
        }
    }

    private func startWaitingCheckTimer() {
        waitingCheckTimer?.invalidate()
        waitingCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.checkStuckWaitingStates()
        }
    }

    private func checkStuckWaitingStates() {
        let now = Date()
        var stuckPeers: [String] = []

        // Check for peers we've been waiting on too long
        for (peerKey, waitStartTime) in waitingForInvitationFrom {
            let waitDuration = now.timeIntervalSince(waitStartTime)

            // Progressive timeout: 5s, 6s, 7s... (reduced for faster recovery)
            let failureCount = failedConnectionAttempts[peerKey] ?? 0
            let baseTimeout = 5.0  // Reduced from 15s for faster detection
            let timeoutThreshold = baseTimeout + (Double(min(failureCount, 3)) * 1.0)

            // Cap maximum wait time at 10 seconds (sockets timeout at ~10s)
            let effectiveThreshold = min(timeoutThreshold, 10.0)

            if waitDuration > effectiveThreshold {
                stuckPeers.append(peerKey)
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("⚠️ STUCK WAITING DETECTED")
                print("   Peer: \(peerKey)")
                print("   Waiting Duration: \(Int(waitDuration))s")
                print("   Threshold: \(Int(effectiveThreshold))s")
                print("   Previous Failures: \(failureCount)")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            }
        }

        // Force reconnect to stuck peers
        for peerKey in stuckPeers {
            // Check if already connected (don't force reconnect if connected)
            if connectedPeers.contains(where: { $0.displayName == peerKey }) {
                print("✓ Peer \(peerKey) already connected - cleaning up stuck waiting state")
                waitingForInvitationFrom.removeValue(forKey: peerKey)
                continue
            }

            waitingForInvitationFrom.removeValue(forKey: peerKey)

            // Find the peer and force connect
            if let peer = availablePeers.first(where: { $0.displayName == peerKey }) {
                print("🔄 FORCE RECONNECT: Overriding conflict resolution for \(peerKey)")

                // Log conflict resolution status for debugging
                let wouldNormallyInitiate = ConnectionConflictResolver.shouldInitiateConnection(localPeer: localPeerID, remotePeer: peer)
                print("   Normal conflict resolution: \(wouldNormallyInitiate ? "WOULD INITIATE" : "WOULD WAIT")")
                print("   Now forcing connection regardless")

                // Clear any session manager blocks
                sessionManager.clearCooldown(for: peer)

                // Increment failure count (for progressive timeout)
                let currentFailures = failedConnectionAttempts[peerKey] ?? 0
                failedConnectionAttempts[peerKey] = currentFailures + 1

                // Force immediate connection, bypassing conflict resolution
                connectToPeer(peer, forceIgnoreConflictResolution: true)
            } else {
                print("⚠️ Cannot force reconnect to \(peerKey) - peer not available")
                // Clean up stale waiting entry
                waitingForInvitationFrom.removeValue(forKey: peerKey)
            }
        }

        // Clean up stale entries for peers that are no longer available
        let availablePeerNames = Set(availablePeers.map { $0.displayName })
        waitingForInvitationFrom = waitingForInvitationFrom.filter { key, _ in
            availablePeerNames.contains(key)
        }
    }

    /// Force reset all connection state for a peer and attempt fresh connection
    /// Use this in recovery scenarios when a peer is stuck
    private func forceResetPeerConnection(_ peerID: MCPeerID) {
        let peerKey = peerID.displayName

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔄 FORCE RESET: Clearing all state for \(peerKey)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // 1. Cancel any pending connection operations
        session.cancelConnectPeer(peerID)
        print("   ✓ Cancelled pending connections")

        // 2. Force release mutex lock
        connectionMutex.forceRelease(for: peerID)
        print("   ✓ Released mutex lock")

        // 3. Clear waiting state
        waitingForInvitationFrom.removeValue(forKey: peerKey)
        print("   ✓ Cleared waiting state")

        // 4. Clear session manager cooldown
        sessionManager.clearCooldown(for: peerID)
        print("   ✓ Cleared session cooldown")

        // 5. Reset failure counts
        failedConnectionAttempts.removeValue(forKey: peerKey)
        print("   ✓ Reset failure count")

        // 6. Attempt fresh connection if peer is still available
        if availablePeers.contains(where: { $0.displayName == peerKey }) {
            print("   🔄 Peer still available, attempting fresh connection...")

            // Wait briefly for MultipeerConnectivity to clean up internal state
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                print("   📤 Initiating fresh connection to \(peerKey)")
                self.connectToPeer(peerID, forceIgnoreConflictResolution: true)
            }
        } else {
            print("   ⚠️ Peer no longer available, reset complete")
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    func sendMessage(_ content: String, type: MessageType = .chat, recipientId: String = "broadcast", requiresAck: Bool = false) {
        let networkMessage = NetworkMessage(
            senderId: localPeerID.displayName,
            recipientId: recipientId,
            content: content,
            messageType: type,
            requiresAck: requiresAck
        )

        messageQueue.enqueue(networkMessage)

        if requiresAck {
            ackManager.trackMessage(networkMessage)
        }

        let isBroadcast = recipientId == "broadcast"
        let conversationDescriptor: MessageStore.ConversationDescriptor

        if isBroadcast {
            // Broadcast messages go to public chat
            conversationDescriptor = .publicChat()
        } else {
            // Private message - determine if family or direct conversation
            let displayName = familyGroupManager.getMember(withPeerID: recipientId)?.displayName ?? recipientId
            let isFamilyMember = familyGroupManager.isFamilyMember(peerID: recipientId)
            let wasEverFamilyMember = familyGroupManager.wasEverFamilyMember(peerID: recipientId)

            if isFamilyMember || wasEverFamilyMember {
                // Family member conversation (current or historical)
                conversationDescriptor = .familyChat(peerId: recipientId, displayName: displayName)
            } else {
                // Direct (non-family) conversation
                conversationDescriptor = .directChat(peerId: recipientId, displayName: displayName)
            }
        }

        let message = Message(
            sender: localPeerID.displayName,
            content: content,
            recipientId: isBroadcast ? nil : recipientId,
            conversationId: conversationDescriptor.id,
            conversationName: conversationDescriptor.title
        )
        messageStore.addMessage(message, context: conversationDescriptor, localDeviceName: self.localDeviceName)

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📤 SENDING NEW MESSAGE")
        print("   From: \(localPeerID.displayName)")
        print("   To: \(recipientId)")
        print("   Content: \"\(content)\"")
        print("   Type: \(type.displayName)")
        print("   Priority: \(networkMessage.priority)")
        print("   Requires ACK: \(requiresAck)")
        print("   Conversation Type: \(conversationDescriptor.conversationType)")
        print("   Conversation ID: \(conversationDescriptor.id)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    // MARK: - Safe Send Helper

    /// Safely send data to peers by validating against actual session state
    /// This prevents "Peers not connected" errors caused by race conditions
    /// between local connectedPeers array and session.connectedPeers
    private func safeSend(
        _ data: Data,
        toPeers peers: [MCPeerID],
        with mode: MCSessionSendDataMode,
        context: String = ""
    ) throws {
        // Validate peers against actual session state
        let sessionPeers = session.connectedPeers
        let validPeers = peers.filter { sessionPeers.contains($0) }

        guard !validPeers.isEmpty else {
            let contextStr = context.isEmpty ? "" : " (\(context))"
            print("⚠️ safeSend\(contextStr): No valid peers in session")
            print("   Requested: \(peers.map { $0.displayName })")
            print("   Session has: \(sessionPeers.map { $0.displayName })")
            throw NSError(
                domain: "NetworkManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Peers (\(peers.map { $0.displayName })) not connected"]
            )
        }

        // Log if we filtered out some peers
        if validPeers.count < peers.count {
            let filtered = peers.filter { !validPeers.contains($0) }
            print("⚠️ safeSend: Filtered out \(filtered.count) disconnected peers: \(filtered.map { $0.displayName })")
        }

        // Send to validated peers only
        try session.send(data, toPeers: validPeers, with: mode)
    }

    // MARK: - Transport Diagnostics

    /// Track connection success/failure for transport layer diagnostics
    private var connectionMetrics: [String: ConnectionMetrics] = [:]

    private struct ConnectionMetrics {
        var successfulSends: Int = 0
        var failedSends: Int = 0
        var lastSocketTimeout: Date?
        var connectionEstablished: Date?
        var lastDisconnect: Date?
        var disconnectCount: Int = 0

        var connectionDuration: TimeInterval? {
            guard let established = connectionEstablished else { return nil }
            return Date().timeIntervalSince(established)
        }

        var isUnstable: Bool {
            // Connection is unstable if:
            // 1. Disconnects within 30 seconds of connection
            // 2. More than 3 disconnects
            // 3. High failure rate in sends
            if let established = connectionEstablished,
               let lastDisconnect = lastDisconnect,
               lastDisconnect.timeIntervalSince(established) < 30 {
                return true
            }
            if disconnectCount > 3 {
                return true
            }
            if failedSends > 0 && successfulSends > 0 {
                let failureRate = Double(failedSends) / Double(successfulSends + failedSends)
                return failureRate > 0.3  // More than 30% failure rate
            }
            return false
        }
    }

    /// Log connection metrics for diagnostics
    private func recordConnectionMetrics(peer: MCPeerID, event: ConnectionMetricEvent) {
        let peerKey = peer.displayName

        if connectionMetrics[peerKey] == nil {
            connectionMetrics[peerKey] = ConnectionMetrics()
        }

        switch event {
        case .sendSuccess:
            connectionMetrics[peerKey]?.successfulSends += 1
        case .sendFailure:
            connectionMetrics[peerKey]?.failedSends += 1
        case .socketTimeout:
            connectionMetrics[peerKey]?.lastSocketTimeout = Date()
            connectionMetrics[peerKey]?.disconnectCount += 1
            logTransportDiagnostics(for: peer)
        case .connected:
            connectionMetrics[peerKey]?.connectionEstablished = Date()
        case .disconnected:
            connectionMetrics[peerKey]?.lastDisconnect = Date()
            connectionMetrics[peerKey]?.disconnectCount += 1
        }

        // Log if connection is unstable
        if let metrics = connectionMetrics[peerKey], metrics.isUnstable {
            print("⚠️ UNSTABLE CONNECTION DETECTED: \(peer.displayName)")
            logTransportDiagnostics(for: peer)
        }
    }

    enum ConnectionMetricEvent {
        case sendSuccess
        case sendFailure
        case socketTimeout
        case connected
        case disconnected
    }

    /// Log detailed transport layer diagnostics when issues are detected
    private func logTransportDiagnostics(for peer: MCPeerID) {
        let peerKey = peer.displayName
        guard let metrics = connectionMetrics[peerKey] else { return }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📊 TRANSPORT LAYER DIAGNOSTICS")
        print("   Peer: \(peer.displayName)")
        print("   Successful sends: \(metrics.successfulSends)")
        print("   Failed sends: \(metrics.failedSends)")
        print("   Disconnect count: \(metrics.disconnectCount)")
        if let duration = metrics.connectionDuration {
            print("   Connection duration: \(String(format: "%.1f", duration))s")
        }
        if let lastTimeout = metrics.lastSocketTimeout {
            print("   Last socket timeout: \(lastTimeout)")
        }
        print("   Is unstable: \(metrics.isUnstable)")
        print("   ")
        print("🔍 PROBABLE CAUSES:")
        print("   ")

        // Diagnose based on metrics
        if let established = metrics.connectionEstablished,
           let lastDisconnect = metrics.lastDisconnect,
           lastDisconnect.timeIntervalSince(established) < 15 {
            print("   ❌ VERY SHORT CONNECTION (<15s)")
            print("      → WiFi Direct transport likely failing")
            print("      → TCP socket timing out after handshake")
            print("      → Data channel establishment failing")
        }

        if metrics.lastSocketTimeout != nil {
            print("   ❌ SOCKET TIMEOUT DETECTED")
            print("      → TCP connection established but data transfer failed")
            print("      → Network path switched mid-connection")
            print("      → WiFi Direct → Bluetooth fallback not working")
        }

        if metrics.disconnectCount > 3 {
            print("   ❌ MULTIPLE DISCONNECTS (\(metrics.disconnectCount))")
            print("      → Connection establishment works")
            print("      → But transport layer is unstable")
            print("      → Likely WiFi interference or weak Bluetooth")
        }

        print("   ")
        print("💡 RECOMMENDED ACTIONS:")
        if hasNetworkConfigurationIssue {
            print("   1. ⚠️ Fix WiFi configuration (connect to network or disable)")
        } else {
            print("   1. Try disabling WiFi to force Bluetooth-only mode")
            print("   2. Move devices closer together (< 10m)")
            print("   3. Check for WiFi/Bluetooth interference")
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    private func sendNetworkMessage(_ message: NetworkMessage) {
        guard !connectedPeers.isEmpty else {
            print("⚠️ NetworkManager: No connected peers to send message to")
            return
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📤 SENDING NETWORK MESSAGE")
        print("   Message ID: \(message.id.uuidString.prefix(8))")
        print("   From: \(message.senderId)")
        print("   To: \(message.recipientId)")
        print("   Type: \(message.messageType.displayName)")
        print("   Hop Count: \(message.hopCount)/\(message.ttl)")
        print("   Route Path: \(message.routePath.joined(separator: " → "))")
        print("   Connected Peers: \(connectedPeers.map { $0.displayName })")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        var targetPeers: [MCPeerID]

        // INTELLIGENT ROUTING: Use routing table for directed messages
        if message.recipientId != "broadcast" {
            // Check if recipient is directly connected
            if let directPeer = connectedPeers.first(where: { $0.displayName == message.recipientId }) {
                targetPeers = [directPeer]
                print("🎯 Direct connection to recipient")
            } else if let nextHopNames = routingTable.getNextHops(to: message.recipientId) {
                // Recipient is reachable indirectly - send only to next hops
                targetPeers = connectedPeers.filter { nextHopNames.contains($0.displayName) }
                print("🗺️ Using routing table - next hops: [\(nextHopNames.joined(separator: ", "))]")
            } else {
                // Recipient not reachable - fallback to broadcast
                targetPeers = connectedPeers
                print("⚠️ Recipient not in routing table - broadcasting to all peers")
            }
        } else {
            // Broadcast message
            targetPeers = connectedPeers
            print("📢 Broadcasting to all peers")
        }

        // INTELLIGENT DISCONNECTION: Filter out peers marked as pendingDisconnect
        // These peers should not receive or relay messages
        var blockedPeers: [String] = []
        processingQueue.sync {
            blockedPeers = peerConnectionStates.filter { $0.value == .pendingDisconnect }.map { $0.key }
        }

        if !blockedPeers.isEmpty {
            let originalCount = targetPeers.count
            targetPeers = targetPeers.filter { !blockedPeers.contains($0.displayName) }
            let filteredCount = originalCount - targetPeers.count

            if filteredCount > 0 {
                print("🚫 Filtered \(filteredCount) peer(s) in pendingDisconnect state:")
                print("   Blocked: [\(blockedPeers.joined(separator: ", "))]")
            }
        }

        // Testing multi-hop: Filter out blocked connections
        if TestingConfig.forceMultiHop && message.recipientId != "broadcast" {
            targetPeers = targetPeers.filter { peer in
                !TestingConfig.shouldBlockDirectConnection(
                    from: localPeerID.displayName,
                    to: peer.displayName
                )
            }
            if targetPeers.count < connectedPeers.count {
                print("🧪 TEST MODE: Forcing multi-hop by limiting direct connections")
                print("🧪 Allowed peers: \(targetPeers.map { $0.displayName })")
            }
        }

        let payload = NetworkPayload.message(message)

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(payload)
            try safeSend(data, toPeers: targetPeers, with: .reliable, context: "sendNetworkMessage")
            print("📤 Sent to \(targetPeers.count) peers - Type: \(message.messageType.displayName)")
        } catch {
            print("❌ Failed to send message: \(error.localizedDescription)")
        }
    }

    private func sendAck(for originalMessageId: UUID, to senderId: String) {
        let ackMessage = AckMessage(originalMessageId: originalMessageId, ackSenderId: localPeerID.displayName)
        let payload = NetworkPayload.ack(ackMessage)

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(payload)

            let targetPeer = connectedPeers.first { $0.displayName == senderId }
            let peers = targetPeer != nil ? [targetPeer!] : connectedPeers

            try safeSend(data, toPeers: peers, with: .reliable, context: "sendAck")
            print("📬 ACK sent for message \(originalMessageId) to \(senderId)")
        } catch {
            print("❌ Failed to send ACK: \(error.localizedDescription)")
        }
    }

    /// Send raw data to a specific peer (for keep-alive pings, etc.)
    /// This is a low-level helper used by KeepAliveManager and other background services
    func sendRawData(_ data: Data, to peer: MCPeerID, reliable: Bool = false) {
        do {
            let mode: MCSessionSendDataMode = reliable ? .reliable : .unreliable
            try safeSend(data, toPeers: [peer], with: mode, context: "sendRawData")
        } catch {
            print("❌ Failed to send raw data to \(peer.displayName): \(error.localizedDescription)")
        }
    }

    func connectToPeer(_ peerID: MCPeerID, forceIgnoreConflictResolution: Bool = false) {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔗 CONNECT TO PEER - STEP 1: Entry")
        print("   Peer: \(peerID.displayName)")
        print("   Force: \(forceIgnoreConflictResolution)")
        print("   Timestamp: \(Date())")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        guard let browser = browser else {
            print("❌ CONNECT FAILED: Browser not available")
            return
        }
        print("   ✓ Browser available")

        // Check if peer is manually blocked
        print("   Step 2: Checking manual blocking...")
        if connectionManager.isPeerBlocked(peerID.displayName) {
            print("🚫 CONNECT ABORTED: Peer \(peerID.displayName) is manually blocked")
            return
        }
        print("   ✓ Not manually blocked")

        // Check conflict resolution (unless forcing)
        print("   Step 3: Checking conflict resolution...")
        if !forceIgnoreConflictResolution {
            let shouldInitiate = ConnectionConflictResolver.shouldInitiateConnection(localPeer: localPeerID, remotePeer: peerID)
            print("      Should initiate: \(shouldInitiate)")
            print("      Local ID: \(localPeerID.displayName)")
            print("      Remote ID: \(peerID.displayName)")
            guard shouldInitiate else {
                print("🆔 CONNECT ABORTED: Conflict resolution says we should defer to \(peerID.displayName)")
                return
            }
        } else {
            print("⚡ FORCING connection - bypassing conflict resolution")
        }
        print("   ✓ Conflict resolution passed")

        // Acquire mutex lock to serialize invites
        print("   Step 4: Acquiring ConnectionMutex lock...")
        guard connectionMutex.tryAcquireLock(for: peerID, operation: .browserInvite) else {
            print("🔒 CONNECT ABORTED: Connection operation already in progress for \(peerID.displayName)")
            return
        }
        print("   ✓ Mutex lock acquired")

        var lockReleased = false
        let releaseLock: () -> Void = { [weak self] in
            guard let self = self, !lockReleased else { return }
            lockReleased = true
            self.connectionMutex.releaseLock(for: peerID)
            print("   🔓 Mutex lock released for \(peerID.displayName)")
        }

        print("   Step 5: Checking SessionManager...")
        let sessionManagerAllows = sessionManager.shouldAttemptConnection(to: peerID)
        print("      SessionManager allows: \(sessionManagerAllows)")
        guard sessionManagerAllows else {
            print("⏸️ CONNECT ABORTED: SessionManager blocking connection to \(peerID.displayName)")
            releaseLock()
            return
        }
        print("   ✓ SessionManager allows")

        print("   Step 6: Recording connection attempt...")
        sessionManager.recordConnectionAttempt(to: peerID)
        print("   ✓ Attempt recorded")

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📤 BROWSER.INVITEPEER() - STEP 7: Calling iOS API")
        print("   Peer: \(peerID.displayName)")
        print("   Timeout: \(SessionManager.connectionTimeout)s")
        print("   Timestamp: \(Date())")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        browser.invitePeer(peerID, to: session, withContext: nil, timeout: SessionManager.connectionTimeout)

        print("   ✓ invitePeer() called")
        print("   Waiting for remote peer to accept invitation...")
        print("   If accepted, session(_:peer:didChange: .connecting) will be called")

        // Watchdog: if the session never transitions, clear the lock to avoid deadlocks
        let handshakeTimeout = SessionManager.connectionTimeout + 4.0
        print("   ⏰ Watchdog timer set for \(handshakeTimeout)s")

        DispatchQueue.main.asyncAfter(deadline: .now() + handshakeTimeout) { [weak self] in
            guard let self = self else { return }
            if self.connectionMutex.hasActiveOperation(for: peerID) {
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("⏳ WATCHDOG TIMEOUT")
                print("   Peer: \(peerID.displayName)")
                print("   Timeout: \(handshakeTimeout)s elapsed")
                print("   Action: Releasing mutex lock")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                releaseLock()
            } else {
                print("   ✓ Watchdog: Lock already released normally")
            }
        }
    }

    /// Intelligent disconnection system with two cases:
    /// Case A: Alternative peers available → Disconnect immediately
    /// Case B: No alternatives → Mark as pending, disconnect when new peer arrives
    func requestDisconnect(from peerID: MCPeerID) {
        let peerKey = peerID.displayName

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔌 DISCONNECT REQUEST")
        print("   Peer: \(peerKey)")
        print("   Current connected peers: \(connectedPeers.count)")
        print("   Current available peers: \(availablePeers.count)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Check if there are alternative peers available
        let hasAlternatives = !availablePeers.isEmpty || connectedPeers.count > 1

        if hasAlternatives {
            // CASE A: Alternative peers available → Disconnect immediately
            print("✅ CASE A: Alternative peers available")
            print("   Disconnecting immediately from \(peerKey)")

            // Mark as pendingDisconnect temporarily (will be removed after actual disconnect)
            processingQueue.async(flags: .barrier) { [weak self] in
                self?.peerConnectionStates[peerKey] = .pendingDisconnect
            }

            // Perform actual disconnection
            session.cancelConnectPeer(peerID)

            // Clean up all state for this peer
            cleanupPeerState(peerID)

            print("✅ Immediate disconnection completed for \(peerKey)")

        } else {
            // CASE B: No alternatives → Mark as pending, wait for new peer
            print("⚠️ CASE B: No alternative peers available")
            print("   Marking \(peerKey) as pendingDisconnect")
            print("   Will disconnect automatically when new peer connects")

            // Mark peer as pending disconnect
            processingQueue.async(flags: .barrier) { [weak self] in
                self?.peerConnectionStates[peerKey] = .pendingDisconnect
            }

            // Force UI update to show pending state
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
            }

            print("⏳ Peer \(peerKey) marked as pendingDisconnect - waiting for alternatives")
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    /// Helper function to get the connection state of a peer
    func getPeerConnectionState(_ peerID: MCPeerID) -> PeerConnectionState {
        var state: PeerConnectionState = .active
        processingQueue.sync {
            state = peerConnectionStates[peerID.displayName] ?? .active
        }
        return state
    }

    /// Helper function to check if a peer is in pending disconnect state
    func isPeerPendingDisconnect(_ peerID: MCPeerID) -> Bool {
        return getPeerConnectionState(peerID) == .pendingDisconnect
    }

    /// Clean up all state associated with a peer
    private func cleanupPeerState(_ peerID: MCPeerID) {
        let peerKey = peerID.displayName

        print("🧹 Cleaning up state for peer: \(peerKey)")

        // Remove from connection state tracking
        processingQueue.async(flags: .barrier) { [weak self] in
            self?.peerConnectionStates.removeValue(forKey: peerKey)
        }

        // Release mutex lock
        connectionMutex.releaseLock(for: peerID)

        // Remove from routing table
        routingTable.removePeer(peerKey)

        // Stop health monitoring
        healthMonitor.removePeer(peerID)

        // Clear location tracking
        peerLocationTracker.removePeerLocation(peerID: peerKey)

        // Clear any received location responses for this peer
        DispatchQueue.main.async { [weak self] in
            self?.locationRequestManager.receivedResponses.removeValue(forKey: peerKey)
        }

        // Stop LinkFinder session if active
        if #available(iOS 14.0, *) {
            uwbSessionManager?.stopSession(with: peerID)
        }

        // Record disconnection in session manager
        sessionManager.recordDisconnection(from: peerID)

        // Remove from connected peers list
        DispatchQueue.main.async { [weak self] in
            self?.connectedPeers.removeAll { $0.displayName == peerKey }
        }

        print("✅ Cleanup completed for \(peerKey)")
    }

    @available(*, deprecated, renamed: "requestDisconnect", message: "Use requestDisconnect for intelligent disconnection management")
    func disconnectFromPeer(_ peerID: MCPeerID) {
        // Legacy method - redirect to new implementation
        requestDisconnect(from: peerID)
    }

    // MARK: - Intelligent Reconnection

    private func shouldAutoReconnect(to peerID: MCPeerID) -> Bool {
        // Don't auto-reconnect if we're in a disconnection cooldown
        guard sessionManager.shouldAttemptConnection(to: peerID) else {
            return false
        }

        // Check conflict resolution - only reconnect if we should initiate
        guard ConnectionConflictResolver.shouldInitiateConnection(localPeer: localPeerID, remotePeer: peerID) else {
            print("🔄 Skipping auto-reconnect - waiting for peer \(peerID.displayName) to initiate")
            return false
        }

        return true
    }

    func resetConnectionState() {
        print("♾️ Resetting all connection states")
        connectionMutex.clearAll()
        sessionManager.clearAll()
        messageCache.clear()
        ackManager.clear()
        healthMonitor.clearAll()

        // Restart services after a brief delay
        stopServices()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.startServices()
        }
    }

    // MARK: - Private Methods

    private func startAdvertising() {
        let now = Date()
        guard now.timeIntervalSince(lastAdvertiseTime) >= throttleInterval else {
            print("⚠️ Throttling advertise request")
            return
        }
        lastAdvertiseTime = now

        advertiser = MCNearbyServiceAdvertiser(peer: localPeerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()

        DispatchQueue.main.async {
            self.isAdvertising = true
        }

        print("📡 NetworkManager: Started advertising with service type: \(serviceType)")
    }

    private func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil

        DispatchQueue.main.async {
            self.isAdvertising = false
        }

        print("📡 NetworkManager: Stopped advertising")
    }

    private func startProcessingTimer() {
        processingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.processMessageQueue()
        }
    }

    private func processMessageQueue() {
        guard let message = messageQueue.dequeue() else { return }

        processingQueue.async { [weak self] in
            self?.sendNetworkMessage(message)
        }

        DispatchQueue.main.async { [weak self] in
            self?.pendingAcksCount = self?.ackManager.getPendingAcksCount() ?? 0
        }
    }

    private func startBrowsing() {
        let now = Date()
        guard now.timeIntervalSince(lastBrowseTime) >= throttleInterval else {
            print("⚠️ Throttling browse request")
            return
        }
        lastBrowseTime = now

        browser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()

        DispatchQueue.main.async {
            self.isBrowsing = true
        }

        print("🔍 NetworkManager: Started browsing for peers")
    }

    private func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil

        DispatchQueue.main.async {
            self.isBrowsing = false
        }

        print("🔍 NetworkManager: Stopped browsing")
    }

    private func manageBrowsing() {
        // Always keep browsing active to discover new peers
        // This allows the network to dynamically adapt when peers join or leave
        if !isBrowsing {
            startBrowsing()
            print("🔄 Restarting browsing to discover new peers")
        }

        // Optional: Stop browsing only if explicitly configured AND we have reached max connections
        if config.stopBrowsingWhenConnected && connectedPeers.count >= config.maxConnections {
            if isBrowsing {
                stopBrowsing()
                print("🛑 Auto-stopped browsing - max connections reached (\(connectedPeers.count)/\(config.maxConnections))")
            }
        }
    }

    internal func hasReachedMaxConnections() -> Bool {
        return connectedPeers.count >= config.maxConnections
    }

    private func updateConnectionStatus() {
        DispatchQueue.main.async {
            if self.connectedPeers.isEmpty {
                self.connectionStatus = .disconnected
            } else {
                self.connectionStatus = .connected
            }
        }
    }

    private func handleReceivedMessage(data: Data, from peerID: MCPeerID) {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📥 RECEIVED DATA FROM: \(peerID.displayName)")
        print("   Data Size: \(data.count) bytes")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        do {
            let decoder = JSONDecoder()
            let payload = try decoder.decode(NetworkPayload.self, from: data)

            switch payload {
            case .message(var networkMessage):
                print("   Payload Type: Network Message")
                handleNetworkMessage(&networkMessage, from: peerID)
            case .ack(let ackMessage):
                print("   Payload Type: ACK Message")
                handleAckMessage(ackMessage, from: peerID)
            case .ping(_):
                print("   Payload Type: Ping (handled by health monitor)")
            case .pong(_):
                print("   Payload Type: Pong (handled by health monitor)")
            case .keepAlive(let keepAlive):
                print("   Payload Type: Keep-Alive (peer count: \(keepAlive.peerCount))")
                // Keep-alive messages are lightweight network stability pings
                // No action needed - just receiving them keeps connection alive
            case .locationRequest(let locationRequest):
                print("   Payload Type: Location Request")
                handleLocationRequest(locationRequest, from: peerID)
            case .locationResponse(let locationResponse):
                print("   Payload Type: Location Response")
                handleLocationResponse(locationResponse, from: peerID)
            case .uwbDiscoveryToken(let tokenMessage):
                print("   Payload Type: LinkFinder Discovery Token")
                handleUWBDiscoveryToken(tokenMessage, from: peerID)
            case .familySync(let familySyncMessage):
                print("   Payload Type: Family Sync")
                handleFamilySync(familySyncMessage, from: peerID)
            case .familyJoinRequest(let joinRequest):
                print("   Payload Type: Family Join Request")
                handleFamilyJoinRequest(joinRequest, from: peerID)
            case .familyGroupInfo(let groupInfo):
                print("   Payload Type: Family Group Info")
                handleFamilyGroupInfo(groupInfo, from: peerID)
            case .topology(var topologyMessage):
                print("   Payload Type: Topology")
                handleTopologyMessage(&topologyMessage, from: peerID)
            case .linkfenceEvent(let linkfenceEvent):
                print("   Payload Type: LinkFence Event")
                handleGeofenceEvent(linkfenceEvent, from: peerID)
            case .linkfenceShare(let linkfenceShare):
                print("   Payload Type: LinkFence Share")
                handleGeofenceShare(linkfenceShare, from: peerID)
            }
        } catch {
            guard let message = Message.fromData(data) else {
                print("❌ Failed to deserialize message: \(error)")
                return
            }
            DispatchQueue.main.async {
                // FORCE immediate UI update - critical for legacy messages
                self.messageStore.objectWillChange.send()

                let identifier = ConversationIdentifier(rawValue: message.conversationId)
                let descriptor: MessageStore.ConversationDescriptor

                if identifier.isFamily, let peerId = identifier.familyPeerId {
                    let displayName = self.familyGroupManager.getMember(withPeerID: peerId)?.displayName ?? message.conversationName ?? peerId
                    descriptor = .familyChat(peerId: peerId, displayName: displayName)
                } else {
                    descriptor = .publicChat()
                }

                self.messageStore.addMessage(message, context: descriptor, localDeviceName: self.localDeviceName)
                print("📥 Legacy message from \(peerID.displayName): \(message.content)")
            }
        }
    }

    private func handleNetworkMessage(_ message: inout NetworkMessage, from peerID: MCPeerID) {
        guard messageCache.shouldProcessMessage(message.id) else {
            print("💭 Ignoring duplicate message \(message.id.uuidString.prefix(8)) from \(peerID.displayName)")
            return
        }

        message.addHop(localPeerID.displayName)

        let isForMe = message.isForMe(localPeerID.displayName)

        // Enhanced logging for multi-hop tracking
        print("📦 Message received:")
        print("   From: \(message.senderId) → To: \(message.recipientId)")
        print("   Route: \(message.routePath.joined(separator: " → "))")
        print("   Hop: \(message.hopCount)/\(message.ttl)")
        print("   For me? \(isForMe ? "✅ YES" : "❌ NO (will relay)")")

        if isForMe {
            let isBroadcast = message.recipientId == "broadcast"
            let conversationDescriptor: MessageStore.ConversationDescriptor

            if isBroadcast {
                // Broadcast messages go to public chat
                conversationDescriptor = .publicChat()
            } else {
                // Private message - determine if family or direct conversation
                let displayName = familyGroupManager.getMember(withPeerID: message.senderId)?.displayName ?? message.senderId
                let isFamilyMember = familyGroupManager.isFamilyMember(peerID: message.senderId)
                let wasEverFamilyMember = familyGroupManager.wasEverFamilyMember(peerID: message.senderId)

                if isFamilyMember || wasEverFamilyMember {
                    // Family member conversation (current or historical)
                    conversationDescriptor = .familyChat(peerId: message.senderId, displayName: displayName)
                } else {
                    // Direct (non-family) conversation
                    conversationDescriptor = .directChat(peerId: message.senderId, displayName: displayName)
                }
            }

            let simpleMessage = Message(
                sender: message.senderId,
                content: message.content,
                recipientId: isBroadcast ? nil : message.recipientId,
                conversationId: conversationDescriptor.id,
                conversationName: conversationDescriptor.title
            )

            // Capture values needed for the async block
            let messageTypeDisplayName = message.messageType.displayName
            let hopCount = message.hopCount
            let route = message.routePath.joined(separator: " → ")
            let senderId = message.senderId
            let content = message.content
            let conversationId = conversationDescriptor.id

            DispatchQueue.main.async {
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("📨 NetworkManager: MESSAGE FOR ME - Delivering to MessageStore")
                print("   Thread: MAIN (via DispatchQueue.main.async)")
                print("   Sender: \(senderId)")
                print("   Content: \"\(content)\"")
                print("   Type: \(messageTypeDisplayName)")
                print("   Hops: \(hopCount)")
                print("   Route: \(route)")
                print("   Conversation: \(conversationId)")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                // FORCE immediate UI update - critical for messages received via MultipeerConnectivity
                print("   📢 Sending objectWillChange to MessageStore...")
                self.messageStore.objectWillChange.send()

                // Special handling for message requests
                if messageTypeDisplayName == "Solicitud" {
                    // This is a first message request - add to pending requests instead of conversations
                    FirstMessageTracker.shared.addIncomingRequest(
                        from: senderId,
                        message: content,
                        localDeviceName: self.localDeviceName
                    )
                    print("📨 NetworkManager: Added message request to pending - NOT added to MessageStore")
                    // Don't add to MessageStore yet - wait for acceptance
                } else {
                    // Regular message - add to MessageStore normally
                    print("   📥 Calling messageStore.addMessage()...")
                    self.messageStore.addMessage(simpleMessage, context: conversationDescriptor, autoSwitch: true, localDeviceName: self.localDeviceName)

                    // Check if this activates a conversation
                    FirstMessageTracker.shared.handleIncomingMessage(from: senderId, localDeviceName: self.localDeviceName)
                }

                print("✅ NetworkManager: Message delivered to MessageStore")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            }

            if message.requiresAck {
                sendAck(for: message.id, to: message.senderId)
            }
        }

        if !isForMe || message.recipientId == "broadcast" {
            if message.canHop() && !message.hasVisited(localPeerID.displayName) {
                // Create a copy of the message for the queue
                let messageCopy = message

                DispatchQueue.main.async {
                    self.relayingMessage = true
                }

                print("🔄 RELAYING message to \(self.connectedPeers.count) peers - Hop \(message.hopCount)/\(message.ttl)")
                print("   Next hops: \(self.connectedPeers.map { $0.displayName }.joined(separator: ", "))")
                messageQueue.enqueue(messageCopy)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.relayingMessage = false
                }
            } else if !message.canHop() {
                print("⏹️ Message reached hop limit: \(message.hopCount)/\(message.ttl)")
            } else if message.hasVisited(localPeerID.displayName) {
                print("⏹️ Already visited this node (loop prevention)")
            }
        }
    }

    private func handleAckMessage(_ ackMessage: AckMessage, from peerID: MCPeerID) {
        ackManager.handleAck(ackMessage)
    }

    // MARK: - Location Request Handling

    /// Send location request for a specific peer
    func sendLocationRequest(to targetPeerId: String) {
        let request = LocationRequestMessage(
            requesterId: localPeerID.displayName,
            targetId: targetPeerId,
            allowCollaborativeTriangulation: true
        )

        // Track request
        locationRequestManager.trackRequest(request)

        // Send via network
        let payload = NetworkPayload.locationRequest(request)

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(payload)
            try safeSend(data, toPeers: connectedPeers, with: .reliable, context: "locationRequest")
            print("📍 NetworkManager: Sent location request to \(targetPeerId)")
        } catch {
            print("❌ NetworkManager: Failed to send location request: \(error.localizedDescription)")
        }
    }

    private func handleLocationRequest(_ request: LocationRequestMessage, from peerID: MCPeerID) {
        print("📍 NetworkManager: Received location request from \(request.requesterId) for \(request.targetId)")

        // Case 1: Request is for me - respond with my location (LinkFinder or GPS)
        if request.targetId == localPeerID.displayName {
            handleLocationRequestForMe(request)
            return
        }

        // Case 2: Relay the request (normal multi-hop routing)
        // Intermediaries do NOT respond with their own LinkFinder data
        print("📍 NetworkManager: Relaying location request for \(request.targetId)")
        let payload = NetworkPayload.locationRequest(request)

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(payload)
            try safeSend(data, toPeers: connectedPeers, with: .reliable, context: "relayLocationRequest")
        } catch {
            print("❌ NetworkManager: Failed to relay location request: \(error.localizedDescription)")
        }
    }

    private func handleLocationRequestForMe(_ request: LocationRequestMessage) {
        // Check if we should respond
        guard locationRequestManager.shouldRespondToRequest(request) else {
            print("📍 NetworkManager: Declining location request from \(request.requesterId)")

            // Send unavailable response
            let response = LocationResponseMessage.unavailableResponse(
                requestId: request.id,
                responderId: localPeerID.displayName,
                targetId: request.targetId
            )
            sendLocationResponse(response)
            return
        }

        // Check if requester is a connected peer and we have LinkFinder session with them
        print("📍 NetworkManager: Checking LinkFinder availability with requester \(request.requesterId)...")

        if #available(iOS 14.0, *) {
            if let uwbManager = uwbSessionManager {
                print("   ✓ LinkFinderSessionManager available")

                if let requesterPeer = connectedPeers.first(where: { $0.displayName == request.requesterId }) {
                    print("   ✓ Requester found in connected peers")

                    let hasSession = uwbManager.hasActiveSession(with: requesterPeer)
                    print("   LinkFinder session active: \(hasSession ? "✓ YES" : "✗ NO")")

                    if hasSession {
                        if let distance = uwbManager.getDistance(to: requesterPeer) {
                            print("   ✓ LinkFinder distance available: \(String(format: "%.2f", distance))m")

                            // We have LinkFinder with the requester! Send precise LinkFinder response
                            let direction = uwbManager.getDirection(to: requesterPeer).map { DirectionVector(from: $0) }

                            let response = LocationResponseMessage.uwbDirectResponse(
                                requestId: request.id,
                                targetId: localPeerID.displayName,
                                distance: distance,
                                direction: direction,
                                accuracy: 0.5  // LinkFinder typical accuracy
                            )

                            sendLocationResponse(response)
                            print("✅ NetworkManager: Sent LinkFinder direct response - \(String(format: "%.2f", distance))m \(direction?.cardinalDirection ?? "no direction")")
                            return
                        } else {
                            print("   ✗ LinkFinder session exists but no distance data yet")
                        }
                    }
                } else {
                    print("   ✗ Requester \(request.requesterId) not in connected peers list")
                }
            } else {
                print("   ✗ LinkFinderSessionManager is nil")
            }
        } else {
            print("   ✗ iOS 14.0+ required for LinkFinder")
        }

        print("📍 NetworkManager: Falling back to GPS (LinkFinder not available)")

        // Fallback: No LinkFinder available, send GPS location
        Task {
            do {
                guard let location = try await locationService.getCurrentLocation() else {
                    print("❌ NetworkManager: Failed to get location")

                    let response = LocationResponseMessage.unavailableResponse(
                        requestId: request.id,
                        responderId: localPeerID.displayName,
                        targetId: request.targetId
                    )
                    sendLocationResponse(response)
                    return
                }

                // Send direct GPS response
                let response = LocationResponseMessage.directResponse(
                    requestId: request.id,
                    targetId: localPeerID.displayName,
                    location: location
                )

                sendLocationResponse(response)
                print("📍 NetworkManager: Sent GPS fallback response")

            } catch {
                print("❌ NetworkManager: Error getting location: \(error)")

                let response = LocationResponseMessage.unavailableResponse(
                    requestId: request.id,
                    responderId: localPeerID.displayName,
                    targetId: request.targetId
                )
                sendLocationResponse(response)
            }
        }
    }

    // REMOVED: Intermediary triangulation no longer supported
    // Only direct requester-target LinkFinder is used

    private func sendLocationResponse(_ response: LocationResponseMessage) {
        let payload = NetworkPayload.locationResponse(response)

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(payload)
            try safeSend(data, toPeers: connectedPeers, with: .reliable, context: "locationResponse")
        } catch {
            print("❌ NetworkManager: Failed to send location response: \(error.localizedDescription)")
        }
    }

    private func handleLocationResponse(_ response: LocationResponseMessage, from peerID: MCPeerID) {
        print("📍 NetworkManager: Received location response: \(response.description)")
        locationRequestManager.handleResponse(response)

        // Auto-update PeerLocationTracker ONLY if we requested this location (privacy guard)
        if locationRequestManager.pendingRequests[response.requestId] != nil,
           response.responseType == .direct,
           let location = response.directLocation {
            peerLocationTracker.updatePeerLocation(peerID: response.responderId, location: location)
        }
    }

    // MARK: - GPS Location Sharing for Navigation

    /// Start sharing GPS location with a peer during active navigation
    func startSharingLocationWithPeer(peerID: String) {
        print("📍 NetworkManager: Starting GPS sharing with peer: \(peerID)")

        peersInNavigation.insert(peerID)

        // Start location monitoring if not already active
        if !locationService.isMonitoring {
            locationService.startMonitoring()
        }

        // Start timer if not already running
        if locationSharingTimer == nil {
            startLocationSharingTimer()
        }

        // Send immediate location update
        broadcastMyLocationToPeersInNavigation()
    }

    /// Stop sharing GPS location with a peer when navigation ends
    func stopSharingLocationWithPeer(peerID: String) {
        print("📍 NetworkManager: Stopping GPS sharing with peer: \(peerID)")

        peersInNavigation.remove(peerID)

        // Stop timer if no more peers in navigation
        if peersInNavigation.isEmpty {
            stopLocationSharingTimer()
        }
    }

    /// Start periodic GPS location broadcast timer
    private func startLocationSharingTimer() {
        guard locationSharingTimer == nil else { return }

        locationSharingTimer = Timer.scheduledTimer(
            withTimeInterval: locationSharingInterval,
            repeats: true
        ) { [weak self] _ in
            self?.broadcastMyLocationToPeersInNavigation()
        }

        print("📍 NetworkManager: Started location sharing timer (every \(locationSharingInterval)s)")
    }

    /// Stop periodic GPS location broadcast timer
    private func stopLocationSharingTimer() {
        locationSharingTimer?.invalidate()
        locationSharingTimer = nil
        print("📍 NetworkManager: Stopped location sharing timer")
    }

    /// Broadcast current GPS location to all peers in active navigation
    private func broadcastMyLocationToPeersInNavigation() {
        guard !peersInNavigation.isEmpty else { return }

        guard let currentLocation = locationService.currentLocation else {
            print("⚠️ NetworkManager: Cannot broadcast location - no GPS fix available")
            return
        }

        guard locationService.hasRecentLocation else {
            print("⚠️ NetworkManager: Cannot broadcast location - GPS data is stale")
            return
        }

        // Create location response message (direct GPS response)
        let response = LocationResponseMessage.directResponse(
            requestId: UUID(),  // No specific request, periodic broadcast
            targetId: localPeerID.displayName,
            location: currentLocation
        )

        // Send to all connected peers (they'll filter if needed)
        let payload = NetworkPayload.locationResponse(response)

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(payload)
            try safeSend(data, toPeers: connectedPeers, with: .reliable, context: "broadcastGPSLocation")
            print("📍 NetworkManager: Broadcasted GPS location to \(connectedPeers.count) peers: \(currentLocation.coordinateString)")
        } catch {
            print("❌ NetworkManager: Failed to broadcast GPS location: \(error.localizedDescription)")
        }
    }

    // MARK: - LinkFinder Discovery Token Exchange

    private func sendUWBDiscoveryToken(to peerID: MCPeerID) {
        print("📡 NetworkManager: Attempting to send LinkFinder token to \(peerID.displayName)...")

        guard #available(iOS 14.0, *) else {
            print("   ✗ iOS 14.0+ required for LinkFinder - skipping token exchange")
            return
        }

        guard let uwbManager = uwbSessionManager else {
            print("   ✗ LinkFinderSessionManager is nil - skipping token exchange")
            return
        }

        guard uwbManager.isLinkFinderSupported else {
            print("   ✗ LinkFinder not supported on this device (requires iPhone 11+ with U1/U2 chip)")
            return
        }

        // Prepare session for this peer (creates session, extracts token, but doesn't run it)
        guard let token = uwbManager.prepareSession(for: peerID) else {
            print("   ✗ Failed to prepare session and get discovery token")
            return
        }

        do {
            let tokenData = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            let message = LinkFinderDiscoveryTokenMessage(senderId: localPeerID.displayName, tokenData: tokenData)
            let payload = NetworkPayload.uwbDiscoveryToken(message)

            let encoder = JSONEncoder()
            let data = try encoder.encode(payload)
            try safeSend(data, toPeers: [peerID], with: .reliable, context: "LinkFinderToken")

            print("✅ NetworkManager: Sent LinkFinder discovery token to \(peerID.displayName)")
            print("   Session prepared and ready to run when we receive peer's token")
        } catch {
            print("❌ NetworkManager: Failed to send LinkFinder token: \(error.localizedDescription)")
        }
    }

    // Coordinate a bidirectional LinkFinder restart with a peer by resetting local state
    // and re-initiating the token exchange. This avoids introducing a new payload
    // type and leverages the existing discovery-token flow to re-establish ranging.
    private func sendUWBResetRequest(to peer: MCPeerID) {
        print("📡 NetworkManager: LinkFinder reset requested for \(peer.displayName) — resetting local session and re-initiating token exchange")

        guard #available(iOS 14.0, *), let uwbManager = uwbSessionManager else {
            print("   ✗ LinkFinder not available — cannot perform reset")
            return
        }

        // Stop any active session with this peer
        uwbManager.stopSession(with: peer)

        // Clear token exchange state and retries so we start fresh
        uwbTokenExchangeState[peer.displayName] = .idle
        uwbRetryCount[peer.displayName] = 0

        // Small delay to allow session invalidation to propagate before restarting
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self = self else { return }

            // Mark that we're initiating a fresh exchange and send our token
            print("📤 NetworkManager: Re-initiating LinkFinder token exchange with \(peer.displayName) after reset")
            self.uwbTokenExchangeState[peer.displayName] = .sentToken
            self.sendUWBDiscoveryToken(to: peer)
        }
    }

    // Track LinkFinder token exchange state
    private var uwbTokenExchangeState: [String: TokenExchangeState] = [:]  // PeerID -> Exchange state
    private var uwbSessionRole: [String: String] = [:]  // PeerID -> "master" or "slave"

    // MARK: - Token Exchange State Enum
    enum TokenExchangeState {
        case idle                 // No exchange started
        case preparing            // Preparing local session
        case waitingForToken      // SLAVE waiting for MASTER's token
        case sentToken            // MASTER sent token, waiting for response
        case receivedToken        // Received token from peer
        case exchangeComplete     // Both tokens exchanged, both sessions running
    }

    private func handleUWBDiscoveryToken(_ tokenMessage: LinkFinderDiscoveryTokenMessage, from peerID: MCPeerID) {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📥 LinkFinder TOKEN RECEIVED")
        print("   From: \(peerID.displayName)")
        print("   Token sender ID: \(tokenMessage.senderId)")
        print("   Token data size: \(tokenMessage.tokenData.count) bytes")
        print("   Current exchange state: \(uwbTokenExchangeState[peerID.displayName] ?? .none)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        guard #available(iOS 14.0, *),
              let uwbManager = uwbSessionManager,
              uwbManager.isLinkFinderSupported else {
            print("   ✗ LinkFinder not supported on this device")
            print("   ❌ FAILED: Device doesn't support UWB")
            return
        }

        do {
            guard let remotePeerToken = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: NIDiscoveryToken.self,
                from: tokenMessage.tokenData
            ) else {
                print("❌ NetworkManager: Failed to unarchive LinkFinder token")
                return
            }

            print("   ✓ Token unarchived successfully")

            // Determine role based on peer ID comparison
            let isMaster = localPeerID.displayName > peerID.displayName
            uwbSessionRole[peerID.displayName] = isMaster ? "master" : "slave"

            print("   🎭 LinkFinder Role: \(isMaster ? "MASTER" : "SLAVE") for session with \(peerID.displayName)")
            print("   📊 Comparison: '\(localPeerID.displayName)' \(isMaster ? ">" : "<") '\(peerID.displayName)'")

            if isMaster {
                // MASTER receives SLAVE's token response
                print("   📥 MASTER received SLAVE's token")

                // Our session should already be prepared (we sent our token first)
                // Now run our session with the slave's token
                uwbManager.startSession(with: peerID, remotePeerToken: remotePeerToken)

                // Mark exchange complete
                uwbTokenExchangeState[peerID.displayName] = .exchangeComplete
                print("   ✅ Token exchange complete - both sessions running")

            } else {
                // SLAVE receives MASTER's initial token
                print("   📥 SLAVE received MASTER's token")
                print("   🎭 Role: SLAVE (will send token back)")

                // Step 1: Prepare our session (if not already prepared)
                // This will create session and extract our token
                guard let myToken = uwbManager.prepareSession(for: peerID) else {
                    print("   ❌ Failed to prepare session - cannot create local token")
                    uwbTokenExchangeState[peerID.displayName] = .none
                    return
                }

                print("   ✅ Session prepared, local token extracted")
                print("   📊 Local token size: \(String(describing: myToken).count) chars")

                // Step 2: Run our session with master's token
                uwbManager.startSession(with: peerID, remotePeerToken: remotePeerToken)
                print("   🚀 Session started with MASTER's token")

                // Step 3: Send our token back to master
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else {
                        print("   ❌ Self deallocated - cannot send token back")
                        return
                    }

                    print("   📤 SLAVE attempting to send token back to MASTER...")
                    print("   📊 Peer connection state: \(self.connectedPeers.contains(peerID) ? "Connected" : "Disconnected")")

                    // Manually encode and send (can't use sendUWBDiscoveryToken since session is already prepared)
                    do {
                        let tokenData = try NSKeyedArchiver.archivedData(withRootObject: myToken, requiringSecureCoding: true)
                        print("   ✅ Token serialized: \(tokenData.count) bytes")

                        let message = LinkFinderDiscoveryTokenMessage(senderId: self.localPeerID.displayName, tokenData: tokenData)
                        let payload = NetworkPayload.uwbDiscoveryToken(message)

                        let encoder = JSONEncoder()
                        let data = try encoder.encode(payload)
                        print("   📦 Payload encoded: \(data.count) bytes")

                        // Check if peer is still connected before sending
                        guard self.connectedPeers.contains(peerID) else {
                            print("   ❌ FAILED: Peer \(peerID.displayName) disconnected before token could be sent")
                            self.uwbTokenExchangeState[peerID.displayName] = .none
                            return
                        }

                        try self.safeSend(data, toPeers: [peerID], with: .reliable, context: "LinkFinderTokenResponse")
                        print("   📨 Token sent to \(peerID.displayName) via reliable channel")

                        self.uwbTokenExchangeState[peerID.displayName] = .exchangeComplete
                        print("   ✅ SLAVE sent token - exchange marked complete")
                    } catch {
                        print("   ❌ CRITICAL ERROR sending token back:")
                        print("      Error: \(error)")
                        print("      Description: \(error.localizedDescription)")
                        self.uwbTokenExchangeState[peerID.displayName] = .none
                    }
                }
            }

        } catch {
            print("❌ NetworkManager: Error handling LinkFinder token: \(error.localizedDescription)")
        }
    }

    // MARK: - Family Sync Handling

    private func handleFamilySync(_ syncMessage: FamilySyncMessage, from peerID: MCPeerID) {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("👨‍👩‍👧‍👦 FAMILY SYNC RECEIVED")
        print("   From: \(peerID.displayName)")
        print("   Code: \(syncMessage.groupCode.displayCode)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Handle sync through family group manager
        familyGroupManager.handleFamilySync(syncMessage)

        // Update member's last seen
        familyGroupManager.updateMemberLastSeen(peerID: peerID.displayName)
    }

    /// Send family sync to a specific peer
    private func sendFamilySync(to peerID: MCPeerID) {
        // Check if we have an active family group
        guard let group = familyGroupManager.currentGroup,
              let syncMessage = FamilySyncMessage.create(from: group, currentPeerID: localPeerID.displayName) else {
            print("⚠️ NetworkManager: No active family group to sync")
            return
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📤 SENDING FAMILY SYNC")
        print("   To: \(peerID.displayName)")
        print("   Code: \(syncMessage.groupCode.displayCode)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        let payload = NetworkPayload.familySync(syncMessage)

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(payload)
            try safeSend(data, toPeers: [peerID], with: .reliable, context: "familySync")
            print("✅ NetworkManager: Sent family sync to \(peerID.displayName)")
        } catch {
            print("❌ NetworkManager: Failed to send family sync: \(error.localizedDescription)")
        }
    }

    // MARK: - LinkFence Handling

    /// Handle received linkfence event from a family member
    private func handleGeofenceEvent(_ event: LinkFenceEventMessage, from peerID: MCPeerID) {
        // Forward to LinkFenceManager if available
        linkfenceManager?.handleGeofenceEvent(event)
    }

    /// Handle received linkfence share from a family member
    private func handleGeofenceShare(_ share: LinkFenceShareMessage, from peerID: MCPeerID) {
        // Forward to LinkFenceManager if available
        linkfenceManager?.handleGeofenceShare(share)
    }

    /// Send linkfence event to family members via mesh
    func sendGeofenceEvent(_ event: LinkFenceEventMessage) {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📤 SENDING GEOFENCE EVENT")
        print("   Type: \(event.eventType.rawValue)")
        print("   Place: \(event.linkfenceName)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        let payload = NetworkPayload.linkfenceEvent(event)

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(payload)
            // Send to all connected peers (family will filter by code)
            try safeSend(data, toPeers: connectedPeers, with: .reliable, context: "linkfenceEvent")
            print("✅ NetworkManager: Sent linkfence event to \(connectedPeers.count) peers")
        } catch {
            print("❌ NetworkManager: Failed to send linkfence event: \(error.localizedDescription)")
        }
    }

    /// Send linkfence share to family members via mesh
    func sendGeofenceShare(_ share: LinkFenceShareMessage) {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📤 SENDING GEOFENCE SHARE")
        print("   LinkFence: \(share.linkfence.name)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        let payload = NetworkPayload.linkfenceShare(share)

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(payload)
            // Send to all connected peers (family will filter by code)
            try safeSend(data, toPeers: connectedPeers, with: .reliable, context: "linkfenceShare")
            print("✅ NetworkManager: Sent linkfence share to \(connectedPeers.count) peers")
        } catch {
            print("❌ NetworkManager: Failed to send linkfence share: \(error.localizedDescription)")
        }
    }

    // MARK: - Family Join Request/Response Handling

    private func handleFamilyJoinRequest(_ request: FamilyJoinRequestMessage, from peerID: MCPeerID) {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔍 FAMILY JOIN REQUEST RECEIVED")
        print("   From: \(request.requesterId)")
        print("   Code: \(request.groupCode.displayCode)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Check if we have this group code
        guard let myGroup = familyGroupManager.currentGroup,
              myGroup.code == request.groupCode else {
            print("⚠️ We don't have group with code \(request.groupCode.displayCode)")
            return
        }

        print("✅ We have this group! Sending info back...")
        print("   Group: \(myGroup.name)")
        print("   Members: \(myGroup.memberCount)")

        // Create response with group info
        let groupInfo = FamilyGroupInfoMessage.create(
            from: myGroup,
            requestId: request.id,
            responderId: localPeerID.displayName
        )

        // Send back to requester
        sendFamilyGroupInfo(groupInfo, to: peerID)
    }

    private func handleFamilyGroupInfo(_ info: FamilyGroupInfoMessage, from peerID: MCPeerID) {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📥 FAMILY GROUP INFO RECEIVED")
        print("   From: \(info.responderId)")
        print("   Group: \(info.groupName)")
        print("   Code: \(info.groupCode.displayCode)")
        print("   Members: \(info.memberCount)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Notify via NotificationCenter (para que JoinFamilyGroupView lo reciba)
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Notification.Name("FamilyGroupInfoReceived"),
                object: nil,
                userInfo: ["groupInfo": info]
            )
        }
    }

    /// Request family group info from connected peers (broadcast)
    func requestFamilyGroupInfo(code: FamilyGroupCode, requesterId: String, memberInfo: FamilySyncMessage.FamilyMemberInfo) {
        guard !connectedPeers.isEmpty else {
            print("⚠️ No connected peers to request family group info from")
            return
        }

        let request = FamilyJoinRequestMessage(
            requesterId: requesterId,
            groupCode: code,
            memberInfo: memberInfo
        )

        let payload = NetworkPayload.familyJoinRequest(request)

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(payload)
            try safeSend(data, toPeers: connectedPeers, with: .reliable, context: "familyJoinRequest")

            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("📤 BROADCASTING FAMILY JOIN REQUEST")
            print("   Code: \(code.displayCode)")
            print("   To: \(connectedPeers.count) peers")
            print("   Peers: \(connectedPeers.map { $0.displayName }.joined(separator: ", "))")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        } catch {
            print("❌ Failed to send family join request: \(error.localizedDescription)")
        }
    }

    private func sendFamilyGroupInfo(_ info: FamilyGroupInfoMessage, to peerID: MCPeerID) {
        let payload = NetworkPayload.familyGroupInfo(info)

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(payload)
            try safeSend(data, toPeers: [peerID], with: .reliable, context: "familyGroupInfo")
            print("✅ Sent family group info to \(peerID.displayName)")
        } catch {
            print("❌ Failed to send family group info: \(error.localizedDescription)")
        }
    }

    // MARK: - Topology Discovery

    private var topologyBroadcastTimer: Timer?

    private func startTopologyBroadcastTimer() {
        // Broadcast topology every 10 seconds
        topologyBroadcastTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.broadcastTopology()
        }
    }

    /// Broadcast current topology to all connected peers
    private func broadcastTopology() {
        guard !connectedPeers.isEmpty else { return }

        // RACE CONDITION FIX: Validate against actual session state
        // The local connectedPeers array may be out of sync with session.connectedPeers
        // if a peer disconnected between updates
        let sessionPeers = session.connectedPeers
        let validPeers = connectedPeers.filter { sessionPeers.contains($0) }

        guard !validPeers.isEmpty else {
            print("⚠️ broadcastTopology: No valid peers in session, skipping broadcast")
            print("   Local array has \(connectedPeers.count), but session has \(sessionPeers.count)")
            return
        }

        let connectedPeerNames = validPeers.map { $0.displayName }
        let topologyMessage = TopologyMessage(
            senderId: localPeerID.displayName,
            connectedPeers: connectedPeerNames
        )

        let payload = NetworkPayload.topology(topologyMessage)

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(payload)
            // STABILITY FIX: Use unreliable mode for topology broadcasts
            // Topology updates are periodic, so occasional packet loss is acceptable
            // This reduces buffer pressure and prevents connection drops
            try session.send(data, toPeers: validPeers, with: .unreliable)

            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("📡 TOPOLOGY BROADCAST (unreliable)")
            print("   Connections: [\(connectedPeerNames.joined(separator: ", "))]")
            print("   Sent to: \(validPeers.count) peers (validated against session)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            // Update local routing table
            routingTable.updateLocalTopology(connectedPeers: validPeers)

        } catch {
            print("❌ Failed to broadcast topology: \(error.localizedDescription)")
            print("   Valid peers: \(validPeers.count), Session peers: \(sessionPeers.count)")
        }
    }

    /// Handle received topology message
    private func handleTopologyMessage(_ message: inout TopologyMessage, from peerID: MCPeerID) {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🗺️ TOPOLOGY RECEIVED")
        print("   From: \(message.senderId)")
        print("   Connections: [\(message.connectedPeers.joined(separator: ", "))]")
        print("   Hop: \(message.hopCount)/\(message.ttl)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Update routing table
        routingTable.updateTopology(message)

        // Relay to other peers if possible
        if message.canHop() && !message.hasVisited(localPeerID.displayName) {
            message.addHop(localPeerID.displayName)

            let payload = NetworkPayload.topology(message)

            // RACE CONDITION FIX: Validate peers against session state
            let sessionPeers = session.connectedPeers
            let validPeers = connectedPeers.filter { sessionPeers.contains($0) }

            guard !validPeers.isEmpty else {
                print("⚠️ Cannot relay topology: No valid peers in session")
                return
            }

            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(payload)
                // STABILITY FIX: Use unreliable mode for topology relays too
                try session.send(data, toPeers: validPeers, with: .unreliable)
                print("🔄 Relayed topology message (hop \(message.hopCount)/\(message.ttl)) to \(validPeers.count) peers (unreliable)")
            } catch {
                print("❌ Failed to relay topology: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - MCSessionDelegate

extension NetworkManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔄 SESSION STATE CHANGE CALLBACK")
        print("   Peer: \(peerID.displayName)")
        print("   New State: \(state == .connected ? "CONNECTED" : state == .connecting ? "CONNECTING" : "NOT_CONNECTED")")
        print("   Timestamp: \(Date())")
        print("   Thread: \(Thread.current)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        DispatchQueue.main.async {
            switch state {
            case .connected:
                print("🔍 DEBUG: Handling .connected state...")

                // Release any connection locks
                print("   Step 1: Releasing connection mutex...")
                self.connectionMutex.releaseLock(for: peerID)
                print("   ✓ Mutex released")

                // Clear failure counters on successful connection
                print("   Step 2: Clearing failure counters...")
                self.failedConnectionAttempts[peerID.displayName] = 0
                self.consecutiveFailures = 0
                print("   ✓ Failure counters cleared")

                // Record connection metrics for diagnostics
                self.recordConnectionMetrics(peer: peerID, event: .connected)

                // Remove any stale entries for this displayName first
                print("   Step 3: Cleaning stale peer entries...")
                let previousCount = self.connectedPeers.count
                self.connectedPeers.removeAll { $0.displayName == peerID.displayName }
                print("   ✓ Removed \(previousCount - self.connectedPeers.count) stale entries")

                // Now add the fresh connection
                print("   Step 4: Adding peer to connectedPeers array...")
                self.connectedPeers.append(peerID)
                print("   ✓ Peer added. Total connected: \(self.connectedPeers.count)")

                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("🆕 NEW CONNECTION ESTABLISHED")
                print("   Peer: \(peerID.displayName)")
                print("   Total Connections: \(self.connectedPeers.count)")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                print("   Step 5: Recording successful connection in SessionManager...")
                self.sessionManager.recordSuccessfulConnection(to: peerID)
                print("   ✓ Recorded in SessionManager")

                if !TestingConfig.disableHealthMonitoring {
                    self.healthMonitor.addPeer(peerID)
                } else {
                    print("🧪 TEST MODE: Health monitoring disabled for \(peerID.displayName)")
                }

                self.updateConnectionStatus()
                self.manageBrowsing()  // Stop browsing if configured
                print("✅ NetworkManager: Connected to peer: \(peerID.displayName) | Total peers: \(self.connectedPeers.count)")

                // Record successful connection with orchestrator
                if self.isOrchestratorEnabled {
                    print("   🎯 Recording successful connection with Orchestrator")
                    self.recordSuccessfulConnection(to: peerID)
                }

                // Auto-start Live Activity when first peer connects
                if #available(iOS 16.1, *) {
                    if self.connectedPeers.count == 1 && !self.hasActiveLiveActivity {
                        print("🎬 Auto-starting Live Activity for first peer connection")
                        self.startLiveActivity()
                    }
                }

                // ACCESSIBILITY: Announce connection + haptic feedback
                AudioManager.shared.announceConnectionChange(connected: true, peerName: peerID.displayName)
                HapticManager.shared.playPattern(.peerConnected, priority: .notification)

                // Stagger topology and family sync broadcasts based on peer ID comparison
                // This prevents message collision when both peers try to send at the same time
                let shouldInitiateMessages = self.localPeerID.displayName > peerID.displayName

                // Broadcast updated topology after connection stabilizes
                // Higher ID sends at 2.0s, lower ID at 2.5s to avoid collision
                let topologyDelay = shouldInitiateMessages ? 2.0 : 2.5
                DispatchQueue.main.asyncAfter(deadline: .now() + topologyDelay) { [weak self] in
                    self?.broadcastTopology()
                }

                // Send family sync if we have an active group
                // Higher ID sends at 3.0s, lower ID at 3.5s
                let familySyncDelay = shouldInitiateMessages ? 3.0 : 3.5
                DispatchQueue.main.asyncAfter(deadline: .now() + familySyncDelay) { [weak self] in
                    guard let self = self else { return }
                    if self.familyGroupManager.hasActiveGroup {
                        self.sendFamilySync(to: peerID)
                    }
                }

                // Reset LinkFinder retry count and token exchange state for this peer
                self.uwbRetryCount[peerID.displayName] = 0
                self.uwbTokenExchangeState[peerID.displayName] = .idle
                self.uwbSessionRole.removeValue(forKey: peerID.displayName)

                // Determine who should initiate LinkFinder token exchange based on peer ID
                let shouldInitiate = self.localPeerID.displayName > peerID.displayName

                if shouldInitiate {
                    // We initiate if we have the higher ID (master role)
                    // STABILITY FIX: Increased from 2.0s to 4.0s to ensure topology and family sync complete first
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                        guard let self = self else { return }
                        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        print("🎯 LinkFinder TOKEN EXCHANGE INITIATOR")
                        print("   Local: \(self.localPeerID.displayName)")
                        print("   Remote: \(peerID.displayName)")
                        print("   Role: MASTER (initiating)")
                        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        self.uwbTokenExchangeState[peerID.displayName] = .sentToken
                        self.sendUWBDiscoveryToken(to: peerID)
                    }
                } else {
                    // Wait for the other peer to initiate (slave role)
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    print("⏳ LinkFinder TOKEN EXCHANGE WAITER")
                    print("   Local: \(self.localPeerID.displayName)")
                    print("   Remote: \(peerID.displayName)")
                    print("   Role: SLAVE (waiting for token)")
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    self.uwbTokenExchangeState[peerID.displayName] = .waitingForToken
                }

            case .connecting:
                print("🔍 DEBUG: Handling .connecting state...")
                self.connectionStatus = .connecting
                // No longer need mutex here - iOS handles connection serialization
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("🔄 PEER STATE: CONNECTING")
                print("   Peer: \(peerID.displayName)")
                print("   Handshake in progress...")
                print("   Session encryption: \(session.encryptionPreference == .required ? ".required" : session.encryptionPreference == .optional ? ".optional" : ".none")")
                print("   Current connected peers in session: \(session.connectedPeers.map { $0.displayName })")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                // Start a timer to monitor TLS handshake timeout
                let handshakeStartTime = Date()
                let peerName = peerID.displayName
                DispatchQueue.main.asyncAfter(deadline: .now() + 11.0) { [weak self] in
                    guard let self = self else { return }
                    // Check if still in connecting state after 11 seconds (iOS internal timeout is 10s)
                    if !self.connectedPeers.contains(where: { $0.displayName == peerName }) {
                        let elapsed = Date().timeIntervalSince(handshakeStartTime)
                        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        print("⚠️ TLS HANDSHAKE TIMEOUT DETECTED")
                        print("   Peer: \(peerName)")
                        print("   Elapsed: \(String(format: "%.1f", elapsed))s")
                        print("   Likely cause: Encryption mismatch or network issue")
                        print("   Session encryption: \(session.encryptionPreference == .required ? ".required" : ".optional")")
                        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    }
                }

            case .notConnected:
                // Aggressively release any connection locks
                self.connectionMutex.releaseLock(for: peerID)

                // Double-check and force release if needed (in case of stuck locks)
                DispatchQueue.main.async {
                    self.connectionMutex.releaseLock(for: peerID)
                }

                // Note: MCNearbyServiceBrowser doesn't have cancelConnectPeer method
                // Disconnection is handled by the session state changes

                let wasConnected = self.connectedPeers.contains(peerID)
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("🔌 PEER DISCONNECTION EVENT")
                print("   Peer: \(peerID.displayName)")
                print("   Was connected: \(wasConnected)")
                print("   Remaining connected peers: \(self.connectedPeers.count - 1)")

                self.connectedPeers.removeAll { $0 == peerID }
                self.sessionManager.recordDisconnection(from: peerID)
                self.healthMonitor.removePeer(peerID)

                // Record disconnection metrics - check if it was a socket timeout
                if wasConnected {
                    if let connectionTime = self.sessionManager.getConnectionTime(for: peerID),
                       Date().timeIntervalSince(connectionTime) < 20 {
                        // Very quick disconnection likely caused by socket timeout
                        self.recordConnectionMetrics(peer: peerID, event: .socketTimeout)
                    } else {
                        self.recordConnectionMetrics(peer: peerID, event: .disconnected)
                    }
                }

                // Auto-stop Live Activity when last peer disconnects
                if #available(iOS 16.1, *) {
                    if self.connectedPeers.isEmpty && self.hasActiveLiveActivity {
                        print("🛑 Auto-stopping Live Activity - no peers connected")
                        self.stopLiveActivity()
                    }
                }

                // Remove from routing table
                self.routingTable.removePeer(peerID.displayName)
                // Immediately broadcast updated topology to reflect disconnection
                self.broadcastTopology()

                // Stop LinkFinder session and clear token exchange state
                if #available(iOS 14.0, *) {
                    self.uwbSessionManager?.stopSession(with: peerID)
                    self.uwbTokenExchangeState[peerID.displayName] = .idle
                    self.uwbRetryCount[peerID.displayName] = 0
                }
                self.updateConnectionStatus()
                self.manageBrowsing()  // Restart browsing if no connections left

                // Record disconnection with orchestrator
                if self.isOrchestratorEnabled {
                    print("   🎯 Recording disconnection with Orchestrator")
                    let reason: PeerReputationSystem.DisconnectionReason
                    if wasConnected, let connectionTime = self.sessionManager.getConnectionTime(for: peerID),
                       Date().timeIntervalSince(connectionTime) < 20 {
                        reason = .timeout
                    } else {
                        reason = .networkIssue
                    }
                    self.recordDisconnection(of: peerID, reason: reason)
                }

                // No longer waiting for this peer to invite us
                self.waitingForInvitationFrom.removeValue(forKey: peerID.displayName)

                // DEBUG: Check if this peer has conversations
                let familyConversationId = ConversationIdentifier.family(peerId: peerID.displayName).rawValue
                let hasConversation = self.messageStore.hasConversation(withId: familyConversationId)
                let conversationDescriptor = self.messageStore.descriptor(for: familyConversationId)

                print("   💬 CONVERSATION STATUS:")
                print("      Has conversation: \(hasConversation)")
                print("      Conversation ID: \(familyConversationId)")
                if let descriptor = conversationDescriptor {
                    print("      Conversation title: \(descriptor.title)")
                    print("      Message count: \(self.messageStore.messages(for: familyConversationId).count)")
                }
                print("   Active conversation: \(self.messageStore.activeConversationId)")
                print("   Total conversations: \(self.messageStore.conversationSummaries.count)")

                if wasConnected {
                    print("❌ DISCONNECTION: Lost connection to peer: \(peerID.displayName)")

                    // ACCESSIBILITY: Announce disconnection + haptic feedback
                    AudioManager.shared.announceConnectionChange(connected: false, peerName: peerID.displayName)
                    HapticManager.shared.playPattern(.peerDisconnected, priority: .notification)
                    print("🔌 Disconnected from \(peerID.displayName)")

                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                } else {
                    print("📵 Connection attempt failed for peer: \(peerID.displayName)")
                    // Handle connection failure with retry logic
                    self.handleConnectionFailure(with: peerID)
                }

                // Always stop monitoring when disconnected
                print("🏥 Stopped monitoring: \(peerID.displayName)")

                if wasConnected {
                    // Force rediscovery for truly disconnected peers
                    self.availablePeers.removeAll { $0 == peerID }

                    // FIX: Clear peerEventTimes to allow immediate rediscovery
                    // Without this, the 10-second deduplication window blocks foundPeer events
                    self.peerEventTimes.removeValue(forKey: peerID.displayName)
                    print("🔍 Peer \(peerID.displayName) removed from available peers and event cache - ready for immediate rediscovery")
                } else {
                    // Keep failed peers in the available list so retry logic can trigger quickly
                    if !self.availablePeers.contains(where: { $0.displayName == peerID.displayName }) {
                        self.availablePeers.append(peerID)
                    }
                    print("🕸️ Retaining \(peerID.displayName) in available peers for retry")
                }

            @unknown default:
                print("⚠️ NetworkManager: Unknown connection state for peer: \(peerID.displayName)")
                self.connectionMutex.releaseLock(for: peerID)
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let pongData = healthMonitor.handleHealthMessage(data, from: peerID) {
            try? safeSend(pongData, toPeers: [peerID], with: .reliable, context: "healthPong")
            return
        }
        handleReceivedMessage(data: data, from: peerID)
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used in this implementation
        print("📡 NetworkManager: Received stream (not implemented): \(streamName) from \(peerID.displayName)")
    }

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not used in this implementation
        print("📡 NetworkManager: Started receiving resource (not implemented): \(resourceName) from \(peerID.displayName)")
    }

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Not used in this implementation
        print("📡 NetworkManager: Finished receiving resource (not implemented): \(resourceName) from \(peerID.displayName)")
    }

    func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
        // CRITICAL FIX: This delegate method is marked as "optional" by Apple,
        // but in practice it MUST be implemented to prevent random disconnections
        // after sending data. Multiple Stack Overflow threads confirm this.
        //
        // For development and encrypted sessions, we accept all certificates.
        // In production, you can add certificate validation logic here.

        let startTime = Date()

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔐 CERTIFICATE EXCHANGE STARTED")
        print("   From peer: \(peerID.displayName)")
        print("   Certificate count: \(certificate?.count ?? 0)")
        print("   Thread: \(Thread.current.isMainThread ? "MAIN" : "BACKGROUND [\(Thread.current.description)]")")
        print("   Timestamp: \(Date())")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Accept certificate immediately
        certificateHandler(true)

        let elapsed = Date().timeIntervalSince(startTime) * 1000.0 // Convert to milliseconds

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("✅ CERTIFICATE ACCEPTED")
        print("   Peer: \(peerID.displayName)")
        print("   Handler response time: \(String(format: "%.2f", elapsed))ms")
        print("   Total elapsed: \(String(format: "%.2f", elapsed))ms")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension NetworkManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📨 INVITATION RECEIVED - STEP 1: Initial Reception")
        print("   From: \(peerID.displayName)")
        print("   To: \(localPeerID.displayName)")
        print("   Connected Peers: \(connectedPeers.count)/\(config.maxConnections)")
        print("   Timestamp: \(Date())")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Check TestingConfig blocking
        print("🔍 DEBUG STEP 2: Checking TestingConfig blocking...")
        if TestingConfig.shouldBlockDirectConnection(from: localPeerID.displayName, to: peerID.displayName) {
            print("🧪 TEST MODE: Declining invitation from \(peerID.displayName) - blocked by TestingConfig")
            invitationHandler(false, nil)
            sessionManager.recordConnectionDeclined(to: peerID, reason: "blocked by TestingConfig")
            return
        }
        print("   ✓ TestingConfig: Not blocked")

        // Check if peer is manually blocked
        print("🔍 DEBUG STEP 3: Checking manual blocking...")
        if connectionManager.isPeerBlocked(peerID.displayName) {
            print("🚫 NetworkManager: Declining invitation from \(peerID.displayName) - peer is manually blocked")
            invitationHandler(false, nil)
            sessionManager.recordConnectionDeclined(to: peerID, reason: "manually blocked")
            return
        }
        print("   ✓ Manual blocking: Not blocked")

        // Check if already connected
        print("🔍 DEBUG STEP 4: Checking if already connected...")
        if connectedPeers.contains(peerID) {
            print("⛔ Declining invitation from \(peerID.displayName) - already connected")
            print("   Current connected peers: \(connectedPeers.map { $0.displayName }.joined(separator: ", "))")
            invitationHandler(false, nil)
            return
        }
        print("   ✓ Already connected: No")

        // Check if we've reached max connections
        print("🔍 DEBUG STEP 5: Checking max connections...")
        if hasReachedMaxConnections() {
            print("⛔ Declining invitation from \(peerID.displayName) - max connections reached (\(connectedPeers.count)/\(config.maxConnections))")
            invitationHandler(false, nil)
            return
        }
        print("   ✓ Max connections: \(connectedPeers.count)/\(config.maxConnections) - OK")

        // Check conflict resolution - should we accept based on ID comparison?
        // BUT: If we've had failures trying to connect to this peer OR SessionManager is blocking us, accept the invitation anyway
        print("🔍 DEBUG STEP 6: Checking conflict resolution...")
        let peerKey = peerID.displayName
        let hasFailedConnections = (failedConnectionAttempts[peerKey] ?? 0) > 0
        let sessionManagerBlocking = !sessionManager.shouldAttemptConnection(to: peerID)
        let conflictResolutionSaysAccept = ConnectionConflictResolver.shouldAcceptInvitation(localPeer: localPeerID, fromPeer: peerID)

        print("   Failed connections count: \(failedConnectionAttempts[peerKey] ?? 0)")
        print("   SessionManager blocking: \(sessionManagerBlocking)")
        print("   Conflict resolution says accept: \(conflictResolutionSaysAccept)")

        if !hasFailedConnections && !sessionManagerBlocking && !conflictResolutionSaysAccept {
            print("🆔 Declining invitation - we should initiate to \(peerID.displayName)")
            print("   Local ID: \(localPeerID.displayName)")
            print("   Remote ID: \(peerID.displayName)")
            print("   Comparison: \(localPeerID.displayName < peerID.displayName ? "Local < Remote" : "Local > Remote")")
            invitationHandler(false, nil)
            sessionManager.recordConnectionDeclined(to: peerID, reason: "conflict resolution says we should initiate")
            return
        } else if hasFailedConnections {
            print("🔄 Accepting invitation despite conflict resolution - previous failures detected for \(peerKey)")
        } else if sessionManagerBlocking {
            print("🔄 Accepting invitation despite conflict resolution - SessionManager is blocking our attempts")
        } else {
            print("   ✓ Conflict resolution: Accept invitation (we are slave)")
        }

        // CRITICAL FIX: Don't hold mutex across iOS callback boundary
        // MultipeerConnectivity already handles connection serialization internally
        // The mutex was causing deadlock when iOS tried to deliver session callbacks

        // Check if another operation is in progress
        print("🔍 DEBUG STEP 7: Checking ConnectionMutex...")
        let mutexHasOperation = connectionMutex.hasActiveOperation(for: peerID)
        print("   Mutex has active operation: \(mutexHasOperation)")

        if mutexHasOperation {
            if hasFailedConnections || sessionManagerBlocking {
                print("⚠️ Force accepting invitation to break potential deadlock")
                print("   Releasing stuck mutex lock...")
                connectionMutex.releaseLock(for: peerID)
                print("   ✓ Mutex lock released")
            } else {
                print("🔒 Declining invitation - connection operation in progress for \(peerID.displayName)")
                invitationHandler(false, nil)
                return
            }
        } else {
            print("   ✓ Mutex: No active operation")
        }

        // Accept invitation if we have failures OR SessionManager is blocking us (deadlock breaker)
        print("🔍 DEBUG STEP 8: Final acceptance decision...")

        // Use orchestrator decision if enabled
        let shouldAccept: Bool
        if isOrchestratorEnabled {
            print("   🎯 Using Orchestrator for invitation decision")
            shouldAccept = shouldAcceptInvitationFromPeer(peerID)
        } else {
            // Legacy decision logic
            shouldAccept = hasFailedConnections || sessionManagerBlocking || sessionManager.shouldAttemptConnection(to: peerID)
        }

        print("   Should accept: \(shouldAccept)")
        print("   Decision source: \(isOrchestratorEnabled ? "Orchestrator" : "Legacy logic")")

        guard shouldAccept else {
            print("⛔ Declining invitation from \(peerID.displayName) - connection not allowed")
            invitationHandler(false, nil)
            sessionManager.recordConnectionDeclined(to: peerID, reason: isOrchestratorEnabled ? "orchestrator declined" : "session manager not allowing")
            return
        }

        if sessionManagerBlocking {
            print("⚠️ DEBUG STEP 9: Clearing SessionManager cooldown to break deadlock...")
            sessionManager.clearCooldown(for: peerID)
            print("   ✓ Cooldown cleared")
        } else if hasFailedConnections && !sessionManager.shouldAttemptConnection(to: peerID) {
            print("⚠️ DEBUG STEP 9: Accepting despite session manager - compensating for failures")
        }

        // Record attempt BEFORE accepting (but don't hold mutex)
        print("🔍 DEBUG STEP 10: Recording connection attempt...")
        sessionManager.recordConnectionAttempt(to: peerID)
        print("   ✓ Connection attempt recorded")

        // Accept invitation WITHOUT holding mutex - iOS handles serialization
        print("🔍 DEBUG STEP 11: Calling invitationHandler(true, session)...")
        print("   Session ID: \(session)")
        print("   Session connected peers: \(session.connectedPeers.map { $0.displayName })")
        print("   About to accept invitation at: \(Date())")

        invitationHandler(true, session)

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("✅ INVITATION ACCEPTED (mutex-free)")
        print("   From: \(peerID.displayName)")
        print("   Session encryption: \(session.encryptionPreference == .required ? ".required" : session.encryptionPreference == .optional ? ".optional" : ".none")")
        print("   Waiting for iOS to complete handshake...")
        print("   Next: session(_:peer:didChange:) will be called")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("❌ NetworkManager: Failed to start advertising: \(error.localizedDescription)")

        DispatchQueue.main.async {
            self.isAdvertising = false
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension NetworkManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔍 BROWSER: PEER DISCOVERED")
        print("   Peer: \(peerID.displayName)")
        print("   Discovery Info: \(info ?? [:])")
        print("   Timestamp: \(Date())")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        let peerKey = peerID.displayName
        let now = Date()

        // Update last peer discovery time
        lastPeerDiscoveryTime = now

        // Check for recent found event
        print("🔍 DEBUG: Checking for duplicate discovery events...")
        if let lastFound = peerEventTimes[peerKey]?.found,
           now.timeIntervalSince(lastFound) < eventDeduplicationWindow {
            print("🔇 Ignoring duplicate found event for \(peerKey)")
            print("   Last found: \(String(format: "%.1f", now.timeIntervalSince(lastFound)))s ago")
            return
        }
        print("   ✓ Not a duplicate")

        // Update event time
        if peerEventTimes[peerKey] != nil {
            peerEventTimes[peerKey]?.found = now
        } else {
            peerEventTimes[peerKey] = (found: now, lost: nil)
        }

        DispatchQueue.main.async {
            print("🔍 DEBUG: Adding peer to availablePeers...")

            // Remove any existing entries for this displayName first (handles stale entries)
            let previousCount = self.availablePeers.count
            self.availablePeers.removeAll { $0.displayName == peerID.displayName }
            if previousCount != self.availablePeers.count {
                print("   Removed \(previousCount - self.availablePeers.count) stale entries")
            }

            // Now add the peer (fresh entry)
            if peerID != self.localPeerID {
                self.availablePeers.append(peerID)
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("✅ PEER ADDED TO AVAILABLE LIST")
                print("   Peer: \(peerID.displayName)")
                print("   Total Available Peers: \(self.availablePeers.count)")
                print("   Total Connected Peers: \(self.connectedPeers.count)")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                // INTELLIGENT DISCONNECTION: Check for peers marked as pendingDisconnect
                // When a new peer is discovered, disconnect any peers user wanted to disconnect
                self.processingQueue.async { [weak self] in
                    guard let self = self else { return }

                    let pendingDisconnectPeers = self.peerConnectionStates.filter { $0.value == .pendingDisconnect }

                    if !pendingDisconnectPeers.isEmpty {
                        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        print("🔌 AUTO-DISCONNECTION: New peer available")
                        print("   New peer: \(peerID.displayName)")
                        print("   Peers pending disconnect: \(pendingDisconnectPeers.keys.joined(separator: ", "))")
                        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                        // Disconnect all pending peers now that we have an alternative
                        for (peerKey, _) in pendingDisconnectPeers {
                            if let peerToDisconnect = self.connectedPeers.first(where: { $0.displayName == peerKey }) {
                                print("   Executing delayed disconnect for \(peerKey)")

                                DispatchQueue.main.async {
                                    // Perform actual disconnection
                                    self.session.cancelConnectPeer(peerToDisconnect)

                                    // Clean up all state for this peer
                                    self.cleanupPeerState(peerToDisconnect)

                                    print("   ✅ Auto-disconnection completed for \(peerKey)")
                                }
                            }
                        }

                        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    }
                }

                // Minimal delay for instant reconnection
                let jitter = Double.random(in: 0.1...0.5)
                print("⏱️ Will attempt connection to \(peerID.displayName) in \(String(format: "%.1f", jitter)) seconds")

                DispatchQueue.main.asyncAfter(deadline: .now() + jitter) { [weak self] in
                    guard let self = self else { return }

                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    print("🔍 AUTO-CONNECTION EVALUATION")
                    print("   Peer: \(peerID.displayName)")
                    print("   Timestamp: \(Date())")
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                    // Check TestingConfig blocking first
                    print("   Step 1: Checking TestingConfig...")
                    if TestingConfig.shouldBlockDirectConnection(from: self.localPeerID.displayName, to: peerID.displayName) {
                        print("🧪 TEST MODE: Blocked direct connection to \(peerID.displayName)")
                        return
                    }
                    print("   ✓ TestingConfig: Not blocked")

                    // Enhanced logging for conflict resolution decision
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    print("👥 PEER DISCOVERY DECISION ANALYSIS")
                    print("   Local: \(self.localPeerID.displayName)")
                    print("   Remote: \(peerID.displayName)")

                    let shouldInitiate = ConnectionConflictResolver.shouldInitiateConnection(localPeer: self.localPeerID, remotePeer: peerID)
                    let peerKey = peerID.displayName

                    print("   📊 Hash-Based Decision:")
                    print("      Local hash: \(self.localPeerID.displayName.hashValue)")
                    print("      Remote hash: \(peerID.displayName.hashValue)")
                    print("      We should: \(shouldInitiate ? "INITIATE 🟢" : "WAIT 🟡")")
                    print("      They should: \(shouldInitiate ? "WAIT 🟡" : "INITIATE 🟢")")

                    if !shouldInitiate {
                        print("   ⏰ Will wait max 5s for invitation before forcing")
                    }
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                    let isWaitingForInvitation = self.waitingForInvitationFrom[peerKey] != nil
                    let alreadyConnected = self.connectedPeers.contains(where: { $0.displayName == peerID.displayName })
                    let maxConnectionsReached = self.hasReachedMaxConnections()
                    let stillAvailable = self.availablePeers.contains(where: { $0.displayName == peerID.displayName })
                    let sessionManagerAllows = self.sessionManager.shouldAttemptConnection(to: peerID)

                    print("   Step 2: Connection criteria check:")
                    print("      Already connected? \(alreadyConnected)")
                    print("      Max connections reached? \(maxConnectionsReached) (\(self.connectedPeers.count)/\(self.config.maxConnections))")
                    print("      Still available? \(stillAvailable)")
                    print("      Should initiate? \(shouldInitiate)")
                    print("      Already waiting? \(isWaitingForInvitation)")
                    print("      Session manager allows? \(sessionManagerAllows)")

                    // Use orchestrator decision if enabled
                    let shouldConnect: Bool
                    if self.isOrchestratorEnabled {
                        print("   🎯 Using Orchestrator for decision")
                        shouldConnect = self.shouldConnectToDiscoveredPeer(peerID, discoveryInfo: info)
                    } else {
                        // Legacy decision logic
                        shouldConnect = !alreadyConnected &&
                                      !maxConnectionsReached &&
                                      stillAvailable &&
                                      shouldInitiate &&
                                      sessionManagerAllows
                    }

                    if shouldConnect {
                        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        print("✅ INITIATING CONNECTION")
                        print("   To: \(peerID.displayName)")
                        print("   Reason: \(self.isOrchestratorEnabled ? "Orchestrator approved" : "All criteria met")")
                        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        self.waitingForInvitationFrom.removeValue(forKey: peerKey)  // Clear waiting status
                        self.connectToPeer(peerID)
                    } else {
                        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        print("⏸️ SKIPPING CONNECTION")
                        print("   To: \(peerID.displayName)")
                        if alreadyConnected {
                            print("   Reason: Already connected")
                        } else if maxConnectionsReached {
                            print("   Reason: Max connections reached (\(self.connectedPeers.count)/\(self.config.maxConnections))")
                        } else if !stillAvailable {
                            print("   Reason: Peer no longer available")
                        } else if !shouldInitiate {
                            print("   Reason: Conflict resolution - waiting for them to initiate")
                            // Record that we're waiting for an invitation
                            if self.waitingForInvitationFrom[peerKey] == nil {
                                self.waitingForInvitationFrom[peerKey] = Date()
                                print("   ⏰ Started waiting for invitation")
                            }
                        } else if !sessionManagerAllows {
                            print("   Reason: SessionManager blocking (cooldown/retry limit)")
                        }
                        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    }
                }
            } else {
                print("   ⚠️ Discovered self - ignoring")
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let peerKey = peerID.displayName
        let now = Date()

        // Check for recent lost event
        if let lastLost = peerEventTimes[peerKey]?.lost,
           now.timeIntervalSince(lastLost) < eventDeduplicationWindow {
            print("🔇 Ignoring duplicate lost event for \(peerKey)")
            return
        }

        // Update event time
        if peerEventTimes[peerKey] != nil {
            peerEventTimes[peerKey]?.lost = now
        } else {
            peerEventTimes[peerKey] = (found: nil, lost: now)
        }

        DispatchQueue.main.async {
            self.availablePeers.removeAll { $0 == peerID }
            print("👻 NetworkManager: Lost peer: \(peerID.displayName)")
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("❌ NetworkManager: Failed to start browsing: \(error.localizedDescription)")

        DispatchQueue.main.async {
            self.isBrowsing = false
        }
    }
}

// MARK: - Helper Extensions

extension NetworkManager {
    var localDeviceName: String {
        return localPeerID.displayName
    }

    var isConnected: Bool {
        return !connectedPeers.isEmpty
    }

    var connectedPeerNames: [String] {
        return connectedPeers.map { $0.displayName }
    }

    var availablePeerNames: [String] {
        return availablePeers.map { $0.displayName }
    }

    func getQueueStatus() -> [(MessageType, Int)] {
        return messageQueue.getQueueStatus()
    }

    func getPendingAcksStatus() -> [(messageId: UUID, type: MessageType, retryCount: Int, timePending: TimeInterval)] {
        return ackManager.getPendingAcksStatus()
    }

    // MARK: - Connection Diagnostics

    func getConnectionDiagnostics() -> String {
        let mutexStatus = connectionMutex.getStatus()
        let sessionStats = sessionManager.getConnectionStats()

        return """
        === CONNECTION DIAGNOSTICS ===
        📱 Local Device: \(localPeerID.displayName)
        🔗 Connected Peers: \(connectedPeers.count)
        👀 Available Peers: \(availablePeers.count)
        🔒 Mutex - Active: \(mutexStatus.activeCount), Pending: \(mutexStatus.pendingCount)
        📊 Session - Attempts: \(sessionStats.attempts), Blocked: \(sessionStats.blocked), Active: \(sessionStats.active)
        ⏱️ Pending ACKs: \(pendingAcksCount)
        🌐 Connection Quality: \(connectionQuality.displayName)
        =============================
        """
    }

    func logDetailedConnectionStatus() {
        print(getConnectionDiagnostics())

        if !connectedPeers.isEmpty {
            print("Connected to:")
            for peer in connectedPeers {
                if let stats = healthMonitor.getHealthStats(for: peer) {
                    print("  • \(peer.displayName) - Quality: \(stats.quality.rawValue), Latency: \(Int(stats.latency))ms")
                } else {
                    print("  • \(peer.displayName) - No health data")
                }
            }
        }
    }

    /// Get location diagnostics for debugging
    func getLocationDiagnostics() -> String {
        var diag = "=== LOCATION DIAGNOSTICS ===\n"

        // Location Service Status
        diag += locationService.getDetailedStatus()
        diag += "\n"

        // LinkFinder Status
        if #available(iOS 14.0, *), let uwbManager = uwbSessionManager {
            diag += "LinkFinder Status:\n"
            diag += "  Supported: \(uwbManager.isLinkFinderSupported)\n"
            diag += "  Active Sessions: \(uwbManager.activeSessions.count)\n"

            if !uwbManager.activeSessions.isEmpty {
                diag += "  Sessions:\n"
                for (peerId, _) in uwbManager.activeSessions {
                    let hasDistance = uwbManager.nearbyObjects[peerId]?.distance != nil
                    let hasDirection = uwbManager.nearbyObjects[peerId]?.direction != nil
                    diag += "    • \(peerId): distance=\(hasDistance), direction=\(hasDirection)\n"
                }
            }
        } else {
            diag += "LinkFinder: Not available\n"
        }

        diag += "============================\n"
        return diag
    }
}

// MARK: - AckManagerDelegate

extension NetworkManager: AckManagerDelegate {
    func ackManager(_ manager: AckManager, shouldResendMessage message: NetworkMessage) {
        messageQueue.enqueue(message)
        print("🔄 Re-enqueuing message for retry: \(message.id)")
    }

    func ackManager(_ manager: AckManager, didReceiveAckFor messageId: UUID) {
        DispatchQueue.main.async {
            self.pendingAcksCount = manager.getPendingAcksCount()
        }
    }

    func ackManager(_ manager: AckManager, didFailToReceiveAckFor messageId: UUID) {
        DispatchQueue.main.async {
            self.pendingAcksCount = manager.getPendingAcksCount()
            print("❌ Message failed after max retries: \(messageId)")
        }
    }
}

// MARK: - PeerHealthMonitorDelegate

extension NetworkManager: PeerHealthMonitorDelegate {
    func peerHealthMonitor(_ monitor: PeerHealthMonitor, shouldDisconnect peer: MCPeerID) {
        disconnectFromPeer(peer)
        sessionManager.resetPeer(peer)
    }

    func peerHealthMonitor(_ monitor: PeerHealthMonitor, qualityChanged quality: ConnectionQuality, for peer: MCPeerID) {
        DispatchQueue.main.async {
            self.connectionQuality = quality
        }
    }
}

// MARK: - LinkFinderSessionManagerDelegate

@available(iOS 14.0, *)
extension NetworkManager: LinkFinderSessionManagerDelegate {
    func uwbSessionManager(_ manager: LinkFinderSessionManager, didUpdateDistanceTo peerId: String, distance: Float?, direction: SIMD3<Float>?) {
        // LinkFinder distance/direction updated - handled automatically by LinkFinderSessionManager
        // We can use this for additional UI feedback if needed
    }

    func uwbSessionManager(_ manager: LinkFinderSessionManager, didLoseTrackingOf peerId: String, reason: NINearbyObject.RemovalReason) {
        print("⚠️ NetworkManager: Lost LinkFinder tracking of \(peerId) - Reason: \(reason.description)")
    }

    func uwbSessionManager(_ manager: LinkFinderSessionManager, sessionInvalidatedFor peerId: String, error: Error) {
        print("❌ NetworkManager: LinkFinder session invalidated for \(peerId): \(error.localizedDescription)")

        // Check if it's a permission denied error
        if error.localizedDescription.contains("USER_DID_NOT_ALLOW") {
            print("⚠️ NetworkManager: LinkFinder permission denied by user for \(peerId)")
            // Reset retry count but don't retry - user needs to grant permission
            uwbRetryCount[peerId] = 0

            // Notify UI about permission issue
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Notification.Name("UWBPermissionDenied"),
                    object: nil,
                    userInfo: ["peerId": peerId]
                )
            }
            return
        }

        // Check retry count
        let retries = uwbRetryCount[peerId] ?? 0

        // Try to restart session if peer is still connected and under retry limit
        if let peer = connectedPeers.first(where: { $0.displayName == peerId }) {
            if retries < maxUWBRetries {
                uwbRetryCount[peerId] = retries + 1
                print("🔄 NetworkManager: Attempting to restart LinkFinder session with \(peerId) (retry \(retries + 1)/\(maxUWBRetries))")

                // Add a delay before retrying
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.sendUWBDiscoveryToken(to: peer)
                }
            } else {
                print("❌ NetworkManager: Max LinkFinder retries reached for \(peerId)")
                uwbRetryCount[peerId] = 0
            }
        }
    }

    func uwbSessionManager(_ manager: LinkFinderSessionManager, requestsRestartFor peerId: String) {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔄 LinkFinder RESTART REQUESTED")
        print("   Peer: \(peerId)")
        print("   Action: Coordinating bidirectional restart")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Send LinkFinder_RESET_REQUEST to peer
        if let peer = connectedPeers.first(where: { $0.displayName == peerId }) {
            sendUWBResetRequest(to: peer)
        }
    }

    func uwbSessionManager(_ manager: LinkFinderSessionManager, needsFreshTokenFor peerId: String) {
        print("🔄 NetworkManager: Restarting token exchange for \(peerId)")

        guard #available(iOS 14.0, *) else {
            return
        }

        // Send fresh token to peer
        if let peer = connectedPeers.first(where: { $0.displayName == peerId }) {
            // Reset exchange state
            uwbTokenExchangeState[peerId] = .idle

            // Determine role and re-initiate exchange
            let isMaster = localPeerID.displayName > peer.displayName

            if isMaster {
                // MASTER re-initiates
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    print("📤 NetworkManager: MASTER re-sending LinkFinder token to \(peerId)")
                    self?.uwbTokenExchangeState[peerId] = .sentToken
                    self?.sendUWBDiscoveryToken(to: peer)
                }
            } else {
                // SLAVE waits for master
                uwbTokenExchangeState[peerId] = .waitingForToken
                print("⏳ NetworkManager: SLAVE waiting for MASTER to re-send token")
            }
        }
    }

    // MARK: - Testing & Simulation

    /// Send a simulated message for testing Live Activity message display
    /// This creates a fake message and adds it to the message store
    /// IMPORTANT: Uses a separate "test-chat" conversation so it counts as UNREAD
    func sendSimulatedMessage(content: String = "Mensaje de prueba", sender: String = "Test User") {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🧪 SENDING SIMULATED MESSAGE")
        print("   Sender: \(sender)")
        print("   Content: \(content)")
        print("   Current active conversation: \(messageStore.activeConversationId)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Use a SEPARATE conversation ID so messages count as unread
        // MessageStore.calculateUnreadCount() skips activeConversationId
        let testConversationId = "test-chat-simulation"

        let simulatedMessage = Message(
            sender: sender,
            content: content,
            conversationId: testConversationId,
            conversationName: "Chat de Prueba"
        )

        // Create a test conversation context (NOT the active one)
        let testContext = MessageStore.ConversationDescriptor(
            id: testConversationId,
            title: "Chat de Prueba (\(sender))",
            isFamily: false,
            isDirect: false,  // Test chat is neither family nor direct
            participantId: nil,
            defaultRecipientId: "test-broadcast"
        )

        // Add to message store (this will trigger Live Activity update)
        messageStore.addMessage(simulatedMessage, context: testContext, localDeviceName: self.localDeviceName)

        print("✅ Simulated message added to MessageStore")
        print("   Message ID: \(simulatedMessage.id)")
        print("   Unread count: \(messageStore.unreadCount)")
        print("   Total messages: \(messageStore.messageCount)")
        print("   Latest message sender: \(messageStore.latestMessage?.sender ?? "none")")
        print("   Latest message content: \(messageStore.latestMessage?.content ?? "none")")
        print("   Latest message timestamp: \(messageStore.latestMessage?.timestamp.description ?? "none")")
        print("   🔔 MessageStore observers should trigger Live Activity update")

        // Force Live Activity update immediately
        print("   🔄 Forcing Live Activity update NOW...")
        updateLiveActivity()

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    /// Send multiple simulated messages for testing
    func sendSimulatedMessages(count: Int = 3) {
        let senders = ["Ana", "Carlos", "María", "Test User", "Beta Tester"]
        let messages = [
            "Hola, ¿dónde están?",
            "Estoy en la sección 12",
            "¿Alguien vio a Pedro?",
            "Nos vemos en la entrada norte",
            "Ya casi llego",
            "¿Quién tiene las entradas?",
            "La fila está muy larga",
            "Mensaje de prueba largo para ver cómo se trunca en la vista previa del Live Activity"
        ]

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🧪 SENDING \(count) SIMULATED MESSAGES")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        for i in 0..<count {
            let sender = senders[i % senders.count]
            let content = messages[i % messages.count]

            sendSimulatedMessage(content: content, sender: sender)

            // Small delay between messages
            Thread.sleep(forTimeInterval: 0.2)
        }

        print("✅ Sent \(count) simulated messages")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}
