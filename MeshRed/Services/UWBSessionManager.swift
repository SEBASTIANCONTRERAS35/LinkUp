//
//  UWBSessionManager.swift
//  MeshRed
//
//  Created by Emilio Contreras on 29/09/25.
//

import Foundation
import NearbyInteraction
import MultipeerConnectivity
import Combine

/// Manages UWB (Ultra Wideband) ranging sessions with peers using NearbyInteraction framework
/// Provides centimeter-level precision for distance and direction measurements
@available(iOS 14.0, *)
class UWBSessionManager: NSObject, ObservableObject {
    // MARK: - Session State
    enum SessionState: CustomStringConvertible {
        case preparing       // Session created, token extracted, not running yet
        case tokenReady      // Waiting for remote peer's token
        case running         // .run() called, waiting for ranging to establish
        case ranging         // didUpdate received, ranging active
        case suspended       // System suspended UWB
        case disconnected    // Session invalidated

        var description: String {
            switch self {
            case .preparing: return "preparing"
            case .tokenReady: return "tokenReady"
            case .running: return "running"
            case .ranging: return "ranging"
            case .suspended: return "suspended"
            case .disconnected: return "disconnected"
            }
        }
    }

    // MARK: - Published Properties
    @Published var activeSessions: [String: NISession] = [:]  // PeerID -> Session
    @Published var nearbyObjects: [String: NINearbyObject] = [:]  // PeerID -> Object
    @Published var isUWBSupported: Bool = false
    @Published var sessionStates: [String: SessionState] = [:]  // PeerID -> State
    @Published var supportsDirectionMeasurement: Bool = false

    // MARK: - Private Properties
    private var discoveryTokens: [String: NIDiscoveryToken] = [:]  // PeerID -> Remote peer's token
    private var localTokens: [String: NIDiscoveryToken] = [:]  // PeerID -> Our token for this peer
    private let queue = DispatchQueue(label: "com.meshred.uwb", qos: .userInitiated)
    private var sessionHealthTimers: [String: Timer] = [:]  // PeerID -> Health check timer
    private var sessionRetryCount: [String: Int] = [:]  // PeerID -> Retry attempt count
    private var lastRestartTime: [String: Date] = [:]  // PeerID -> Last restart timestamp

    // MARK: - Delegates
    weak var delegate: UWBSessionManagerDelegate?

    // MARK: - Initialization
    override init() {
        super.init()
        checkUWBSupport()
    }

    // MARK: - Public Methods

    /// Check if device supports UWB (NearbyInteraction)
    private func checkUWBSupport() {
        #if targetEnvironment(simulator)
        isUWBSupported = false
        supportsDirectionMeasurement = false
        print("⚠️ UWBSessionManager: UWB not available in simulator")
        #else
        isUWBSupported = NISession.deviceCapabilities.supportsPreciseDistanceMeasurement

        if isUWBSupported {
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("📡 UWB DEVICE CAPABILITIES")
            print("   Distance measurement: ✅")

            // Check direction measurement capability
            supportsDirectionMeasurement = NISession.deviceCapabilities.supportsDirectionMeasurement
            print("   Direction measurement: \(supportsDirectionMeasurement ? "✅" : "❌")")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            // Check if Nearby Interaction permission is available (iOS 15+)
            if #available(iOS 15.0, *) {
                checkNearbyInteractionPermission()
            }
        } else {
            supportsDirectionMeasurement = false
            print("⚠️ UWBSessionManager: UWB not supported (requires iPhone 11+ with U1/U2 chip)")
        }
        #endif
    }

    /// Check and request Nearby Interaction permission if needed
    @available(iOS 15.0, *)
    private func checkNearbyInteractionPermission() {
        // Note: iOS doesn't provide a direct way to check Nearby Interaction permission status
        // The permission dialog will be shown automatically when starting a session
        // We can only detect permission issues when a session fails
        print("📡 UWBSessionManager: Nearby Interaction permission will be requested when needed")
    }

    /// Prepare a UWB session for a specific peer (step 1 of token exchange)
    /// Creates the session, extracts token, but does NOT run it yet
    /// Returns the token to send to the remote peer
    func prepareSession(for peerID: MCPeerID) -> NIDiscoveryToken? {
        guard isUWBSupported else {
            print("❌ UWBSessionManager: Cannot prepare session - UWB not supported")
            return nil
        }

        let peerId = peerID.displayName

        // Check if session already prepared
        if activeSessions[peerId] != nil,
           let existingToken = localTokens[peerId],
           let state = sessionStates[peerId],
           state == .preparing || state == .tokenReady {
            print("✅ UWBSessionManager: Session already prepared for \(peerId)")
            return existingToken
        }

        // Clean up any stale session
        if let oldSession = activeSessions[peerId] {
            print("🧹 UWBSessionManager: Cleaning up old session for \(peerId)")
            oldSession.invalidate()
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔧 UWB SESSION PREPARATION")
        print("   Peer: \(peerId)")
        print("   Creating session WITHOUT running it")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Create new session for this specific peer
        let session = NISession()
        session.delegate = self
        session.delegateQueue = queue

        // Extract token from THIS session (not running yet)
        guard let token = session.discoveryToken else {
            print("❌ UWBSessionManager: Failed to get discovery token from session")
            return nil
        }

        // Store session and token
        DispatchQueue.main.async {
            self.activeSessions[peerId] = session
            self.localTokens[peerId] = token
            self.sessionStates[peerId] = .preparing
            self.sessionRetryCount[peerId] = 0
        }

        print("✅ UWBSessionManager: Session prepared for \(peerId)")
        print("   Token extracted: \(String(describing: token).prefix(40))...")
        print("   State: preparing")
        print("   Ready to send token to peer")

        return token
    }

    /// Start UWB ranging session with a peer (step 2 of token exchange)
    /// Requires that prepareSession() was called first
    /// Now runs the session with the remote peer's token
    func startSession(with peerID: MCPeerID, remotePeerToken: NIDiscoveryToken) {
        guard isUWBSupported else {
            print("❌ UWBSessionManager: Cannot start session - UWB not supported")
            return
        }

        let peerId = peerID.displayName

        queue.async { [weak self] in
            guard let self = self else { return }

            // Verify we have a prepared session
            guard let session = self.activeSessions[peerId] else {
                print("❌ UWBSessionManager: No prepared session found for \(peerId)")
                print("   Call prepareSession() first before startSession()")
                return
            }

            let currentState = self.sessionStates[peerId] ?? .disconnected

            // Check if already running or ranging
            if currentState == .running || currentState == .ranging {
                print("✅ UWBSessionManager: Session already running for \(peerId) (state: \(currentState))")
                return
            }

            // Verify we're in preparing or tokenReady state
            if currentState != .preparing && currentState != .tokenReady {
                print("⚠️ UWBSessionManager: Invalid state \(currentState) for \(peerId), expected .preparing or .tokenReady")
            }

            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("🚀 UWB SESSION START")
            print("   Peer: \(peerId)")
            print("   Remote token: \(String(describing: remotePeerToken).prefix(40))...")
            print("   Our token: \(String(describing: self.localTokens[peerId]).prefix(40))...")
            print("   Previous state: \(currentState)")
            print("   Now executing session.run()")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            // Store remote peer's token
            self.discoveryTokens[peerId] = remotePeerToken

            // Configure and run session with remote peer's token
            let config = NINearbyPeerConfiguration(peerToken: remotePeerToken)
            session.run(config)

            DispatchQueue.main.async {
                self.sessionStates[peerId] = .running
                print("📡 UWBSessionManager: Session RUNNING for \(peerId)")
                print("   State: preparing → running")
                print("   Total active sessions: \(self.activeSessions.count)")
                print("   Waiting for ranging to establish...")
            }

            // Start health monitoring (give it time to establish ranging)
            self.startHealthCheck(for: peerId, initialDelay: 15.0)
        }
    }

    /// Stop UWB ranging session with a peer
    func stopSession(with peerID: MCPeerID) {
        let peerId = peerID.displayName

        queue.async { [weak self] in
            guard let self = self else { return }

            if let session = self.activeSessions[peerId] {
                session.invalidate()
                self.stopHealthCheck(for: peerId)

                DispatchQueue.main.async {
                    self.activeSessions.removeValue(forKey: peerId)
                    self.nearbyObjects.removeValue(forKey: peerId)
                    self.discoveryTokens.removeValue(forKey: peerId)
                    self.localTokens.removeValue(forKey: peerId)
                    self.sessionStates[peerId] = .disconnected
                    self.sessionRetryCount.removeValue(forKey: peerId)
                    self.lastRestartTime.removeValue(forKey: peerId)
                }

                print("📡 UWBSessionManager: Stopped session with \(peerId)")
            }
        }
    }

    // MARK: - Health Monitoring

    private func startHealthCheck(for peerId: String, initialDelay: TimeInterval = 10.0) {
        stopHealthCheck(for: peerId)  // Clear any existing timer

        // First check after initial delay
        DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay) { [weak self] in
            self?.checkSessionHealth(for: peerId)

            // Then continue with regular checks
            let timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
                self?.checkSessionHealth(for: peerId)
            }

            self?.sessionHealthTimers[peerId] = timer
        }
    }

    private func stopHealthCheck(for peerId: String) {
        sessionHealthTimers[peerId]?.invalidate()
        sessionHealthTimers[peerId] = nil
    }

    private func checkSessionHealth(for peerId: String) {
        guard activeSessions[peerId] != nil else {
            stopHealthCheck(for: peerId)
            return
        }

        let state = sessionStates[peerId] ?? .disconnected
        let hasObject = nearbyObjects[peerId] != nil

        print("🏥 UWB Health Check for \(peerId): State=\(state), HasObject=\(hasObject)")

        // Only check health if we're in .running state (not .preparing or .tokenReady)
        // If we're .running but haven't received any objects for a while, try to restart
        if state == .running && !hasObject {
            let retryCount = sessionRetryCount[peerId] ?? 0

            print("⚠️ UWBSessionManager: Session connected but no ranging data for \(peerId) (retry: \(retryCount)/3)")

            // Check backoff: Don't retry too frequently
            if let lastRestart = lastRestartTime[peerId] {
                let backoffDelay = pow(2.0, Double(retryCount)) * 5.0  // 5s, 10s, 20s, 40s...
                let timeSinceLastRestart = Date().timeIntervalSince(lastRestart)

                if timeSinceLastRestart < backoffDelay {
                    print("⏳ UWBSessionManager: Backoff in effect for \(peerId) - waiting \(String(format: "%.1f", backoffDelay - timeSinceLastRestart))s more")
                    return
                }
            }

            // Check if we should restart (limit retries)
            if retryCount < 3 {
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("🔄 UWB SESSION RESTART REQUIRED")
                print("   Peer: \(peerId)")
                print("   Reason: No ranging data received")
                print("   Retry: \(retryCount + 1)/3")
                print("   Action: Requesting bidirectional restart")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                // Increment retry count and record timestamp
                sessionRetryCount[peerId] = retryCount + 1
                lastRestartTime[peerId] = Date()

                // Notify delegate to coordinate restart with peer
                if let delegate = delegate {
                    delegate.uwbSessionManager(self, requestsRestartFor: peerId)
                } else {
                    // Fallback: local restart only (less effective)
                    performLocalSessionRestart(for: peerId)
                }
            } else {
                print("❌ UWBSessionManager: Max restart attempts (3) reached for \(peerId)")
                print("   UWB ranging may not be working on this device pair")
                stopHealthCheck(for: peerId)
            }
        }

        // If we successfully have ranging, reset retry count
        if state == .ranging && hasObject {
            sessionRetryCount[peerId] = 0
            lastRestartTime.removeValue(forKey: peerId)
        }
    }

    /// Perform local session restart (called when coordinated restart is confirmed)
    func performLocalSessionRestart(for peerId: String) {
        guard let session = activeSessions[peerId] else { return }

        print("🔄 UWBSessionManager: Performing local session restart for \(peerId)")

        // Invalidate current session
        session.invalidate()
        activeSessions.removeValue(forKey: peerId)
        sessionStates[peerId] = .disconnected

        // Request fresh token generation from delegate
        // This ensures we get a new token for the restarted session
        if let delegate = delegate {
            delegate.uwbSessionManager(self, needsFreshTokenFor: peerId)
        }
    }

    /// Stop all active sessions
    func stopAllSessions() {
        queue.async { [weak self] in
            guard let self = self else { return }

            for (peerId, session) in self.activeSessions {
                session.invalidate()
                self.stopHealthCheck(for: peerId)
                print("📡 UWBSessionManager: Stopped session with \(peerId)")
            }

            DispatchQueue.main.async {
                self.activeSessions.removeAll()
                self.nearbyObjects.removeAll()
                self.discoveryTokens.removeAll()
                self.localTokens.removeAll()
                self.sessionStates.removeAll()
                self.sessionRetryCount.removeAll()
                self.lastRestartTime.removeAll()
            }

            // Invalidate all health check timers
            for (_, timer) in self.sessionHealthTimers {
                timer.invalidate()
            }
            self.sessionHealthTimers.removeAll()
        }
    }

    /// Get current distance to a peer (if available)
    func getDistance(to peerID: MCPeerID) -> Float? {
        let peerId = peerID.displayName
        return nearbyObjects[peerId]?.distance
    }

    /// Get current direction to a peer (if available)
    func getDirection(to peerID: MCPeerID) -> SIMD3<Float>? {
        let peerId = peerID.displayName
        return nearbyObjects[peerId]?.direction
    }

    /// Check if we have an active UWB session with a peer
    func hasActiveSession(with peerID: MCPeerID) -> Bool {
        return activeSessions[peerID.displayName] != nil
    }

    /// Get detailed UWB status for debugging
    func getUWBStatus(for peerID: MCPeerID) -> String {
        let peerId = peerID.displayName
        let hasSession = activeSessions[peerId] != nil
        let state = sessionStates[peerId] ?? .disconnected
        let hasObject = nearbyObjects[peerId] != nil
        let distance = nearbyObjects[peerId]?.distance

        var status = "UWB Status for \(peerId):\n"
        status += "  • Session: \(hasSession ? "✅" : "❌")\n"
        status += "  • State: \(state)\n"
        status += "  • Ranging: \(hasObject ? "✅" : "❌")\n"
        if let distance = distance {
            status += "  • Distance: \(String(format: "%.2f", distance))m\n"
        } else {
            status += "  • Distance: N/A\n"
        }

        return status
    }

    /// Force restart session with peer (for debugging)
    func forceRestartSession(with peerID: MCPeerID) {
        let peerId = peerID.displayName

        print("⚡ UWBSessionManager: Force restarting session with \(peerId)")

        // Stop existing session
        if let session = activeSessions[peerId] {
            session.invalidate()
        }

        // Clear state
        activeSessions.removeValue(forKey: peerId)
        sessionStates.removeValue(forKey: peerId)
        nearbyObjects.removeValue(forKey: peerId)
        stopHealthCheck(for: peerId)

        // If we have a token, restart immediately
        if let token = discoveryTokens[peerId] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                let mcPeer = MCPeerID(displayName: peerId)
                self.startSession(with: mcPeer, remotePeerToken: token)
            }
        }
    }

    /// Get relative location info for a peer (for triangulation)
    func getRelativeLocationInfo(for peerID: MCPeerID, intermediaryLocation: UserLocation) -> RelativeLocation? {
        let peerId = peerID.displayName

        guard let nearbyObject = nearbyObjects[peerId],
              let distance = nearbyObject.distance else {
            return nil
        }

        let direction = nearbyObject.direction.map { DirectionVector(from: $0) }

        // Determine accuracy based on UWB quality
        // UWB is typically accurate to ±0.1-0.5 meters
        let accuracy: Float = 0.5

        return RelativeLocation(
            intermediaryId: "", // Will be filled by caller
            intermediaryLocation: intermediaryLocation,
            targetDistance: distance,
            targetDirection: direction,
            accuracy: accuracy
        )
    }
}

// MARK: - NISessionDelegate
@available(iOS 14.0, *)
extension UWBSessionManager: NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        // Find which peer this session belongs to
        guard let peerId = activeSessions.first(where: { $0.value === session })?.key else {
            print("⚠️ UWBSessionManager: didUpdate called but no matching session found")
            return
        }

        print("🎯 UWBSessionManager: didUpdate called for \(peerId) with \(nearbyObjects.count) objects")

        // Track if this is first update
        let isFirstUpdate = self.nearbyObjects[peerId] == nil
        let previousState = sessionStates[peerId] ?? .disconnected

        // Update nearby object for this peer
        if let object = nearbyObjects.first {
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("📊 UWB UPDATE DETAILS")
            print("   Peer: \(peerId)")
            print("   Distance: \(object.distance?.description ?? "nil")")
            if let dir = object.direction {
                print("   Direction SIMD: x=\(dir.x), y=\(dir.y), z=\(dir.z)")
            } else {
                print("   Direction: nil")
            }
            print("   IsFirstUpdate: \(isFirstUpdate)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            DispatchQueue.main.async {
                self.nearbyObjects[peerId] = object
                print("✅ Published nearbyObjects update for \(peerId) to @Published property")

                // Transition to .ranging state when we receive ranging data
                if self.sessionStates[peerId] != .ranging {
                    self.sessionStates[peerId] = .ranging
                    print("✅ Published sessionStates update: \(previousState) → ranging")
                    // Reset retry count since ranging is working
                    self.sessionRetryCount[peerId] = 0
                    self.lastRestartTime.removeValue(forKey: peerId)
                }
            }

            if isFirstUpdate {
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("🎉 UWB RANGING ESTABLISHED")
                print("   Peer: \(peerId)")
                print("   State transition: \(previousState) → ranging")
                print("   First ranging data received!")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            }

            if let distance = object.distance {
                let directionString = object.direction != nil ? "with direction" : "no direction"
                print("📡 UWB: \(peerId) - \(String(format: "%.2f", distance))m (\(directionString))")
            } else {
                print("⚠️ UWBSessionManager: Object detected but no distance for \(peerId)")
            }

            // Notify delegate
            delegate?.uwbSessionManager(self, didUpdateDistanceTo: peerId, distance: object.distance, direction: object.direction)
        } else {
            print("⚠️ UWBSessionManager: didUpdate called but no objects in array for \(peerId)")
        }
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        // Find which peer this session belongs to
        guard let peerId = activeSessions.first(where: { $0.value === session })?.key else {
            return
        }

        DispatchQueue.main.async {
            self.nearbyObjects.removeValue(forKey: peerId)
            self.sessionStates[peerId] = .running  // Still running but not ranging
        }

        print("⚠️ UWBSessionManager: Lost tracking of \(peerId) - Reason: \(reason.description)")

        // Notify delegate
        delegate?.uwbSessionManager(self, didLoseTrackingOf: peerId, reason: reason)
    }

    func sessionWasSuspended(_ session: NISession) {
        guard let peerId = activeSessions.first(where: { $0.value === session })?.key else {
            return
        }

        DispatchQueue.main.async {
            self.sessionStates[peerId] = .suspended
        }

        print("⏸️ UWBSessionManager: Session suspended for \(peerId)")
        print("   Suspension reason: System suspended UWB ranging (app backgrounded, device locked, or low power)")
    }

    func sessionSuspensionEnded(_ session: NISession) {
        guard let peerId = activeSessions.first(where: { $0.value === session })?.key else {
            return
        }

        print("▶️ UWBSessionManager: Session resumed for \(peerId)")
        print("   Session ready to continue ranging")

        DispatchQueue.main.async {
            self.sessionStates[peerId] = .running
        }

        // Try to restart ranging if we have the token
        if let token = discoveryTokens[peerId] {
            print("   Attempting to restart ranging...")
            let config = NINearbyPeerConfiguration(peerToken: token)
            session.run(config)
        }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {

        guard let peerId = activeSessions.first(where: { $0.value === session })?.key else {
            return
        }

        print("❌ UWBSessionManager: Session invalidated for \(peerId): \(error.localizedDescription)")

        // Check for specific error types
        if isPermissionError(error) {
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("🔐 NEARBY INTERACTION PERMISSION ERROR")
            print("   Peer: \(peerId)")
            print("   Action: User needs to grant permission in Settings")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        }

        stopHealthCheck(for: peerId)

        DispatchQueue.main.async {
            self.activeSessions.removeValue(forKey: peerId)
            self.nearbyObjects.removeValue(forKey: peerId)
            self.sessionStates[peerId] = .disconnected
        }

        // Notify delegate
        delegate?.uwbSessionManager(self, sessionInvalidatedFor: peerId, error: error)
    }

    /// Check if error is related to permission denial
    private func isPermissionError(_ error: Error) -> Bool {
        let errorString = error.localizedDescription.lowercased()
        return errorString.contains("user did not allow") ||
               errorString.contains("permission") ||
               errorString.contains("privacy") ||
               errorString.contains("not authorized") ||
               errorString.contains("denied")
    }
}

// MARK: - UWBSessionManagerDelegate
@available(iOS 14.0, *)
protocol UWBSessionManagerDelegate: AnyObject {
    func uwbSessionManager(_ manager: UWBSessionManager, didUpdateDistanceTo peerId: String, distance: Float?, direction: SIMD3<Float>?)
    func uwbSessionManager(_ manager: UWBSessionManager, didLoseTrackingOf peerId: String, reason: NINearbyObject.RemovalReason)
    func uwbSessionManager(_ manager: UWBSessionManager, sessionInvalidatedFor peerId: String, error: Error)
    func uwbSessionManager(_ manager: UWBSessionManager, requestsRestartFor peerId: String)
    func uwbSessionManager(_ manager: UWBSessionManager, needsFreshTokenFor peerId: String)
}

// MARK: - NINearbyObject.RemovalReason Extension
@available(iOS 14.0, *)
extension NINearbyObject.RemovalReason {
    var description: String {
        switch self {
        case .timeout:
            return "Timeout"
        case .peerEnded:
            return "Peer Ended"
        @unknown default:
            return "Unknown"
        }
    }
}