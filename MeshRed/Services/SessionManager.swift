import Foundation
import MultipeerConnectivity

struct PeerConnectionInfo {
    let peerId: MCPeerID
    var firstAttempt: Date
    var lastAttempt: Date
    var attemptCount: Int
    var isBlocked: Bool
    var blockUntil: Date?
    var lastDisconnection: Date?
    var lastSuccessfulConnection: Date?
    var connectionEstablishedTime: Date?  // Track when connection was established
    var isConnecting: Bool = false
    var connectionStabilityScore: Int = 0  // Track connection stability
    var connectionRefusedCount: Int = 0  // Track "Connection refused" errors (error 61)
    var shouldAttemptBidirectional: Bool = false  // Enable aggressive bidirectional mode

    init(peerId: MCPeerID) {
        self.peerId = peerId
        self.firstAttempt = Date()
        self.lastAttempt = Date()
        self.attemptCount = 1
        self.isBlocked = false
        self.blockUntil = nil
    }

    mutating func recordAttempt() {
        lastAttempt = Date()
        attemptCount += 1
    }

    mutating func block(for duration: TimeInterval) {
        isBlocked = true
        blockUntil = Date().addingTimeInterval(duration)
    }

    mutating func unblockIfNeeded() {
        if let blockUntil = blockUntil, Date() > blockUntil {
            isBlocked = false
            self.blockUntil = nil
            attemptCount = 0
        }
    }

    mutating func shouldRetry() -> Bool {
        unblockIfNeeded()
        return !isBlocked && attemptCount < SessionManager.maxRetryAttempts
    }

    func nextRetryDelay() -> TimeInterval {
        // ⚡ CIRCUIT BREAKER: Exponential backoff based on consecutive refused count
        // Independent per peer - each peer has its own delay schedule
        let isUltraFast = UserDefaults.standard.bool(forKey: "lightningModeUltraFast")

        if isUltraFast && connectionRefusedCount > 0 {
            // Ultra-fast mode with progressive backoff per peer
            switch connectionRefusedCount {
            case 1...3:
                return 0.1   // First 3 attempts: ultra-fast
            case 4...6:
                return 0.5   // Next 3: slightly slower
            case 7...9:
                return 1.0   // Getting slower
            case 10...12:
                return 2.0   // Moderate delay
            case 13...15:
                return 5.0   // Significant delay
            default:
                return 10.0  // Maximum backoff before circuit breaker
            }
        } else {
            // Normal mode backoff
            let baseDelay: TimeInterval = 2.0
            let exponentialDelay = baseDelay * pow(2.0, Double(min(attemptCount - 1, 4)))
            return min(exponentialDelay, 32.0)
        }
    }

    // Circuit breaker state (per peer)
    var circuitBreakerActive: Bool = false
    var circuitBreakerUntil: Date?

    mutating func activateCircuitBreaker() {
        circuitBreakerActive = true
        circuitBreakerUntil = Date().addingTimeInterval(30.0) // 30 second pause
    }

    mutating func checkCircuitBreaker() -> Bool {
        if let until = circuitBreakerUntil, Date() < until {
            return true // Still in circuit breaker period
        }
        // Circuit breaker expired, reset
        if circuitBreakerActive {
            circuitBreakerActive = false
            circuitBreakerUntil = nil
            connectionRefusedCount = 0 // Reset refused count
            print("🔄 Circuit breaker reset for \(peerId.displayName)")
        }
        return false
    }
}

class SessionManager {
    static let maxRetryAttempts = 10  // Increased for more persistent reconnection
    static let connectionTimeout: TimeInterval = 30.0  // DOUBLED: Increased to 30s to allow slower TLS handshakes to complete
    static let blockDuration: TimeInterval = 10.0  // Only block for 10s
    static let cleanupInterval: TimeInterval = 5.0  // Aggressive cleanup every 5s
    static let disconnectionCooldown: TimeInterval = 2.0  // Increased to allow message exchange completion
    static let connectionGracePeriod: TimeInterval = 2.0  // Very short grace period
    static let unstablePeerCooldown: TimeInterval = 5.0   // Even unstable peers get quick retry

    private var connectionAttempts: [String: PeerConnectionInfo] = [:]
    private var activeConnections: Set<String> = []
    private let queue = DispatchQueue(label: "com.meshred.sessionmanager", attributes: .concurrent)
    private var cleanupTimer: Timer?

    init() {
        startCleanupTimer()
    }

    deinit {
        cleanupTimer?.invalidate()
    }

    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: SessionManager.cleanupInterval, repeats: true) { [weak self] _ in
            self?.cleanupStaleConnections()
        }
    }

    private func cleanupStaleConnections() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let now = Date()
            let staleThreshold = now.addingTimeInterval(-600)

            self.connectionAttempts = self.connectionAttempts.filter { _, info in
                if info.lastAttempt < staleThreshold && !info.isBlocked {
                    print("🧹 Removing stale connection info for: \(info.peerId.displayName)")
                    return false
                }
                return true
            }

            for key in self.connectionAttempts.keys {
                self.connectionAttempts[key]?.unblockIfNeeded()
            }
        }
    }

    func shouldAttemptConnection(to peer: MCPeerID) -> Bool {
        return queue.sync {
            let peerKey = peer.displayName

            if activeConnections.contains(peerKey) {
                print("🔗 Already connected to \(peerKey)")
                return false
            }

            if var info = connectionAttempts[peerKey] {
                info.unblockIfNeeded()

                // ⚡ CIRCUIT BREAKER: Check if circuit breaker is active for this peer
                if info.checkCircuitBreaker() {
                    let remaining = info.circuitBreakerUntil?.timeIntervalSinceNow ?? 0
                    print("⛔ CIRCUIT BREAKER ACTIVE for \(peerKey)")
                    print("   Refused count: \(info.connectionRefusedCount)")
                    print("   Waiting \(Int(max(0, remaining)))s before retry")
                    connectionAttempts[peerKey] = info  // Update stored info
                    return false
                }

                // Update the stored info after unblock check
                connectionAttempts[peerKey] = info

                if info.isBlocked {
                    print("🚫 Peer blocked until \(info.blockUntil?.description ?? "unknown"): \(peerKey)")
                    return false
                }

                if info.isConnecting {
                    print("🔄 Already connecting to \(peerKey)")
                    return false
                }

                // ⚡ ULTRA-FAST: Skip grace period in Lightning Mode Ultra-Fast
                let isUltraFast = UserDefaults.standard.bool(forKey: "lightningModeUltraFast")
                if !isUltraFast {
                    // Check for recent successful connection (grace period)
                    if let lastSuccess = info.lastSuccessfulConnection {
                        let timeSinceSuccess = Date().timeIntervalSince(lastSuccess)
                        if timeSinceSuccess < SessionManager.connectionGracePeriod {
                            let waitTime = SessionManager.connectionGracePeriod - timeSinceSuccess
                            let waitTimeStr = waitTime.isFinite ? "\(Int(max(0, waitTime)))" : "0"
                            print("⏰ Grace period active for \(peerKey). Wait \(waitTimeStr)s")
                            return false
                        }
                    }
                } else if info.lastSuccessfulConnection != nil {
                    print("⚡ ULTRA-FAST: Bypassing grace period for \(peerKey)")
                }

                // ⚡ ULTRA-FAST: Skip cooldowns in Lightning Mode Ultra-Fast
                if !isUltraFast {
                    // Check disconnection cooldown (adaptive based on stability score)
                    if let lastDisconnection = info.lastDisconnection {
                        let timeSinceDisconnection = Date().timeIntervalSince(lastDisconnection)

                        // Adaptive cooldown based on stability score (REDUCED for faster reconnection)
                        let requiredCooldown: TimeInterval
                        if info.connectionStabilityScore >= 3 {
                            // Very stable peer - almost instant reconnect
                            requiredCooldown = 0.2  // Reduced from 0.5
                        } else if info.connectionStabilityScore >= 0 {
                            // Neutral to slightly stable - short cooldown
                            requiredCooldown = 1.0  // Reduced from 2.0
                        } else if info.connectionStabilityScore >= -2 {
                            // Slightly unstable - moderate cooldown
                            requiredCooldown = 2.0  // Reduced from 5.0
                        } else {
                            // Very unstable - still reasonable cooldown
                            requiredCooldown = 4.0  // Reduced from 10.0
                        }

                        if timeSinceDisconnection < requiredCooldown {
                            let waitTime = requiredCooldown - timeSinceDisconnection
                            let waitTimeStr = waitTime.isFinite ? "\(Int(max(0, waitTime)))" : "0"
                            print("🆒 Adaptive cooldown for \(peerKey): \(waitTimeStr)s (stability: \(info.connectionStabilityScore))")
                            return false
                        }
                    }
                } else if info.lastDisconnection != nil {
                    print("⚡ ULTRA-FAST: Bypassing disconnection cooldown for \(peerKey)")
                }

                // ⚡ ULTRA-FAST: No retry delays in Lightning Mode Ultra-Fast
                if !isUltraFast {
                    let timeSinceLastAttempt = Date().timeIntervalSince(info.lastAttempt)
                    let requiredDelay = info.nextRetryDelay()

                    if timeSinceLastAttempt < requiredDelay {
                        let waitTime = requiredDelay - timeSinceLastAttempt
                        let waitTimeStr = waitTime.isFinite ? "\(Int(max(0, waitTime)))" : "0"
                        print("⏳ Too soon to retry \(peerKey). Wait \(waitTimeStr)s")
                        return false
                    }
                } else {
                    print("⚡ ULTRA-FAST: No retry delay for \(peerKey) - immediate connection allowed")
                }

                return info.attemptCount < SessionManager.maxRetryAttempts
            }

            return true
        }
    }

    func recordConnectionAttempt(to peer: MCPeerID) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let peerKey = peer.displayName

            if var info = self.connectionAttempts[peerKey] {
                // Don't increment if already blocked
                if info.isBlocked {
                    print("⚠️ Attempt to record connection for blocked peer: \(peerKey)")
                    return
                }

                // If this is a new discovery after a disconnection, reset attempt count
                if let lastDisconnection = info.lastDisconnection,
                   Date().timeIntervalSince(lastDisconnection) > 5.0 {
                    print("🔄 Resetting attempts for \(peerKey) - rediscovered after disconnection")
                    info.attemptCount = 0
                }

                info.recordAttempt()
                info.isConnecting = true

                if info.attemptCount >= SessionManager.maxRetryAttempts {
                    info.block(for: SessionManager.blockDuration)
                    info.isConnecting = false
                    print("❌ Max attempts reached for \(peerKey). Blocking for \(Int(SessionManager.blockDuration))s.")
                } else {
                    // ⚡ ULTRA-FAST: No delays in Lightning Mode Ultra-Fast
                    let isUltraFast = UserDefaults.standard.bool(forKey: "lightningModeUltraFast")
                    let delay = isUltraFast ? 0.0 : info.nextRetryDelay()
                    if isUltraFast {
                        print("⚡ ULTRA-FAST: Bypassing retry delay for \(peerKey) - immediate retry allowed")
                    } else {
                        print("🔄 Connection attempt #\(info.attemptCount) to \(peerKey). Next retry in \(Int(delay))s")
                    }
                }

                self.connectionAttempts[peerKey] = info
            } else {
                var newInfo = PeerConnectionInfo(peerId: peer)
                newInfo.isConnecting = true
                self.connectionAttempts[peerKey] = newInfo
                print("📝 Recording first connection attempt to \(peerKey)")
            }
        }
    }

    func recordConnectionDeclined(to peer: MCPeerID, reason: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let peerKey = peer.displayName

            if var info = self.connectionAttempts[peerKey] {
                // Mark as not connecting
                info.isConnecting = false
                // Don't increment attemptCount for conflict resolution declines
                self.connectionAttempts[peerKey] = info
                print("📝 Connection declined for \(peerKey): \(reason) (not counting as failed attempt)")
            }
        }
    }

    func recordSuccessfulConnection(to peer: MCPeerID) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let peerKey = peer.displayName
            self.activeConnections.insert(peerKey)

            if var info = self.connectionAttempts[peerKey] {
                info.isConnecting = false
                info.attemptCount = 0
                info.lastDisconnection = nil
                info.lastSuccessfulConnection = Date()
                info.connectionEstablishedTime = Date()  // Track when connection was established
                info.connectionStabilityScore = min(5, info.connectionStabilityScore + 1)  // Improve stability score
                self.connectionAttempts[peerKey] = info
            } else {
                var newInfo = PeerConnectionInfo(peerId: peer)
                newInfo.lastSuccessfulConnection = Date()
                newInfo.connectionEstablishedTime = Date()  // Track when connection was established
                newInfo.connectionStabilityScore = 1
                self.connectionAttempts[peerKey] = newInfo
            }

            print("✅ Successfully connected to \(peerKey)")
        }
    }

    func recordDisconnection(from peer: MCPeerID) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let peerKey = peer.displayName
            self.activeConnections.remove(peerKey)

            if var info = self.connectionAttempts[peerKey] {
                info.lastDisconnection = Date()
                info.isConnecting = false

                // Decrease stability score ONLY for VERY quick disconnections
                // STABILITY FIX: Reduced from 30s to 10s and penalty from -2 to -1
                // This allows legitimate connection exchanges (topology, family sync, UWB) to complete
                if let lastSuccess = info.lastSuccessfulConnection,
                   Date().timeIntervalSince(lastSuccess) < 10 {
                    info.connectionStabilityScore = max(-5, info.connectionStabilityScore - 1)
                    print("📉 Stability score decreased for \(peerKey): \(info.connectionStabilityScore)")
                }

                // FIX: Clear lastSuccessfulConnection to disable grace period
                // This allows immediate reconnection attempts after disconnect
                // Grace period was blocking legitimate user-initiated reconnections
                info.lastSuccessfulConnection = nil

                self.connectionAttempts[peerKey] = info
            } else {
                var newInfo = PeerConnectionInfo(peerId: peer)
                newInfo.lastDisconnection = Date()
                newInfo.isConnecting = false
                self.connectionAttempts[peerKey] = newInfo
            }

            print("🔌 Disconnected from \(peerKey)")
        }
    }

    func resetPeer(_ peer: MCPeerID) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let peerKey = peer.displayName
            self.connectionAttempts.removeValue(forKey: peerKey)
            self.activeConnections.remove(peerKey)

            print("♻️ Reset connection info for \(peerKey)")
        }
    }

    func getConnectionStats() -> (attempts: Int, blocked: Int, active: Int) {
        queue.sync {
            let blockedCount = connectionAttempts.values.filter { $0.isBlocked }.count
            return (
                attempts: connectionAttempts.count,
                blocked: blockedCount,
                active: activeConnections.count
            )
        }
    }

    func clearAll() {
        queue.async(flags: .barrier) { [weak self] in
            self?.connectionAttempts.removeAll()
            self?.activeConnections.removeAll()
            print("🗑️ Cleared all session data")
        }
    }

    func clearCooldown(for peer: MCPeerID) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            let peerKey = peer.displayName

            if var info = self.connectionAttempts[peerKey] {
                // Reset all blocking and cooldown states
                info.isBlocked = false
                info.blockUntil = nil
                info.attemptCount = 0
                info.isConnecting = false
                info.lastAttempt = Date.distantPast  // Allow immediate retry
                self.connectionAttempts[peerKey] = info
                print("🔓 Cleared cooldown for \(peerKey) - ready for immediate reconnection")
            } else {
                print("ℹ️ No cooldown to clear for \(peerKey)")
            }
        }
    }

    func getConnectionTime(for peer: MCPeerID) -> Date? {
        var connectionTime: Date? = nil
        queue.sync {
            let peerKey = peer.displayName
            connectionTime = connectionAttempts[peerKey]?.connectionEstablishedTime
        }
        return connectionTime
    }

    // MARK: - Bidirectional Connection Mode (Connection Refused Handling)

    /// Record a "Connection refused" error (error 61) for a peer
    /// After 2-3 consecutive errors, enable bidirectional connection mode
    func recordConnectionRefused(to peer: MCPeerID) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let peerKey = peer.displayName

            if var info = self.connectionAttempts[peerKey] {
                info.connectionRefusedCount += 1
                info.isConnecting = false

                // ⚡ CIRCUIT BREAKER: Check if we need to activate circuit breaker
                if info.connectionRefusedCount >= 15 {
                    info.activateCircuitBreaker()
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    print("⛔ CIRCUIT BREAKER ACTIVATED for \(peerKey)")
                    print("   Too many failures: \(info.connectionRefusedCount)")
                    print("   Action: Pausing attempts for 30 seconds")
                    print("   This peer appears unreachable")
                    print("   Other peers are NOT affected")
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                } else if info.connectionRefusedCount >= 1 {
                    // Enable bidirectional mode after first failure
                    info.shouldAttemptBidirectional = true

                    // Get the appropriate delay for this peer
                    let delay = info.nextRetryDelay()

                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    print("⚡ BIDIRECTIONAL MODE - Progressive Backoff")
                    print("   Peer: \(peerKey)")
                    print("   Connection refused count: \(info.connectionRefusedCount)")
                    print("   Next retry delay: \(delay)s (per-peer backoff)")
                    print("   Action: Both peers will attempt connection")
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                }

                self.connectionAttempts[peerKey] = info
                print("📝 Connection refused for \(peerKey) (count: \(info.connectionRefusedCount))")
            } else {
                var newInfo = PeerConnectionInfo(peerId: peer)
                newInfo.connectionRefusedCount = 1
                newInfo.isConnecting = false
                // ⚡ ULTRA-FAST: Enable bidirectional immediately on first failure
                newInfo.shouldAttemptBidirectional = true
                self.connectionAttempts[peerKey] = newInfo
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("⚡ ULTRA-FAST BIDIRECTIONAL MODE ENABLED")
                print("   Peer: \(peerKey)")
                print("   First connection refused - activating bidirectional immediately")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            }
        }
    }

    /// Check if bidirectional connection mode should be used for a peer
    /// Get the appropriate retry delay for a specific peer based on their failure history
    func getRetryDelay(for peer: MCPeerID) -> TimeInterval {
        return queue.sync {
            let peerKey = peer.displayName
            if let info = connectionAttempts[peerKey] {
                return info.nextRetryDelay()
            }
            // Default minimal delay for new peers
            return 0.1
        }
    }

    func shouldUseBidirectionalConnection(for peer: MCPeerID) -> Bool {
        return queue.sync {
            let peerKey = peer.displayName
            return connectionAttempts[peerKey]?.shouldAttemptBidirectional ?? false
        }
    }

    /// Reset connection refused count (called on successful connection)
    func resetConnectionRefusedCount(for peer: MCPeerID) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let peerKey = peer.displayName

            if var info = self.connectionAttempts[peerKey] {
                info.connectionRefusedCount = 0
                info.shouldAttemptBidirectional = false
                self.connectionAttempts[peerKey] = info
                print("✅ Reset connection refused count for \(peerKey)")
            }
        }
    }
}