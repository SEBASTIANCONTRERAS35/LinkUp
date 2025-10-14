import Foundation
import MultipeerConnectivity
import Combine
import os

/// Tracks and manages peer reputation scores for trust-based decisions
class PeerReputationSystem: ObservableObject {

    // MARK: - Types

    enum ReputationEvent {
        // Positive events
        case successfulConnection
        case messageDelivered
        case ackReceived
        case stableConnection(duration: TimeInterval)
        case helpedRelay
        case sharedResource

        // Negative events
        case connectionFailed(reason: ConnectionFailureReason)
        case connectionDropped(reason: DisconnectionReason)
        case messageDropped
        case ackTimeout
        case excessiveRetries
        case suspiciousBehavior

        // Neutral events
        case connectionAttempt
        case discovered
        case rediscovered
    }

    enum ConnectionFailureReason {
        case timeout
        case rejected
        case resourceExhaustion
        case unknown
    }

    enum DisconnectionReason {
        case timeout
        case userInitiated
        case networkIssue
        case appBackground
        case unknown
    }

    enum TrustLevel: String {
        case untrusted = "❌"    // Score: 0-20
        case low = "🟡"         // Score: 21-40
        case moderate = "🟢"    // Score: 41-60
        case high = "⭐"        // Score: 61-80
        case verified = "✅"    // Score: 81-100

        init(score: Float) {
            switch score {
            case 0..<21: self = .untrusted
            case 21..<41: self = .low
            case 41..<61: self = .moderate
            case 61..<81: self = .high
            default: self = .verified
            }
        }

        var displayName: String {
            switch self {
            case .untrusted: return "No Confiable"
            case .low: return "Confianza Baja"
            case .moderate: return "Confianza Moderada"
            case .high: return "Confianza Alta"
            case .verified: return "Verificado"
            }
        }

        var minimumScore: Float {
            switch self {
            case .untrusted: return 0
            case .low: return 21
            case .moderate: return 41
            case .high: return 61
            case .verified: return 81
            }
        }
    }

    struct PeerReputation: Codable {
        let peerId: String
        var trustScore: Float = 60.0  // Start slightly higher to avoid initial rejections
        var successfulConnections: Int = 0
        var failedConnections: Int = 0
        var totalMessages: Int = 0
        var droppedMessages: Int = 0
        var averageLatency: Double = 0
        var totalConnectionTime: TimeInterval = 0
        var lastSeen: Date?
        var firstSeen: Date
        var notes: [String] = []

        // Computed properties
        var connectionSuccessRate: Float {
            let total = successfulConnections + failedConnections
            guard total > 0 else { return 0 }
            return Float(successfulConnections) / Float(total)
        }

        var messageSuccessRate: Float {
            guard totalMessages > 0 else { return 1.0 }
            return Float(totalMessages - droppedMessages) / Float(totalMessages)
        }

        var trustLevel: TrustLevel {
            return TrustLevel(score: trustScore)
        }

        var relationshipAge: TimeInterval {
            return Date().timeIntervalSince(firstSeen)
        }

        init(peerId: String) {
            self.peerId = peerId
            self.firstSeen = Date()
        }

        mutating func updateScore(event: ReputationEvent) {
            let previousScore = trustScore

            switch event {
            // Positive events
            case .successfulConnection:
                trustScore = min(100, trustScore + 3.0)
                successfulConnections += 1

            case .messageDelivered:
                trustScore = min(100, trustScore + 0.5)
                totalMessages += 1

            case .ackReceived:
                trustScore = min(100, trustScore + 0.3)

            case .stableConnection(let duration):
                // Bonus for long stable connections
                let hours = duration / 3600
                let bonus = min(5.0, Float(hours) * 0.5)
                trustScore = min(100, trustScore + bonus)
                totalConnectionTime += duration

            case .helpedRelay:
                trustScore = min(100, trustScore + 1.0)

            case .sharedResource:
                trustScore = min(100, trustScore + 2.0)

            // Negative events
            case .connectionFailed(let reason):
                failedConnections += 1
                switch reason {
                case .timeout:
                    trustScore = max(0, trustScore - 2.0)
                case .rejected:
                    trustScore = max(0, trustScore - 3.0)
                case .resourceExhaustion:
                    trustScore = max(0, trustScore - 1.0)
                case .unknown:
                    trustScore = max(0, trustScore - 1.5)
                }

            case .connectionDropped(let reason):
                switch reason {
                case .timeout:
                    trustScore = max(0, trustScore - 2.5)
                case .userInitiated:
                    // Minimal penalty for user-initiated
                    trustScore = max(0, trustScore - 0.5)
                case .networkIssue:
                    trustScore = max(0, trustScore - 1.0)
                case .appBackground:
                    // No penalty for app lifecycle
                    break
                case .unknown:
                    trustScore = max(0, trustScore - 1.5)
                }

            case .messageDropped:
                trustScore = max(0, trustScore - 1.0)
                droppedMessages += 1
                totalMessages += 1

            case .ackTimeout:
                trustScore = max(0, trustScore - 0.5)

            case .excessiveRetries:
                trustScore = max(0, trustScore - 2.0)

            case .suspiciousBehavior:
                trustScore = max(0, trustScore - 10.0)
                notes.append("Suspicious behavior detected at \(Date())")

            // Neutral events
            case .connectionAttempt:
                // No score change, just track
                break

            case .discovered, .rediscovered:
                lastSeen = Date()
            }

            // Apply decay for old relationships with no recent activity
            applyDecay()

            // Log significant changes
            // NOTE: Logging disabled here due to mutating function constraints
            // if abs(previousScore - trustScore) > 5 {
            //     LoggingService.network.info("📊 Reputation changed significantly")
            // }
        }

        private mutating func applyDecay() {
            guard let lastSeen = lastSeen else { return }

            let daysSinceLastSeen = Date().timeIntervalSince(lastSeen) / 86400

            if daysSinceLastSeen > 7 {
                // Gradual decay for inactive peers
                let decayRate: Float = 0.1 * Float(daysSinceLastSeen / 7)
                trustScore = max(30, trustScore - decayRate)  // Don't decay below 30
            }
        }

        mutating func recordLatency(_ latency: Double) {
            if averageLatency == 0 {
                averageLatency = latency
            } else {
                // Exponential moving average
                averageLatency = (averageLatency * 0.8) + (latency * 0.2)
            }

            // Adjust score based on latency
            if latency < 50 {
                trustScore = min(100, trustScore + 0.1)
            } else if latency > 200 {
                trustScore = max(0, trustScore - 0.1)
            }
        }
    }

    // MARK: - Properties

    @Published private(set) var reputations: [String: PeerReputation] = [:]
    @Published private(set) var trustedPeers: Set<String> = []
    @Published private(set) var blacklistedPeers: Set<String> = []

    private let persistenceKey = "PeerReputations"
    private let blacklistKey = "BlacklistedPeers"
    private let queue = DispatchQueue(label: "com.meshred.reputation", attributes: .concurrent)

    // Configuration
    private let blacklistThreshold: Float = 15.0
    private let trustedThreshold: Float = 70.0
    private let autoBlacklistEnabled = true

    // MARK: - Initialization

    init() {
        loadReputations()
        loadBlacklist()
    }

    // MARK: - Event Recording

    func recordEvent(_ event: ReputationEvent, for peer: MCPeerID) {
        recordEvent(event, forPeerId: peer.displayName)
    }

    func recordEvent(_ event: ReputationEvent, forPeerId peerId: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            // Get or create reputation
            var reputation = self.reputations[peerId] ?? PeerReputation(peerId: peerId)

            // Update score
            reputation.updateScore(event: event)

            // Check for auto-blacklist
            if self.autoBlacklistEnabled && reputation.trustScore < self.blacklistThreshold {
                self.blacklistPeer(peerId)
                reputation.notes.append("Auto-blacklisted at \(Date())")
            }

            // Update trusted set
            if reputation.trustScore >= self.trustedThreshold {
                DispatchQueue.main.async {
                    self.trustedPeers.insert(peerId)
                }
            } else {
                DispatchQueue.main.async {
                    self.trustedPeers.remove(peerId)
                }
            }

            // Save reputation
            self.reputations[peerId] = reputation
            self.saveReputations()

            // Log significant events
            self.logEvent(event, for: peerId, newScore: reputation.trustScore)
        }
    }

    func recordLatency(_ latency: Double, for peer: MCPeerID) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            var reputation = self.reputations[peer.displayName] ?? PeerReputation(peerId: peer.displayName)
            reputation.recordLatency(latency)
            self.reputations[peer.displayName] = reputation
        }
    }

    // MARK: - Queries

    func getReputation(for peer: MCPeerID) -> PeerReputation? {
        return getReputation(forPeerId: peer.displayName)
    }

    func getReputation(forPeerId peerId: String) -> PeerReputation? {
        return queue.sync {
            return reputations[peerId]
        }
    }

    func getTrustScore(for peer: MCPeerID) -> Float {
        return getTrustScore(forPeerId: peer.displayName)
    }

    func getTrustScore(forPeerId peerId: String) -> Float {
        return queue.sync {
            return reputations[peerId]?.trustScore ?? 50.0  // Default neutral score
        }
    }

    func getTrustLevel(for peer: MCPeerID) -> TrustLevel {
        let score = getTrustScore(for: peer)
        return TrustLevel(score: score)
    }

    func isBlacklisted(_ peer: MCPeerID) -> Bool {
        return queue.sync {
            return blacklistedPeers.contains(peer.displayName)
        }
    }

    func isTrusted(_ peer: MCPeerID) -> Bool {
        return queue.sync {
            return trustedPeers.contains(peer.displayName)
        }
    }

    func shouldAcceptConnection(from peer: MCPeerID) -> Bool {
        if isBlacklisted(peer) {
            LoggingService.network.info("❌ Rejecting connection from blacklisted peer: \(peer.displayName)")
            return false
        }

        let trustScore = getTrustScore(for: peer)
        if trustScore < 20 {
            LoggingService.network.info("⚠️ Low trust score for \(peer.displayName): \(trustScore)")
            // Could implement additional logic here
        }

        return true
    }

    // MARK: - Management

    func blacklistPeer(_ peerId: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.blacklistedPeers.insert(peerId)
            }

            self.saveBlacklist()

            LoggingService.network.info("🚫 Peer blacklisted: \(peerId)")

            NotificationCenter.default.post(
                name: .peerBlacklisted,
                object: nil,
                userInfo: ["peerId": peerId]
            )
        }
    }

    func removeFromBlacklist(_ peerId: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.blacklistedPeers.remove(peerId)
            }

            // Reset reputation to neutral
            if var reputation = self.reputations[peerId] {
                reputation.trustScore = 30.0  // Start low but not at zero
                reputation.notes.append("Removed from blacklist at \(Date())")
                self.reputations[peerId] = reputation
            }

            self.saveBlacklist()
            LoggingService.network.info("✅ Peer removed from blacklist: \(peerId)")
        }
    }

    func resetReputation(for peerId: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            self.reputations[peerId] = PeerReputation(peerId: peerId)
            self.saveReputations()

            DispatchQueue.main.async {
                self.trustedPeers.remove(peerId)
            }

            LoggingService.network.info("🔄 Reputation reset for: \(peerId)")
        }
    }

    // MARK: - Analytics

    func getTopPeers(limit: Int = 10) -> [PeerReputation] {
        return queue.sync {
            return Array(reputations.values
                .sorted { $0.trustScore > $1.trustScore }
                .prefix(limit))
        }
    }

    func getReputationSummary() -> (average: Float, trusted: Int, blacklisted: Int) {
        return queue.sync {
            let scores = reputations.values.map { $0.trustScore }
            let average = scores.isEmpty ? 50.0 : scores.reduce(0, +) / Float(scores.count)
            return (average, trustedPeers.count, blacklistedPeers.count)
        }
    }

    func getRecommendedPriority(for peer: MCPeerID) -> ConnectionPoolManager.ConnectionPriority {
        let trustLevel = getTrustLevel(for: peer)

        switch trustLevel {
        case .verified:
            return .high
        case .high:
            return .normal
        case .moderate:
            return .normal
        case .low:
            return .low
        case .untrusted:
            return .low
        }
    }

    // MARK: - Persistence

    private func saveReputations() {
        queue.async { [weak self] in
            guard let self = self else { return }

            if let encoded = try? JSONEncoder().encode(Array(self.reputations.values)) {
                UserDefaults.standard.set(encoded, forKey: self.persistenceKey)
            }
        }
    }

    private func loadReputations() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            if let data = UserDefaults.standard.data(forKey: self.persistenceKey),
               let decoded = try? JSONDecoder().decode([PeerReputation].self, from: data) {

                for reputation in decoded {
                    self.reputations[reputation.peerId] = reputation

                    if reputation.trustScore >= self.trustedThreshold {
                        DispatchQueue.main.async {
                            self.trustedPeers.insert(reputation.peerId)
                        }
                    }
                }

                LoggingService.network.info("📊 Loaded \(self.reputations.count) peer reputations")
            }
        }
    }

    private func saveBlacklist() {
        UserDefaults.standard.set(Array(blacklistedPeers), forKey: blacklistKey)
    }

    private func loadBlacklist() {
        if let blacklist = UserDefaults.standard.stringArray(forKey: blacklistKey) {
            DispatchQueue.main.async { [weak self] in
                self?.blacklistedPeers = Set(blacklist)
            }
            LoggingService.network.info("🚫 Loaded \(blacklist.count) blacklisted peers")
        }
    }

    // MARK: - Logging

    private func logEvent(_ event: ReputationEvent, for peerId: String, newScore: Float) {
        let eventDescription: String
        switch event {
        case .successfulConnection: eventDescription = "✅ Connection"
        case .connectionFailed: eventDescription = "❌ Failed"
        case .messageDelivered: eventDescription = "📬 Message"
        case .suspiciousBehavior: eventDescription = "⚠️ Suspicious"
        default: return  // Don't log every event
        }

        LoggingService.network.info("📊 Reputation: \(peerId) - \(eventDescription) → Score: \(newScore)")
    }

    // MARK: - Lightning Mode Support

    /// Reset all peer reputations to neutral starting value
    /// Used when Lightning Mode is enabled to provide fresh start without historical penalties
    func resetAllReputations() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            LoggingService.network.info("🗑️ RESETTING ALL PEER REPUTATIONS")
            LoggingService.network.info("   Reason: Lightning Mode enabled - fresh start")

            let previousCount = self.reputations.count

            // Reset all reputations to neutral (60.0 starting score)
            for (peerId, _) in self.reputations {
                var newReputation = PeerReputation(peerId: peerId)
                newReputation.trustScore = 60.0  // Neutral starting score
                newReputation.successfulConnections = 0
                newReputation.failedConnections = 0
                newReputation.totalMessages = 0
                newReputation.droppedMessages = 0
                newReputation.firstSeen = Date()
                self.reputations[peerId] = newReputation
            }

            // Clear blacklist (Lightning Mode shouldn't be blocked by old blacklists)
            self.blacklistedPeers.removeAll()

            // Persist changes to disk
            self.saveReputations()

            LoggingService.network.info("   ✓ Reset \(previousCount) peer reputations")
            LoggingService.network.info("   ✓ All peers now have neutral score (60.0)")
            LoggingService.network.info("   ✓ Blacklist cleared (\(previousCount) entries)")
            LoggingService.network.info("   Lightning Mode: Maximum speed, no historical penalties")
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let peerBlacklisted = Notification.Name("PeerBlacklisted")
    static let peerTrusted = Notification.Name("PeerTrusted")
    static let reputationChanged = Notification.Name("ReputationChanged")
}