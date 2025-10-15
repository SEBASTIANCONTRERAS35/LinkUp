import Foundation
import MultipeerConnectivity
import os

/// Thread-safe mutex for managing connection operations
/// Ensures only one connection operation happens per peer at a time
class ConnectionMutex {
    private let queue = DispatchQueue(label: "com.meshred.connectionmutex", attributes: .concurrent)
    private var activeOperations: Set<String> = []
    private var pendingConnections: [String: Date] = [:]
    private var operationTypes: [String: String] = [:]  // Track operation type for each peer

    // Dynamic timeout based on Lightning Mode
    private var operationTimeout: TimeInterval {
        if UserDefaults.standard.bool(forKey: "lightningModeUltraFast") {
            return 3.0  // Ultra-fast: 3s timeout for FIFA 2026 stadiums
        }
        return 5.0  // Normal: 5s timeout
    }

    /// Connection operation types (now used for tracking specific operations)
    enum Operation: String {
        case browserInvite = "browser_invite"
        case acceptInvitation = "accept_invitation"
        case sessionConnecting = "session_connecting"
    }

    /// Handshake role enum - determines who invites in a peer pair
    enum HandshakeRole {
        case inviter    // This peer should initiate the invitation
        case acceptor   // This peer should wait for and accept invitations
    }

    /// Try to acquire lock for a connection operation
    /// Returns true if lock acquired, false if another operation is in progress
    func tryAcquireLock(for peer: MCPeerID, operation: Operation) -> Bool {
        return queue.sync(flags: .barrier) {
            let peerKey = peer.displayName
            let now = Date()

            // Clean up expired operations
            cleanupExpiredOperations(now: now)

            // Check if there's an active operation for this peer
            if activeOperations.contains(peerKey) {
                LoggingService.network.info("🔒 Connection mutex: Operation already in progress for \(peerKey)")
                return false
            }

            // Check if there's a recent pending connection
            if let pendingTime = pendingConnections[peerKey],
               now.timeIntervalSince(pendingTime) < 1.0 {  // Reduced to 1s for faster operations
                LoggingService.network.info("🔒 Connection mutex: Recent pending connection for \(peerKey)")
                return false
            }

            // Acquire lock
            activeOperations.insert(peerKey)
            pendingConnections[peerKey] = now
            operationTypes[peerKey] = operation.rawValue  // Store operation type
            LoggingService.network.info("🔓 Connection mutex: Lock acquired for \(peerKey) - Operation: \(operation.rawValue)")
            return true
        }
    }

    /// Release lock for a peer
    func releaseLock(for peer: MCPeerID) {
        queue.async(flags: .barrier) { [weak self] in
            let peerKey = peer.displayName
            self?.activeOperations.remove(peerKey)
            self?.operationTypes.removeValue(forKey: peerKey)  // Clear operation type
            LoggingService.network.info("🔓 Connection mutex: Lock released for \(peerKey)")
        }
    }

    /// Check if there's an active operation for a peer
    func hasActiveOperation(for peer: MCPeerID) -> Bool {
        return queue.sync {
            activeOperations.contains(peer.displayName)
        }
    }

    /// Get the type of operation currently active for a peer
    func getOperationType(for peer: MCPeerID) -> String? {
        return queue.sync {
            operationTypes[peer.displayName]
        }
    }

    /// Get current operation as enum (returns nil if no active operation)
    func currentOperation(for peer: MCPeerID) -> Operation? {
        return queue.sync {
            guard let opString = operationTypes[peer.displayName] else { return nil }
            return Operation(rawValue: opString)
        }
    }

    /// Force swap to a different operation for a peer (for preemption scenarios)
    /// Use with caution - this bypasses normal lock acquisition
    func forceSwap(to operation: Operation, for peer: MCPeerID) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            let peerKey = peer.displayName

            LoggingService.network.info("⚡ Connection mutex: FORCE SWAPPING operation for \(peerKey)")
            LoggingService.network.info("   Previous operation: \(self.operationTypes[peerKey] ?? "none")")
            LoggingService.network.info("   New operation: \(operation.rawValue)")

            // Update operation type (keep peer in activeOperations)
            self.operationTypes[peerKey] = operation.rawValue
            self.pendingConnections[peerKey] = Date()  // Reset timestamp

            LoggingService.network.info("   ✅ Operation swapped successfully")
        }
    }

    /// Clean up expired operations (in case of failures)
    private func cleanupExpiredOperations(now: Date) {
        // Capture timeout value once to avoid repeated computed property access
        let timeout = self.operationTimeout

        // Find expired peers BEFORE filtering (critical fix)
        let expiredPeers = pendingConnections.compactMap { peerKey, timestamp -> String? in
            if now.timeIntervalSince(timestamp) >= timeout {
                return peerKey
            }
            return nil
        }

        // Clean up expired operations
        for peerKey in expiredPeers {
            activeOperations.remove(peerKey)
            pendingConnections.removeValue(forKey: peerKey)
            operationTypes.removeValue(forKey: peerKey)
            LoggingService.network.info("🧹 Connection mutex: Cleaned up expired operation for \(peerKey) after \(timeout)s")
        }

        // Filter remaining non-expired connections
        pendingConnections = pendingConnections.filter { _, timestamp in
            now.timeIntervalSince(timestamp) < timeout
        }
    }

    /// Clear all locks (use carefully)
    func clearAll() {
        queue.async(flags: .barrier) { [weak self] in
            self?.activeOperations.removeAll()
            self?.pendingConnections.removeAll()
            self?.operationTypes.removeAll()
            LoggingService.network.info("🗑️ Connection mutex: All locks cleared")
        }
    }

    /// Alias for clearAll() for better semantic clarity
    func releaseAllLocks() {
        clearAll()
    }

    /// Force release lock for a specific peer (use in recovery scenarios)
    func forceRelease(for peerID: MCPeerID) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let peerKey = peerID.displayName

            // Remove from active operations
            if self.activeOperations.contains(peerKey) {
                self.activeOperations.remove(peerKey)
                LoggingService.network.info("🔓 Connection mutex: FORCE released lock for \(peerKey)")
            }

            // Remove from pending connections
            if self.pendingConnections[peerKey] != nil {
                self.pendingConnections.removeValue(forKey: peerKey)
                LoggingService.network.info("🔓 Connection mutex: Cleared pending connection for \(peerKey)")
            }

            // Remove operation type
            self.operationTypes.removeValue(forKey: peerKey)
        }
    }

    /// Get current status
    func getStatus() -> (activeCount: Int, pendingCount: Int) {
        return queue.sync {
            (activeOperations.count, pendingConnections.count)
        }
    }
}

/// Connection conflict resolver using deterministic algorithm
/// CRITICAL: This resolver's rules are IMMUTABLE and ALWAYS enforced,
/// even in Lightning/Bidirectional modes. The handshake role is determined
/// by displayName lexicographic order and never changes.
class ConnectionConflictResolver {

    /// Determine the handshake role for a local peer relative to a remote peer
    /// Uses deterministic lexicographic comparison of displayName
    /// IMPORTANT: This rule is NEVER overridden, even in Lightning/Bidirectional mode
    /// - Parameters:
    ///   - local: Local peer ID
    ///   - remote: Remote peer ID
    /// - Returns: HandshakeRole indicating who should invite
    static func handshakeRole(local: MCPeerID, remote: MCPeerID) -> ConnectionMutex.HandshakeRole {
        let localName = local.displayName
        let remoteName = remote.displayName

        // Lexicographic comparison - stable across all devices/executions
        // Ensures one and only one peer invites in any peer pair
        if localName < remoteName {
            return .inviter
        } else {
            return .acceptor
        }
    }

    /// Check if local peer should invite remote peer
    /// This is the ONLY source of truth for invitation decisions
    /// CRITICAL: Lightning/Bidirectional mode MUST NOT override this
    /// - Parameters:
    ///   - local: Local peer ID
    ///   - remote: Remote peer ID
    /// - Returns: true if local should invite, false otherwise
    static func shouldInvite(_ local: MCPeerID, _ remote: MCPeerID) -> Bool {
        let role = handshakeRole(local: local, remote: remote)
        let shouldInvite = role == .inviter

        LoggingService.network.info("🎯 Conflict resolver (IMMUTABLE RULE):")
        LoggingService.network.info("   Local: \(local.displayName)")
        LoggingService.network.info("   Remote: \(remote.displayName)")
        LoggingService.network.info("   Role: \(role == .inviter ? "INVITER 🟢" : "ACCEPTOR 🟡")")
        LoggingService.network.info("   Decision: \(shouldInvite ? "Local SHOULD invite" : "Local should WAIT for invitation")")
        LoggingService.network.info("   Comparison: \"\(local.displayName)\" \(local.displayName < remote.displayName ? "<" : ">=") \"\(remote.displayName)\"")

        return shouldInvite
    }

    /// Check if we should accept an invitation based on conflict resolution
    /// CRITICAL: This respects the immutable handshake role
    /// - Parameters:
    ///   - localPeer: Local peer ID
    ///   - fromPeer: Remote peer sending invitation
    /// - Returns: true if should accept, false otherwise
    static func shouldAcceptInvitation(localPeer: MCPeerID, fromPeer: MCPeerID) -> Bool {
        // We accept invitations if we are the acceptor role
        let shouldAccept = !shouldInvite(localPeer, fromPeer)

        if shouldAccept {
            LoggingService.network.info("✅ Should ACCEPT invitation from \(fromPeer.displayName) (we are acceptor)")
        } else {
            LoggingService.network.info("⛔ Should REJECT invitation from \(fromPeer.displayName) (we are inviter)")
        }

        return shouldAccept
    }

    /// Legacy method for backward compatibility - now always uses immutable rule
    /// NOTE: overrideBidirectional parameter is IGNORED - no more overrides
    @available(*, deprecated, message: "Use shouldInvite() instead - no more bidirectional override")
    static func shouldInitiateConnection(localPeer: MCPeerID, remotePeer: MCPeerID, overrideBidirectional: Bool = false) -> Bool {
        if overrideBidirectional {
            LoggingService.network.warning("⚠️ DEPRECATED: overrideBidirectional parameter is ignored")
            LoggingService.network.warning("   Using immutable handshake role instead")
        }
        return shouldInvite(localPeer, remotePeer)
    }
}

// MARK: - BackoffScheduler

/// Manages exponential backoff with jitter for connection retries
/// Prevents thundering herd problem when multiple peers retry simultaneously
final class BackoffScheduler {
    private var timers: [String: DispatchSourceTimer] = [:]
    private var attemptCounts: [String: Int] = [:]  // Track retry attempts per peer
    private let queue = DispatchQueue(label: "com.meshred.backoff", attributes: .concurrent)

    /// Schedule a retry action with exponential backoff and jitter
    /// - Parameters:
    ///   - peerID: Peer to schedule retry for
    ///   - base: Base delay in seconds (default: 0.6s)
    ///   - factor: Exponential factor (default: 2.0)
    ///   - max: Maximum delay in seconds (default: 8.0s)
    ///   - jitter: Jitter factor as percentage of delay (default: 0.2 = ±20%)
    ///   - queue: Dispatch queue to execute action on (default: .main)
    ///   - action: Closure to execute after delay
    func scheduleRetry(_ peerID: MCPeerID,
                       base: TimeInterval = 0.6,
                       factor: Double = 2.0,
                       max: TimeInterval = 8.0,
                       jitter: Double = 0.2,
                       queue: DispatchQueue = .main,
                       action: @escaping () -> Void) {
        self.queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let key = peerID.displayName

            // Cancel existing timer for this peer
            self.timers[key]?.cancel()
            self.timers.removeValue(forKey: key)

            // Get current attempt count
            let attempt = self.attemptCounts[key] ?? 0
            self.attemptCounts[key] = attempt + 1

            // Calculate exponential backoff: base * (factor ^ attempt)
            let exponentialDelay = base * pow(factor, Double(attempt))
            let cappedDelay = min(max, exponentialDelay)

            // Add jitter: ±jitter% of the delay
            let jitterAmount = cappedDelay * jitter
            let jitterOffset = Double.random(in: -jitterAmount...jitterAmount)
            let finalDelay = cappedDelay + jitterOffset

            LoggingService.network.info("⏱️ BackoffScheduler: Scheduling retry for \(key)")
            LoggingService.network.info("   Attempt: \(attempt + 1)")
            LoggingService.network.info("   Base delay: \(base)s")
            LoggingService.network.info("   Exponential delay: \(String(format: "%.2f", exponentialDelay))s")
            LoggingService.network.info("   Capped delay: \(String(format: "%.2f", cappedDelay))s")
            LoggingService.network.info("   Jitter: \(String(format: "%.2f", jitterOffset))s")
            LoggingService.network.info("   Final delay: \(String(format: "%.2f", finalDelay))s")

            // Create timer
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + finalDelay)
            timer.setEventHandler { [weak self] in
                // Execute action
                action()

                // Clean up
                self?.queue.async(flags: .barrier) {
                    self?.timers[key]?.cancel()
                    self?.timers.removeValue(forKey: key)
                }
            }

            self.timers[key] = timer
            timer.resume()
        }
    }

    /// Reset backoff state for a peer (call when connection succeeds)
    func reset(for peerID: MCPeerID) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            let key = peerID.displayName

            // Cancel any pending timer
            self.timers[key]?.cancel()
            self.timers.removeValue(forKey: key)

            // Reset attempt count
            self.attemptCounts.removeValue(forKey: key)

            LoggingService.network.info("🔄 BackoffScheduler: Reset backoff for \(key)")
        }
    }

    /// Cancel pending retry for a peer
    func cancel(for peerID: MCPeerID) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            let key = peerID.displayName

            if let timer = self.timers[key] {
                timer.cancel()
                self.timers.removeValue(forKey: key)
                LoggingService.network.info("❌ BackoffScheduler: Cancelled retry for \(key)")
            }
        }
    }

    /// Cancel all pending retries
    func cancelAll() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            for (_, timer) in self.timers {
                timer.cancel()
            }

            self.timers.removeAll()
            self.attemptCounts.removeAll()

            LoggingService.network.info("🗑️ BackoffScheduler: Cancelled all retries")
        }
    }

    /// Get current attempt count for a peer
    func getAttemptCount(for peerID: MCPeerID) -> Int {
        return queue.sync {
            return attemptCounts[peerID.displayName] ?? 0
        }
    }
}