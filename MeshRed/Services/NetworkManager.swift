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

    // MARK: - Core Components
    private let serviceType = "meshred-chat"
    private let localPeerID: MCPeerID = {
        let deviceName = ProcessInfo.processInfo.hostName
        // Use public name from UserDisplayNameManager
        let displayNameManager = UserDisplayNameManager.shared
        let publicName = displayNameManager.getCurrentPublicName(deviceName: deviceName)
        print("📡 [NetworkManager] Creating MCPeerID with public name: '\(publicName)'")
        return MCPeerID(displayName: publicName)
    }()
    private var session: MCSession
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
    private let sessionManager = SessionManager()
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

    // Network configuration
    private let config = NetworkConfig.shared

    // MARK: - Connection Status Enum
    enum ConnectionStatus {
        case disconnected
        case connecting
        case connected
    }

    override init() {
        // DEVELOPMENT: Use .optional for Simulator-Device compatibility
        // PRODUCTION: Change back to .required for security
        #if targetEnvironment(simulator)
        self.session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .optional)
        print("🔓 [SIMULATOR] Using .optional encryption for Simulator-Device compatibility")
        #else
        self.session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .required)
        print("🔐 [DEVICE] Using .required encryption for maximum security")
        #endif
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
        #if targetEnvironment(simulator)
        self.session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .optional)
        print("🔓 [RESTART-SIMULATOR] Using .optional encryption for Simulator-Device compatibility")
        #else
        self.session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .required)
        print("🔐 [RESTART-DEVICE] Using .required encryption for maximum security")
        #endif
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

        if consecutiveFailures >= 3 {
            print("⚠️ Multiple connection failures detected. Initiating recovery...")
            restartServicesIfNeeded()
            failedConnectionAttempts.removeAll()  // Reset after restart
        } else {
            // Try to reconnect after a delay
            let delay = Double(consecutiveFailures) * 2.0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }

                if self.availablePeers.contains(peerID) &&
                   !self.connectedPeers.contains(peerID) &&
                   self.sessionManager.shouldAttemptConnection(to: peerID) {
                    print("🔄 Retrying connection to \(peerID.displayName) after failure")
                    self.browser?.invitePeer(peerID, to: self.session, withContext: nil, timeout: SessionManager.connectionTimeout)
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
                        try self.session.send(pingData, toPeers: [peer], with: .reliable)
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

            // Progressive timeout: 15s, 18s, 22s... (increased from 5s to reduce noise)
            let failureCount = failedConnectionAttempts[peerKey] ?? 0
            let timeoutThreshold = 15.0 + (Double(failureCount) * 3.0)

            // Cap maximum wait time at 30 seconds
            let effectiveThreshold = min(timeoutThreshold, 30.0)

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
        messageStore.addMessage(message, context: conversationDescriptor)

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
            try session.send(data, toPeers: targetPeers, with: .reliable)
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

            try session.send(data, toPeers: peers, with: .reliable)
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
            try session.send(data, toPeers: [peer], with: mode)
        } catch {
            print("❌ Failed to send raw data to \(peer.displayName): \(error.localizedDescription)")
        }
    }

    func connectToPeer(_ peerID: MCPeerID, forceIgnoreConflictResolution: Bool = false) {
        guard let browser = browser else {
            print("❌ NetworkManager: Browser not available")
            return
        }

        // Check if peer is manually blocked
        if connectionManager.isPeerBlocked(peerID.displayName) {
            print("🚫 NetworkManager: Peer \(peerID.displayName) is manually blocked - skipping connection")
            return
        }

        // Check conflict resolution (unless forcing)
        if !forceIgnoreConflictResolution {
            guard ConnectionConflictResolver.shouldInitiateConnection(localPeer: localPeerID, remotePeer: peerID) else {
                print("🆔 Deferring to peer \(peerID.displayName) for connection initiation")
                return
            }
        } else {
            print("⚡ FORCING connection to \(peerID.displayName) - bypassing conflict resolution")
        }

        // Acquire mutex lock to serialize invites
        guard connectionMutex.tryAcquireLock(for: peerID, operation: .browserInvite) else {
            print("🔒 Connection operation already in progress for \(peerID.displayName)")
            return
        }

        var lockReleased = false
        let releaseLock: () -> Void = { [weak self] in
            guard let self = self, !lockReleased else { return }
            lockReleased = true
            self.connectionMutex.releaseLock(for: peerID)
        }

        guard sessionManager.shouldAttemptConnection(to: peerID) else {
            print("⏸️ Skipping connection attempt to \(peerID.displayName)")
            releaseLock()
            return
        }

        sessionManager.recordConnectionAttempt(to: peerID)
        print("🔗 NetworkManager: Attempting to connect to peer: \(peerID.displayName)")
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: SessionManager.connectionTimeout)

        // Watchdog: if the session never transitions, clear the lock to avoid deadlocks
        let handshakeTimeout = SessionManager.connectionTimeout + 4.0
        DispatchQueue.main.asyncAfter(deadline: .now() + handshakeTimeout) { [weak self] in
            guard let self = self else { return }
            if self.connectionMutex.hasActiveOperation(for: peerID) {
                print("⏳ Connection handshake timeout for \(peerID.displayName) - releasing lock")
                // Note: Browser doesn't have cancelConnectPeer - session handles timeouts
                releaseLock()
            }
        }
    }

    func disconnectFromPeer(_ peerID: MCPeerID) {
        // Note: MCNearbyServiceBrowser doesn't have cancelConnectPeer, only MCSession does
        // This would be handled by the session state changes
        connectionMutex.releaseLock(for: peerID)
        print("🔌 NetworkManager: Manually disconnected from peer: \(peerID.displayName)")
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

    private func hasReachedMaxConnections() -> Bool {
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

                self.messageStore.addMessage(message, context: descriptor)
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

                // CRITICAL: Auto-switch to conversation when receiving messages
                print("   📥 Calling messageStore.addMessage()...")
                self.messageStore.addMessage(simpleMessage, context: conversationDescriptor, autoSwitch: true)
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
            try session.send(data, toPeers: connectedPeers, with: .reliable)
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
            try session.send(data, toPeers: connectedPeers, with: .reliable)
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
            try session.send(data, toPeers: connectedPeers, with: .reliable)
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
            try session.send(data, toPeers: connectedPeers, with: .reliable)
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
            try session.send(data, toPeers: [peerID], with: .reliable)

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
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        guard #available(iOS 14.0, *),
              let uwbManager = uwbSessionManager,
              uwbManager.isLinkFinderSupported else {
            print("   ✗ LinkFinder not supported on this device")
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

                // Step 1: Prepare our session (if not already prepared)
                // This will create session and extract our token
                guard let myToken = uwbManager.prepareSession(for: peerID) else {
                    print("   ❌ Failed to prepare session")
                    return
                }

                // Step 2: Run our session with master's token
                uwbManager.startSession(with: peerID, remotePeerToken: remotePeerToken)

                // Step 3: Send our token back to master
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }

                    print("   📤 SLAVE sending token back to MASTER")

                    // Manually encode and send (can't use sendUWBDiscoveryToken since session is already prepared)
                    do {
                        let tokenData = try NSKeyedArchiver.archivedData(withRootObject: myToken, requiringSecureCoding: true)
                        let message = LinkFinderDiscoveryTokenMessage(senderId: self.localPeerID.displayName, tokenData: tokenData)
                        let payload = NetworkPayload.uwbDiscoveryToken(message)

                        let encoder = JSONEncoder()
                        let data = try encoder.encode(payload)
                        try self.session.send(data, toPeers: [peerID], with: .reliable)

                        self.uwbTokenExchangeState[peerID.displayName] = .exchangeComplete
                        print("   ✅ SLAVE sent token - exchange complete")
                    } catch {
                        print("   ❌ Failed to send token back: \(error.localizedDescription)")
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
            try session.send(data, toPeers: [peerID], with: .reliable)
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
            try session.send(data, toPeers: connectedPeers, with: .reliable)
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
            try session.send(data, toPeers: connectedPeers, with: .reliable)
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
            try session.send(data, toPeers: connectedPeers, with: .reliable)

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
            try session.send(data, toPeers: [peerID], with: .reliable)
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

        let connectedPeerNames = connectedPeers.map { $0.displayName }
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
            try session.send(data, toPeers: connectedPeers, with: .unreliable)

            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("📡 TOPOLOGY BROADCAST (unreliable)")
            print("   Connections: [\(connectedPeerNames.joined(separator: ", "))]")
            print("   Sent to: \(connectedPeers.count) peers")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            // Update local routing table
            routingTable.updateLocalTopology(connectedPeers: connectedPeers)

        } catch {
            print("❌ Failed to broadcast topology: \(error.localizedDescription)")
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

            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(payload)
                // STABILITY FIX: Use unreliable mode for topology relays too
                try session.send(data, toPeers: connectedPeers, with: .unreliable)
                print("🔄 Relayed topology message (hop \(message.hopCount)/\(message.ttl)) (unreliable)")
            } catch {
                print("❌ Failed to relay topology: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - MCSessionDelegate

extension NetworkManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                // Release any connection locks
                self.connectionMutex.releaseLock(for: peerID)

                // Clear failure counters on successful connection
                self.failedConnectionAttempts[peerID.displayName] = 0
                self.consecutiveFailures = 0

                // Remove any stale entries for this displayName first
                self.connectedPeers.removeAll { $0.displayName == peerID.displayName }

                // Now add the fresh connection
                self.connectedPeers.append(peerID)
                print("🆕 NEW CONNECTION ESTABLISHED: \(peerID.displayName)")

                self.sessionManager.recordSuccessfulConnection(to: peerID)

                if !TestingConfig.disableHealthMonitoring {
                    self.healthMonitor.addPeer(peerID)
                } else {
                    print("🧪 TEST MODE: Health monitoring disabled for \(peerID.displayName)")
                }

                self.updateConnectionStatus()
                self.manageBrowsing()  // Stop browsing if configured
                print("✅ NetworkManager: Connected to peer: \(peerID.displayName) | Total peers: \(self.connectedPeers.count)")

                // ACCESSIBILITY: Announce connection + haptic feedback
                AudioManager.shared.announceConnectionChange(connected: true, peerName: peerID.displayName)
                HapticManager.shared.playPattern(.peerConnected, priority: .notification)

                // Broadcast updated topology after connection stabilizes
                // STABILITY FIX: Increased from 0.5s to 2.0s to allow connection to fully establish
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.broadcastTopology()
                }

                // Send family sync if we have an active group
                // STABILITY FIX: Increased from 1.0s to 3.0s to space out initial messages
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
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
                self.connectionStatus = .connecting
                // Track this state change with mutex
                _ = self.connectionMutex.tryAcquireLock(for: peerID, operation: .sessionConnecting)
                print("🔄 NetworkManager: State changed to CONNECTING for peer: \(peerID.displayName)")

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
                    print("🔍 Peer \(peerID.displayName) removed from available peers - requires rediscovery")
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
            try? session.send(pongData, toPeers: [peerID], with: .reliable)
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
        certificateHandler(true)
        print("🔐 NetworkManager: Certificate received from \(peerID.displayName) - ACCEPTED")
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension NetworkManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📨 INVITATION RECEIVED")
        print("   From: \(peerID.displayName)")
        print("   To: \(localPeerID.displayName)")
        print("   Connected Peers: \(connectedPeers.count)/\(config.maxConnections)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Check TestingConfig blocking
        if TestingConfig.shouldBlockDirectConnection(from: localPeerID.displayName, to: peerID.displayName) {
            print("🧪 TEST MODE: Declining invitation from \(peerID.displayName) - blocked by TestingConfig")
            invitationHandler(false, nil)
            sessionManager.recordConnectionDeclined(to: peerID, reason: "blocked by TestingConfig")
            return
        }

        // Check if peer is manually blocked
        if connectionManager.isPeerBlocked(peerID.displayName) {
            print("🚫 NetworkManager: Declining invitation from \(peerID.displayName) - peer is manually blocked")
            invitationHandler(false, nil)
            sessionManager.recordConnectionDeclined(to: peerID, reason: "manually blocked")
            return
        }

        // Check if already connected
        if connectedPeers.contains(peerID) {
            print("⛔ Declining invitation from \(peerID.displayName) - already connected")
            invitationHandler(false, nil)
            return
        }

        // Check if we've reached max connections
        if hasReachedMaxConnections() {
            print("⛔ Declining invitation from \(peerID.displayName) - max connections reached (\(connectedPeers.count)/\(config.maxConnections))")
            invitationHandler(false, nil)
            return
        }

        // Check conflict resolution - should we accept based on ID comparison?
        // BUT: If we've had failures trying to connect to this peer OR SessionManager is blocking us, accept the invitation anyway
        let peerKey = peerID.displayName
        let hasFailedConnections = (failedConnectionAttempts[peerKey] ?? 0) > 0
        let sessionManagerBlocking = !sessionManager.shouldAttemptConnection(to: peerID)

        if !hasFailedConnections && !sessionManagerBlocking && !ConnectionConflictResolver.shouldAcceptInvitation(localPeer: localPeerID, fromPeer: peerID) {
            print("🆔 Declining invitation - we should initiate to \(peerID.displayName)")
            invitationHandler(false, nil)
            sessionManager.recordConnectionDeclined(to: peerID, reason: "conflict resolution says we should initiate")
            return
        } else if hasFailedConnections {
            print("🔄 Accepting invitation despite conflict resolution - previous failures detected for \(peerKey)")
        } else if sessionManagerBlocking {
            print("🔄 Accepting invitation despite conflict resolution - SessionManager is blocking our attempts")
        }

        // Try to acquire mutex lock
        // BUT: If we have failures or SessionManager is blocking us, force accept even with pending operations
        if !connectionMutex.tryAcquireLock(for: peerID, operation: .acceptInvitation) {
            if hasFailedConnections || sessionManagerBlocking {
                print("⚠️ Forcing invitation acceptance despite mutex - breaking deadlock")
                // Release any existing lock and acquire new one
                connectionMutex.releaseLock(for: peerID)
                _ = connectionMutex.tryAcquireLock(for: peerID, operation: .acceptInvitation)
            } else {
                print("🔒 Declining invitation - connection operation in progress for \(peerID.displayName)")
                invitationHandler(false, nil)
                return
            }
        }

        // Schedule lock release
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.connectionMutex.releaseLock(for: peerID)
        }

        // Accept invitation if we have failures OR SessionManager is blocking us (deadlock breaker)
        let shouldAccept = hasFailedConnections || sessionManagerBlocking || sessionManager.shouldAttemptConnection(to: peerID)

        guard shouldAccept else {
            print("⛔ Declining invitation from \(peerID.displayName) - connection not allowed")
            connectionMutex.releaseLock(for: peerID)
            invitationHandler(false, nil)
            sessionManager.recordConnectionDeclined(to: peerID, reason: "session manager not allowing")
            return
        }

        if sessionManagerBlocking {
            print("⚠️ Accepting invitation to break deadlock - clearing SessionManager cooldown")
            sessionManager.clearCooldown(for: peerID)
        } else if hasFailedConnections && !sessionManager.shouldAttemptConnection(to: peerID) {
            print("⚠️ Accepting invitation despite session manager - compensating for previous failures")
        }

        // Record attempt and accept
        sessionManager.recordConnectionAttempt(to: peerID)
        invitationHandler(true, session)
        print("✅ NetworkManager: Accepted invitation from: \(peerID.displayName)")
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
        let peerKey = peerID.displayName
        let now = Date()

        // Update last peer discovery time
        lastPeerDiscoveryTime = now

        // Check for recent found event
        if let lastFound = peerEventTimes[peerKey]?.found,
           now.timeIntervalSince(lastFound) < eventDeduplicationWindow {
            print("🔇 Ignoring duplicate found event for \(peerKey)")
            return
        }

        // Update event time
        if peerEventTimes[peerKey] != nil {
            peerEventTimes[peerKey]?.found = now
        } else {
            peerEventTimes[peerKey] = (found: now, lost: nil)
        }

        DispatchQueue.main.async {
            // Remove any existing entries for this displayName first (handles stale entries)
            self.availablePeers.removeAll { $0.displayName == peerID.displayName }

            // Now add the peer (fresh entry)
            if peerID != self.localPeerID {
                self.availablePeers.append(peerID)
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("🔍 PEER DISCOVERED")
                print("   Name: \(peerID.displayName)")
                print("   Discovery Info: \(info ?? [:])")
                print("   Available Peers: \(self.availablePeers.count)")
                print("   Connected Peers: \(self.connectedPeers.count)")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                // Minimal delay for instant reconnection
                let jitter = Double.random(in: 0.1...0.5)
                print("⏱️ Will attempt connection to \(peerID.displayName) in \(String(format: "%.1f", jitter)) seconds")

                DispatchQueue.main.asyncAfter(deadline: .now() + jitter) { [weak self] in
                    guard let self = self else { return }

                    // Only auto-connect if:
                    // - Not already connected to this peer
                    // - Haven't reached max connections
                    // - Peer still available
                    // - Should initiate based on conflict resolution
                    // - Session manager allows it
                    // - Not blocked by TestingConfig

                    // Check TestingConfig blocking first
                    if TestingConfig.shouldBlockDirectConnection(from: self.localPeerID.displayName, to: peerID.displayName) {
                        print("🧪 TEST MODE: Blocked direct connection to \(peerID.displayName)")
                        return
                    }

                    let shouldInitiate = ConnectionConflictResolver.shouldInitiateConnection(localPeer: self.localPeerID, remotePeer: peerID)
                    let peerKey = peerID.displayName

                    // Note: Force connection is now handled by checkStuckWaitingStates()
                    // This prevents duplicate force connection logic
                    let isWaitingForInvitation = self.waitingForInvitationFrom[peerKey] != nil

                    print("🔍 Auto-connection check for \(peerID.displayName):")
                    print("   Already connected? \(self.connectedPeers.contains(where: { $0.displayName == peerID.displayName }))")
                    print("   Max connections reached? \(self.hasReachedMaxConnections())")
                    print("   Still available? \(self.availablePeers.contains(where: { $0.displayName == peerID.displayName }))")
                    print("   Should initiate? \(shouldInitiate)")
                    print("   Already waiting? \(isWaitingForInvitation)")
                    print("   Session manager allows? \(self.sessionManager.shouldAttemptConnection(to: peerID))")

                    if !self.connectedPeers.contains(where: { $0.displayName == peerID.displayName }) &&
                       !self.hasReachedMaxConnections() &&
                       self.availablePeers.contains(where: { $0.displayName == peerID.displayName }) &&
                       shouldInitiate &&
                       self.sessionManager.shouldAttemptConnection(to: peerID) {
                        self.waitingForInvitationFrom.removeValue(forKey: peerKey)  // Clear waiting status
                        self.connectToPeer(peerID)
                    } else if self.hasReachedMaxConnections() {
                        print("⏸️ Skipping auto-connect to \(peerID.displayName) - max connections reached")
                    } else if !shouldInitiate {
                        // Record that we're waiting for an invitation
                        if self.waitingForInvitationFrom[peerKey] == nil {
                            self.waitingForInvitationFrom[peerKey] = Date()
                            print("⏰ Starting to wait for invitation from \(peerKey)")
                        }
                    }
                }
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
        messageStore.addMessage(simulatedMessage, context: testContext)

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
