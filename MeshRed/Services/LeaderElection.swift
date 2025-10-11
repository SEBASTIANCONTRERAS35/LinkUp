import Foundation
import MultipeerConnectivity
import UIKit
import Combine

/// Leader Election System using modified Bully Algorithm
/// The leader coordinates connections for the local cluster to prevent conflicts
class LeaderElection: ObservableObject {

    // MARK: - Types

    enum LeaderState: Equatable {
        case follower
        case candidate
        case leader(term: Int)

        var isLeader: Bool {
            if case .leader = self { return true }
            return false
        }
    }

    struct ElectionMessage: Codable {
        enum MessageType: String, Codable {
            case election
            case victory
            case heartbeat
            case acknowledgment
        }

        let type: MessageType
        let senderId: String
        let term: Int
        let score: Float
        let timestamp: Date
    }

    struct PeerScore: Comparable {
        let peerId: String
        let score: Float
        let timestamp: Date

        static func < (lhs: PeerScore, rhs: PeerScore) -> Bool {
            if lhs.score != rhs.score {
                return lhs.score < rhs.score
            }
            // Tiebreaker: use hash to ensure consistency
            return lhs.peerId.hashValue < rhs.peerId.hashValue
        }
    }

    // MARK: - Properties

    @Published private(set) var currentState: LeaderState = .follower
    @Published private(set) var currentLeader: String?
    @Published private(set) var currentTerm: Int = 0
    @Published private(set) var clusterMembers: Set<String> = []

    private let localPeerId: String
    private var localScore: Float = 0.0
    private var peerScores: [String: PeerScore] = [:]

    // Election timing
    private var electionTimer: Timer?
    private var heartbeatTimer: Timer?
    private let electionTimeout: TimeInterval = 5.0
    private let heartbeatInterval: TimeInterval = 2.0

    // Callbacks
    var onBecomeLeader: (() -> Void)?
    var onLoseLeadership: (() -> Void)?
    var onLeaderChanged: ((String?) -> Void)?

    private let queue = DispatchQueue(label: "com.meshred.leaderelection", attributes: .concurrent)

    // MARK: - Initialization

    init(localPeerId: String) {
        self.localPeerId = localPeerId
        calculateLocalScore()
        startElectionTimer()
    }

    deinit {
        electionTimer?.invalidate()
        heartbeatTimer?.invalidate()
    }

    // MARK: - Score Calculation

    private func calculateLocalScore() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            // Factor 1: Number of connections (normalized to 0-25)
            let connectionScore = min(Float(self.clusterMembers.count) * 5.0, 25.0)

            // Factor 2: Device battery (0-25)
            let batteryLevel = UIDevice.current.batteryLevel
            let batteryScore = batteryLevel >= 0 ? batteryLevel * 25.0 : 12.5 // Default if unknown

            // Factor 3: Uptime stability (0-25)
            // In a real implementation, track connection stability over time
            let stabilityScore: Float = 15.0 // Default moderate stability

            // Factor 4: Processing power indicator (0-25)
            // Use device model as proxy for processing power
            let deviceScore = self.getDeviceScore()

            self.localScore = connectionScore + batteryScore + stabilityScore + deviceScore

            print("📊 Leader Score Calculated: \(self.localScore)")
            print("   Connections: \(connectionScore), Battery: \(batteryScore)")
            print("   Stability: \(stabilityScore), Device: \(deviceScore)")
        }
    }

    private func getDeviceScore() -> Float {
        let deviceModel = UIDevice.current.model

        // Simple heuristic based on device type
        if deviceModel.contains("iPhone") {
            if deviceModel.contains("Pro") {
                return 25.0  // Latest Pro models
            }
            return 20.0  // Regular iPhone
        } else if deviceModel.contains("iPad") {
            return 22.0  // iPad generally has good performance
        }
        return 15.0  // Default/unknown
    }

    // MARK: - Election Process

    func startElection() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("🗳️ STARTING ELECTION")
            print("   Local ID: \(self.localPeerId)")
            print("   Local Score: \(self.localScore)")
            print("   Current Term: \(self.currentTerm)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            // Increment term
            self.currentTerm += 1

            // Become candidate
            DispatchQueue.main.async {
                self.currentState = .candidate
            }

            // Check if we have the highest score
            if self.shouldBecomeLeader() {
                self.declareVictory()
            } else {
                // Send election message to higher-scored peers
                self.sendElectionMessage()

                // Wait for responses
                self.resetElectionTimer()
            }
        }
    }

    private func shouldBecomeLeader() -> Bool {
        let myScore = PeerScore(peerId: localPeerId, score: localScore, timestamp: Date())

        for (_, peerScore) in peerScores {
            if peerScore > myScore {
                return false
            }
        }

        return true
    }

    private func declareVictory() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("👑 DECLARING VICTORY")
            print("   New Leader: \(self.localPeerId)")
            print("   Term: \(self.currentTerm)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            DispatchQueue.main.async {
                self.currentState = .leader(term: self.currentTerm)
                self.currentLeader = self.localPeerId
                self.onBecomeLeader?()
                self.onLeaderChanged?(self.localPeerId)
            }

            // Start sending heartbeats
            self.startHeartbeatTimer()

            // Broadcast victory
            self.broadcastVictory()
        }
    }

    // MARK: - Message Handling

    func handleElectionMessage(_ data: Data, from peerId: String) {
        guard let message = try? JSONDecoder().decode(ElectionMessage.self, from: data) else {
            print("❌ Failed to decode election message")
            return
        }

        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            // Update peer score
            self.peerScores[peerId] = PeerScore(
                peerId: peerId,
                score: message.score,
                timestamp: message.timestamp
            )

            switch message.type {
            case .election:
                self.handleElection(from: message)

            case .victory:
                self.handleVictory(from: message)

            case .heartbeat:
                self.handleHeartbeat(from: message)

            case .acknowledgment:
                self.handleAcknowledgment(from: message)
            }
        }
    }

    private func handleElection(from message: ElectionMessage) {
        print("🗳️ Received election message from \(message.senderId) with score \(message.score)")

        if message.score < localScore {
            // We have higher score, send acknowledgment and start our own election
            sendAcknowledgment(to: message.senderId)

            if case .follower = currentState {
                startElection()
            }
        }
    }

    private func handleVictory(from message: ElectionMessage) {
        print("👑 Received victory message from \(message.senderId)")

        // Accept the new leader
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let wasLeader = self.currentState.isLeader

            self.currentState = .follower
            self.currentLeader = message.senderId
            self.currentTerm = message.term

            if wasLeader {
                self.onLoseLeadership?()
            }

            self.onLeaderChanged?(message.senderId)
        }

        // Reset election timer
        resetElectionTimer()
    }

    private func handleHeartbeat(from message: ElectionMessage) {
        // Reset election timer when receiving heartbeat from leader
        if message.senderId == currentLeader {
            resetElectionTimer()
        }
    }

    private func handleAcknowledgment(from message: ElectionMessage) {
        print("✅ Received acknowledgment from \(message.senderId)")
        // Higher-scored peer acknowledged, cancel our election attempt
        if message.score > localScore {
            DispatchQueue.main.async { [weak self] in
                self?.currentState = .follower
            }
        }
    }

    // MARK: - Timers

    private func startElectionTimer() {
        electionTimer?.invalidate()

        // Add randomization to prevent election storms
        let timeout = electionTimeout + Double.random(in: 0...2)

        electionTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }

            if !self.currentState.isLeader {
                print("⏰ Election timeout - starting election")
                self.startElection()
            }
        }
    }

    private func resetElectionTimer() {
        startElectionTimer()
    }

    private func startHeartbeatTimer() {
        heartbeatTimer?.invalidate()

        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            if self.currentState.isLeader {
                self.sendHeartbeat()
            } else {
                self.heartbeatTimer?.invalidate()
            }
        }
    }

    // MARK: - Network Communication

    private func sendElectionMessage() {
        let message = ElectionMessage(
            type: .election,
            senderId: localPeerId,
            term: currentTerm,
            score: localScore,
            timestamp: Date()
        )

        broadcastMessage(message)
    }

    private func broadcastVictory() {
        let message = ElectionMessage(
            type: .victory,
            senderId: localPeerId,
            term: currentTerm,
            score: localScore,
            timestamp: Date()
        )

        broadcastMessage(message)
    }

    private func sendHeartbeat() {
        let message = ElectionMessage(
            type: .heartbeat,
            senderId: localPeerId,
            term: currentTerm,
            score: localScore,
            timestamp: Date()
        )

        broadcastMessage(message)
    }

    private func sendAcknowledgment(to peerId: String) {
        let message = ElectionMessage(
            type: .acknowledgment,
            senderId: localPeerId,
            term: currentTerm,
            score: localScore,
            timestamp: Date()
        )

        // In real implementation, send to specific peer
        broadcastMessage(message)
    }

    private func broadcastMessage(_ message: ElectionMessage) {
        guard let data = try? JSONEncoder().encode(message) else { return }

        // This will be called by NetworkManager to actually send
        NotificationCenter.default.post(
            name: .leaderElectionMessage,
            object: nil,
            userInfo: ["data": data, "message": message]
        )
    }

    // MARK: - Cluster Management

    func addClusterMember(_ peerId: String) {
        queue.async(flags: .barrier) { [weak self] in
            self?.clusterMembers.insert(peerId)
            self?.calculateLocalScore()  // Recalculate with new member
        }
    }

    func removeClusterMember(_ peerId: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            self.clusterMembers.remove(peerId)
            self.peerScores.removeValue(forKey: peerId)
            self.calculateLocalScore()

            // If the leader left, start new election
            if peerId == self.currentLeader {
                print("👑 Leader disconnected - starting new election")
                self.startElection()
            }
        }
    }

    // MARK: - Public Interface

    func isLeader() -> Bool {
        return currentState.isLeader
    }

    func shouldCoordinateConnections() -> Bool {
        // Only the leader coordinates to prevent conflicts
        return isLeader()
    }

    func getLeaderScore() -> Float {
        return localScore
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let leaderElectionMessage = Notification.Name("LeaderElectionMessage")
    static let leaderChanged = Notification.Name("LeaderChanged")
}