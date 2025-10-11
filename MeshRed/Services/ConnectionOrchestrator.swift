import Foundation
import MultipeerConnectivity
import UIKit
import Combine

/// Central coordinator for intelligent connection management
/// Integrates all connection subsystems for optimal decision making
class ConnectionOrchestrator: ObservableObject {

    // MARK: - Types

    enum ConnectionDecision {
        case accept
        case reject(reason: String)
        case postpone(until: Date)
        case conditionalAccept(conditions: [String])
    }

    enum DisconnectionPrediction {
        case imminent(timeInterval: TimeInterval)
        case likely(timeInterval: TimeInterval)
        case stable
    }

    struct NetworkState {
        var totalPeers: Int = 0
        var connectedPeers: Int = 0
        var availablePeers: Int = 0
        var pendingConnections: Int = 0
        var averageLatency: Double = 0
        var networkLoad: Float = 0  // 0.0 to 1.0
        var batteryLevel: Float = 0.7
        var isLeader: Bool = false

        var networkDensity: Float {
            return Float(totalPeers) / 20.0  // Normalized to 20 peers
        }

        var connectionSaturation: Float {
            guard totalPeers > 0 else { return 0 }
            return Float(connectedPeers) / Float(min(totalPeers, 5))  // Max 5 connections
        }
    }

    struct ConnectionRequest {
        let peer: MCPeerID
        let timestamp: Date
        let priority: ConnectionPoolManager.ConnectionPriority
        let metadata: [String: Any]?
    }

    // MARK: - Properties

    @Published internal(set) var networkState = NetworkState()
    @Published private(set) var isOrchestrating: Bool = false
    @Published private(set) var lastDecision: String = ""

    // Subsystems
    let leaderElection: LeaderElection
    let connectionPool: ConnectionPoolManager
    let reputationSystem: PeerReputationSystem
    let backoffManager: AdaptiveBackoffManager
    let healthMonitor: PeerHealthMonitor

    // Internal state
    private var pendingRequests: [ConnectionRequest] = []
    private var connectionHistory: [String: [(Date, Bool)]] = [:]  // peerId -> [(timestamp, success)]
    private var predictionModels: [String: DisconnectionPrediction] = [:]

    private let queue = DispatchQueue(label: "com.meshred.orchestrator", attributes: .concurrent)
    private var cancellables = Set<AnyCancellable>()

    // Configuration
    private let minReputationForAutoAccept: Float = 60.0
    private let maxReputationForAutoReject: Float = 20.0
    private let criticalBatteryThreshold: Float = 0.15
    private let highLoadThreshold: Float = 0.8

    // MARK: - Initialization

    init(localPeerId: String, healthMonitor: PeerHealthMonitor) {
        self.leaderElection = LeaderElection(localPeerId: localPeerId)
        self.connectionPool = ConnectionPoolManager()
        self.reputationSystem = PeerReputationSystem()
        self.backoffManager = AdaptiveBackoffManager()
        self.healthMonitor = healthMonitor

        setupObservers()
        startNetworkMonitoring()
    }

    // MARK: - Setup

    private func setupObservers() {
        // Observe leader changes
        leaderElection.$currentState
            .sink { [weak self] state in
                self?.networkState.isLeader = state.isLeader
            }
            .store(in: &cancellables)

        // Observe connection pool
        connectionPool.$occupiedSlots
            .sink { [weak self] occupied in
                self?.networkState.connectedPeers = occupied
            }
            .store(in: &cancellables)
    }

    private func startNetworkMonitoring() {
        Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateNetworkState()
                self?.checkPredictions()
            }
            .store(in: &cancellables)
    }

    // MARK: - Connection Decision Making

    func shouldAcceptConnection(from peer: MCPeerID, context: [String: Any]? = nil) -> ConnectionDecision {
        return queue.sync {
            DispatchQueue.main.async { [weak self] in
                self?.isOrchestrating = true
            }

            let decision = evaluateConnectionRequest(from: peer, context: context)

            DispatchQueue.main.async { [weak self] in
                self?.isOrchestrating = false
                self?.lastDecision = self?.describeDecision(decision, for: peer) ?? ""
            }

            logDecision(decision, for: peer)
            return decision
        }
    }

    private func evaluateConnectionRequest(from peer: MCPeerID, context: [String: Any]?) -> ConnectionDecision {
        // Step 1: Check blacklist
        if reputationSystem.isBlacklisted(peer) {
            return .reject(reason: "Peer is blacklisted")
        }

        // Step 2: Check battery critical
        if UIDevice.current.batteryLevel < criticalBatteryThreshold {
            let reputation = reputationSystem.getTrustScore(for: peer)
            if reputation < minReputationForAutoAccept {
                return .reject(reason: "Battery critical, accepting only trusted peers")
            }
        }

        // Step 3: Check reputation
        let reputation = reputationSystem.getTrustScore(for: peer)
        if reputation < maxReputationForAutoReject {
            return .reject(reason: "Reputation too low: \(reputation)")
        }

        // Step 4: Check connection pool availability
        let priority = determinePriority(for: peer, reputation: reputation, context: context)
        if !connectionPool.canAcceptPeer(peer, withPriority: priority) {
            // Try to defer if high reputation
            if reputation > minReputationForAutoAccept {
                let deferTime = Date().addingTimeInterval(10)
                return .postpone(until: deferTime)
            }
            return .reject(reason: "No available connection slots")
        }

        // Step 5: Check network load
        if networkState.networkLoad > highLoadThreshold {
            if !isCriticalPeer(peer, context: context) {
                return .postpone(until: Date().addingTimeInterval(30))
            }
        }

        // Step 6: Leader coordination
        if !networkState.isLeader && shouldDeferToLeader() {
            return .postpone(until: Date().addingTimeInterval(2))
        }

        // Step 7: Conditional accept based on predictions
        if let prediction = predictionModels[peer.displayName] {
            switch prediction {
            case .imminent(let time) where time < 30:
                return .reject(reason: "Predicted disconnection in \(Int(time))s")
            case .likely(let time) where time < 60:
                return .conditionalAccept(conditions: ["Monitor closely", "Low priority"])
            case .imminent, .likely:
                // Accept but with monitoring
                break
            case .stable:
                break
            }
        }

        // Accept the connection
        return .accept
    }

    private func determinePriority(
        for peer: MCPeerID,
        reputation: Float,
        context: [String: Any]?
    ) -> ConnectionPoolManager.ConnectionPriority {

        // Check if emergency/critical from context
        if let isEmergency = context?["emergency"] as? Bool, isEmergency {
            return .critical
        }

        // Check if family member
        if let isFamily = context?["family"] as? Bool, isFamily {
            return .critical
        }

        // Use reputation-based priority
        return reputationSystem.getRecommendedPriority(for: peer)
    }

    private func isCriticalPeer(_ peer: MCPeerID, context: [String: Any]?) -> Bool {
        // Check context flags
        if let critical = context?["critical"] as? Bool {
            return critical
        }

        // Check reputation
        return reputationSystem.getTrustScore(for: peer) > 80
    }

    private func shouldDeferToLeader() -> Bool {
        // Only defer if we're not the leader and leader exists
        return !networkState.isLeader && leaderElection.currentLeader != nil
    }

    // MARK: - Connection Execution

    func executeConnection(to peer: MCPeerID, context: [String: Any]? = nil) -> Bool {
        let priority = determinePriority(
            for: peer,
            reputation: reputationSystem.getTrustScore(for: peer),
            context: context
        )

        // Request slot from pool
        guard let slot = connectionPool.requestSlot(for: peer, priority: priority) else {
            print("❌ Orchestrator: Failed to allocate slot for \(peer.displayName)")
            return false
        }

        // Update leader election cluster
        leaderElection.addClusterMember(peer.displayName)

        // Record successful allocation
        recordConnectionAttempt(for: peer, success: true)

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("✅ ORCHESTRATED CONNECTION")
        print("   Peer: \(peer.displayName)")
        print("   Priority: \(priority.displayName)")
        print("   Slot: \(slot.id)")
        print("   Leader: \(networkState.isLeader ? "Yes" : "No")")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        return true
    }

    func handleDisconnection(of peer: MCPeerID, reason: PeerReputationSystem.DisconnectionReason) {
        // Release connection slot
        connectionPool.releaseSlot(for: peer)

        // Update reputation
        reputationSystem.recordEvent(.connectionDropped(reason: reason), for: peer)

        // Remove from leader election
        leaderElection.removeClusterMember(peer.displayName)

        // Clear predictions
        predictionModels.removeValue(forKey: peer.displayName)

        // Record for history
        recordConnectionAttempt(for: peer, success: false)
    }

    // MARK: - Predictive Analytics

    func predictDisconnection(for peer: MCPeerID) -> DisconnectionPrediction {
        // Check health monitor trends
        guard let health = healthMonitor.getHealthStats(for: peer) else {
            return .stable
        }

        // Analyze latency trend
        let latencyIncreasing = health.latency > 200 && health.lossRate > 0.1

        // Check historical patterns
        let historicalStability = getHistoricalStability(for: peer)

        // Battery consideration
        let batteryLow = UIDevice.current.batteryLevel < 0.2

        // Make prediction
        if latencyIncreasing && health.lossRate > 0.2 {
            return .imminent(timeInterval: 30)
        } else if latencyIncreasing || historicalStability < 0.5 {
            return .likely(timeInterval: 120)
        } else if batteryLow {
            return .likely(timeInterval: 300)
        }

        return .stable
    }

    private func getHistoricalStability(for peer: MCPeerID) -> Float {
        guard let history = connectionHistory[peer.displayName],
              !history.isEmpty else {
            return 0.5  // Unknown
        }

        let recentHistory = history.suffix(10)
        let successCount = recentHistory.filter { $0.1 }.count
        return Float(successCount) / Float(recentHistory.count)
    }

    private func checkPredictions() {
        for peer in getCurrentPeers() {
            let prediction = predictDisconnection(for: peer)
            predictionModels[peer.displayName] = prediction

            // Alert if imminent disconnection predicted
            if case .imminent(let time) = prediction {
                print("⚠️ Predicted disconnection for \(peer.displayName) in \(Int(time))s")
                NotificationCenter.default.post(
                    name: .disconnectionPredicted,
                    object: nil,
                    userInfo: ["peer": peer, "time": time]
                )
            }
        }
    }

    // MARK: - Backoff Coordination

    func calculateBackoff(for peer: MCPeerID, attemptNumber: Int) -> TimeInterval {
        let context = AdaptiveBackoffManager.ConnectionContext(
            timeOfDay: .init(hour: Calendar.current.component(.hour, from: Date())),
            peerDensity: .init(peerCount: networkState.availablePeers),
            batteryLevel: .init(level: UIDevice.current.batteryLevel),
            networkMode: "standard",
            failureCount: attemptNumber
        )

        let delay = backoffManager.calculateBackoff(
            attemptNumber: attemptNumber,
            for: peer,
            nearbyPeers: networkState.availablePeers,
            failureCount: attemptNumber
        )

        // Record attempt for learning
        Timer.scheduledTimer(withTimeInterval: delay + 5, repeats: false) { [weak self] _ in
            // Check if connection succeeded after backoff
            let success = self?.isConnected(to: peer) ?? false
            let strategy = self?.backoffManager.currentStrategy ?? .standard
            self?.backoffManager.recordAttempt(
                for: peer,
                success: success,
                context: context,
                strategy: strategy
            )
        }

        return delay
    }

    // MARK: - Network State Management

    private func updateNetworkState() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            // Update battery
            self.networkState.batteryLevel = UIDevice.current.batteryLevel

            // Calculate network load (0.0 to 1.0)
            let connectionRatio = Float(self.networkState.connectedPeers) / 5.0
            let pendingRatio = Float(self.pendingRequests.count) / 10.0
            self.networkState.networkLoad = min(1.0, (connectionRatio + pendingRatio) / 2.0)

            // Update average latency from health monitor
            let latencies = self.getCurrentPeers().compactMap {
                self.healthMonitor.getHealthStats(for: $0)?.latency
            }
            if !latencies.isEmpty {
                self.networkState.averageLatency = latencies.reduce(0, +) / Double(latencies.count)
            }
        }
    }

    // MARK: - Helpers

    private func recordConnectionAttempt(for peer: MCPeerID, success: Bool) {
        queue.async(flags: .barrier) { [weak self] in
            var history = self?.connectionHistory[peer.displayName] ?? []
            history.append((Date(), success))

            // Keep only recent history
            if history.count > 50 {
                history.removeFirst()
            }

            self?.connectionHistory[peer.displayName] = history
        }
    }

    private func getCurrentPeers() -> [MCPeerID] {
        // This would be provided by NetworkManager
        return []
    }

    private func isConnected(to peer: MCPeerID) -> Bool {
        return connectionPool.getSlotInfo().contains { $0.peer == peer.displayName }
    }

    private func logDecision(_ decision: ConnectionDecision, for peer: MCPeerID) {
        let description = describeDecision(decision, for: peer)
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🎯 ORCHESTRATOR DECISION")
        print("   Peer: \(peer.displayName)")
        print("   Decision: \(description)")
        print("   Network Load: \(String(format: "%.1f%%", networkState.networkLoad * 100))")
        print("   Battery: \(String(format: "%.0f%%", networkState.batteryLevel * 100))")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    private func describeDecision(_ decision: ConnectionDecision, for peer: MCPeerID) -> String {
        switch decision {
        case .accept:
            return "✅ Accept"
        case .reject(let reason):
            return "❌ Reject: \(reason)"
        case .postpone(let until):
            let seconds = until.timeIntervalSinceNow
            return "⏰ Postpone for \(Int(seconds))s"
        case .conditionalAccept(let conditions):
            return "✅ Accept with conditions: \(conditions.joined(separator: ", "))"
        }
    }

    // MARK: - Public Interface

    func getNetworkSummary() -> String {
        return """
        Network State:
        - Connected: \(networkState.connectedPeers)/5
        - Available: \(networkState.availablePeers)
        - Load: \(String(format: "%.1f%%", networkState.networkLoad * 100))
        - Latency: \(String(format: "%.1f", networkState.averageLatency))ms
        - Battery: \(String(format: "%.0f%%", networkState.batteryLevel * 100))
        - Role: \(networkState.isLeader ? "Leader" : "Follower")
        """
    }

    func getConnectionRecommendations() -> [String] {
        var recommendations: [String] = []

        if networkState.batteryLevel < 0.3 {
            recommendations.append("🔋 Consider power saving mode")
        }

        if networkState.networkLoad > 0.8 {
            recommendations.append("📊 High network load - defer non-critical connections")
        }

        if networkState.averageLatency > 150 {
            recommendations.append("⚡ High latency detected - check network conditions")
        }

        if !networkState.isLeader && leaderElection.currentLeader == nil {
            recommendations.append("👑 No leader elected - consider starting election")
        }

        return recommendations
    }

    func optimizeConnections() {
        queue.async { [weak self] in
            guard let self = self else { return }

            print("🔧 Starting connection optimization...")

            // Analyze current connections
            let slots = self.connectionPool.getSlotInfo()

            for slot in slots {
                guard let peerName = slot.peer else { continue }

                // Check if connection should be maintained
                let reputation = self.reputationSystem.getTrustScore(forPeerId: peerName)
                let prediction = self.predictionModels[peerName]

                // Consider dropping low-value connections
                if reputation < 30 {
                    if case .imminent = prediction {
                        print("🔧 Suggesting disconnect from \(peerName) (low value + unstable)")
                    }
                }
            }

            print("✅ Optimization complete")
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let disconnectionPredicted = Notification.Name("DisconnectionPredicted")
    static let orchestratorDecision = Notification.Name("OrchestratorDecision")
    static let networkStateChanged = Notification.Name("NetworkStateChanged")
}