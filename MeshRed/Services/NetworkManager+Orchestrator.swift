import Foundation
import MultipeerConnectivity
import Combine

/// Extension to integrate the Connection Orchestrator system with NetworkManager
/// This provides intelligent connection management without disrupting existing functionality
extension NetworkManager {

    // MARK: - Orchestrator Properties

    /// Access to the connection orchestrator (lazy initialized)
    private static var _orchestrator: ConnectionOrchestrator?

    var orchestrator: ConnectionOrchestrator {
        if NetworkManager._orchestrator == nil {
            NetworkManager._orchestrator = ConnectionOrchestrator(
                localPeerId: localPeerID.displayName,
                healthMonitor: healthMonitor
            )
            setupOrchestratorCallbacks()
        }
        return NetworkManager._orchestrator!
    }

    /// Flag to enable/disable orchestrator (for gradual rollout)
    var isOrchestratorEnabled: Bool {
        get {
            return UserDefaults.standard.object(forKey: "orchestratorEnabled") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "orchestratorEnabled")
            print("🎯 Orchestrator \(newValue ? "ENABLED" : "DISABLED")")
        }
    }

    // MARK: - Setup

    func setupOrchestratorCallbacks() {
        guard let orchestrator = NetworkManager._orchestrator else { return }

        // Leader election callbacks
        orchestrator.leaderElection.onBecomeLeader = { [weak self] in
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("👑 BECAME CLUSTER LEADER")
            print("   Peer: \(self?.localPeerID.displayName ?? "unknown")")
            print("   Responsibilities: Connection coordination")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            NotificationCenter.default.post(name: .becameLeader, object: nil)
        }

        orchestrator.leaderElection.onLoseLeadership = { [weak self] in
            print("👤 LOST LEADERSHIP - Now following cluster leader")

            NotificationCenter.default.post(name: .lostLeadership, object: nil)
        }

        orchestrator.leaderElection.onLeaderChanged = { [weak self] newLeader in
            print("👑 Cluster leader changed to: \(newLeader ?? "none")")

            NotificationCenter.default.post(
                name: .leaderChanged,
                object: nil,
                userInfo: ["leader": newLeader as Any]
            )
        }

        // Connection pool callbacks
        NotificationCenter.default.addObserver(
            forName: .connectionEvicted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let peer = notification.userInfo?["peer"] as? MCPeerID else { return }
            print("⚡ Connection evicted by pool manager: \(peer.displayName)")

            // Disconnect the evicted peer
            self?.session.cancelConnectPeer(peer)
        }

        NotificationCenter.default.addObserver(
            forName: .connectionIdleTimeout,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let peer = notification.userInfo?["peer"] as? MCPeerID,
                  let idleTime = notification.userInfo?["idleTime"] as? TimeInterval else { return }

            print("⏰ Idle timeout for \(peer.displayName) after \(Int(idleTime))s")

            // For non-critical connections, disconnect
            if self?.orchestrator.connectionPool.getPriority(for: peer) == .low {
                self?.session.cancelConnectPeer(peer)
            }
        }

        // Prediction notifications
        NotificationCenter.default.addObserver(
            forName: .disconnectionPredicted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let peer = notification.userInfo?["peer"] as? MCPeerID,
                  let time = notification.userInfo?["time"] as? TimeInterval else { return }

            print("⚠️ Disconnection predicted for \(peer.displayName) in \(Int(time))s")

            // Proactively look for alternative connections
            if time < 30 {
                self?.restartServicesIfNeeded()
            }
        }

        print("✅ Orchestrator callbacks configured")
    }

    // MARK: - Connection Decision Making

    /// Orchestrated connection decision for discovered peer
    func shouldConnectToDiscoveredPeer(_ peer: MCPeerID, discoveryInfo: [String: String]?) -> Bool {
        guard isOrchestratorEnabled else {
            // Fallback to legacy behavior
            return shouldConnectLegacy(to: peer)
        }

        // Update orchestrator state
        updateOrchestratorNetworkState()

        // Check if peer is family member (critical priority)
        let context = createConnectionContext(for: peer, discoveryInfo: discoveryInfo)

        // Get orchestrated decision
        let decision = orchestrator.shouldAcceptConnection(from: peer, context: context)

        switch decision {
        case .accept:
            print("✅ Orchestrator: ACCEPT connection to \(peer.displayName)")
            return true

        case .reject(let reason):
            print("❌ Orchestrator: REJECT connection to \(peer.displayName)")
            print("   Reason: \(reason)")
            return false

        case .postpone(let until):
            let seconds = until.timeIntervalSinceNow
            print("⏰ Orchestrator: POSTPONE connection to \(peer.displayName) for \(Int(seconds))s")

            // Schedule retry
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, seconds)) { [weak self] in
                guard let self = self else { return }

                if self.availablePeers.contains(where: { $0.displayName == peer.displayName }) {
                    print("🔄 Retrying postponed connection to \(peer.displayName)")
                    self.connectToPeer(peer)
                }
            }
            return false

        case .conditionalAccept(let conditions):
            print("✅ Orchestrator: CONDITIONAL ACCEPT for \(peer.displayName)")
            print("   Conditions: \(conditions.joined(separator: ", "))")
            return true
        }
    }

    /// Orchestrated invitation acceptance decision
    func shouldAcceptInvitationFromPeer(_ peer: MCPeerID) -> Bool {
        guard isOrchestratorEnabled else {
            // Fallback to legacy behavior
            return shouldAcceptInvitationLegacy(from: peer)
        }

        updateOrchestratorNetworkState()

        let context = createConnectionContext(for: peer, discoveryInfo: nil)
        let decision = orchestrator.shouldAcceptConnection(from: peer, context: context)

        switch decision {
        case .accept, .conditionalAccept:
            print("✅ Orchestrator: ACCEPT invitation from \(peer.displayName)")
            return true
        case .reject(let reason):
            print("❌ Orchestrator: REJECT invitation from \(peer.displayName)")
            print("   Reason: \(reason)")
            return false
        case .postpone:
            // Can't postpone invitation - must decide now
            // Accept if reputation is decent
            let reputation = orchestrator.reputationSystem.getTrustScore(for: peer)
            return reputation > 40
        }
    }

    /// Record successful connection with orchestrator
    func recordSuccessfulConnection(to peer: MCPeerID) {
        guard isOrchestratorEnabled else { return }

        // Execute connection through orchestrator
        let context = createConnectionContext(for: peer, discoveryInfo: nil)
        let success = orchestrator.executeConnection(to: peer, context: context)

        if success {
            // Record reputation event
            orchestrator.reputationSystem.recordEvent(.successfulConnection, for: peer)

            // Record activity
            orchestrator.connectionPool.recordActivity(for: peer)
        }
    }

    /// Record disconnection with orchestrator
    func recordDisconnection(of peer: MCPeerID, reason: PeerReputationSystem.DisconnectionReason) {
        guard isOrchestratorEnabled else { return }

        orchestrator.handleDisconnection(of: peer, reason: reason)
    }

    /// Record message sent to peer
    func recordMessageSent(to peer: MCPeerID, success: Bool) {
        guard isOrchestratorEnabled else { return }

        if success {
            orchestrator.reputationSystem.recordEvent(.messageDelivered, for: peer)
            orchestrator.connectionPool.recordActivity(for: peer)
        } else {
            orchestrator.reputationSystem.recordEvent(.messageDropped, for: peer)
        }
    }

    /// Record ACK received from peer
    func recordAckReceived(from peer: MCPeerID) {
        guard isOrchestratorEnabled else { return }

        orchestrator.reputationSystem.recordEvent(.ackReceived, for: peer)
    }

    /// Record latency measurement
    func recordLatency(_ latency: Double, for peer: MCPeerID) {
        guard isOrchestratorEnabled else { return }

        orchestrator.reputationSystem.recordLatency(latency, for: peer)
    }

    // MARK: - Backoff Calculation

    func calculateAdaptiveBackoff(for peer: MCPeerID, attemptNumber: Int) -> TimeInterval {
        guard isOrchestratorEnabled else {
            // Fallback to simple exponential backoff
            return min(pow(2.0, Double(attemptNumber)) * 2.0, 60.0)
        }

        return orchestrator.calculateBackoff(for: peer, attemptNumber: attemptNumber)
    }

    // MARK: - Helper Methods

    private func createConnectionContext(for peer: MCPeerID, discoveryInfo: [String: String]?) -> [String: Any] {
        var context: [String: Any] = [:]

        // Check if family member
        let isFamilyMember = familyGroupManager.isFamilyMember(peerID: peer.displayName)
        if isFamilyMember {
            context["family"] = true
            context["critical"] = true
        }

        // Check if emergency context
        if let emergencyFlag = discoveryInfo?["emergency"], emergencyFlag == "true" {
            context["emergency"] = true
            context["critical"] = true
        }

        // Add discovery info
        if let info = discoveryInfo {
            context["discoveryInfo"] = info
        }

        return context
    }

    private func updateOrchestratorNetworkState() {
        var state = orchestrator.networkState

        state.connectedPeers = connectedPeers.count
        state.availablePeers = availablePeers.count
        state.totalPeers = availablePeers.count + connectedPeers.count

        // Update via reflection (since networkState is internal)
        // This is a workaround - in production, expose a setter
        orchestrator.networkState = state
    }

    // MARK: - Legacy Fallback Methods

    private func shouldConnectLegacy(to peer: MCPeerID) -> Bool {
        // Original logic from foundPeer
        let shouldInitiate = ConnectionConflictResolver.shouldInitiateConnection(
            localPeer: localPeerID,
            remotePeer: peer
        )

        let alreadyConnected = connectedPeers.contains(where: { $0.displayName == peer.displayName })
        let maxConnectionsReached = hasReachedMaxConnections()
        let sessionManagerAllows = sessionManager.shouldAttemptConnection(to: peer)

        return !alreadyConnected && !maxConnectionsReached && shouldInitiate && sessionManagerAllows
    }

    private func shouldAcceptInvitationLegacy(from peer: MCPeerID) -> Bool {
        // Original logic from didReceiveInvitation
        if connectedPeers.contains(peer) {
            return false
        }

        if hasReachedMaxConnections() {
            return false
        }

        return true
    }

    // MARK: - Public Interface

    /// Get orchestrator status summary
    func getOrchestratorStatus() -> String {
        guard isOrchestratorEnabled else {
            return "Orchestrator: DISABLED (using legacy system)"
        }

        return orchestrator.getNetworkSummary()
    }

    /// Get connection recommendations
    func getConnectionRecommendations() -> [String] {
        guard isOrchestratorEnabled else {
            return ["Orchestrator disabled"]
        }

        return orchestrator.getConnectionRecommendations()
    }

    /// Trigger connection optimization
    func optimizeConnections() {
        guard isOrchestratorEnabled else {
            print("⚠️ Orchestrator disabled - cannot optimize")
            return
        }

        orchestrator.optimizeConnections()
    }

    /// Get peer reputation
    func getPeerReputation(for peer: MCPeerID) -> PeerReputationSystem.PeerReputation? {
        guard isOrchestratorEnabled else { return nil }

        return orchestrator.reputationSystem.getReputation(for: peer)
    }

    /// Get peer trust level
    func getPeerTrustLevel(for peer: MCPeerID) -> PeerReputationSystem.TrustLevel {
        guard isOrchestratorEnabled else {
            return .moderate
        }

        return orchestrator.reputationSystem.getTrustLevel(for: peer)
    }

    /// Check if peer is blacklisted
    func isPeerBlacklisted(_ peer: MCPeerID) -> Bool {
        guard isOrchestratorEnabled else { return false }

        return orchestrator.reputationSystem.isBlacklisted(peer)
    }

    /// Force elect new leader
    func forceLeaderElection() {
        guard isOrchestratorEnabled else {
            print("⚠️ Orchestrator disabled")
            return
        }

        orchestrator.leaderElection.startElection()
    }

    /// Check if we're the cluster leader
    func isClusterLeader() -> Bool {
        guard isOrchestratorEnabled else { return false }

        return orchestrator.leaderElection.isLeader()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let becameLeader = Notification.Name("BecameLeader")
    static let lostLeadership = Notification.Name("LostLeadership")
}