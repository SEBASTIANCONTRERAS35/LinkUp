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
import CoreLocation
import os

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
    internal let serviceType = "meshred-chat"
    internal let localPeerID: MCPeerID = {
        let deviceName = ProcessInfo.processInfo.hostName
        // Use public name from UserDisplayNameManager
        let displayNameManager = UserDisplayNameManager.shared
        let publicName = displayNameManager.getCurrentPublicName(deviceName: deviceName)
        LoggingService.network.info("📡 Creating MCPeerID with public name: '\(publicName, privacy: .public)'")
        return MCPeerID(displayName: publicName)
    }()
    internal var session: MCSession
    internal var advertiser: MCNearbyServiceAdvertiser?
    internal var browser: MCNearbyServiceBrowser?

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

    // MARK: - Route Discovery Cache
    /// On-demand route discovery cache (AODV-like protocol)
    private let routeCache = RouteCache()

    // MARK: - Advanced Components
    private let messageQueue = MessageQueue()
    private let messageCache = MessageCache()
    private let ackManager = AckManager()
    internal let sessionManager = SessionManager()
    let healthMonitor = PeerHealthMonitor()
    internal let connectionMutex = ConnectionMutex()

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

    // Network configuration detector (detects problematic WiFi configurations)
    let networkConfigDetector = NetworkConfigurationDetector()

    // Connection diagnostics (tracks connection attempts and failure patterns)
    // let diagnostics = ConnectionDiagnostics() // Temporarily disabled

    // Network configuration
    internal var config = NetworkConfig.shared

    // MARK: - Stadium Mode Components
    private var stadiumMode: StadiumMode?
    private var lightningManager: LightningMeshManager?
    private var isLightningModeActive: Bool = false

    // MARK: - Lightning Mode Tracking
    internal var connectionAttemptTimestamps: [String: Date] = [:]
    internal var lightningConnectionTimes: [TimeInterval] = []

    // MARK: - Route Discovery Management
    /// Pending route discovery requests with completion handlers
    private var pendingRouteDiscoveries: [UUID: (RouteInfo?) -> Void] = [:]
    private let routeDiscoveryTimeout: TimeInterval = 10.0
    private let routeDiscoveryQueue = DispatchQueue(label: "com.meshred.routediscovery", attributes: .concurrent)

    // MARK: - Peer Connection State Management
    /// Tracks the connection state of each peer for intelligent disconnection management
    enum PeerConnectionState {
        case active              // Normal connection, can send/receive messages
        case pendingDisconnect   // User requested disconnect, waiting for alternative peer
    }

    /// Dictionary tracking connection state for each peer (by displayName)
    /// Thread-safe access via processingQueue barriers
    private var peerConnectionStates: [String: PeerConnectionState] = [:]

    /// Set of peers currently in .connecting state (handshake in progress)
    /// Used by stuck waiting detector to avoid forcing reconnect during active handshakes
    private var connectingPeers: Set<String> = []

    /// Set of peers that have started certificate exchange
    /// Used to detect handshake stalls (if peer stays in .connecting but never reaches certificate exchange)
    private var certificateExchangeStarted: Set<String> = []

    // MARK: - Connection Status Enum
    enum ConnectionStatus {
        case disconnected
        case connecting
        case connected
    }

    override init() {
        // PRODUCTION MODE: Use .optional encryption (allows both encrypted and unencrypted)
        // .optional provides best balance: tries encryption but falls back if needed
        // Previous diagnostic mode (.none) confirmed issue was NOT TLS-related but state corruption
        // With improved session recreation and intelligent delays, .optional now works reliably

        // Encryption preference configuration:
        // .none = No encryption (diagnostic only, fastest handshake)
        // .optional = Preferred encryption with fallback (RECOMMENDED for production)
        // .required = Always encrypted (most secure but may fail with older devices)
        let encryptionMode: MCEncryptionPreference = .optional

        self.session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: encryptionMode)

        switch encryptionMode {
        case .none:
            LoggingService.network.warning("🔓 [DIAGNOSTIC MODE] Using .none encryption - NO TLS HANDSHAKE")
            LoggingService.network.warning("⚠️ Security DISABLED - Debug mode only")
        case .optional:
            LoggingService.network.info("🔒 [PRODUCTION MODE] Using .optional encryption")
            LoggingService.network.info("✅ Secure connections preferred, fallback available")
        case .required:
            LoggingService.network.info("🔐 [SECURE MODE] Using .required encryption")
            LoggingService.network.info("✅ All connections must be encrypted")
        @unknown default:
            LoggingService.network.error("❓ Unknown encryption mode")
        }
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
            uwbManager.networkManager = self  // Set reference for GPS location sharing
            self.uwbSessionManager = uwbManager
        }

        startServices()
        startProcessingTimer()
        startStatsUpdateTimer()
        startHealthCheck()
        startWaitingCheckTimer()
        startTopologyBroadcastTimer()
        startAdvertiserHealthCheck()

        // Setup notification observers for settings actions
        setupNotificationObservers()

        // DEVELOPMENT: Clear any blocked peers to allow Simulator-Device connections
        #if DEBUG
        connectionManager.clearAllBlocksForDevelopment()
        #endif

        LoggingService.network.info("🚀 NetworkManager: Initialized with peer ID: \(self.localPeerID.displayName, privacy: .public)")

        // 🏟️ CONFIGURE STADIUM MODE MANAGER
        // Setup dependencies for automatic activation on first connection
        StadiumModeManager.shared.setup(
            networkManager: self,
            locationService: locationService
        )
        LoggingService.network.info("🏟️ StadiumModeManager configured - will auto-activate on first peer connection")

        // ⚡ AUTO-ACTIVATE LIGHTNING MODE FOR FIFA 2026
        // Use simplified Lightning Mode - only core optimizations, no experimental features
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.enableLightningMode()
            LoggingService.network.warning("⚡⚡⚡ LIGHTNING MODE AUTO-ACTIVATED ⚡⚡⚡")
            LoggingService.network.info("🏟️ FIFA 2026 Ready: Fast connections enabled by default")
            LoggingService.network.info("⚡ Using simplified mode: No cooldowns, faster timeouts, bypass validations")
        }
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
        LoggingService.network.info("🔄 NetworkManager: Started advertising and browsing services")
    }

    func stopServices() {
        // Print diagnostic summary before stopping
        // diagnostics.printDiagnosticSummary() // Temporarily disabled

        stopAdvertising()
        stopBrowsing()
        session.disconnect()
        LoggingService.network.info("⏹️ NetworkManager: Stopped all services and disconnected session")
    }

    /// Restart services in Bluetooth-only mode after transport failures
    func restartServicesInBluetoothMode() {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🔄 RESTARTING IN BLUETOOTH-ONLY MODE")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Stop all current services
        stopServices()

        // Clear transport failure counts
        transportFailureCount.removeAll()

        // Set a flag to indicate Bluetooth-only mode
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Update UI to show Bluetooth-only mode
            self.hasNetworkConfigurationIssue = true
            self.networkConfigurationMessage = "Modo Bluetooth activado automáticamente debido a fallos de WiFi Direct. Las conexiones deberían ser más estables ahora."

            // Wait briefly before restarting
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }

                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                LoggingService.network.info("✅ BLUETOOTH-ONLY MODE ACTIVE")
                LoggingService.network.info("   WiFi Direct disabled automatically")
                LoggingService.network.info("   Using pure Bluetooth transport")
                LoggingService.network.info("   Connections should be more stable now")
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                // Start services again
                self.startServices()
            }
        }
    }

    // MARK: - LinkFinder Privacy Mode (On-Demand Start)

    /// Start LinkFinder session on demand when user opens LinkFinder view
    func startLinkFinderSession(with peerID: MCPeerID) {
        guard #available(iOS 14.0, *), let uwbManager = uwbSessionManager else {
            LoggingService.network.info("❌ LinkFinder not available on this device")
            return
        }

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🚀 STARTING LINKFINDER SESSION ON-DEMAND")
        LoggingService.network.info("   Target peer: \(peerID.displayName)")
        LoggingService.network.info("   Privacy mode: Only when user requests")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Check if we already have an active session
        if uwbManager.activeSessions[peerID.displayName] != nil {
            LoggingService.network.info("   ℹ️ Session already active for \(peerID.displayName)")
            return
        }

        // Determine who should initiate based on peer ID
        let shouldInitiate = self.localPeerID.displayName > peerID.displayName

        if shouldInitiate {
            LoggingService.network.info("   Role: MASTER (initiating token exchange)")
            self.uwbTokenExchangeState[peerID.displayName] = .sentToken
            self.sendUWBDiscoveryToken(to: peerID)
        } else {
            LoggingService.network.info("   Role: SLAVE (requesting token from peer)")
            // Send a request to peer to start LinkFinder
            self.requestUWBToken(from: peerID)
        }
    }

    /// Stop LinkFinder session when user leaves LinkFinder view
    func stopLinkFinderSession(with peerID: MCPeerID) {
        guard #available(iOS 14.0, *), let uwbManager = uwbSessionManager else {
            return
        }

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🛑 STOPPING LINKFINDER SESSION")
        LoggingService.network.info("   Target peer: \(peerID.displayName)")
        LoggingService.network.info("   Privacy mode: Session ended by user")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Stop the session
        uwbManager.stopSession(with: peerID)

        // Clean up exchange state
        self.uwbTokenExchangeState[peerID.displayName] = .idle
        self.uwbRetryCount[peerID.displayName] = 0
    }

    /// Request UWB token from peer (for SLAVE role)
    private func requestUWBToken(from peerID: MCPeerID) {
        let request = [
            "type": "uwb_token_request",
            "from": localPeerID.displayName,
            "timestamp": Date().timeIntervalSince1970
        ] as [String: Any]

        do {
            let data = try JSONSerialization.data(withJSONObject: request)
            try safeSend(data, toPeers: [peerID], with: .reliable, context: "uwbTokenRequest")
            LoggingService.network.info("📤 Sent UWB token request to \(peerID.displayName)")
        } catch {
            LoggingService.network.info("❌ Failed to send UWB token request: \(error)")
        }
    }

    // MARK: - Network Configuration Validation

    private func validateNetworkConfiguration() {
        // Use NetworkConfigurationDetector instead of manual monitoring
        // The detector already handles all the logic and provides @Published updates

        LoggingService.network.info("🔍 Network configuration validation using NetworkConfigurationDetector")

        // Sync initial state from detector
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.hasNetworkConfigurationIssue = self.networkConfigDetector.isProblematic
            self.networkConfigurationMessage = self.networkConfigDetector.suggestionText
        }

        // The detector is already monitoring - no need for separate NWPathMonitor
        // UI will subscribe to detector's @Published properties
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
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🧹 NetworkManager: Clearing all connections")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

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

        LoggingService.network.info("✅ NetworkManager: All connections cleared and services restarted")
    }

    @objc private func handleRestartNetworkServices() {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🔄 NetworkManager: Restarting network services")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Stop services
        stopAdvertising()
        stopBrowsing()

        // Wait a moment then restart
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startAdvertising()
            self?.startBrowsing()
            LoggingService.network.info("✅ NetworkManager: Services restarted successfully")
        }
    }

    // MARK: - Recovery and Error Handling

    private var serviceRestartTimer: Timer?
    private var lastServiceRestart = Date.distantPast
    private var lastSessionRecreation = Date.distantPast  // Track session recreation for intelligent retry delays
    private var consecutiveFailures = 0
    private var failedConnectionAttempts: [String: Int] = [:]  // Track failed attempts per peer
    private var lastPeerDiscoveryTime = Date()  // Track when we last discovered a peer
    private var waitingForInvitationFrom: [String: Date] = [:]  // Track when we started waiting for invitation
    private var invitationEventTimes: [String: Date] = [:]  // Track invitation timestamps for deduplication
    private var waitingCheckTimer: Timer?  // Timer to check for stuck waiting states

    func restartServicesIfNeeded() {
        let now = Date()
        // Increase minimum interval between restarts to 15 seconds to prevent disruptions
        let minimumRestartInterval = 15.0
        guard now.timeIntervalSince(lastServiceRestart) >= minimumRestartInterval else {
            let timeRemaining = minimumRestartInterval - now.timeIntervalSince(lastServiceRestart)
            LoggingService.network.info("⚠️ Skipping service restart - too soon (wait \(Int(timeRemaining))s)")
            return
        }

        lastServiceRestart = now

        LoggingService.network.info("🔧 NetworkManager: Restarting services to recover from errors...")

        // Stop everything cleanly
        stopServices()

        // Clear stale state and reset failure counters
        DispatchQueue.main.async { [weak self] in
            self?.availablePeers.removeAll()
            self?.connectionMutex.releaseAllLocks()
            self?.failedConnectionAttempts.removeAll()  // Reset failure tracking
            self?.waitingForInvitationFrom.removeAll()  // Clear waiting status
        }

        // Create a new session to clear any corrupted state
        // Use .optional for production (secure but flexible)
        self.session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .optional)
        LoggingService.network.info("🔒 [RESTART] Creating new session with .optional encryption")
        self.session.delegate = self

        // Restart almost immediately for faster recovery
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startServices()
            self?.consecutiveFailures = 0
            LoggingService.network.info("✅ Services restarted successfully with fresh session")
        }
    }

    private func handleConnectionFailure(with peerID: MCPeerID) {
        consecutiveFailures += 1

        // Track failures per peer
        let peerKey = peerID.displayName
        failedConnectionAttempts[peerKey] = (failedConnectionAttempts[peerKey] ?? 0) + 1
        let failCount = failedConnectionAttempts[peerKey] ?? 1

        LoggingService.network.info("⚠️ Connection failure #\(failCount) for \(peerKey)")

        // CRITICAL FIX: Recreate session IMMEDIATELY on first connection refused to prevent socket-level corruption
        // Socket Error 61 (Connection Refused) indicates iOS networking stack has blacklisted the connection
        // Only way to recover is to create a completely new MCSession on BOTH sides
        // BUT: Only if no handshakes are currently in progress (prevents interrupting active connections)
        if failCount >= 1 {
            if connectingPeers.isEmpty {
                // THROTTLING: Don't recreate session too frequently
                // iOS needs time to fully clean up between recreations
                let timeSinceLastRecreation = Date().timeIntervalSince(lastSessionRecreation)
                let minRecreationInterval: TimeInterval = 5.0  // Minimum 5 seconds between recreations

                if timeSinceLastRecreation < minRecreationInterval {
                    LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    LoggingService.network.info("⏰ SESSION RECREATION THROTTLED")
                    LoggingService.network.info("   Reason: Too soon since last recreation")
                    LoggingService.network.info("   Time since last: \(String(format: "%.1f", timeSinceLastRecreation))s")
                    LoggingService.network.info("   Minimum interval: \(minRecreationInterval)s")
                    LoggingService.network.info("   Action: Skipping recreation, will retry connection normally")
                    LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                } else {
                    LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    LoggingService.network.info("🔄 RECREATING SESSION IMMEDIATELY")
                    LoggingService.network.info("   Reason: \(failCount) connection refused (Socket Error 61)")
                    LoggingService.network.info("   iOS networking stack has blacklisted this peer")
                    LoggingService.network.info("   Session MUST be recreated to clear socket-level block")
                    LoggingService.network.info("   No handshakes in progress - safe to recreate")
                    LoggingService.network.info("   Time since last recreation: \(String(format: "%.1f", timeSinceLastRecreation))s ✅")
                    LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                    // Clear all state for this specific peer before recreating session
                    sessionManager.clearPeerState(for: peerID)
                    failedConnectionAttempts[peerKey] = 0

                    recreateSession()
                }
            } else {
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                LoggingService.network.info("⏸️ DEFERRED SESSION RECREATION")
                LoggingService.network.info("   Reason: \(failCount) connection refused with \(peerKey)")
                LoggingService.network.info("   Handshakes in progress: \(self.connectingPeers.count)")
                LoggingService.network.info("   Connecting to: \(Array(self.connectingPeers).joined(separator: ", "))")
                LoggingService.network.info("   Will recreate after current handshakes complete")
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            }
        }

        if consecutiveFailures >= 5 {
            LoggingService.network.info("⚠️ Multiple connection failures detected (5+). Initiating recovery...")
            restartServicesIfNeeded()
            failedConnectionAttempts.removeAll()  // Reset after restart
        } else {
            // INTELLIGENT RETRY DELAY SYSTEM
            // Base delay increased from 2s to 5s to give iOS more time to clean up state
            // Exponential backoff: 5s, 10s, 16s (capped at 16s)
            let baseDelay: TimeInterval = 5.0
            let exponentialDelay = baseDelay * pow(2.0, Double(min(consecutiveFailures - 1, 2)))
            var delay = min(exponentialDelay, 16.0)

            // CRITICAL FIX: Add extra delay after session recreation
            // iOS needs time to fully clean up internal MCSession state after disconnect
            // INCREASED: 15s grace period to clear Socket Error 61 blacklist (was 5s - too fast)
            let timeSinceRecreation = Date().timeIntervalSince(lastSessionRecreation)
            if timeSinceRecreation < 20.0 {
                // Session was recently recreated - add 15s grace period for iOS internal cleanup
                // This prevents mDNS resolution failures, transport layer corruption, and Socket Error 61
                // iOS networking stack needs more time to clear blacklisted peers
                let extraDelay: TimeInterval = 15.0
                delay += extraDelay
                LoggingService.network.info("⏰ Session recently recreated (\(String(format: "%.1f", timeSinceRecreation))s ago)")
                LoggingService.network.info("   Adding \(Int(extraDelay))s grace period for iOS cleanup (prevents transport corruption)")
                LoggingService.network.info("   Total delay: \(Int(delay))s")
            }

            LoggingService.network.info("⏳ Will retry connection to \(peerKey) in \(Int(delay))s (attempt #\(failCount))")

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }

                if self.availablePeers.contains(peerID) &&
                   !self.connectedPeers.contains(peerID) &&
                   self.sessionManager.shouldAttemptConnection(to: peerID) {
                    LoggingService.network.info("🔄 Retrying connection to \(peerID.displayName) after failure")
                    self.connectToPeer(peerID)  // Use proper connection method with SessionManager tracking
                }
            }
        }
    }

    /// Recreate MCSession to clear corrupted state after failed connection attempts
    /// Also performs deep cleanup of advertiser/browser and internal state
    internal func recreateSession() {
        // Print diagnostic summary before recreation
        LoggingService.network.info("🔬 CONNECTION DIAGNOSTICS BEFORE SESSION RECREATION:")
        // diagnostics.printDiagnosticSummary() // Temporarily disabled

        let oldSessionAddress = Unmanaged.passUnretained(self.session).toOpaque()

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("✨ RECREATING MC SESSION - DEEP CLEANUP")
        LoggingService.network.info("   Old session: \(self.session)")
        LoggingService.network.info("   Old session memory address: \(String(describing: oldSessionAddress))")
        LoggingService.network.info("   Connected peers before: \(self.session.connectedPeers.map { $0.displayName })")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // STEP 1: Disconnect all peers from old session
        LoggingService.network.info("   Step 1: Disconnecting old session...")
        session.disconnect()

        // STEP 2: Clear waiting states (prevents stuck invitation waits)
        LoggingService.network.info("   Step 2: Clearing waiting states...")
        waitingForInvitationFrom.removeAll()

        // STEP 3: Stop and restart advertiser/browser to clear discovery state
        // This ensures iOS MultipeerConnectivity framework fully resets
        LoggingService.network.info("   Step 3: Restarting advertiser and browser...")
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()

        // CRITICAL: Longer delay to let iOS networking stack FULLY clean up
        // Socket Error 61 requires complete TCP/IP stack reset
        // 0.5s gives iOS time to:
        // - Close all socket file descriptors
        // - Clear TCP connection tables
        // - Reset Bonjour/mDNS state
        // - Flush any buffered packets
        Thread.sleep(forTimeInterval: 0.5)

        advertiser?.startAdvertisingPeer()
        browser?.startBrowsingForPeers()

        // STEP 4: Create fresh session with same encryption preference
        LoggingService.network.info("   Step 4: Creating new session...")
        let oldEncryption = self.session.encryptionPreference
        self.session = MCSession(
            peer: localPeerID,
            securityIdentity: nil,
            encryptionPreference: oldEncryption
        )
        self.session.delegate = self

        // STEP 5: Record recreation timestamp for intelligent retry delays
        lastSessionRecreation = Date()

        let newSessionAddress = Unmanaged.passUnretained(self.session).toOpaque()

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("✅ SESSION RECREATION COMPLETE")
        LoggingService.network.info("   New session: \(self.session)")
        LoggingService.network.info("   New session memory address: \(String(describing: newSessionAddress))")
        LoggingService.network.info("   Session changed: \(oldSessionAddress != newSessionAddress ? "✅ YES" : "❌ NO (BUG!)")")
        LoggingService.network.info("   Encryption: \(oldEncryption == .required ? ".required" : oldEncryption == .optional ? ".optional" : ".none")")
        LoggingService.network.info("   Advertiser/Browser: Restarted")
        LoggingService.network.info("   Waiting states: Cleared")
        LoggingService.network.info("   State: Fully clean (ready for fresh handshake)")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
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
                        LoggingService.network.info("❌ Failed to send ping to \(peer.displayName): \(error.localizedDescription)")
                    }
                }
            }

            // Check if we've been disconnected
            if self.connectedPeers.isEmpty {
                if self.availablePeers.isEmpty {
                    // No peers at all - wait longer before restarting (20 seconds)
                    // BUT: Don't restart if we're waiting for an invitation (advertiser must stay up)
                    // ⚡ ULTRA-FAST: Keep advertiser always running in Lightning Mode
                    let isWaitingForInvitation = !self.waitingForInvitationFrom.isEmpty
                    let isUltraFast = self.isUltraFastModeEnabled

                    if isWaitingForInvitation || isUltraFast {
                        if isUltraFast {
                            LoggingService.network.info("⚡ ULTRA-FAST: Keeping advertiser alive for instant connections")
                        } else {
                            LoggingService.network.info("⏸️ No auto-restart: Waiting for invitation from \(self.waitingForInvitationFrom.count) peer(s)")
                            LoggingService.network.info("   Advertiser must stay alive to receive incoming connections")
                        }
                    } else if now.timeIntervalSince(self.lastServiceRestart) > 20.0 {
                        LoggingService.network.info("⚠️ No peers found for 20 seconds. Auto-restarting...")
                        self.restartServicesIfNeeded()
                    }
                } else {
                    // Have available peers but can't connect - wait much longer before restarting
                    self.consecutiveFailures += 1
                    if self.consecutiveFailures >= 6 {  // Restart after 6 failures (3 minutes with 30s timer)
                        LoggingService.network.info("⚠️ Multiple connection failures. Auto-restarting...")
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
                    LoggingService.network.info("🔄 No peers in 30s. Force restarting...")
                    self.restartServicesIfNeeded()
                }
            }
        }
    }

    private func startAdvertiserHealthCheck() {
        // ⚡ Check advertiser health every 5 seconds
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            // Only check if we're supposed to be advertising
            if self.advertiser != nil {
                // Verify advertiser delegate is still set (iOS bug sometimes clears it)
                if self.advertiser?.delegate == nil {
                    LoggingService.network.info("⚠️ ADVERTISER DEAD - Delegate was nil!")
                    LoggingService.network.info("   Restarting advertiser to restore incoming connections...")

                    // Restart advertiser
                    self.stopAdvertising()
                    self.startAdvertising()
                    LoggingService.network.info("✅ Advertiser restarted")
                }

                // In Ultra-Fast mode, ensure advertiser is always running
                if self.isUltraFastModeEnabled && self.advertiser == nil {
                    LoggingService.network.info("⚡ ULTRA-FAST: Restarting advertiser (should always be active)")
                    self.startAdvertising()
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

            // Progressive timeout: 15s, 16s, 17s...
            // MultipeerConnectivity can take 10-15s for Bluetooth handshake
            let failureCount = failedConnectionAttempts[peerKey] ?? 0
            let baseTimeout = 15.0  // Extended to allow Bluetooth handshake to complete
            let timeoutThreshold = baseTimeout + (Double(min(failureCount, 3)) * 1.0)

            // Cap maximum wait time at 20 seconds (allow for slow Bluetooth handshakes)
            let effectiveThreshold = min(timeoutThreshold, 20.0)

            if waitDuration > effectiveThreshold {
                stuckPeers.append(peerKey)
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                LoggingService.network.info("⚠️ STUCK WAITING DETECTED")
                LoggingService.network.info("   Peer: \(peerKey)")
                LoggingService.network.info("   Waiting Duration: \(Int(waitDuration))s")
                LoggingService.network.info("   Threshold: \(Int(effectiveThreshold))s")
                LoggingService.network.info("   Previous Failures: \(failureCount)")
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            }
        }

        // Force reconnect to stuck peers
        for peerKey in stuckPeers {
            // Check if already connected (don't force reconnect if connected)
            if connectedPeers.contains(where: { $0.displayName == peerKey }) {
                LoggingService.network.info("✓ Peer \(peerKey) already connected - cleaning up stuck waiting state")
                waitingForInvitationFrom.removeValue(forKey: peerKey)
                continue
            }

            // CRITICAL: Check if peer is currently in .connecting state
            // If so, handshake is in progress - DO NOT force reconnect
            if connectingPeers.contains(peerKey) {
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                LoggingService.network.info("⏸️ NOT FORCING RECONNECT")
                LoggingService.network.info("   Peer: \(peerKey)")
                LoggingService.network.info("   Reason: Handshake in progress (.connecting state)")
                LoggingService.network.info("   Waiting for MultipeerConnectivity to complete...")
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                continue
            }

            waitingForInvitationFrom.removeValue(forKey: peerKey)

            // Find the peer and force connect
            if let peer = availablePeers.first(where: { $0.displayName == peerKey }) {
                // Check if mutex has active operation
                if connectionMutex.hasActiveOperation(for: peer) {
                    LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    LoggingService.network.info("⏸️ NOT FORCING RECONNECT")
                    LoggingService.network.info("   Peer: \(peerKey)")
                    LoggingService.network.info("   Reason: Active mutex operation in progress")
                    LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    continue
                }
                LoggingService.network.info("🔄 FORCE RECONNECT: Overriding conflict resolution for \(peerKey)")

                // Log conflict resolution status for debugging
                let wouldNormallyInitiate = ConnectionConflictResolver.shouldInitiateConnection(localPeer: localPeerID, remotePeer: peer)
                LoggingService.network.info("   Normal conflict resolution: \(wouldNormallyInitiate ? "WOULD INITIATE" : "WOULD WAIT")")
                LoggingService.network.info("   Now forcing connection regardless")

                // Clear any session manager blocks
                sessionManager.clearCooldown(for: peer)

                // Increment failure count (for progressive timeout)
                let currentFailures = failedConnectionAttempts[peerKey] ?? 0
                failedConnectionAttempts[peerKey] = currentFailures + 1

                // Force immediate connection, bypassing conflict resolution
                connectToPeer(peer, forceIgnoreConflictResolution: true)
            } else {
                LoggingService.network.info("⚠️ Cannot force reconnect to \(peerKey) - peer not available")
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

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🔄 FORCE RESET: Clearing all state for \(peerKey)")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // 1. Cancel any pending connection operations
        session.cancelConnectPeer(peerID)
        LoggingService.network.info("   ✓ Cancelled pending connections")

        // 2. Force release mutex lock
        connectionMutex.forceRelease(for: peerID)
        LoggingService.network.info("   ✓ Released mutex lock")

        // 3. Clear waiting state
        waitingForInvitationFrom.removeValue(forKey: peerKey)
        LoggingService.network.info("   ✓ Cleared waiting state")

        // 4. Clear session manager cooldown
        sessionManager.clearCooldown(for: peerID)
        LoggingService.network.info("   ✓ Cleared session cooldown")

        // 5. Reset failure counts
        failedConnectionAttempts.removeValue(forKey: peerKey)
        LoggingService.network.info("   ✓ Reset failure count")

        // 6. Attempt fresh connection if peer is still available
        if availablePeers.contains(where: { $0.displayName == peerKey }) {
            LoggingService.network.info("   🔄 Peer still available, attempting fresh connection...")

            // Wait briefly for MultipeerConnectivity to clean up internal state
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                LoggingService.network.info("   📤 Initiating fresh connection to \(peerKey)")
                self.connectToPeer(peerID, forceIgnoreConflictResolution: true)
            }
        } else {
            LoggingService.network.info("   ⚠️ Peer no longer available, reset complete")
        }

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
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

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("📤 SENDING NEW MESSAGE")
        LoggingService.network.info("   From: \(self.localPeerID.displayName)")
        LoggingService.network.info("   To: \(recipientId)")
        LoggingService.network.info("   Content: \"\(content)\"")
        LoggingService.network.info("   Type: \(type.displayName)")
        LoggingService.network.info("   Priority: \(networkMessage.priority)")
        LoggingService.network.info("   Requires ACK: \(requiresAck)")
        LoggingService.network.info("   Conversation Type: \(conversationDescriptor.conversationType)")
        LoggingService.network.info("   Conversation ID: \(conversationDescriptor.id)")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    // MARK: - Safe Send Helper
    // NOTE: Implementation moved to NetworkManager+Diagnostics.swift
    // This section is commented to avoid duplication

    /*
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
            LoggingService.network.info("⚠️ safeSend\(contextStr): No valid peers in session")
            LoggingService.network.info("   Requested: \(peers.map { $0.displayName })")
            LoggingService.network.info("   Session has: \(sessionPeers.map { $0.displayName })")
            throw NSError(
                domain: "NetworkManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Peers (\(peers.map { $0.displayName })) not connected"]
            )
        }

        // Log if we filtered out some peers
        if validPeers.count < peers.count {
            let filtered = peers.filter { !validPeers.contains($0) }
            LoggingService.network.info("⚠️ safeSend: Filtered out \(filtered.count) disconnected peers: \(filtered.map { $0.displayName })")
        }

        // Send to validated peers only
        try session.send(data, toPeers: validPeers, with: mode)
    }
    */

    // MARK: - Transport Diagnostics
    // NOTE: Diagnostics implementation moved to NetworkManager+Diagnostics.swift

    /// Track connection success/failure for transport layer diagnostics
    var connectionMetrics: [String: ConnectionMetrics] = [:]

    // Transport failure detection and automatic fallback
    var transportFailureCount: [String: Int] = [:]
    let maxTransportFailuresBeforeFallback = 2
    var isBluetoothOnlyMode = false

    // NOTE: struct ConnectionMetrics moved to NetworkManager+Diagnostics.swift
    /*
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
    */

    // NOTE: recordConnectionMetrics, ConnectionMetricEvent, and logTransportDiagnostics moved to NetworkManager+Diagnostics.swift
    /*
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
            LoggingService.network.info("⚠️ UNSTABLE CONNECTION DETECTED: \(peer.displayName)")
            logTransportDiagnostics(for: peer)

            // Check for transport failure (very short connection)
            if let connectionEstablished = metrics.connectionEstablished,
               let lastDisconnect = metrics.lastDisconnect {
                let connectionDuration = lastDisconnect.timeIntervalSince(connectionEstablished)

                if connectionDuration < 15.0 {
                    // This was a transport failure
                    transportFailureCount[peerKey] = (transportFailureCount[peerKey] ?? 0) + 1

                    LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    LoggingService.network.info("🚨 TRANSPORT FAILURE #\(self.transportFailureCount[peerKey] ?? 1) for \(peerKey)")
                    LoggingService.network.info("   Connection lasted only \(String(format: "%.1f", connectionDuration))s")

                    // Enable Lightning Mode Ultra-Fast for immediate reconnections
                    if !UserDefaults.standard.bool(forKey: "lightningModeUltraFast") {
                        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        LoggingService.network.info("⚡ ENABLING LIGHTNING MODE ULTRA-FAST")
                        LoggingService.network.info("   Reason: Transport failure detected")
                        LoggingService.network.info("   Action: Zero cooldowns for instant reconnection")
                        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                        UserDefaults.standard.set(true, forKey: "lightningModeUltraFast")
                    }

                    // Check if we should enable Bluetooth-only mode
                    if !isBluetoothOnlyMode &&
                       (transportFailureCount[peerKey] ?? 0) >= maxTransportFailuresBeforeFallback {
                        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        LoggingService.network.info("🔄 ENABLING BLUETOOTH-ONLY MODE")
                        LoggingService.network.info("   Reason: \(self.transportFailureCount[peerKey] ?? 0) consecutive transport failures")
                        LoggingService.network.info("   Action: Restarting services in Bluetooth-only mode")
                        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                        isBluetoothOnlyMode = true

                        // Restart the services to force Bluetooth-only mode
                        DispatchQueue.main.async { [weak self] in
                            self?.restartServicesInBluetoothMode()
                        }
                    }
                    LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                }
            }
        }
    }

    // NOTE: enum ConnectionMetricEvent moved to NetworkManager+Diagnostics.swift
    /*
    enum ConnectionMetricEvent {
        case sendSuccess
        case sendFailure
        case socketTimeout
        case connected
        case disconnected
    }
    */

    /// Log detailed transport layer diagnostics when issues are detected
    private func logTransportDiagnostics(for peer: MCPeerID) {
        let peerKey = peer.displayName
        guard let metrics = connectionMetrics[peerKey] else { return }

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("📊 TRANSPORT LAYER DIAGNOSTICS")
        LoggingService.network.info("   Peer: \(peer.displayName)")
        LoggingService.network.info("   Successful sends: \(metrics.successfulSends)")
        LoggingService.network.info("   Failed sends: \(metrics.failedSends)")
        LoggingService.network.info("   Disconnect count: \(metrics.disconnectCount)")
        if let duration = metrics.connectionDuration {
            LoggingService.network.info("   Connection duration: \(String(format: "%.1f", duration))s")
        }
        if let lastTimeout = metrics.lastSocketTimeout {
            LoggingService.network.info("   Last socket timeout: \(lastTimeout)")
        }
        LoggingService.network.info("   Is unstable: \(metrics.isUnstable)")
        LoggingService.network.info("   ")
        LoggingService.network.info("🔍 PROBABLE CAUSES:")
        LoggingService.network.info("   ")

        // Diagnose based on metrics
        if let established = metrics.connectionEstablished,
           let lastDisconnect = metrics.lastDisconnect,
           lastDisconnect.timeIntervalSince(established) < 15 {
            LoggingService.network.info("   ❌ VERY SHORT CONNECTION (<15s)")
            LoggingService.network.info("      → WiFi Direct transport likely failing")
            LoggingService.network.info("      → TCP socket timing out after handshake")
            LoggingService.network.info("      → Data channel establishment failing")
        }

        if metrics.lastSocketTimeout != nil {
            LoggingService.network.info("   ❌ SOCKET TIMEOUT DETECTED")
            LoggingService.network.info("      → TCP connection established but data transfer failed")
            LoggingService.network.info("      → Network path switched mid-connection")
            LoggingService.network.info("      → WiFi Direct → Bluetooth fallback not working")
        }

        if metrics.disconnectCount > 3 {
            LoggingService.network.info("   ❌ MULTIPLE DISCONNECTS (\(metrics.disconnectCount))")
            LoggingService.network.info("      → Connection establishment works")
            LoggingService.network.info("      → But transport layer is unstable")
            LoggingService.network.info("      → Likely WiFi interference or weak Bluetooth")
        }

        LoggingService.network.info("   ")
        LoggingService.network.info("💡 RECOMMENDED ACTIONS:")
        if hasNetworkConfigurationIssue {
            LoggingService.network.info("   1. ⚠️ Fix WiFi configuration (connect to network or disable)")
        } else {
            LoggingService.network.info("   1. Try disabling WiFi to force Bluetooth-only mode")
            LoggingService.network.info("   2. Move devices closer together (< 10m)")
            LoggingService.network.info("   3. Check for WiFi/Bluetooth interference")
        }
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
    */

    private func sendNetworkMessage(_ message: NetworkMessage) {
        guard !connectedPeers.isEmpty else {
            LoggingService.network.info("⚠️ NetworkManager: No connected peers to send message to")
            return
        }

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("📤 SENDING NETWORK MESSAGE")
        LoggingService.network.info("   Message ID: \(message.id.uuidString.prefix(8))")
        LoggingService.network.info("   From: \(message.senderId)")
        LoggingService.network.info("   To: \(message.recipientId)")
        LoggingService.network.info("   Type: \(message.messageType.displayName)")
        LoggingService.network.info("   Hop Count: \(message.hopCount)/\(message.ttl)")
        LoggingService.network.info("   Route Path: \(message.routePath.joined(separator: " → "))")
        LoggingService.network.info("   Connected Peers: \(self.connectedPeers.map { $0.displayName })")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        var targetPeers: [MCPeerID]

        // INTELLIGENT ROUTING: Hierarchical routing strategy
        if message.recipientId != "broadcast" {
            // Check if recipient is directly connected
            if let directPeer = connectedPeers.first(where: { $0.displayName == message.recipientId }) {
                targetPeers = [directPeer]
                LoggingService.network.info("🎯 Direct connection to recipient")
            }
            // Check RouteCache (AODV-discovered routes) - most efficient
            else if let route = routeCache.findRoute(to: message.recipientId) {
                LoggingService.network.info("🚀 [RouteCache] Using discovered route: \(route.hopCount) hops via \(route.nextHop)")
                sendDirectMessage(message, via: route.nextHop)
                return // Exit early - direct routing handled
            }
            // Check RoutingTable (topology-based BFS routes)
            else if let nextHopNames = routingTable.getNextHops(to: message.recipientId) {
                // Recipient is reachable indirectly - send only to next hops
                targetPeers = connectedPeers.filter { nextHopNames.contains($0.displayName) }
                LoggingService.network.info("🗺️ Using routing table - next hops: [\(nextHopNames.joined(separator: ", "))]")
            }
            // No route found - fallback to broadcast
            else {
                targetPeers = connectedPeers
                LoggingService.network.info("⚠️ No route found - broadcasting to all peers")
            }
        } else {
            // Broadcast message
            targetPeers = connectedPeers
            LoggingService.network.info("📢 Broadcasting to all peers")
        }

        // INTELLIGENT DISCONNECTION: Filter out peers marked as pendingDisconnect
        // These peers should not receive or relay messages
        // NOTE: Already executing on processingQueue (via processMessageQueue), safe to access peerConnectionStates directly
        let blockedPeers = peerConnectionStates
            .filter { $0.value == .pendingDisconnect }
            .map { $0.key }

        if !blockedPeers.isEmpty {
            let originalCount = targetPeers.count
            targetPeers = targetPeers.filter { !blockedPeers.contains($0.displayName) }
            let filteredCount = originalCount - targetPeers.count

            if filteredCount > 0 {
                LoggingService.network.info("🚫 Filtered \(filteredCount) peer(s) in pendingDisconnect state:")
                LoggingService.network.info("   Blocked: [\(blockedPeers.joined(separator: ", "))]")
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
                LoggingService.network.info("🧪 TEST MODE: Forcing multi-hop - Allowed peers: \(targetPeers.map { $0.displayName })")
            }
        }

        let payload = NetworkPayload.message(message)

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(payload)
            try safeSend(data, toPeers: targetPeers, with: .reliable, context: "sendNetworkMessage")
            LoggingService.network.info("📤 Sent to \(targetPeers.count) peers - Type: \(message.messageType.displayName)")
        } catch {
            LoggingService.network.info("❌ Failed to send message: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                LoggingService.network.info("   Error: [\(nsError.domain)] Code \(nsError.code)")
            }
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
            LoggingService.network.info("📬 ACK sent for message \(originalMessageId) to \(senderId)")
        } catch {
            LoggingService.network.info("❌ Failed to send ACK: \(error.localizedDescription)")
        }
    }

    // MARK: - Route Discovery Protocol (AODV-like)

    /// Initiate route discovery for a destination peer
    /// - Parameters:
    ///   - destination: Destination peer ID
    ///   - timeout: Discovery timeout (default 10 seconds)
    ///   - completion: Called with RouteInfo if found, nil on timeout
    func initiateRouteDiscovery(to destination: String,
                                timeout: TimeInterval = 10.0,
                                completion: @escaping (RouteInfo?) -> Void) {

        // Check if route already exists in cache
        if let existingRoute = routeCache.findRoute(to: destination) {
            LoggingService.network.info("🎯 [RouteDiscovery] Route already cached for \(destination)")
            completion(existingRoute)
            return
        }

        // Create RREQ
        let rreq = RouteRequest(
            origin: localPeerID.displayName,
            destination: destination,
            hopCount: 0,
            routePath: [localPeerID.displayName]
        )

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🔍 [RouteDiscovery] INITIATING")
        LoggingService.network.info("   Origin: \(self.localPeerID.displayName)")
        LoggingService.network.info("   Destination: \(destination)")
        LoggingService.network.info("   Request ID: \(rreq.requestID.uuidString.prefix(8))")
        LoggingService.network.info("   Timeout: \(timeout)s")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Store completion handler
        routeDiscoveryQueue.async(flags: .barrier) { [weak self] in
            self?.pendingRouteDiscoveries[rreq.requestID] = completion
        }

        // Broadcast RREQ
        broadcastRouteRequest(rreq)

        // Set timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self = self else { return }

            self.routeDiscoveryQueue.async(flags: .barrier) {
                if let completion = self.pendingRouteDiscoveries.removeValue(forKey: rreq.requestID) {
                    LoggingService.network.info("⏰ [RouteDiscovery] TIMEOUT for \(destination)")
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                }
            }
        }
    }

    /// Broadcast a route request to all connected peers
    private func broadcastRouteRequest(_ rreq: RouteRequest) {
        let payload = NetworkPayload.routeRequest(rreq)

        do {
            let data = try JSONEncoder().encode(payload)
            try safeSend(data, toPeers: connectedPeers, with: .reliable, context: "broadcastRREQ")
            LoggingService.network.info("📢 [RouteDiscovery] RREQ broadcast to \(self.connectedPeers.count) peers")
        } catch {
            LoggingService.network.info("❌ [RouteDiscovery] Failed to broadcast RREQ: \(error)")
        }
    }

    /// Handle received route request
    func handleRouteRequest(_ rreq: RouteRequest, from peer: MCPeerID) {
        // Check if already processed (deduplicate)
        let cacheKey = "\(rreq.requestID.uuidString)-RREQ"
        if messageCache.contains(cacheKey) {
            LoggingService.network.info("🔁 [RouteDiscovery] RREQ already processed, ignoring")
            return
        }
        messageCache.add(cacheKey)

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("📥 [RouteDiscovery] RREQ RECEIVED")
        LoggingService.network.info("   From: \(peer.displayName)")
        LoggingService.network.info("   Origin: \(rreq.origin)")
        LoggingService.network.info("   Destination: \(rreq.destination)")
        LoggingService.network.info("   Hop Count: \(rreq.hopCount)")
        LoggingService.network.info("   Path: \(rreq.routePath.joined(separator: "→"))")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Update RREQ with my hop
        var updatedRREQ = rreq
        updatedRREQ.routePath.append(localPeerID.displayName)
        updatedRREQ.hopCount += 1

        // Case 1: Am I the destination?
        if rreq.destination == localPeerID.displayName {
            LoggingService.network.info("🎯 [RouteDiscovery] I am the destination! Sending RREP")
            sendRouteReply(for: updatedRREQ, via: peer)
            return
        }

        // Case 2: Do I have direct connection to destination?
        if let destinationPeer = connectedPeers.first(where: { $0.displayName == rreq.destination }) {
            LoggingService.network.info("🎯 [RouteDiscovery] Have direct connection to \(rreq.destination)! Sending RREP")
            updatedRREQ.routePath.append(rreq.destination)
            updatedRREQ.hopCount += 1
            sendRouteReply(for: updatedRREQ, via: peer)
            return
        }

        // Case 3: Propagate RREQ if TTL allows
        if updatedRREQ.hopCount < 7 { // Higher TTL for discovery
            LoggingService.network.info("🔄 [RouteDiscovery] Propagating RREQ to neighbors")
            broadcastRouteRequest(updatedRREQ)
        } else {
            LoggingService.network.info("❌ [RouteDiscovery] TTL reached, discarding RREQ")
        }
    }

    /// Send route reply back to origin
    private func sendRouteReply(for rreq: RouteRequest, via sourcePeer: MCPeerID) {
        let rrep = RouteReply(
            requestID: rreq.requestID,
            destination: rreq.destination,
            routePath: rreq.routePath,
            hopCount: rreq.hopCount
        )

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("📤 [RouteDiscovery] SENDING RREP")
        LoggingService.network.info("   Complete Path: \(rrep.routePath.joined(separator: "→"))")
        LoggingService.network.info("   Total Hops: \(rrep.hopCount)")
        LoggingService.network.info("   Sending to: \(sourcePeer.displayName)")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        let payload = NetworkPayload.routeReply(rrep)

        do {
            let data = try JSONEncoder().encode(payload)
            try safeSend(data, toPeers: [sourcePeer], with: .reliable, context: "sendRREP")
            LoggingService.network.info("✅ [RouteDiscovery] RREP sent")
        } catch {
            LoggingService.network.info("❌ [RouteDiscovery] Failed to send RREP: \(error)")
        }
    }

    /// Handle received route reply
    func handleRouteReply(_ rrep: RouteReply, from peer: MCPeerID) {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("📥 [RouteDiscovery] RREP RECEIVED")
        LoggingService.network.info("   From: \(peer.displayName)")
        LoggingService.network.info("   Destination: \(rrep.destination)")
        LoggingService.network.info("   Path: \(rrep.routePath.joined(separator: "→"))")
        LoggingService.network.info("   Hops: \(rrep.hopCount)")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Find my position in the path
        guard let myIndex = rrep.routePath.firstIndex(of: localPeerID.displayName) else {
            LoggingService.network.info("⚠️ [RouteDiscovery] Not in path, ignoring RREP")
            return
        }

        // Update my route cache
        let destination = rrep.routePath.last!
        let nextHop = rrep.routePath[myIndex + 1]
        let hopsToDestination = rrep.routePath.count - myIndex - 1

        let routeInfo = RouteInfo(
            destination: destination,
            nextHop: nextHop,
            hopCount: hopsToDestination,
            timestamp: Date(),
            fullPath: rrep.routePath
        )

        routeCache.addRoute(routeInfo)
        LoggingService.network.info("📍 [RouteDiscovery] Route learned: \(destination) is \(hopsToDestination) hops via \(nextHop)")

        // Am I the origin?
        if myIndex == 0 {
            LoggingService.network.info("🎉 [RouteDiscovery] DISCOVERY COMPLETE!")

            routeDiscoveryQueue.async(flags: .barrier) { [weak self] in
                if let completion = self?.pendingRouteDiscoveries.removeValue(forKey: rrep.requestID) {
                    DispatchQueue.main.async {
                        completion(routeInfo)
                    }
                }
            }
        } else {
            // Propagate RREP toward origin
            let prevHop = rrep.routePath[myIndex - 1]
            guard let prevPeer = connectedPeers.first(where: { $0.displayName == prevHop }) else {
                LoggingService.network.info("⚠️ [RouteDiscovery] Cannot find previous hop: \(prevHop)")
                return
            }

            LoggingService.network.info("🔄 [RouteDiscovery] Propagating RREP to \(prevHop)")

            let payload = NetworkPayload.routeReply(rrep)
            do {
                let data = try JSONEncoder().encode(payload)
                try safeSend(data, toPeers: [prevPeer], with: .reliable, context: "propagateRREP")
            } catch {
                LoggingService.network.info("❌ [RouteDiscovery] Failed to propagate RREP: \(error)")
            }
        }
    }

    /// Send route error when a route breaks
    private func sendRouteError(destination: String, brokenNextHop: String) {
        let rerr = RouteError(
            destination: destination,
            brokenNextHop: brokenNextHop
        )

        LoggingService.network.info("🚨 [RouteDiscovery] Sending RERR for \(destination) (broken link: \(brokenNextHop))")

        let payload = NetworkPayload.routeError(rerr)

        do {
            let data = try JSONEncoder().encode(payload)
            try safeSend(data, toPeers: connectedPeers, with: .reliable, context: "sendRERR")
        } catch {
            LoggingService.network.info("❌ [RouteDiscovery] Failed to send RERR: \(error)")
        }
    }

    /// Handle received route error
    func handleRouteError(_ rerr: RouteError, from peer: MCPeerID) {
        LoggingService.network.info("🚨 [RouteDiscovery] RERR received: \(rerr.destination) unreachable via \(rerr.brokenNextHop)")

        // Remove affected routes from cache
        if let route = routeCache.findRoute(to: rerr.destination),
           route.nextHop == rerr.brokenNextHop {
            routeCache.removeRoute(to: rerr.destination)
            LoggingService.network.info("🗑️ [RouteDiscovery] Removed broken route to \(rerr.destination)")
        }

        // Propagate RERR to neighbors
        let payload = NetworkPayload.routeError(rerr)
        do {
            let data = try JSONEncoder().encode(payload)
            let peersToNotify = connectedPeers.filter { $0.displayName != peer.displayName }
            try safeSend(data, toPeers: peersToNotify, with: .reliable, context: "propagateRERR")
        } catch {
            LoggingService.network.info("❌ [RouteDiscovery] Failed to propagate RERR: \(error)")
        }
    }

    /// Send message directly via a specific next hop (using discovered route)
    /// - Parameters:
    ///   - message: Message to send
    ///   - nextHopName: Next hop peer ID from route cache
    private func sendDirectMessage(_ message: NetworkMessage, via nextHopName: String) {
        guard let nextPeer = connectedPeers.first(where: { $0.displayName == nextHopName }) else {
            LoggingService.network.info("⚠️ [DirectRouting] NextHop \(nextHopName) not connected")

            // Route is invalid, remove from cache
            routeCache.removeRoute(to: message.recipientId)
            sendRouteError(destination: message.recipientId, brokenNextHop: nextHopName)

            // Fallback to broadcast
            LoggingService.network.info("🔄 [DirectRouting] Falling back to broadcast")
            sendNetworkMessage(message)
            return
        }

        var messageToSend = message
        messageToSend.addHop(localPeerID.displayName)

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🎯 [DirectRouting] SENDING DIRECT")
        LoggingService.network.info("   Next Hop: \(nextHopName)")
        LoggingService.network.info("   Final Dest: \(message.recipientId)")
        LoggingService.network.info("   Hop Count: \(messageToSend.hopCount)/\(messageToSend.ttl)")
        LoggingService.network.info("   Content: \"\(message.content.prefix(30))...\"")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        let payload = NetworkPayload.message(messageToSend)

        do {
            let data = try JSONEncoder().encode(payload)
            try safeSend(data, toPeers: [nextPeer], with: .reliable, context: "sendDirectMessage")
            LoggingService.network.info("✅ [DirectRouting] Sent to \(nextHopName)")
        } catch {
            LoggingService.network.info("❌ [DirectRouting] Failed to send: \(error)")

            // Route failed, invalidate and retry
            routeCache.removeRoute(to: message.recipientId)
            sendRouteError(destination: message.recipientId, brokenNextHop: nextHopName)
        }
    }

    /// Send raw data to a specific peer (for keep-alive pings, etc.)
    /// This is a low-level helper used by KeepAliveManager and other background services
    func sendRawData(_ data: Data, to peer: MCPeerID, reliable: Bool = false) {
        do {
            let mode: MCSessionSendDataMode = reliable ? .reliable : .unreliable
            try safeSend(data, toPeers: [peer], with: mode, context: "sendRawData")
        } catch {
            LoggingService.network.info("❌ Failed to send raw data to \(peer.displayName): \(error.localizedDescription)")
        }
    }

    // MARK: - Adaptive Invitation Timeout

    /// Calculate optimal invitation timeout based on mode, peer history, and attempt count
    private func calculateInvitationTimeout(for peer: MCPeerID, attempt: Int = 0) -> TimeInterval {
        // Base timeout depends on mode
        let baseTimeout: TimeInterval = isUltraFastModeEnabled ? 15.0 : 30.0

        // Adjust based on peer latency (if available)
        var latencyAdjustment: TimeInterval = 0.0
        if let stats = healthMonitor.getHealthStats(for: peer) {
            // Add up to 10 seconds for high-latency peers
            latencyAdjustment = min(stats.latency / 100.0, 10.0)
        }

        // Increase timeout for subsequent attempts (with cap)
        let attemptMultiplier = 1.0 + (0.5 * Double(min(attempt, 3)))

        // Final timeout with 45s cap
        let calculatedTimeout = (baseTimeout + latencyAdjustment) * attemptMultiplier
        let finalTimeout = min(calculatedTimeout, 45.0)

        return finalTimeout
    }

    func connectToPeer(_ peerID: MCPeerID, forceIgnoreConflictResolution: Bool = false) {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🔗 CONNECT TO PEER - STEP 1: Entry")
        LoggingService.network.info("   Peer: \(peerID.displayName)")
        LoggingService.network.info("   Force: \(forceIgnoreConflictResolution)")
        LoggingService.network.info("   Timestamp: \(Date())")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // DIAGNOSTIC: Check network configuration before attempting connection
        let networkStatus = networkConfigDetector.currentStatus
        LoggingService.network.info("   📡 Network Status: \(networkStatus.rawValue)")
        if networkStatus.isProblematic {
            LoggingService.network.warning("   ⚠️ PROBLEMATIC NETWORK CONFIG: \(networkStatus.suggestion)")
            LoggingService.network.warning("   ⚠️ Connection may fail due to: \(networkStatus.explanation)")
        }

        guard let browser = browser else {
            LoggingService.network.info("❌ CONNECT FAILED: Browser not available")
            return
        }
        LoggingService.network.info("   ✓ Browser available")

        // Check if peer is manually blocked
        LoggingService.network.info("   Step 2: Checking manual blocking...")
        if connectionManager.isPeerBlocked(peerID.displayName) {
            LoggingService.network.info("🚫 CONNECT ABORTED: Peer \(peerID.displayName) is manually blocked")
            return
        }
        LoggingService.network.info("   ✓ Not manually blocked")

        // Check for bidirectional mode (Connection refused recovery only - Ultra-Fast disabled)
        LoggingService.network.info("   Step 2.5: Checking bidirectional mode...")
        // FIXED: Removed isUltraFastModeEnabled to prevent race conditions
        // Bidirectional mode now only activates after actual connection failures
        let useBidirectionalMode = sessionManager.shouldUseBidirectionalConnection(for: peerID) // || isUltraFastModeEnabled
        if useBidirectionalMode {
            LoggingService.network.info("   🔀 BIDIRECTIONAL MODE ACTIVE for \(peerID.displayName)")
            LoggingService.network.info("      Previous connection attempts failed with 'Connection refused'")
            LoggingService.network.info("      Both peers will attempt connection simultaneously")
        }

        // Check conflict resolution (unless forcing or bidirectional mode)
        LoggingService.network.info("   Step 3: Checking conflict resolution...")
        if !forceIgnoreConflictResolution && !useBidirectionalMode {
            let shouldInitiate = ConnectionConflictResolver.shouldInitiateConnection(localPeer: localPeerID, remotePeer: peerID, overrideBidirectional: useBidirectionalMode)
            LoggingService.network.info("      Should initiate: \(shouldInitiate)")
            LoggingService.network.info("      Local ID: \(self.localPeerID.displayName)")
            LoggingService.network.info("      Remote ID: \(peerID.displayName)")
            guard shouldInitiate else {
                LoggingService.network.info("🆔 CONNECT ABORTED: Conflict resolution says we should defer to \(peerID.displayName)")
                return
            }
        } else if forceIgnoreConflictResolution {
            LoggingService.network.info("⚡ FORCING connection - bypassing conflict resolution")
        } else if useBidirectionalMode {
            LoggingService.network.info("🔀 BIDIRECTIONAL MODE - bypassing conflict resolution")
        }
        LoggingService.network.info("   ✓ Conflict resolution passed")

        // Acquire mutex lock to serialize invites
        LoggingService.network.info("   Step 4: Acquiring ConnectionMutex lock...")
        guard connectionMutex.tryAcquireLock(for: peerID, operation: .browserInvite) else {
            LoggingService.network.info("🔒 CONNECT ABORTED: Connection operation already in progress for \(peerID.displayName)")
            return
        }
        LoggingService.network.info("   ✓ Mutex lock acquired")

        var lockReleased = false
        let releaseLock: () -> Void = { [weak self] in
            guard let self = self, !lockReleased else { return }
            lockReleased = true
            self.connectionMutex.releaseLock(for: peerID)
            LoggingService.network.info("   🔓 Mutex lock released for \(peerID.displayName)")
        }

        LoggingService.network.info("   Step 5: Checking SessionManager...")
        let sessionManagerAllows = sessionManager.shouldAttemptConnection(to: peerID)
        LoggingService.network.info("      SessionManager allows: \(sessionManagerAllows)")
        guard sessionManagerAllows else {
            LoggingService.network.info("⏸️ CONNECT ABORTED: SessionManager blocking connection to \(peerID.displayName)")
            releaseLock()
            return
        }
        LoggingService.network.info("   ✓ SessionManager allows")

        LoggingService.network.info("   Step 6: Recording connection attempt...")
        sessionManager.recordConnectionAttempt(to: peerID)
        LoggingService.network.info("   ✓ Attempt recorded")

        // ⏱️ ADAPTIVE TIMEOUT: Calculate dynamic timeout based on peer latency and attempt count
        let attemptCount = 0 // Use default attempt count
        let adaptiveTimeout = calculateInvitationTimeout(for: peerID, attempt: attemptCount)

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("📤 BROWSER.INVITEPEER() - STEP 7: Calling iOS API")
        LoggingService.network.info("   Peer: \(peerID.displayName)")
        LoggingService.network.info("   Attempt Count: \(attemptCount)")
        LoggingService.network.info("   Adaptive Timeout: \(String(format: "%.1f", adaptiveTimeout))s (base: \(self.isUltraFastModeEnabled ? "15s" : "30s"))")
        LoggingService.network.info("   Timestamp: \(Date())")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        browser.invitePeer(peerID, to: session, withContext: nil, timeout: adaptiveTimeout)

        LoggingService.network.info("   ✓ invitePeer() called")
        LoggingService.network.info("   Waiting for remote peer to accept invitation...")
        LoggingService.network.info("   If accepted, session(_:peer:didChange: .connecting) will be called")

        // Early detection for "Connection refused" errors (typically happen within 1-3 seconds)
        // ⚡⚡ ULTRA-FAST MODE: Reduced to 1 second for instant detection
        let detectionDelay = self.isUltraFastModeEnabled ? 1.0 : 3.0
        DispatchQueue.main.asyncAfter(deadline: .now() + detectionDelay) { [weak self] in
            guard let self = self else { return }

            // Check if still trying to connect after 3 seconds with no response
            let isStillWaiting = self.connectionMutex.hasActiveOperation(for: peerID) &&
                                !self.connectedPeers.contains(where: { $0.displayName == peerID.displayName }) &&
                                !self.connectingPeers.contains(peerID.displayName)

            if isStillWaiting {
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                LoggingService.network.info("⚡ ULTRA-FAST CONNECTION FAILURE DETECTION")
                LoggingService.network.info("   Peer: \(peerID.displayName)")
                LoggingService.network.info("   No response after \(Int(detectionDelay)) second(s)")
                LoggingService.network.info("   Likely cause: Connection refused (error 61)")
                LoggingService.network.info("   Recording as connection refused...")
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                // Record this as a connection refused error
                self.sessionManager.recordConnectionRefused(to: peerID)

                // Record failure in diagnostics
                // Diagnostics temporarily disabled
                /*
                let attemptCount = self.sessionManager.getAttemptCount(for: peerID)
                let avgLatency = self.healthMonitor.averageLatency(for: peerID)
                self.diagnostics.recordAttempt(
                    peerID: peerID,
                    attemptNumber: attemptCount,
                    timeout: self.calculateInvitationTimeout(for: peerID, attempt: attemptCount),
                    result: .refused,
                    latency: avgLatency,
                    networkStatus: self.networkConfigDetector.currentStatus
                )
                */

                // Check if we should retry with bidirectional mode
                if self.sessionManager.shouldUseBidirectionalConnection(for: peerID) {
                    // ⚡ Get per-peer backoff delay from SessionManager
                    let retryDelay = self.sessionManager.getRetryDelay(for: peerID)
                    LoggingService.network.info("⚡ Scheduling retry with BIDIRECTIONAL MODE")
                    LoggingService.network.info("   Delay: \(retryDelay)s (per-peer progressive backoff)")

                    // Release the lock first
                    self.connectionMutex.releaseLock(for: peerID)

                    // Schedule retry with bidirectional mode (with per-peer backoff)
                    DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
                        LoggingService.network.info("⚡ RETRY with bidirectional mode for \(peerID.displayName)")
                        self.connectToPeer(peerID, forceIgnoreConflictResolution: false)
                    }
                } else {
                    // Circuit breaker might be active or max attempts reached
                    LoggingService.network.info("🛑 No retry scheduled for \(peerID.displayName)")
                    self.connectionMutex.releaseLock(for: peerID)
                }
            }
        }

        // Watchdog: if the session never transitions, clear the lock to avoid deadlocks
        let handshakeTimeout = SessionManager.connectionTimeout + 4.0
        LoggingService.network.info("   ⏰ Watchdog timer set for \(handshakeTimeout)s")

        DispatchQueue.main.asyncAfter(deadline: .now() + handshakeTimeout) { [weak self] in
            guard let self = self else { return }
            if self.connectionMutex.hasActiveOperation(for: peerID) {
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                LoggingService.network.info("⏳ WATCHDOG TIMEOUT")
                LoggingService.network.info("   Peer: \(peerID.displayName)")
                LoggingService.network.info("   Timeout: \(handshakeTimeout)s elapsed")
                LoggingService.network.info("   Action: Releasing mutex lock")
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                releaseLock()
            } else {
                LoggingService.network.info("   ✓ Watchdog: Lock already released normally")
            }
        }
    }

    /// Intelligent disconnection system with two cases:
    /// Case A: Alternative peers available → Disconnect immediately
    /// Case B: No alternatives → Mark as pending, disconnect when new peer arrives
    func requestDisconnect(from peerID: MCPeerID) {
        let peerKey = peerID.displayName

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🔌 DISCONNECT REQUEST")
        LoggingService.network.info("   Peer: \(peerKey)")
        LoggingService.network.info("   Current connected peers: \(self.connectedPeers.count)")
        LoggingService.network.info("   Current available peers: \(self.availablePeers.count)")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Check if there are alternative peers available
        let hasAlternatives = !availablePeers.isEmpty || connectedPeers.count > 1

        if hasAlternatives {
            // CASE A: Alternative peers available → Disconnect immediately
            LoggingService.network.info("✅ CASE A: Alternative peers available")
            LoggingService.network.info("   Disconnecting immediately from \(peerKey)")

            // Mark as pendingDisconnect temporarily (will be removed after actual disconnect)
            processingQueue.async(flags: .barrier) { [weak self] in
                self?.peerConnectionStates[peerKey] = .pendingDisconnect
            }

            // Perform actual disconnection
            session.cancelConnectPeer(peerID)

            // Clean up all state for this peer
            cleanupPeerState(peerID)

            LoggingService.network.info("✅ Immediate disconnection completed for \(peerKey)")

        } else {
            // CASE B: No alternatives → Mark as pending, wait for new peer
            LoggingService.network.info("⚠️ CASE B: No alternative peers available")
            LoggingService.network.info("   Marking \(peerKey) as pendingDisconnect")
            LoggingService.network.info("   Will disconnect automatically when new peer connects")

            // Mark peer as pending disconnect
            processingQueue.async(flags: .barrier) { [weak self] in
                self?.peerConnectionStates[peerKey] = .pendingDisconnect
            }

            // Force UI update to show pending state
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
            }

            LoggingService.network.info("⏳ Peer \(peerKey) marked as pendingDisconnect - waiting for alternatives")
        }

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
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

        LoggingService.network.info("🧹 Cleaning up state for peer: \(peerKey)")

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

        LoggingService.network.info("✅ Cleanup completed for \(peerKey)")
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
            LoggingService.network.info("🔄 Skipping auto-reconnect - waiting for peer \(peerID.displayName) to initiate")
            return false
        }

        return true
    }

    func resetConnectionState() {
        LoggingService.network.info("♾️ Resetting all connection states")
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
            LoggingService.network.info("⚠️ Throttling advertise request")
            return
        }
        lastAdvertiseTime = now

        // Create discovery info based on Lightning Mode status
        let discoveryInfo: [String: String]? = isLightningModeEnabled ?
            ["lightning": "true", "stream": "2"] : nil

        advertiser = MCNearbyServiceAdvertiser(
            peer: localPeerID,
            discoveryInfo: discoveryInfo,
            serviceType: serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()

        DispatchQueue.main.async {
            self.isAdvertising = true
        }

        LoggingService.network.info("📡 NetworkManager: Started advertising")
        LoggingService.network.info("   Service type: \(self.serviceType)")
        LoggingService.network.info("   Local peer: \(self.localPeerID.displayName)")
        LoggingService.network.info("   Discovery info: \(String(describing: discoveryInfo as NSObject?))")
        LoggingService.network.info("   Delegate set: \(self.advertiser?.delegate != nil)")
        LoggingService.network.info("   Lightning Mode: \(self.isLightningModeEnabled)")
    }

    internal func stopAdvertising() {
        LoggingService.network.info("🛑 STOPPING ADVERTISER - DEBUG INFO:")
        LoggingService.network.info("   Current advertiser: \(self.advertiser != nil ? "EXISTS" : "NIL")")
        LoggingService.network.info("   Was advertising: \(self.isAdvertising)")
        LoggingService.network.info("   Waiting for invitation from: \(self.waitingForInvitationFrom.count) peers")
        if !self.waitingForInvitationFrom.isEmpty {
            LoggingService.network.info("   ⚠️ WARNING: Stopping advertiser while waiting for invitations!")
            LoggingService.network.info("   Waiting from: \(Array(self.waitingForInvitationFrom.keys))")
        }

        advertiser?.stopAdvertisingPeer()
        advertiser = nil

        DispatchQueue.main.async {
            self.isAdvertising = false
        }

        LoggingService.network.info("📡 NetworkManager: Stopped advertising")
    }

    // MARK: - Stadium Mode Methods

    /// Activate Stadium Mode for FIFA 2026 with ultra-fast connections
    func activateStadiumMode(profile: StadiumMode.StadiumProfile = .megaStadium) {
        LoggingService.network.info("🏟️🏟️🏟️ ACTIVATING STADIUM MODE FOR FIFA 2026 🏟️🏟️🏟️")

        // Initialize Stadium Mode if not already created
        if stadiumMode == nil {
            stadiumMode = StadiumMode(networkManager: self)
        }

        // Initialize Lightning Manager for ultra-fast connections
        if lightningManager == nil {
            lightningManager = LightningMeshManager(localPeerID: localPeerID)
        }

        // Activate Stadium Mode
        stadiumMode?.activate(profile: profile)

        // Activate Lightning connections for sub-second performance
        lightningManager?.activateLightningMode(.lightning)
        isLightningModeActive = true

        // Enable Lightning Mode in NetworkManager extension
        enableLightningMode()

        LoggingService.network.info("🏟️ Stadium Mode ACTIVE - Target: <1s connections for 80,000+ users")
    }

    /// Deactivate Stadium Mode and return to normal operation
    func deactivateStadiumMode() {
        LoggingService.network.info("🏟️ Deactivating Stadium Mode...")

        stadiumMode?.deactivate()
        lightningManager?.deactivate()
        isLightningModeActive = false

        // Disable Lightning Mode
        disableLightningMode()

        LoggingService.network.info("✅ Returned to normal mode")
    }

    /// Get current Stadium Mode status
    func getStadiumModeStatus() -> String {
        guard let stadiumMode = stadiumMode, stadiumMode.isActive else {
            return "Stadium Mode: INACTIVE"
        }

        var status = stadiumMode.getStatus()

        if let lightningStatus = lightningManager?.getStatus() {
            status += "\n\n" + lightningStatus
        }

        return status
    }

    /// Switch Stadium zone (affects connection priority)
    func switchStadiumZone(_ zone: StadiumMode.StadiumZone) {
        stadiumMode?.switchZone(zone)
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
            LoggingService.network.info("⚠️ Throttling browse request")
            return
        }
        lastBrowseTime = now

        browser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()

        DispatchQueue.main.async {
            self.isBrowsing = true
        }

        LoggingService.network.info("🔍 NetworkManager: Started browsing for peers")
    }

    internal func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil

        DispatchQueue.main.async {
            self.isBrowsing = false
        }

        LoggingService.network.info("🔍 NetworkManager: Stopped browsing")
    }

    private func manageBrowsing() {
        // Always keep browsing active to discover new peers
        // This allows the network to dynamically adapt when peers join or leave
        if !isBrowsing {
            startBrowsing()
            LoggingService.network.info("🔄 Restarting browsing to discover new peers")
        }

        // Optional: Stop browsing only if explicitly configured AND we have reached max connections
        if config.stopBrowsingWhenConnected && connectedPeers.count >= config.maxConnections {
            if isBrowsing {
                stopBrowsing()
                LoggingService.network.info("🛑 Auto-stopped browsing - max connections reached (\(self.connectedPeers.count)/\(self.config.maxConnections))")
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
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("📥 RECEIVED DATA FROM: \(peerID.displayName)")
        LoggingService.network.info("   Data Size: \(data.count) bytes")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        do {
            let decoder = JSONDecoder()
            let payload = try decoder.decode(NetworkPayload.self, from: data)

            switch payload {
            case .message(var networkMessage):
                LoggingService.network.info("   Payload Type: Network Message")
                handleNetworkMessage(&networkMessage, from: peerID)
            case .ack(let ackMessage):
                LoggingService.network.info("   Payload Type: ACK Message")
                handleAckMessage(ackMessage, from: peerID)
            case .ping(_):
                LoggingService.network.info("   Payload Type: Ping (handled by health monitor)")
            case .pong(_):
                LoggingService.network.info("   Payload Type: Pong (handled by health monitor)")
            case .keepAlive(let keepAlive):
                LoggingService.network.info("   Payload Type: Keep-Alive (peer count: \(keepAlive.peerCount))")
                // Keep-alive messages are lightweight network stability pings
                // No action needed - just receiving them keeps connection alive
            case .locationRequest(let locationRequest):
                LoggingService.network.info("   Payload Type: Location Request")
                handleLocationRequest(locationRequest, from: peerID)
            case .locationResponse(let locationResponse):
                LoggingService.network.info("   Payload Type: Location Response")
                handleLocationResponse(locationResponse, from: peerID)
            case .uwbDiscoveryToken(let tokenMessage):
                LoggingService.network.info("   Payload Type: LinkFinder Discovery Token")
                handleUWBDiscoveryToken(tokenMessage, from: peerID)
            case .familySync(let familySyncMessage):
                LoggingService.network.info("   Payload Type: Family Sync")
                handleFamilySync(familySyncMessage, from: peerID)
            case .familyJoinRequest(let joinRequest):
                LoggingService.network.info("   Payload Type: Family Join Request")
                handleFamilyJoinRequest(joinRequest, from: peerID)
            case .familyGroupInfo(let groupInfo):
                LoggingService.network.info("   Payload Type: Family Group Info")
                handleFamilyGroupInfo(groupInfo, from: peerID)
            case .topology(var topologyMessage):
                LoggingService.network.info("   Payload Type: Topology")
                handleTopologyMessage(&topologyMessage, from: peerID)
            case .linkfenceEvent(let linkfenceEvent):
                LoggingService.network.info("   Payload Type: LinkFence Event")
                handleGeofenceEvent(linkfenceEvent, from: peerID)
            case .linkfenceShare(let linkfenceShare):
                LoggingService.network.info("   Payload Type: LinkFence Share")
                handleGeofenceShare(linkfenceShare, from: peerID)
            case .routeRequest(let routeRequest):
                LoggingService.network.info("   Payload Type: Route Request")
                handleRouteRequest(routeRequest, from: peerID)
            case .routeReply(let routeReply):
                LoggingService.network.info("   Payload Type: Route Reply")
                handleRouteReply(routeReply, from: peerID)
            case .routeError(let routeError):
                LoggingService.network.info("   Payload Type: Route Error")
                handleRouteError(routeError, from: peerID)
            case .gpsLocation(let gpsLocation):
                LoggingService.network.info("   Payload Type: GPS Location (LinkFinder Fallback)")
                handleGPSLocationForLinkFinder(gpsLocation, from: peerID)
            }
        } catch {
            // Try to handle as JSON for special requests
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let type = json["type"] as? String {

                switch type {
                case "uwb_token_request":
                    // Handle UWB token request from peer who wants to start LinkFinder
                    LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    LoggingService.network.info("📥 UWB TOKEN REQUEST RECEIVED")
                    LoggingService.network.info("   From: \(peerID.displayName)")
                    LoggingService.network.info("   Action: Starting LinkFinder session")
                    LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                    // Start LinkFinder session by sending our token
                    self.uwbTokenExchangeState[peerID.displayName] = .sentToken
                    self.sendUWBDiscoveryToken(to: peerID)
                    return

                default:
                    LoggingService.network.info("⚠️ Unknown JSON message type: \(type)")
                }
            }

            // Fallback to Message deserialization
            guard let message = Message.fromData(data) else {
                LoggingService.network.info("❌ Failed to deserialize message: \(error)")
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
                LoggingService.network.info("📥 Legacy message from \(peerID.displayName): \(message.content)")
            }
        }
    }

    private func handleNetworkMessage(_ message: inout NetworkMessage, from peerID: MCPeerID) {
        let messageId = message.id
        guard messageCache.shouldProcessMessage(messageId) else {
            LoggingService.network.info("💭 Ignoring duplicate message \(messageId.uuidString.prefix(8)) from \(peerID.displayName)")
            return
        }

        message.addHop(localPeerID.displayName)

        let isForMe = message.isForMe(localPeerID.displayName)

        // Enhanced logging for multi-hop tracking
        let senderId = message.senderId
        let recipientId = message.recipientId
        let routePath = message.routePath
        let hopCount = message.hopCount
        let ttl = message.ttl

        LoggingService.network.info("📦 Message received:")
        LoggingService.network.info("   From: \(senderId) → To: \(recipientId)")
        LoggingService.network.info("   Route: \(routePath.joined(separator: " → "))")
        LoggingService.network.info("   Hop: \(hopCount)/\(ttl)")
        LoggingService.network.info("   For me? \(isForMe ? "✅ YES" : "❌ NO (will relay)")")

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
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                LoggingService.network.info("📨 NetworkManager: MESSAGE FOR ME - Delivering to MessageStore")
                LoggingService.network.info("   Thread: MAIN (via DispatchQueue.main.async)")
                LoggingService.network.info("   Sender: \(senderId)")
                LoggingService.network.info("   Content: \"\(content)\"")
                LoggingService.network.info("   Type: \(messageTypeDisplayName)")
                LoggingService.network.info("   Hops: \(hopCount)")
                LoggingService.network.info("   Route: \(route)")
                LoggingService.network.info("   Conversation: \(conversationId)")
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                // FORCE immediate UI update - critical for messages received via MultipeerConnectivity
                LoggingService.network.info("   📢 Sending objectWillChange to MessageStore...")
                self.messageStore.objectWillChange.send()

                // Special handling for message requests
                if messageTypeDisplayName == "Solicitud" {
                    // This is a first message request - add to pending requests instead of conversations
                    FirstMessageTracker.shared.addIncomingRequest(
                        from: senderId,
                        message: content,
                        localDeviceName: self.localDeviceName
                    )
                    LoggingService.network.info("📨 NetworkManager: Added message request to pending - NOT added to MessageStore")
                    // Don't add to MessageStore yet - wait for acceptance
                } else {
                    // Regular message - add to MessageStore normally
                    LoggingService.network.info("   📥 Calling messageStore.addMessage()...")
                    self.messageStore.addMessage(simpleMessage, context: conversationDescriptor, autoSwitch: true, localDeviceName: self.localDeviceName)

                    // Check if this activates a conversation
                    FirstMessageTracker.shared.handleIncomingMessage(from: senderId, localDeviceName: self.localDeviceName)
                }

                LoggingService.network.info("✅ NetworkManager: Message delivered to MessageStore")
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
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

                let messageHopCount = message.hopCount
                let messageTTL = message.ttl
                LoggingService.network.info("🔄 RELAYING message to \(self.connectedPeers.count) peers - Hop \(messageHopCount)/\(messageTTL)")
                LoggingService.network.info("   Next hops: \(self.connectedPeers.map { $0.displayName }.joined(separator: ", "))")
                messageQueue.enqueue(messageCopy)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.relayingMessage = false
                }
            } else if !message.canHop() {
                let messageHopCount2 = message.hopCount
                let messageTTL2 = message.ttl
                LoggingService.network.info("⏹️ Message reached hop limit: \(messageHopCount2)/\(messageTTL2)")
            } else if message.hasVisited(localPeerID.displayName) {
                LoggingService.network.info("⏹️ Already visited this node (loop prevention)")
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
            LoggingService.network.info("📍 NetworkManager: Sent location request to \(targetPeerId)")
        } catch {
            LoggingService.network.info("❌ NetworkManager: Failed to send location request: \(error.localizedDescription)")
        }
    }

    private func handleLocationRequest(_ request: LocationRequestMessage, from peerID: MCPeerID) {
        LoggingService.network.info("📍 NetworkManager: Received location request from \(request.requesterId) for \(request.targetId)")

        // Case 1: Request is for me - respond with my location (LinkFinder or GPS)
        if request.targetId == localPeerID.displayName {
            handleLocationRequestForMe(request)
            return
        }

        // Case 2: Relay the request (normal multi-hop routing)
        // Intermediaries do NOT respond with their own LinkFinder data
        LoggingService.network.info("📍 NetworkManager: Relaying location request for \(request.targetId)")
        let payload = NetworkPayload.locationRequest(request)

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(payload)
            try safeSend(data, toPeers: connectedPeers, with: .reliable, context: "relayLocationRequest")
        } catch {
            LoggingService.network.info("❌ NetworkManager: Failed to relay location request: \(error.localizedDescription)")
        }
    }

    private func handleLocationRequestForMe(_ request: LocationRequestMessage) {
        // Check if we should respond
        guard locationRequestManager.shouldRespondToRequest(request) else {
            LoggingService.network.info("📍 NetworkManager: Declining location request from \(request.requesterId)")

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
        LoggingService.network.info("📍 NetworkManager: Checking LinkFinder availability with requester \(request.requesterId)...")

        if #available(iOS 14.0, *) {
            if let uwbManager = uwbSessionManager {
                LoggingService.network.info("   ✓ LinkFinderSessionManager available")

                if let requesterPeer = connectedPeers.first(where: { $0.displayName == request.requesterId }) {
                    LoggingService.network.info("   ✓ Requester found in connected peers")

                    let hasSession = uwbManager.hasActiveSession(with: requesterPeer)
                    LoggingService.network.info("   LinkFinder session active: \(hasSession ? "✓ YES" : "✗ NO")")

                    if hasSession {
                        if let distance = uwbManager.getDistance(to: requesterPeer) {
                            LoggingService.network.info("   ✓ LinkFinder distance available: \(String(format: "%.2f", distance))m")

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
                            LoggingService.network.info("✅ NetworkManager: Sent LinkFinder direct response - \(String(format: "%.2f", distance))m \(direction?.cardinalDirection ?? "no direction")")
                            return
                        } else {
                            LoggingService.network.info("   ✗ LinkFinder session exists but no distance data yet")
                        }
                    }
                } else {
                    LoggingService.network.info("   ✗ Requester \(request.requesterId) not in connected peers list")
                }
            } else {
                LoggingService.network.info("   ✗ LinkFinderSessionManager is nil")
            }
        } else {
            LoggingService.network.info("   ✗ iOS 14.0+ required for LinkFinder")
        }

        LoggingService.network.info("📍 NetworkManager: Falling back to GPS (LinkFinder not available)")

        // Fallback: No LinkFinder available, send GPS location
        Task {
            do {
                guard let location = try await locationService.getCurrentLocation() else {
                    LoggingService.network.info("❌ NetworkManager: Failed to get location")

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
                LoggingService.network.info("📍 NetworkManager: Sent GPS fallback response")

            } catch {
                LoggingService.network.info("❌ NetworkManager: Error getting location: \(error)")

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
            LoggingService.network.info("❌ NetworkManager: Failed to send location response: \(error.localizedDescription)")
        }
    }

    private func handleLocationResponse(_ response: LocationResponseMessage, from peerID: MCPeerID) {
        LoggingService.network.info("📍 NetworkManager: Received location response: \(response.description)")
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
        LoggingService.network.info("📍 NetworkManager: Starting GPS sharing with peer: \(peerID)")

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
        LoggingService.network.info("📍 NetworkManager: Stopping GPS sharing with peer: \(peerID)")

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

        LoggingService.network.info("📍 NetworkManager: Started location sharing timer (every \(self.locationSharingInterval)s)")
    }

    /// Stop periodic GPS location broadcast timer
    private func stopLocationSharingTimer() {
        locationSharingTimer?.invalidate()
        locationSharingTimer = nil
        LoggingService.network.info("📍 NetworkManager: Stopped location sharing timer")
    }

    /// Broadcast current GPS location to all peers in active navigation
    private func broadcastMyLocationToPeersInNavigation() {
        guard !peersInNavigation.isEmpty else { return }

        guard let currentLocation = locationService.currentLocation else {
            LoggingService.network.info("⚠️ NetworkManager: Cannot broadcast location - no GPS fix available")
            return
        }

        guard locationService.hasRecentLocation else {
            LoggingService.network.info("⚠️ NetworkManager: Cannot broadcast location - GPS data is stale")
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
            LoggingService.network.info("📍 NetworkManager: Broadcasted GPS location to \(self.connectedPeers.count) peers: \(currentLocation.coordinateString)")
        } catch {
            LoggingService.network.info("❌ NetworkManager: Failed to broadcast GPS location: \(error.localizedDescription)")
        }
    }

    // MARK: - GPS Location for LinkFinder Fallback

    /// Send GPS location to a specific peer for LinkFinder fallback direction calculation
    func sendGPSLocationForLinkFinder(to peerID: MCPeerID) {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("📍 SENDING GPS LOCATION FOR LINKFINDER FALLBACK")
        LoggingService.network.info("   To: \(peerID.displayName)")

        guard let currentLocation = locationService.currentLocation else {
            LoggingService.network.info("   ❌ No current location available")
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            return
        }

        guard locationService.hasRecentLocation else {
            LoggingService.network.info("   ❌ GPS data is stale (older than 30s)")
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            return
        }

        // Convert UserLocation to CLLocation to get all properties
        let clLocation = currentLocation.toCLLocation()

        let gpsMessage = GPSLocationMessage(
            senderId: localPeerID.displayName,
            latitude: clLocation.coordinate.latitude,
            longitude: clLocation.coordinate.longitude,
            horizontalAccuracy: clLocation.horizontalAccuracy,
            altitude: clLocation.altitude,
            verticalAccuracy: clLocation.verticalAccuracy
        )

        let payload = NetworkPayload.gpsLocation(gpsMessage)

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(payload)
            try safeSend(data, toPeers: [peerID], with: .reliable, context: "linkFinderFallbackGPS")

            LoggingService.network.info("   ✅ GPS location sent successfully")
            LoggingService.network.info("      Lat: \(clLocation.coordinate.latitude)")
            LoggingService.network.info("      Lon: \(clLocation.coordinate.longitude)")
            LoggingService.network.info("      Accuracy: ±\(clLocation.horizontalAccuracy)m")
        } catch {
            LoggingService.network.info("   ❌ Failed to send GPS location: \(error.localizedDescription)")
        }

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    /// Start periodic GPS location sharing for LinkFinder fallback (every 5 seconds)
    func startGPSLocationSharingForLinkFinder(with peerID: MCPeerID) {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🔄 STARTING PERIODIC GPS SHARING FOR LINKFINDER FALLBACK")
        LoggingService.network.info("   Peer: \(peerID.displayName)")
        LoggingService.network.info("   Interval: 5 seconds")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Send immediate location
        sendGPSLocationForLinkFinder(to: peerID)

        // TODO: Implement timer-based periodic sharing
        // For now, LinkFinderSessionManager will call sendGPSLocationForLinkFinder manually
    }

    /// Stop periodic GPS location sharing for LinkFinder fallback
    func stopGPSLocationSharingForLinkFinder(with peerID: MCPeerID) {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🛑 STOPPING GPS SHARING FOR LINKFINDER FALLBACK")
        LoggingService.network.info("   Peer: \(peerID.displayName)")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // TODO: Cancel timer if implemented
    }

    // MARK: - LinkFinder Discovery Token Exchange

    private func sendUWBDiscoveryToken(to peerID: MCPeerID) {
        LoggingService.network.info("📡 NetworkManager: Attempting to send LinkFinder token to \(peerID.displayName)...")

        guard #available(iOS 14.0, *) else {
            LoggingService.network.info("   ✗ iOS 14.0+ required for LinkFinder - skipping token exchange")
            return
        }

        guard let uwbManager = uwbSessionManager else {
            LoggingService.network.info("   ✗ LinkFinderSessionManager is nil - skipping token exchange")
            return
        }

        guard uwbManager.isLinkFinderSupported else {
            LoggingService.network.info("   ✗ LinkFinder not supported on this device (requires iPhone 11+ with U1/U2 chip)")
            return
        }

        // Prepare session for this peer (creates session, extracts token, but doesn't run it)
        guard let token = uwbManager.prepareSession(for: peerID) else {
            LoggingService.network.info("   ✗ Failed to prepare session and get discovery token")
            return
        }

        do {
            let tokenData = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)

            // Get local device capabilities
            var deviceCapabilities: UWBDeviceCapabilities? = nil
            if let localCaps = uwbManager.getLocalCapabilities() {
                deviceCapabilities = UWBDeviceCapabilities(
                    deviceModel: localCaps.deviceModel,
                    hasUWB: localCaps.hasUWB,
                    hasU1Chip: localCaps.hasU1Chip,
                    hasU2Chip: localCaps.hasU2Chip,
                    supportsDistance: localCaps.supportsDistance,
                    supportsDirection: localCaps.supportsDirection,
                    supportsCameraAssist: localCaps.supportsCameraAssist,
                    supportsExtendedRange: localCaps.supportsExtendedRange,
                    osVersion: localCaps.osVersion
                )
                LoggingService.network.info("   ✓ Including device capabilities: \(localCaps.deviceModel) - \(localCaps.summary)")
            }

            let message = LinkFinderDiscoveryTokenMessage(
                senderId: localPeerID.displayName,
                tokenData: tokenData,
                deviceCapabilities: deviceCapabilities
            )
            let payload = NetworkPayload.uwbDiscoveryToken(message)

            let encoder = JSONEncoder()
            let data = try encoder.encode(payload)
            try safeSend(data, toPeers: [peerID], with: .reliable, context: "LinkFinderToken")

            LoggingService.network.info("✅ NetworkManager: Sent LinkFinder discovery token to \(peerID.displayName)")
            LoggingService.network.info("   Session prepared and ready to run when we receive peer's token")
        } catch {
            LoggingService.network.info("❌ NetworkManager: Failed to send LinkFinder token: \(error.localizedDescription)")
        }
    }

    // Coordinate a bidirectional LinkFinder restart with a peer by resetting local state
    // and re-initiating the token exchange. This avoids introducing a new payload
    // type and leverages the existing discovery-token flow to re-establish ranging.
    private func sendUWBResetRequest(to peer: MCPeerID) {
        LoggingService.network.info("📡 NetworkManager: LinkFinder reset requested for \(peer.displayName) — resetting local session and re-initiating token exchange")

        guard #available(iOS 14.0, *), let uwbManager = uwbSessionManager else {
            LoggingService.network.info("   ✗ LinkFinder not available — cannot perform reset")
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
            LoggingService.network.info("📤 NetworkManager: Re-initiating LinkFinder token exchange with \(peer.displayName) after reset")
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
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("📥 LinkFinder TOKEN RECEIVED")
        LoggingService.network.info("   From: \(peerID.displayName)")
        LoggingService.network.info("   Token sender ID: \(tokenMessage.senderId)")
        LoggingService.network.info("   Token data size: \(tokenMessage.tokenData.count) bytes")
        LoggingService.network.info("   Current exchange state: \(String(describing: self.uwbTokenExchangeState[peerID.displayName] ?? .none))")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        guard #available(iOS 14.0, *),
              let uwbManager = uwbSessionManager,
              uwbManager.isLinkFinderSupported else {
            LoggingService.network.info("   ✗ LinkFinder not supported on this device")
            LoggingService.network.info("   ❌ FAILED: Device doesn't support UWB")
            return
        }

        do {
            guard let remotePeerToken = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: NIDiscoveryToken.self,
                from: tokenMessage.tokenData
            ) else {
                LoggingService.network.info("❌ NetworkManager: Failed to unarchive LinkFinder token")
                return
            }

            LoggingService.network.info("   ✓ Token unarchived successfully")

            // Process device capabilities if present
            if let deviceCaps = tokenMessage.deviceCapabilities {
                LoggingService.network.info("   📱 Peer capabilities received:")
                LoggingService.network.info("      Device: \(deviceCaps.deviceModel)")
                LoggingService.network.info("      UWB: \(deviceCaps.hasUWB ? "✅" : "❌")")
                LoggingService.network.info("      Direction: \(deviceCaps.supportsDirection ? "✅" : "❌")")

                // Convert to LinkFinderSessionManager.DeviceCapabilities
                let capabilities = LinkFinderSessionManager.DeviceCapabilities(
                    deviceModel: deviceCaps.deviceModel,
                    hasUWB: deviceCaps.hasUWB,
                    hasU1Chip: deviceCaps.hasU1Chip,
                    hasU2Chip: deviceCaps.hasU2Chip,
                    supportsDistance: deviceCaps.supportsDistance,
                    supportsDirection: deviceCaps.supportsDirection,
                    supportsCameraAssist: deviceCaps.supportsCameraAssist,
                    supportsExtendedRange: deviceCaps.supportsExtendedRange,
                    osVersion: deviceCaps.osVersion
                )
                uwbManager.setPeerCapabilities(capabilities, for: peerID)
            } else {
                LoggingService.network.info("   ⚠️ No device capabilities in message (older app version?)")
            }

            // Determine role based on peer ID comparison
            let isMaster = localPeerID.displayName > peerID.displayName
            uwbSessionRole[peerID.displayName] = isMaster ? "master" : "slave"

            LoggingService.network.info("   🎭 LinkFinder Role: \(isMaster ? "MASTER" : "SLAVE") for session with \(peerID.displayName)")
            LoggingService.network.info("   📊 Comparison: '\(self.localPeerID.displayName)' \(isMaster ? ">" : "<") '\(peerID.displayName)'")

            if isMaster {
                // MASTER receives SLAVE's token response
                LoggingService.network.info("   📥 MASTER received SLAVE's token")

                // Our session should already be prepared (we sent our token first)
                // Now run our session with the slave's token
                uwbManager.startSession(with: peerID, remotePeerToken: remotePeerToken)

                // Mark exchange complete
                uwbTokenExchangeState[peerID.displayName] = .exchangeComplete
                LoggingService.network.info("   ✅ Token exchange complete - both sessions running")

            } else {
                // SLAVE receives MASTER's initial token
                LoggingService.network.info("   📥 SLAVE received MASTER's token")
                LoggingService.network.info("   🎭 Role: SLAVE (will send token back)")

                // Step 1: Prepare our session (if not already prepared)
                // This will create session and extract our token
                guard let myToken = uwbManager.prepareSession(for: peerID) else {
                    LoggingService.network.info("   ❌ Failed to prepare session - cannot create local token")
                    uwbTokenExchangeState[peerID.displayName] = .none
                    return
                }

                LoggingService.network.info("   ✅ Session prepared, local token extracted")
                LoggingService.network.info("   📊 Local token size: \(String(describing: myToken).count) chars")

                // Step 2: Run our session with master's token
                uwbManager.startSession(with: peerID, remotePeerToken: remotePeerToken)
                LoggingService.network.info("   🚀 Session started with MASTER's token")

                // Step 3: Send our token back to master
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else {
                        LoggingService.network.info("   ❌ Self deallocated - cannot send token back")
                        return
                    }

                    LoggingService.network.info("   📤 SLAVE attempting to send token back to MASTER...")
                    LoggingService.network.info("   📊 Peer connection state: \(self.connectedPeers.contains(peerID) ? "Connected" : "Disconnected")")

                    // Manually encode and send (can't use sendUWBDiscoveryToken since session is already prepared)
                    do {
                        let tokenData = try NSKeyedArchiver.archivedData(withRootObject: myToken, requiringSecureCoding: true)
                        LoggingService.network.info("   ✅ Token serialized: \(tokenData.count) bytes")

                        // Include device capabilities in response
                        var deviceCapabilities: UWBDeviceCapabilities? = nil
                        if let localCaps = uwbManager.getLocalCapabilities() {
                            deviceCapabilities = UWBDeviceCapabilities(
                                deviceModel: localCaps.deviceModel,
                                hasUWB: localCaps.hasUWB,
                                hasU1Chip: localCaps.hasU1Chip,
                                hasU2Chip: localCaps.hasU2Chip,
                                supportsDistance: localCaps.supportsDistance,
                                supportsDirection: localCaps.supportsDirection,
                                supportsCameraAssist: localCaps.supportsCameraAssist,
                                supportsExtendedRange: localCaps.supportsExtendedRange,
                                osVersion: localCaps.osVersion
                            )
                            LoggingService.network.info("   ✓ Including device capabilities: \(localCaps.deviceModel)")
                        }

                        let message = LinkFinderDiscoveryTokenMessage(
                            senderId: self.localPeerID.displayName,
                            tokenData: tokenData,
                            deviceCapabilities: deviceCapabilities
                        )
                        let payload = NetworkPayload.uwbDiscoveryToken(message)

                        let encoder = JSONEncoder()
                        let data = try encoder.encode(payload)
                        LoggingService.network.info("   📦 Payload encoded: \(data.count) bytes")

                        // Check if peer is still connected before sending
                        guard self.connectedPeers.contains(peerID) else {
                            LoggingService.network.info("   ❌ FAILED: Peer \(peerID.displayName) disconnected before token could be sent")
                            self.uwbTokenExchangeState[peerID.displayName] = .none
                            return
                        }

                        try self.safeSend(data, toPeers: [peerID], with: .reliable, context: "LinkFinderTokenResponse")
                        LoggingService.network.info("   📨 Token sent to \(peerID.displayName) via reliable channel")

                        self.uwbTokenExchangeState[peerID.displayName] = .exchangeComplete
                        LoggingService.network.info("   ✅ SLAVE sent token - exchange marked complete")
                    } catch {
                        LoggingService.network.info("   ❌ CRITICAL ERROR sending token back:")
                        LoggingService.network.info("      Error: \(error)")
                        LoggingService.network.info("      Description: \(error.localizedDescription)")
                        self.uwbTokenExchangeState[peerID.displayName] = .none
                    }
                }
            }

        } catch {
            LoggingService.network.info("❌ NetworkManager: Error handling LinkFinder token: \(error.localizedDescription)")
        }
    }

    // MARK: - GPS Location for LinkFinder Fallback Handler

    private func handleGPSLocationForLinkFinder(_ gpsMessage: GPSLocationMessage, from peerID: MCPeerID) {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("📍 GPS LOCATION RECEIVED FOR LINKFINDER FALLBACK")
        LoggingService.network.info("   From: \(peerID.displayName)")
        LoggingService.network.info("   Sender ID: \(gpsMessage.senderId)")
        LoggingService.network.info("   Lat: \(gpsMessage.latitude)")
        LoggingService.network.info("   Lon: \(gpsMessage.longitude)")
        LoggingService.network.info("   Accuracy: ±\(gpsMessage.horizontalAccuracy)m")
        LoggingService.network.info("   Timestamp: \(gpsMessage.timestamp)")

        guard #available(iOS 14.0, *),
              let uwbManager = uwbSessionManager else {
            LoggingService.network.info("   ❌ LinkFinderSessionManager not available")
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            return
        }

        // Convert GPSLocationMessage to CLLocation
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: gpsMessage.latitude, longitude: gpsMessage.longitude),
            altitude: gpsMessage.altitude,
            horizontalAccuracy: gpsMessage.horizontalAccuracy,
            verticalAccuracy: gpsMessage.verticalAccuracy,
            timestamp: gpsMessage.timestamp
        )

        LoggingService.network.info("   ✅ GPS location converted to CLLocation")
        LoggingService.network.info("   📍 Forwarding to LinkFinderSessionManager for fallback direction calculation")

        // Forward to LinkFinderSessionManager for fallback direction calculation
        uwbManager.updatePeerGPSLocation(location, for: peerID)

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    // MARK: - Family Sync Handling

    private func handleFamilySync(_ syncMessage: FamilySyncMessage, from peerID: MCPeerID) {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("👨‍👩‍👧‍👦 FAMILY SYNC RECEIVED")
        LoggingService.network.info("   From: \(peerID.displayName)")
        LoggingService.network.info("   Code: \(syncMessage.groupCode.displayCode)")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

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
            LoggingService.network.info("⚠️ NetworkManager: No active family group to sync")
            return
        }

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("📤 SENDING FAMILY SYNC")
        LoggingService.network.info("   To: \(peerID.displayName)")
        LoggingService.network.info("   Code: \(syncMessage.groupCode.displayCode)")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        let payload = NetworkPayload.familySync(syncMessage)

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(payload)
            try safeSend(data, toPeers: [peerID], with: .reliable, context: "familySync")
            LoggingService.network.info("✅ NetworkManager: Sent family sync to \(peerID.displayName)")
        } catch {
            LoggingService.network.info("❌ NetworkManager: Failed to send family sync: \(error.localizedDescription)")
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
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("📤 SENDING GEOFENCE EVENT")
        LoggingService.network.info("   Type: \(event.eventType.rawValue)")
        LoggingService.network.info("   Place: \(event.linkfenceName)")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        let payload = NetworkPayload.linkfenceEvent(event)

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(payload)
            // Send to all connected peers (family will filter by code)
            try safeSend(data, toPeers: connectedPeers, with: .reliable, context: "linkfenceEvent")
            LoggingService.network.info("✅ NetworkManager: Sent linkfence event to \(self.connectedPeers.count) peers")
        } catch {
            LoggingService.network.info("❌ NetworkManager: Failed to send linkfence event: \(error.localizedDescription)")
        }
    }

    /// Send linkfence share to family members via mesh
    func sendGeofenceShare(_ share: LinkFenceShareMessage) {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("📤 SENDING GEOFENCE SHARE")
        LoggingService.network.info("   LinkFence: \(share.linkfence.name)")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        let payload = NetworkPayload.linkfenceShare(share)

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(payload)
            // Send to all connected peers (family will filter by code)
            try safeSend(data, toPeers: connectedPeers, with: .reliable, context: "linkfenceShare")
            LoggingService.network.info("✅ NetworkManager: Sent linkfence share to \(self.connectedPeers.count) peers")
        } catch {
            LoggingService.network.info("❌ NetworkManager: Failed to send linkfence share: \(error.localizedDescription)")
        }
    }

    // MARK: - Family Join Request/Response Handling

    private func handleFamilyJoinRequest(_ request: FamilyJoinRequestMessage, from peerID: MCPeerID) {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🔍 FAMILY JOIN REQUEST RECEIVED")
        LoggingService.network.info("   From: \(request.requesterId)")
        LoggingService.network.info("   Code: \(request.groupCode.displayCode)")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Check if we have this group code
        guard let myGroup = familyGroupManager.currentGroup,
              myGroup.code == request.groupCode else {
            LoggingService.network.info("⚠️ We don't have group with code \(request.groupCode.displayCode)")
            return
        }

        LoggingService.network.info("✅ We have this group! Sending info back...")
        LoggingService.network.info("   Group: \(myGroup.name)")
        LoggingService.network.info("   Members: \(myGroup.memberCount)")

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
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("📥 FAMILY GROUP INFO RECEIVED")
        LoggingService.network.info("   From: \(info.responderId)")
        LoggingService.network.info("   Group: \(info.groupName)")
        LoggingService.network.info("   Code: \(info.groupCode.displayCode)")
        LoggingService.network.info("   Members: \(info.memberCount)")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

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
            LoggingService.network.info("⚠️ No connected peers to request family group info from")
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

            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            LoggingService.network.info("📤 BROADCASTING FAMILY JOIN REQUEST")
            LoggingService.network.info("   Code: \(code.displayCode)")
            LoggingService.network.info("   To: \(self.connectedPeers.count) peers")
            LoggingService.network.info("   Peers: \(self.connectedPeers.map { $0.displayName }.joined(separator: ", "))")
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        } catch {
            LoggingService.network.info("❌ Failed to send family join request: \(error.localizedDescription)")
        }
    }

    private func sendFamilyGroupInfo(_ info: FamilyGroupInfoMessage, to peerID: MCPeerID) {
        let payload = NetworkPayload.familyGroupInfo(info)

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(payload)
            try safeSend(data, toPeers: [peerID], with: .reliable, context: "familyGroupInfo")
            LoggingService.network.info("✅ Sent family group info to \(peerID.displayName)")
        } catch {
            LoggingService.network.info("❌ Failed to send family group info: \(error.localizedDescription)")
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
            LoggingService.network.info("⚠️ broadcastTopology: No valid peers in session, skipping broadcast")
            LoggingService.network.info("   Local array has \(self.connectedPeers.count), but session has \(sessionPeers.count)")
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

            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            LoggingService.network.info("📡 TOPOLOGY BROADCAST (unreliable)")
            LoggingService.network.info("   Connections: [\(connectedPeerNames.joined(separator: ", "))]")
            LoggingService.network.info("   Sent to: \(validPeers.count) peers (validated against session)")
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            // Update local routing table
            routingTable.updateLocalTopology(connectedPeers: validPeers)

        } catch {
            LoggingService.network.info("❌ Failed to broadcast topology: \(error.localizedDescription)")
            LoggingService.network.info("   Valid peers: \(validPeers.count), Session peers: \(sessionPeers.count)")
        }
    }

    /// Handle received topology message
    private func handleTopologyMessage(_ message: inout TopologyMessage, from peerID: MCPeerID) {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        let msgSenderId = message.senderId
        let msgConnectedPeers = message.connectedPeers
        let msgHopCount = message.hopCount
        let msgTTL = message.ttl

        LoggingService.network.info("🗺️ TOPOLOGY RECEIVED")
        LoggingService.network.info("   From: \(msgSenderId)")
        LoggingService.network.info("   Connections: [\(msgConnectedPeers.joined(separator: ", "))]")
        LoggingService.network.info("   Hop: \(msgHopCount)/\(msgTTL)")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

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
                LoggingService.network.info("⚠️ Cannot relay topology: No valid peers in session")
                return
            }

            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(payload)
                // STABILITY FIX: Use unreliable mode for topology relays too
                try session.send(data, toPeers: validPeers, with: .unreliable)
                let relayHopCount = message.hopCount
                let relayTTL = message.ttl
                LoggingService.network.info("🔄 Relayed topology message (hop \(relayHopCount)/\(relayTTL)) to \(validPeers.count) peers (unreliable)")
            } catch {
                LoggingService.network.info("❌ Failed to relay topology: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - MCSessionDelegate

extension NetworkManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🔄 SESSION STATE CHANGE CALLBACK")
        LoggingService.network.info("   Peer: \(peerID.displayName)")
        LoggingService.network.info("   New State: \(state == .connected ? "CONNECTED" : state == .connecting ? "CONNECTING" : "NOT_CONNECTED")")
        LoggingService.network.info("   Session memory address: \(String(describing: Unmanaged.passUnretained(session).toOpaque()))")
        LoggingService.network.info("   Self.session memory address: \(String(describing: Unmanaged.passUnretained(self.session).toOpaque()))")
        LoggingService.network.info("   Session match: \(session === self.session ? "✅ SAME" : "❌ DIFFERENT")")
        LoggingService.network.info("   Timestamp: \(Date())")
        LoggingService.network.info("   Thread: \(Thread.current)")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // CRITICAL: Detect if callback is for a different session (dual session bug)
        if session !== self.session {
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            LoggingService.network.info("🚨 CRITICAL BUG DETECTED: DUAL SESSION MISMATCH")
            LoggingService.network.info("   Callback session: \(String(describing: Unmanaged.passUnretained(session).toOpaque()))")
            LoggingService.network.info("   Current session: \(String(describing: Unmanaged.passUnretained(self.session).toOpaque()))")
            LoggingService.network.info("   Peer: \(peerID.displayName)")
            LoggingService.network.info("   State: \(state == .connected ? "CONNECTED" : state == .connecting ? "CONNECTING" : "NOT_CONNECTED")")
            LoggingService.network.info("   This is likely causing handshake failures!")
            LoggingService.network.info("   Action: Ignoring callback from stale session")
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            return
        }

        DispatchQueue.main.async {
            switch state {
            case .connected:
                LoggingService.network.info("🔍 DEBUG: Handling .connected state...")

                // Remove from connecting peers set
                self.connectingPeers.remove(peerID.displayName)

                // Clean up certificate exchange tracking (connection succeeded)
                self.certificateExchangeStarted.remove(peerID.displayName)

                // Release any connection locks
                LoggingService.network.info("   Step 1: Releasing connection mutex...")
                self.connectionMutex.releaseLock(for: peerID)
                LoggingService.network.info("   ✓ Mutex released")

                // Clear failure counters on successful connection
                LoggingService.network.info("   Step 2: Clearing failure counters...")
                self.failedConnectionAttempts[peerID.displayName] = 0
                self.consecutiveFailures = 0
                LoggingService.network.info("   ✓ Failure counters cleared")

                // Record connection metrics for diagnostics
                self.recordConnectionMetrics(peer: peerID, event: .connected)

                // Remove any stale entries for this displayName first
                LoggingService.network.info("   Step 3: Cleaning stale peer entries...")
                let previousCount = self.connectedPeers.count
                self.connectedPeers.removeAll { $0.displayName == peerID.displayName }
                LoggingService.network.info("   ✓ Removed \(previousCount - self.connectedPeers.count) stale entries")

                // Now add the fresh connection
                LoggingService.network.info("   Step 4: Adding peer to connectedPeers array...")
                self.connectedPeers.append(peerID)
                LoggingService.network.info("   ✓ Peer added. Total connected: \(self.connectedPeers.count)")

                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                LoggingService.network.info("🆕 NEW CONNECTION ESTABLISHED")
                LoggingService.network.info("   Peer: \(peerID.displayName)")
                LoggingService.network.info("   Total Connections: \(self.connectedPeers.count)")
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                LoggingService.network.info("   Step 5: Recording successful connection in SessionManager...")
                self.sessionManager.recordSuccessfulConnection(to: peerID)
                LoggingService.network.info("   ✓ Recorded in SessionManager")

                // Reset connection refused count on successful connection
                LoggingService.network.info("   Step 5.5: Resetting connection refused counter...")
                self.sessionManager.resetConnectionRefusedCount(for: peerID)
                LoggingService.network.info("   ✓ Connection refused counter reset")

                // Record successful connection in diagnostics
                // Diagnostics temporarily disabled
                /*
                LoggingService.network.info("   Step 5.6: Recording success in diagnostics...")
                let attemptCount = self.sessionManager.getAttemptCount(for: peerID)
                let avgLatency = self.healthMonitor.averageLatency(for: peerID)
                self.diagnostics.recordAttempt(
                    peerID: peerID,
                    attemptNumber: attemptCount,
                    timeout: SessionManager.connectionTimeout,
                    result: .success,
                    latency: avgLatency,
                    networkStatus: self.networkConfigDetector.currentStatus
                )
                LoggingService.network.info("   ✓ Success recorded in diagnostics")
                */

                if !TestingConfig.disableHealthMonitoring {
                    self.healthMonitor.addPeer(peerID)
                } else {
                    LoggingService.network.info("🧪 TEST MODE: Health monitoring disabled for \(peerID.displayName)")
                }

                self.updateConnectionStatus()
                self.manageBrowsing()  // Stop browsing if configured
                LoggingService.network.info("✅ NetworkManager: Connected to peer: \(peerID.displayName) | Total peers: \(self.connectedPeers.count)")

                // Record successful connection with orchestrator
                if self.isOrchestratorEnabled {
                    LoggingService.network.info("   🎯 Recording successful connection with Orchestrator")
                    self.recordSuccessfulConnection(to: peerID)
                }

                // 🏟️ AUTO-ACTIVATE STADIUM MODE when first peer connects
                // This enables Live Activities + background location + keep-alive pings
                // NOTE: User can also manually control this from Settings
                if self.connectedPeers.count == 1 {
                    // Check if Stadium Mode is not already active
                    if !StadiumModeManager.shared.isActive {
                        // Check if user has disabled auto-activation
                        let autoActivateStadiumMode = UserDefaults.standard.object(forKey: "autoActivateStadiumMode") as? Bool ?? true

                        if autoActivateStadiumMode {
                            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                            LoggingService.network.info("🏟️ AUTO-ACTIVATING STADIUM MODE")
                            LoggingService.network.info("   First peer connected: \(peerID.displayName)")
                            LoggingService.network.info("   Enabling: Live Activity + Background Survival")
                            LoggingService.network.info("   (User can disable auto-activation in Settings)")
                            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                            // Enable full Stadium Mode (includes Live Activity)
                            StadiumModeManager.shared.enable()
                        } else {
                            LoggingService.network.info("🏟️ Stadium Mode auto-activation disabled by user")
                            LoggingService.network.info("   User can manually enable from Settings")

                            // Still start Live Activity even if Stadium Mode is disabled
                            // This provides minimal functionality without background survival
                            if #available(iOS 16.1, *) {
                                if !self.hasActiveLiveActivity {
                                    LoggingService.network.info("🎬 Starting Live Activity (without full Stadium Mode)")
                                    self.startLiveActivity()
                                }
                            }
                        }
                    } else {
                        LoggingService.network.info("🏟️ Stadium Mode already active (manually enabled by user)")
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

                // PRIVACY FIX: LinkFinder should NOT start automatically
                // It will only start when user explicitly opens the LinkFinder view
                // Reset LinkFinder retry count and token exchange state for this peer
                self.uwbRetryCount[peerID.displayName] = 0
                self.uwbTokenExchangeState[peerID.displayName] = .idle
                self.uwbSessionRole.removeValue(forKey: peerID.displayName)

                /* DISABLED: Automatic LinkFinder initiation for privacy
                // Determine who should initiate LinkFinder token exchange based on peer ID
                let shouldInitiate = self.localPeerID.displayName > peerID.displayName

                if shouldInitiate {
                    // We initiate if we have the higher ID (master role)
                    // STABILITY FIX: Increased from 2.0s to 4.0s to ensure topology and family sync complete first
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                        guard let self = self else { return }
                        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        LoggingService.network.info("🎯 LinkFinder TOKEN EXCHANGE INITIATOR")
                        LoggingService.network.info("   Local: \(self.localPeerID.displayName)")
                        LoggingService.network.info("   Remote: \(peerID.displayName)")
                        LoggingService.network.info("   Role: MASTER (initiating)")
                        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        self.uwbTokenExchangeState[peerID.displayName] = .sentToken
                        self.sendUWBDiscoveryToken(to: peerID)
                    }
                } else {
                    // Wait for the other peer to initiate (slave role)
                    LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    LoggingService.network.info("⏳ LinkFinder TOKEN EXCHANGE WAITER")
                    LoggingService.network.info("   Local: \(self.localPeerID.displayName)")
                    LoggingService.network.info("   Remote: \(peerID.displayName)")
                    LoggingService.network.info("   Role: SLAVE (waiting for token)")
                    LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    self.uwbTokenExchangeState[peerID.displayName] = .waitingForToken
                }
                */

                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                LoggingService.network.info("🔒 LinkFinder PRIVACY MODE")
                LoggingService.network.info("   LinkFinder will NOT start automatically")
                LoggingService.network.info("   User must explicitly open LinkFinder view")
                LoggingService.network.info("   Location data remains private until requested")
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            case .connecting:
                LoggingService.network.info("🔍 DEBUG: Handling .connecting state...")
                self.connectionStatus = .connecting

                // Track this peer as currently connecting
                self.connectingPeers.insert(peerID.displayName)

                // No longer need mutex here - iOS handles connection serialization
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                LoggingService.network.info("🔄 PEER STATE: CONNECTING")
                LoggingService.network.info("   Peer: \(peerID.displayName)")
                LoggingService.network.info("   Handshake in progress...")
                LoggingService.network.info("   Session encryption: \(self.session.encryptionPreference == .required ? ".required" : self.session.encryptionPreference == .optional ? ".optional" : ".none")")
                LoggingService.network.info("   Current connected peers in session: \(session.connectedPeers.map { $0.displayName })")
                LoggingService.network.info("   🔒 Added to connectingPeers set (protected from forced reconnect)")
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                let handshakeStartTime = Date()
                let peerName = peerID.displayName

                // FINAL TIMEOUT: Monitor full handshake timeout
                // Lightning Mode: 6s (ultra-fast recovery), Normal: 11s
                let handshakeTimeout: TimeInterval = UserDefaults.standard.bool(forKey: "lightningModeUltraFast") ? 6.0 : 11.0

                // EARLY DETECTION: Check if certificate exchange starts within 3 seconds
                // In healthy handshakes, certificate exchange happens almost immediately
                // If it doesn't start within 3s, the handshake is likely stalled
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    guard let self = self else { return }

                    // Check if still connecting and certificate exchange hasn't started
                    if self.connectingPeers.contains(peerName) &&
                       !self.certificateExchangeStarted.contains(peerName) &&
                       !self.connectedPeers.contains(where: { $0.displayName == peerName }) {

                        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        LoggingService.network.info("⚠️ EARLY WARNING: Certificate exchange not started")
                        LoggingService.network.info("   Peer: \(peerName)")
                        LoggingService.network.info("   Elapsed: 3.0s")
                        LoggingService.network.info("   Status: Still in .connecting but no certificate exchange")

                        // DEBUGGING: Add detailed diagnostic information
                        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        LoggingService.network.info("🔍 DIAGNOSTIC INFORMATION:")
                        LoggingService.network.info("   Session connected peers: \(self.session.connectedPeers.map { $0.displayName })")
                        LoggingService.network.info("   Connection mutex has active operation: \(self.connectionMutex.hasActiveOperation(for: peerID))")
                        LoggingService.network.info("   Network status: \(self.networkConfigDetector.currentStatus.rawValue)")
                        LoggingService.network.info("   Bidirectional mode would be: \(self.sessionManager.shouldUseBidirectionalConnection(for: peerID))")
                        LoggingService.network.info("   Failed connection attempts: \(self.failedConnectionAttempts[peerName] ?? 0)")
                        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                        LoggingService.network.info("   Likely causes:")
                        LoggingService.network.info("   1. Race condition - both peers trying to connect simultaneously")
                        LoggingService.network.info("   2. iOS networking stack has blacklisted peer (Socket Error 61)")
                        LoggingService.network.info("   3. WiFi enabled but not connected (tries WiFi Direct, fails)")
                        LoggingService.network.info("   4. Session state corrupted from previous failed attempt")
                        LoggingService.network.info("   This will likely timeout in ~\(Int(handshakeTimeout - 3.0)) more seconds")
                        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    }
                }

                // Second timeout check after full handshake timeout period
                DispatchQueue.main.asyncAfter(deadline: .now() + handshakeTimeout) { [weak self] in
                    guard let self = self else { return }
                    // Check if still in connecting state after 11 seconds (iOS internal timeout is 10s)
                    if !self.connectedPeers.contains(where: { $0.displayName == peerName }) {
                        let elapsed = Date().timeIntervalSince(handshakeStartTime)
                        let hadCertExchange = self.certificateExchangeStarted.contains(peerName)

                        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        LoggingService.network.info("⚠️ HANDSHAKE TIMEOUT DETECTED")
                        LoggingService.network.info("   Peer: \(peerName)")
                        LoggingService.network.info("   Elapsed: \(String(format: "%.1f", elapsed))s")
                        LoggingService.network.info("   Certificate exchange started: \(hadCertExchange ? "✅ YES" : "❌ NO")")
                        LoggingService.network.info("   Diagnosis: \(hadCertExchange ? "Handshake started but failed to complete" : "Handshake never started - session state corrupted")")
                        LoggingService.network.info("   Session encryption: \(self.session.encryptionPreference == .required ? ".required" : self.session.encryptionPreference == .optional ? ".optional" : ".none")")
                        LoggingService.network.info("   Action: Releasing mutex and cleaning up connection state")
                        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                        // Clean up tracking for this peer
                        self.certificateExchangeStarted.remove(peerName)
                        self.connectingPeers.remove(peerName)

                        // CRITICAL: Release mutex to unblock future connection attempts
                        self.connectionMutex.forceRelease(for: peerID)

                        // Force disconnect to trigger .notConnected callback
                        // This ensures proper cleanup via the normal disconnection path
                        if self.session.connectedPeers.contains(peerID) {
                            LoggingService.network.info("   Forcing disconnect to trigger cleanup...")
                            // Note: MultipeerConnectivity doesn't expose cancelConnection
                            // Rely on iOS to timeout and trigger .notConnected
                        }
                    }
                }

            case .notConnected:
                // Remove from connecting peers set
                let wasInConnectingState = self.connectingPeers.contains(peerID.displayName)
                self.connectingPeers.remove(peerID.displayName)

                // Clean up certificate exchange tracking
                self.certificateExchangeStarted.remove(peerID.displayName)

                // Aggressively release any connection locks
                self.connectionMutex.releaseLock(for: peerID)

                // Double-check and force release if needed (in case of stuck locks)
                DispatchQueue.main.async {
                    self.connectionMutex.releaseLock(for: peerID)
                }

                // Note: MCNearbyServiceBrowser doesn't have cancelConnectPeer method
                // Disconnection is handled by the session state changes

                let wasConnected = self.connectedPeers.contains(peerID)
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                LoggingService.network.info("🔌 PEER DISCONNECTION EVENT")
                LoggingService.network.info("   Peer: \(peerID.displayName)")
                LoggingService.network.info("   Was connected: \(wasConnected)")
                LoggingService.network.info("   Was in connecting state: \(wasInConnectingState)")
                LoggingService.network.info("   Remaining connected peers: \(self.connectedPeers.count - 1)")

                // DETECT CONNECTION REFUSED: If peer never connected but went to .notConnected quickly
                // This typically happens with "Connection refused" (error 61) errors
                if !wasConnected && wasInConnectingState {
                    LoggingService.network.info("   🚨 LIKELY CONNECTION REFUSED ERROR")
                    LoggingService.network.info("      Peer went from .connecting → .notConnected without ever being .connected")
                    LoggingService.network.info("      This usually indicates:")
                    LoggingService.network.info("      - Advertiser not listening on expected port")
                    LoggingService.network.info("      - TCP connection refused by remote peer")
                    LoggingService.network.info("      - Firewall/network blocking connection")
                    self.sessionManager.recordConnectionRefused(to: peerID)

                    // Record failure in diagnostics
                    // Diagnostics temporarily disabled
                    /*
                    let attemptCount = self.sessionManager.getAttemptCount(for: peerID)
                    let avgLatency = self.healthMonitor.averageLatency(for: peerID)
                    self.diagnostics.recordAttempt(
                        peerID: peerID,
                        attemptNumber: attemptCount,
                        timeout: self.calculateInvitationTimeout(for: peerID, attempt: attemptCount),
                        result: .refused,
                        latency: avgLatency,
                        networkStatus: self.networkConfigDetector.currentStatus
                    )
                    */

                    // Check if we should enable bidirectional mode
                    if self.sessionManager.shouldUseBidirectionalConnection(for: peerID) {
                        LoggingService.network.info("   🔀 ENABLING AGGRESSIVE BIDIRECTIONAL CONNECTION")
                        LoggingService.network.info("      Will attempt connection from both sides simultaneously")

                        // Schedule a retry with bidirectional mode after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                            guard let self = self else { return }

                            // Check if peer is still available and not connected
                            if self.availablePeers.contains(where: { $0 == peerID }) &&
                               !self.connectedPeers.contains(peerID) {
                                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                                LoggingService.network.info("🔀 RETRYING WITH BIDIRECTIONAL MODE")
                                LoggingService.network.info("   Peer: \(peerID.displayName)")
                                LoggingService.network.info("   Mode: Both sides attempt connection")
                                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                                self.connectToPeer(peerID, forceIgnoreConflictResolution: false)
                            }
                        }
                    }
                }

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
                        LoggingService.network.info("🛑 Auto-stopping Live Activity - no peers connected")
                        self.stopLiveActivity()
                    }
                }

                // Remove from routing table
                self.routingTable.removePeer(peerID.displayName)

                // Remove from route cache - invalidate all routes using this peer as next hop
                self.routeCache.removeRoutesVia(nextHop: peerID.displayName)
                LoggingService.network.info("🗑️ [RouteCache] Cleaned routes via disconnected peer: \(peerID.displayName)")

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
                    LoggingService.network.info("   🎯 Recording disconnection with Orchestrator")
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

                LoggingService.network.info("   💬 CONVERSATION STATUS:")
                LoggingService.network.info("      Has conversation: \(hasConversation)")
                LoggingService.network.info("      Conversation ID: \(familyConversationId)")
                if let descriptor = conversationDescriptor {
                    LoggingService.network.info("      Conversation title: \(descriptor.title)")
                    LoggingService.network.info("      Message count: \(self.messageStore.messages(for: familyConversationId).count)")
                }
                LoggingService.network.info("   Active conversation: \(self.messageStore.activeConversationId)")
                LoggingService.network.info("   Total conversations: \(self.messageStore.conversationSummaries.count)")

                if wasConnected {
                    LoggingService.network.info("❌ DISCONNECTION: Lost connection to peer: \(peerID.displayName)")

                    // ACCESSIBILITY: Announce disconnection + haptic feedback
                    AudioManager.shared.announceConnectionChange(connected: false, peerName: peerID.displayName)
                    HapticManager.shared.playPattern(.peerDisconnected, priority: .notification)
                    LoggingService.network.info("🔌 Disconnected from \(peerID.displayName)")

                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                } else {
                    LoggingService.network.info("📵 Connection attempt failed for peer: \(peerID.displayName)")
                    // Handle connection failure with retry logic
                    self.handleConnectionFailure(with: peerID)
                }

                // Always stop monitoring when disconnected
                LoggingService.network.info("🏥 Stopped monitoring: \(peerID.displayName)")

                if wasConnected {
                    // Force rediscovery for truly disconnected peers
                    self.availablePeers.removeAll { $0 == peerID }

                    // FIX: Clear peerEventTimes to allow immediate rediscovery
                    // Without this, the 10-second deduplication window blocks foundPeer events
                    self.peerEventTimes.removeValue(forKey: peerID.displayName)
                    LoggingService.network.info("🔍 Peer \(peerID.displayName) removed from available peers and event cache - ready for immediate rediscovery")
                } else {
                    // Keep failed peers in the available list so retry logic can trigger quickly
                    if !self.availablePeers.contains(where: { $0.displayName == peerID.displayName }) {
                        self.availablePeers.append(peerID)
                    }
                    LoggingService.network.info("🕸️ Retaining \(peerID.displayName) in available peers for retry")
                }

            @unknown default:
                LoggingService.network.info("⚠️ NetworkManager: Unknown connection state for peer: \(peerID.displayName)")
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
        LoggingService.network.info("📡 NetworkManager: Received stream (not implemented): \(streamName) from \(peerID.displayName)")
    }

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not used in this implementation
        LoggingService.network.info("📡 NetworkManager: Started receiving resource (not implemented): \(resourceName) from \(peerID.displayName)")
    }

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Not used in this implementation
        LoggingService.network.info("📡 NetworkManager: Finished receiving resource (not implemented): \(resourceName) from \(peerID.displayName)")
    }

    func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
        // CRITICAL FIX: This delegate method is marked as "optional" by Apple,
        // but in practice it MUST be implemented to prevent random disconnections
        // after sending data. Multiple Stack Overflow threads confirm this.
        //
        // For development and encrypted sessions, we accept all certificates.
        // In production, you can add certificate validation logic here.

        let startTime = Date()

        // Mark that certificate exchange has started for this peer
        DispatchQueue.main.async { [weak self] in
            self?.certificateExchangeStarted.insert(peerID.displayName)
        }

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🔐 CERTIFICATE EXCHANGE STARTED")
        LoggingService.network.info("   From peer: \(peerID.displayName)")
        LoggingService.network.info("   Certificate count: \(certificate?.count ?? 0)")
        LoggingService.network.info("   Thread: \(Thread.current.isMainThread ? "MAIN" : "BACKGROUND [\(Thread.current.description)]")")
        LoggingService.network.info("   Timestamp: \(Date())")
        LoggingService.network.info("   ✅ Marked certificate exchange as started")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Accept certificate immediately
        certificateHandler(true)

        let elapsed = Date().timeIntervalSince(startTime) * 1000.0 // Convert to milliseconds

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("✅ CERTIFICATE ACCEPTED")
        LoggingService.network.info("   Peer: \(peerID.displayName)")
        LoggingService.network.info("   Handler response time: \(String(format: "%.2f", elapsed))ms")
        LoggingService.network.info("   Total elapsed: \(String(format: "%.2f", elapsed))ms")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension NetworkManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("📨 ADVERTISER: RECEIVED INVITATION ✅")
        LoggingService.network.info("   From: \(peerID.displayName)")
        LoggingService.network.info("   To: \(self.localPeerID.displayName)")
        LoggingService.network.info("   Advertiser active: \(self.advertiser != nil)")
        LoggingService.network.info("   Advertiser delegate: \(self.advertiser?.delegate != nil)")
        LoggingService.network.info("   Connected Peers: \(self.connectedPeers.count)/\(self.config.maxConnections)")
        LoggingService.network.info("   Timestamp: \(Date())")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // STEP 1: Temporal deduplication - reject duplicate invitations received within 500ms
        LoggingService.network.info("🔍 DEBUG STEP 1: Checking for duplicate invitation...")
        let peerKey = peerID.displayName
        let now = Date()
        if let lastInvitationTime = invitationEventTimes[peerKey],
           now.timeIntervalSince(lastInvitationTime) < 0.5 {
            let timeSince = now.timeIntervalSince(lastInvitationTime)
            LoggingService.network.info("🔇 REJECTING DUPLICATE INVITATION from \(peerKey)")
            LoggingService.network.info("   Last invitation: \(String(format: "%.3f", timeSince))s ago")
            LoggingService.network.info("   This is likely a rapid-fire duplicate from remote peer")
            invitationHandler(false, nil)
            return
        }
        LoggingService.network.info("   ✓ Not a duplicate invitation")

        // Record this invitation timestamp
        invitationEventTimes[peerKey] = now

        // Clean up old invitation timestamps (older than 10 seconds)
        invitationEventTimes = invitationEventTimes.filter { _, timestamp in
            now.timeIntervalSince(timestamp) < 10.0
        }

        // STEP 1.5: Try to acquire mutex lock for accept_invitation operation
        LoggingService.network.info("🔍 DEBUG STEP 1.5: Trying to acquire ConnectionMutex...")
        guard connectionMutex.tryAcquireLock(for: peerID, operation: .acceptInvitation) else {
            LoggingService.network.info("🔒 REJECTING INVITATION - Another operation in progress for \(peerKey)")
            LoggingService.network.info("   An invitation is already being processed or connection is in progress")
            invitationHandler(false, nil)
            return
        }
        LoggingService.network.info("   ✓ Mutex lock acquired for accept_invitation")

        // Check TestingConfig blocking
        LoggingService.network.info("🔍 DEBUG STEP 2: Checking TestingConfig blocking...")
        if TestingConfig.shouldBlockDirectConnection(from: localPeerID.displayName, to: peerID.displayName) {
            LoggingService.network.info("🧪 TEST MODE: Declining invitation from \(peerID.displayName) - blocked by TestingConfig")
            connectionMutex.releaseLock(for: peerID)
            invitationHandler(false, nil)
            sessionManager.recordConnectionDeclined(to: peerID, reason: "blocked by TestingConfig")
            return
        }
        LoggingService.network.info("   ✓ TestingConfig: Not blocked")

        // Check if peer is manually blocked
        LoggingService.network.info("🔍 DEBUG STEP 3: Checking manual blocking...")
        if connectionManager.isPeerBlocked(peerID.displayName) {
            LoggingService.network.info("🚫 NetworkManager: Declining invitation from \(peerID.displayName) - peer is manually blocked")
            connectionMutex.releaseLock(for: peerID)
            invitationHandler(false, nil)
            sessionManager.recordConnectionDeclined(to: peerID, reason: "manually blocked")
            return
        }
        LoggingService.network.info("   ✓ Manual blocking: Not blocked")

        // Check if already connected
        LoggingService.network.info("🔍 DEBUG STEP 4: Checking if already connected...")
        if connectedPeers.contains(peerID) {
            LoggingService.network.info("⛔ Declining invitation from \(peerID.displayName) - already connected")
            LoggingService.network.info("   Current connected peers: \(self.connectedPeers.map { $0.displayName }.joined(separator: ", "))")
            connectionMutex.releaseLock(for: peerID)
            invitationHandler(false, nil)
            return
        }
        LoggingService.network.info("   ✓ Already connected: No")

        // Check if we've reached max connections
        LoggingService.network.info("🔍 DEBUG STEP 5: Checking max connections...")
        if hasReachedMaxConnections() {
            LoggingService.network.info("⛔ Declining invitation from \(peerID.displayName) - max connections reached (\(self.connectedPeers.count)/\(self.config.maxConnections))")
            connectionMutex.releaseLock(for: peerID)
            invitationHandler(false, nil)
            return
        }
        LoggingService.network.info("   ✓ Max connections: \(self.connectedPeers.count)/\(self.config.maxConnections) - OK")

        // Check conflict resolution - should we accept based on ID comparison?
        // BUT: If we've had failures trying to connect to this peer OR SessionManager is blocking us, accept the invitation anyway
        LoggingService.network.info("🔍 DEBUG STEP 6: Checking conflict resolution...")
        let hasFailedConnections = (failedConnectionAttempts[peerKey] ?? 0) > 0
        let sessionManagerBlocking = !sessionManager.shouldAttemptConnection(to: peerID)
        // FIXED: Removed isUltraFastModeEnabled to prevent race conditions
        let useBidirectionalMode = sessionManager.shouldUseBidirectionalConnection(for: peerID) // || isUltraFastModeEnabled
        let conflictResolutionSaysAccept = ConnectionConflictResolver.shouldAcceptInvitation(localPeer: localPeerID, fromPeer: peerID, overrideBidirectional: useBidirectionalMode)

        LoggingService.network.info("   Failed connections count: \(self.failedConnectionAttempts[peerKey] ?? 0)")
        LoggingService.network.info("   SessionManager blocking: \(sessionManagerBlocking)")
        LoggingService.network.info("   Bidirectional mode: \(useBidirectionalMode)")
        LoggingService.network.info("   Conflict resolution says accept: \(conflictResolutionSaysAccept)")

        if !hasFailedConnections && !sessionManagerBlocking && !useBidirectionalMode && !conflictResolutionSaysAccept {
            LoggingService.network.info("🆔 Declining invitation - we should initiate to \(peerID.displayName)")
            LoggingService.network.info("   Local ID: \(self.localPeerID.displayName)")
            LoggingService.network.info("   Remote ID: \(peerID.displayName)")
            LoggingService.network.info("   Comparison: \(self.localPeerID.displayName < peerID.displayName ? "Local < Remote" : "Local > Remote")")
            connectionMutex.releaseLock(for: peerID)
            invitationHandler(false, nil)
            sessionManager.recordConnectionDeclined(to: peerID, reason: "conflict resolution says we should initiate")
            return
        } else if hasFailedConnections {
            LoggingService.network.info("🔄 Accepting invitation despite conflict resolution - previous failures detected for \(peerKey)")
        } else if sessionManagerBlocking {
            LoggingService.network.info("🔄 Accepting invitation despite conflict resolution - SessionManager is blocking our attempts")
        } else if useBidirectionalMode {
            LoggingService.network.info("🔀 ACCEPTING invitation - BIDIRECTIONAL MODE active for \(peerKey)")
            LoggingService.network.info("   Previous connection attempts failed with 'Connection refused'")
            LoggingService.network.info("   Both peers attempting connection to maximize success")
        } else {
            LoggingService.network.info("   ✓ Conflict resolution: Accept invitation (we are slave)")
        }

        // NOTE: We already acquired the mutex lock at the beginning of this function
        // This ensures only ONE invitation is processed at a time per peer
        LoggingService.network.info("🔍 DEBUG STEP 7: Mutex lock verification...")
        LoggingService.network.info("   ✓ Mutex lock is held for accept_invitation operation")

        // Accept invitation if we have failures OR SessionManager is blocking us (deadlock breaker)
        LoggingService.network.info("🔍 DEBUG STEP 8: Final acceptance decision...")

        // Use orchestrator decision if enabled
        let shouldAccept: Bool
        if isOrchestratorEnabled {
            LoggingService.network.info("   🎯 Using Orchestrator for invitation decision")
            shouldAccept = shouldAcceptInvitationFromPeer(peerID)
        } else {
            // Legacy decision logic
            shouldAccept = hasFailedConnections || sessionManagerBlocking || sessionManager.shouldAttemptConnection(to: peerID)
        }

        LoggingService.network.info("   Should accept: \(shouldAccept)")
        LoggingService.network.info("   Decision source: \(self.isOrchestratorEnabled ? "Orchestrator" : "Legacy logic")")

        guard shouldAccept else {
            LoggingService.network.info("⛔ Declining invitation from \(peerID.displayName) - connection not allowed")
            connectionMutex.releaseLock(for: peerID)
            invitationHandler(false, nil)
            sessionManager.recordConnectionDeclined(to: peerID, reason: isOrchestratorEnabled ? "orchestrator declined" : "session manager not allowing")
            return
        }

        // REMOVED: Unconditional SessionManager clearing
        // This was causing race conditions when multiple invitations arrived simultaneously
        // Now we only clear if this is genuinely the first invitation (protected by mutex)
        LoggingService.network.info("🔍 DEBUG STEP 9: Session manager state check...")
        if sessionManagerBlocking {
            LoggingService.network.info("   ℹ️ SessionManager was blocking, but proceeding with invitation")
            LoggingService.network.info("   (Mutex ensures this is the first/only invitation being processed)")
        }
        if hasFailedConnections {
            LoggingService.network.info("   ℹ️ Previous connection failures detected: \(self.failedConnectionAttempts[peerKey] ?? 0)")
        }

        // Record attempt BEFORE accepting
        LoggingService.network.info("🔍 DEBUG STEP 10: Recording connection attempt...")
        sessionManager.recordConnectionAttempt(to: peerID)
        LoggingService.network.info("   ✓ Connection attempt recorded")

        // Accept invitation while holding mutex
        // Mutex will be released in session(_:peer:didChange:) when connection completes or fails
        LoggingService.network.info("🔍 DEBUG STEP 11: Calling invitationHandler(true, session)...")
        LoggingService.network.info("   Session ID: \(self.session)")
        LoggingService.network.info("   Session memory address: \(String(describing: Unmanaged.passUnretained(self.session).toOpaque()))")
        LoggingService.network.info("   Session encryption: \(self.self.session.encryptionPreference == .required ? ".required" : self.self.session.encryptionPreference == .optional ? ".optional" : ".none")")
        LoggingService.network.info("   Session connected peers: \(self.session.connectedPeers.map { $0.displayName })")
        LoggingService.network.info("   LocalPeerID: \(self.localPeerID.displayName)")
        LoggingService.network.info("   LocalPeerID memory address: \(String(describing: Unmanaged.passUnretained(self.localPeerID).toOpaque()))")
        LoggingService.network.info("   About to accept invitation at: \(Date())")

        invitationHandler(true, session)

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("✅ INVITATION ACCEPTED (mutex held)")
        LoggingService.network.info("   From: \(peerID.displayName)")
        LoggingService.network.info("   Session encryption: \(self.session.encryptionPreference == .required ? ".required" : self.session.encryptionPreference == .optional ? ".optional" : ".none")")
        LoggingService.network.info("   Mutex will be released when handshake completes")
        LoggingService.network.info("   Waiting for iOS to complete handshake...")
        LoggingService.network.info("   Next: session(_:peer:didChange:) will be called")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // NOTE: We do NOT release the mutex here
        // It will be released in session(_:peer:didChange:) when state becomes .connected or .notConnected
        // This prevents duplicate invitations from being accepted while handshake is in progress
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        LoggingService.network.info("❌ NetworkManager: Failed to start advertising: \(error.localizedDescription)")

        DispatchQueue.main.async {
            self.isAdvertising = false
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension NetworkManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🔍 BROWSER: PEER DISCOVERED")
        LoggingService.network.info("   Peer: \(peerID.displayName)")
        LoggingService.network.info("   Discovery Info: \(info ?? [:])")
        LoggingService.network.info("   Timestamp: \(Date())")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        let peerKey = peerID.displayName
        let now = Date()

        // Update last peer discovery time
        lastPeerDiscoveryTime = now

        // Check for recent found event
        LoggingService.network.info("🔍 DEBUG: Checking for duplicate discovery events...")
        if let lastFound = peerEventTimes[peerKey]?.found,
           now.timeIntervalSince(lastFound) < eventDeduplicationWindow {
            LoggingService.network.info("🔇 Ignoring duplicate found event for \(peerKey)")
            LoggingService.network.info("   Last found: \(String(format: "%.1f", now.timeIntervalSince(lastFound)))s ago")
            return
        }
        LoggingService.network.info("   ✓ Not a duplicate")

        // Update event time
        if peerEventTimes[peerKey] != nil {
            peerEventTimes[peerKey]?.found = now
        } else {
            peerEventTimes[peerKey] = (found: now, lost: nil)
        }

        DispatchQueue.main.async {
            LoggingService.network.info("🔍 DEBUG: Adding peer to availablePeers...")

            // Remove any existing entries for this displayName first (handles stale entries)
            let previousCount = self.availablePeers.count
            self.availablePeers.removeAll { $0.displayName == peerID.displayName }
            if previousCount != self.availablePeers.count {
                LoggingService.network.info("   Removed \(previousCount - self.availablePeers.count) stale entries")
            }

            // Now add the peer (fresh entry)
            if peerID != self.localPeerID {
                self.availablePeers.append(peerID)
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                LoggingService.network.info("✅ PEER ADDED TO AVAILABLE LIST")
                LoggingService.network.info("   Peer: \(peerID.displayName)")
                LoggingService.network.info("   Total Available Peers: \(self.availablePeers.count)")
                LoggingService.network.info("   Total Connected Peers: \(self.connectedPeers.count)")
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                // INTELLIGENT DISCONNECTION: Check for peers marked as pendingDisconnect
                // When a new peer is discovered, disconnect any peers user wanted to disconnect
                self.processingQueue.async { [weak self] in
                    guard let self = self else { return }

                    let pendingDisconnectPeers = self.peerConnectionStates.filter { $0.value == .pendingDisconnect }

                    if !pendingDisconnectPeers.isEmpty {
                        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        LoggingService.network.info("🔌 AUTO-DISCONNECTION: New peer available")
                        LoggingService.network.info("   New peer: \(peerID.displayName)")
                        LoggingService.network.info("   Peers pending disconnect: \(pendingDisconnectPeers.keys.joined(separator: ", "))")
                        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                        // Disconnect all pending peers now that we have an alternative
                        for (peerKey, _) in pendingDisconnectPeers {
                            if let peerToDisconnect = self.connectedPeers.first(where: { $0.displayName == peerKey }) {
                                LoggingService.network.info("   Executing delayed disconnect for \(peerKey)")

                                DispatchQueue.main.async {
                                    // Perform actual disconnection
                                    self.session.cancelConnectPeer(peerToDisconnect)

                                    // Clean up all state for this peer
                                    self.cleanupPeerState(peerToDisconnect)

                                    LoggingService.network.info("   ✅ Auto-disconnection completed for \(peerKey)")
                                }
                            }
                        }

                        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    }
                }

                // INCREASED DELAY: Give iOS time to stabilize mDNS resolution and transport layer
                // Was 0.1-0.5s (too fast, causes state corruption)
                // Now 2-4s to prevent iOS networking stack saturation
                let jitter = Double.random(in: 2.0...4.0)
                LoggingService.network.info("⏱️ Will attempt connection to \(peerID.displayName) in \(String(format: "%.1f", jitter)) seconds (increased delay for stability)")

                DispatchQueue.main.asyncAfter(deadline: .now() + jitter) { [weak self] in
                    guard let self = self else { return }

                    LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    LoggingService.network.info("🔍 AUTO-CONNECTION EVALUATION")
                    LoggingService.network.info("   Peer: \(peerID.displayName)")
                    LoggingService.network.info("   Timestamp: \(Date())")
                    LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                    // Check TestingConfig blocking first
                    LoggingService.network.info("   Step 1: Checking TestingConfig...")
                    if TestingConfig.shouldBlockDirectConnection(from: self.localPeerID.displayName, to: peerID.displayName) {
                        LoggingService.network.info("🧪 TEST MODE: Blocked direct connection to \(peerID.displayName)")
                        return
                    }
                    LoggingService.network.info("   ✓ TestingConfig: Not blocked")

                    // Enhanced logging for conflict resolution decision
                    LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    LoggingService.network.info("👥 PEER DISCOVERY DECISION ANALYSIS")
                    LoggingService.network.info("   Local: \(self.localPeerID.displayName)")
                    LoggingService.network.info("   Remote: \(peerID.displayName)")

                    let shouldInitiate = ConnectionConflictResolver.shouldInitiateConnection(localPeer: self.localPeerID, remotePeer: peerID)
                    let peerKey = peerID.displayName

                    LoggingService.network.info("   📊 Hash-Based Decision:")
                    LoggingService.network.info("      Local hash: \(self.localPeerID.displayName.hashValue)")
                    LoggingService.network.info("      Remote hash: \(peerID.displayName.hashValue)")
                    LoggingService.network.info("      We should: \(shouldInitiate ? "INITIATE 🟢" : "WAIT 🟡")")
                    LoggingService.network.info("      They should: \(shouldInitiate ? "WAIT 🟡" : "INITIATE 🟢")")

                    if !shouldInitiate {
                        LoggingService.network.info("   ⏰ Will wait max 5s for invitation before forcing")
                    }
                    LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                    let isWaitingForInvitation = self.waitingForInvitationFrom[peerKey] != nil
                    let alreadyConnected = self.connectedPeers.contains(where: { $0.displayName == peerID.displayName })
                    let maxConnectionsReached = self.hasReachedMaxConnections()
                    let stillAvailable = self.availablePeers.contains(where: { $0.displayName == peerID.displayName })
                    let sessionManagerAllows = self.sessionManager.shouldAttemptConnection(to: peerID)

                    LoggingService.network.info("   Step 2: Connection criteria check:")
                    LoggingService.network.info("      Already connected? \(alreadyConnected)")
                    LoggingService.network.info("      Max connections reached? \(maxConnectionsReached) (\(self.connectedPeers.count)/\(self.config.maxConnections))")
                    LoggingService.network.info("      Still available? \(stillAvailable)")
                    LoggingService.network.info("      Should initiate? \(shouldInitiate)")
                    LoggingService.network.info("      Already waiting? \(isWaitingForInvitation)")
                    LoggingService.network.info("      Session manager allows? \(sessionManagerAllows)")

                    // Use orchestrator decision if enabled
                    let shouldConnect: Bool
                    if self.isOrchestratorEnabled {
                        LoggingService.network.info("   🎯 Using Orchestrator for decision")
                        let orchestratorAccepts = self.shouldConnectToDiscoveredPeer(peerID, discoveryInfo: info)

                        // CRITICAL: Orchestrator must respect conflict resolution to prevent bidirectional deadlock
                        // Only initiate if BOTH orchestrator approves AND we should be the initiator
                        if orchestratorAccepts && !shouldInitiate {
                            LoggingService.network.info("   ⚠️ Orchestrator approved BUT conflict resolver says WAIT")
                            LoggingService.network.info("   → Will wait for their invitation instead of initiating")
                            shouldConnect = false
                        } else {
                            shouldConnect = orchestratorAccepts && shouldInitiate
                        }
                    } else {
                        // Legacy decision logic
                        shouldConnect = !alreadyConnected &&
                                      !maxConnectionsReached &&
                                      stillAvailable &&
                                      shouldInitiate &&
                                      sessionManagerAllows
                    }

                    if shouldConnect {
                        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        LoggingService.network.info("✅ INITIATING CONNECTION")
                        LoggingService.network.info("   To: \(peerID.displayName)")
                        LoggingService.network.info("   Reason: \(self.isOrchestratorEnabled ? "Orchestrator + Conflict resolver approved" : "All criteria met")")
                        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        self.waitingForInvitationFrom.removeValue(forKey: peerKey)  // Clear waiting status
                        // Don't force ignore conflict resolution - we already checked it above
                        self.connectToPeer(peerID, forceIgnoreConflictResolution: false)
                    } else {
                        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        LoggingService.network.info("⏸️ SKIPPING CONNECTION")
                        LoggingService.network.info("   To: \(peerID.displayName)")
                        if alreadyConnected {
                            LoggingService.network.info("   Reason: Already connected")
                        } else if maxConnectionsReached {
                            LoggingService.network.info("   Reason: Max connections reached (\(self.connectedPeers.count)/\(self.config.maxConnections))")
                        } else if !stillAvailable {
                            LoggingService.network.info("   Reason: Peer no longer available")
                        } else if !shouldInitiate {
                            LoggingService.network.info("   Reason: Conflict resolution - waiting for them to initiate")
                            // Record that we're waiting for an invitation
                            if self.waitingForInvitationFrom[peerKey] == nil {
                                self.waitingForInvitationFrom[peerKey] = Date()
                                LoggingService.network.info("   ⏰ Started waiting for invitation")
                            }
                        } else if !sessionManagerAllows {
                            LoggingService.network.info("   Reason: SessionManager blocking (cooldown/retry limit)")
                        }
                        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    }
                }
            } else {
                LoggingService.network.info("   ⚠️ Discovered self - ignoring")
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let peerKey = peerID.displayName
        let now = Date()

        // Check for recent lost event
        if let lastLost = peerEventTimes[peerKey]?.lost,
           now.timeIntervalSince(lastLost) < eventDeduplicationWindow {
            LoggingService.network.info("🔇 Ignoring duplicate lost event for \(peerKey)")
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
            LoggingService.network.info("👻 NetworkManager: Lost peer: \(peerID.displayName)")
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        LoggingService.network.info("❌ NetworkManager: Failed to start browsing: \(error.localizedDescription)")

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
        LoggingService.network.info("\(self.getConnectionDiagnostics())")

        if !connectedPeers.isEmpty {
            LoggingService.network.info("Connected to:")
            for peer in connectedPeers {
                if let stats = healthMonitor.getHealthStats(for: peer) {
                    LoggingService.network.info("  • \(peer.displayName) - Quality: \(stats.quality.rawValue), Latency: \(Int(stats.latency))ms")
                } else {
                    LoggingService.network.info("  • \(peer.displayName) - No health data")
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
        LoggingService.network.info("🔄 Re-enqueuing message for retry: \(message.id)")
    }

    func ackManager(_ manager: AckManager, didReceiveAckFor messageId: UUID) {
        DispatchQueue.main.async {
            self.pendingAcksCount = manager.getPendingAcksCount()
        }
    }

    func ackManager(_ manager: AckManager, didFailToReceiveAckFor messageId: UUID) {
        DispatchQueue.main.async {
            self.pendingAcksCount = manager.getPendingAcksCount()
            LoggingService.network.info("❌ Message failed after max retries: \(messageId)")
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
        LoggingService.network.info("⚠️ NetworkManager: Lost LinkFinder tracking of \(peerId) - Reason: \(reason.description)")
    }

    func uwbSessionManager(_ manager: LinkFinderSessionManager, sessionInvalidatedFor peerId: String, error: Error) {
        LoggingService.network.info("❌ NetworkManager: LinkFinder session invalidated for \(peerId): \(error.localizedDescription)")

        // Check if it's a permission denied error
        if error.localizedDescription.contains("USER_DID_NOT_ALLOW") {
            LoggingService.network.info("⚠️ NetworkManager: LinkFinder permission denied by user for \(peerId)")
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
                LoggingService.network.info("🔄 NetworkManager: Attempting to restart LinkFinder session with \(peerId) (retry \(retries + 1)/\(self.maxUWBRetries))")

                // Add a delay before retrying
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.sendUWBDiscoveryToken(to: peer)
                }
            } else {
                LoggingService.network.info("❌ NetworkManager: Max LinkFinder retries reached for \(peerId)")
                uwbRetryCount[peerId] = 0
            }
        }
    }

    func uwbSessionManager(_ manager: LinkFinderSessionManager, requestsRestartFor peerId: String) {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🔄 LinkFinder RESTART REQUESTED")
        LoggingService.network.info("   Peer: \(peerId)")
        LoggingService.network.info("   Action: Coordinating bidirectional restart")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Send LinkFinder_RESET_REQUEST to peer
        if let peer = connectedPeers.first(where: { $0.displayName == peerId }) {
            sendUWBResetRequest(to: peer)
        }
    }

    func uwbSessionManager(_ manager: LinkFinderSessionManager, needsFreshTokenFor peerId: String) {
        LoggingService.network.info("🔄 NetworkManager: Restarting token exchange for \(peerId)")

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
                    LoggingService.network.info("📤 NetworkManager: MASTER re-sending LinkFinder token to \(peerId)")
                    self?.uwbTokenExchangeState[peerId] = .sentToken
                    self?.sendUWBDiscoveryToken(to: peer)
                }
            } else {
                // SLAVE waits for master
                uwbTokenExchangeState[peerId] = .waitingForToken
                LoggingService.network.info("⏳ NetworkManager: SLAVE waiting for MASTER to re-send token")
            }
        }
    }

    // MARK: - Testing & Simulation

    /// Send a simulated message for testing Live Activity message display
    /// This creates a fake message and adds it to the message store
    /// IMPORTANT: Uses a separate "test-chat" conversation so it counts as UNREAD
    func sendSimulatedMessage(content: String = "Mensaje de prueba", sender: String = "Test User") {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🧪 SENDING SIMULATED MESSAGE")
        LoggingService.network.info("   Sender: \(sender)")
        LoggingService.network.info("   Content: \(content)")
        LoggingService.network.info("   Current active conversation: \(self.messageStore.activeConversationId)")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

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

        LoggingService.network.info("✅ Simulated message added to MessageStore")
        LoggingService.network.info("   Message ID: \(simulatedMessage.id)")
        LoggingService.network.info("   Unread count: \(self.messageStore.unreadCount)")
        LoggingService.network.info("   Total messages: \(self.messageStore.messageCount)")
        LoggingService.network.info("   Latest message sender: \(self.messageStore.latestMessage?.sender ?? "none")")
        LoggingService.network.info("   Latest message content: \(self.messageStore.latestMessage?.content ?? "none")")
        LoggingService.network.info("   Latest message timestamp: \(self.messageStore.latestMessage?.timestamp.description ?? "none")")
        LoggingService.network.info("   🔔 MessageStore observers should trigger Live Activity update")

        // Force Live Activity update immediately
        LoggingService.network.info("   🔄 Forcing Live Activity update NOW...")
        updateLiveActivity()

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
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

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🧪 SENDING \(count) SIMULATED MESSAGES")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        for i in 0..<count {
            let sender = senders[i % senders.count]
            let content = messages[i % messages.count]

            sendSimulatedMessage(content: content, sender: sender)

            // Small delay between messages
            Thread.sleep(forTimeInterval: 0.2)
        }

        LoggingService.network.info("✅ Sent \(count) simulated messages")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}
