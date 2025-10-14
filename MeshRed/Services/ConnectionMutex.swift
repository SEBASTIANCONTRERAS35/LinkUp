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

    /// Connection operation types
    enum Operation: String {
        case browserInvite = "browser_invite"
        case acceptInvitation = "accept_invitation"
        case sessionConnecting = "session_connecting"
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
class ConnectionConflictResolver {

    /// Determines who should initiate the connection based on peer IDs
    /// Returns true if local peer should initiate, false if should wait for invitation
    /// - Parameters:
    ///   - localPeer: Local peer ID
    ///   - remotePeer: Remote peer ID
    ///   - overrideBidirectional: If true, ignores conflict resolution and both peers can attempt connection
    static func shouldInitiateConnection(localPeer: MCPeerID, remotePeer: MCPeerID, overrideBidirectional: Bool = false) -> Bool {
        let localName = localPeer.displayName
        let remoteName = remotePeer.displayName

        // BIDIRECTIONAL OVERRIDE: Allow both peers to attempt connection simultaneously
        if overrideBidirectional {
            LoggingService.network.info("🔀 Conflict resolver: BIDIRECTIONAL MODE - Local(\(localName)) ATTEMPTS 🔄 with Remote(\(remoteName))")
            LoggingService.network.info("   Override enabled: Both peers will attempt connection")
            LoggingService.network.info("   Reason: Previous connection attempts failed with 'Connection refused'")
            return true  // Always return true when bidirectional mode is enabled
        }

        // CRITICAL FIX: Use deterministic string comparison instead of hashValue
        // hashValue is NOT stable across devices/executions and causes deadlocks
        // where both peers decide to wait or both decide to initiate

        let shouldInitiate: Bool
        if localName != remoteName {
            // Lexicographic comparison - ALWAYS produces same result on all devices
            shouldInitiate = localName > remoteName
        } else {
            // Impossible case: same display name (shouldn't happen in real scenarios)
            // Fallback to MCPeerID hash (more stable than String hash)
            shouldInitiate = localPeer.hashValue > remotePeer.hashValue
        }

        LoggingService.network.info("🎯 Conflict resolver: Local(\(localName)) \(shouldInitiate ? "INITIATES 🟢" : "WAITS 🟡") with Remote(\(remoteName))")
        LoggingService.network.info("   String comparison: \"\(localName)\" \(shouldInitiate ? ">" : "<=") \"\(remoteName)\"")
        LoggingService.network.info("   Decision: Local name \(shouldInitiate ? ">" : "<=") Remote name (lexicographic)")

        return shouldInitiate
    }

    /// Check if we should accept an invitation based on conflict resolution
    /// - Parameters:
    ///   - localPeer: Local peer ID
    ///   - fromPeer: Remote peer sending invitation
    ///   - overrideBidirectional: If true, always accepts invitation (bidirectional mode)
    static func shouldAcceptInvitation(localPeer: MCPeerID, fromPeer: MCPeerID, overrideBidirectional: Bool = false) -> Bool {
        // BIDIRECTIONAL OVERRIDE: Always accept in bidirectional mode
        if overrideBidirectional {
            LoggingService.network.info("🔀 Conflict resolver: BIDIRECTIONAL MODE - Accepting invitation from \(fromPeer.displayName)")
            return true
        }

        // We accept invitations if we shouldn't initiate
        return !shouldInitiateConnection(localPeer: localPeer, remotePeer: fromPeer)
    }
}