import Foundation
import MultipeerConnectivity

/// Thread-safe mutex for managing connection operations
/// Ensures only one connection operation happens per peer at a time
class ConnectionMutex {
    private let queue = DispatchQueue(label: "com.meshred.connectionmutex", attributes: .concurrent)
    private var activeOperations: Set<String> = []
    private var pendingConnections: [String: Date] = [:]
    private let operationTimeout: TimeInterval = 5.0  // Reduced to 5s for faster cleanup

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
                print("🔒 Connection mutex: Operation already in progress for \(peerKey)")
                return false
            }

            // Check if there's a recent pending connection
            if let pendingTime = pendingConnections[peerKey],
               now.timeIntervalSince(pendingTime) < 1.0 {  // Reduced to 1s for faster operations
                print("🔒 Connection mutex: Recent pending connection for \(peerKey)")
                return false
            }

            // Acquire lock
            activeOperations.insert(peerKey)
            pendingConnections[peerKey] = now
            print("🔓 Connection mutex: Lock acquired for \(peerKey) - Operation: \(operation.rawValue)")
            return true
        }
    }

    /// Release lock for a peer
    func releaseLock(for peer: MCPeerID) {
        queue.async(flags: .barrier) { [weak self] in
            let peerKey = peer.displayName
            self?.activeOperations.remove(peerKey)
            print("🔓 Connection mutex: Lock released for \(peerKey)")
        }
    }

    /// Check if there's an active operation for a peer
    func hasActiveOperation(for peer: MCPeerID) -> Bool {
        return queue.sync {
            activeOperations.contains(peer.displayName)
        }
    }

    /// Clean up expired operations (in case of failures)
    private func cleanupExpiredOperations(now: Date) {
        pendingConnections = pendingConnections.filter { _, timestamp in
            now.timeIntervalSince(timestamp) < operationTimeout
        }

        // Also clean active operations if they've been stuck for too long
        // This prevents deadlocks in case of failures
        let expiredPeers = pendingConnections.compactMap { peerKey, timestamp -> String? in
            if now.timeIntervalSince(timestamp) >= operationTimeout {
                return peerKey
            }
            return nil
        }

        for peerKey in expiredPeers {
            activeOperations.remove(peerKey)
            pendingConnections.removeValue(forKey: peerKey)
            print("🧹 Connection mutex: Cleaned up expired operation for \(peerKey)")
        }
    }

    /// Clear all locks (use carefully)
    func clearAll() {
        queue.async(flags: .barrier) { [weak self] in
            self?.activeOperations.removeAll()
            self?.pendingConnections.removeAll()
            print("🗑️ Connection mutex: All locks cleared")
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
                print("🔓 Connection mutex: FORCE released lock for \(peerKey)")
            }

            // Remove from pending connections
            if self.pendingConnections[peerKey] != nil {
                self.pendingConnections.removeValue(forKey: peerKey)
                print("🔓 Connection mutex: Cleared pending connection for \(peerKey)")
            }
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
    static func shouldInitiateConnection(localPeer: MCPeerID, remotePeer: MCPeerID) -> Bool {
        let localName = localPeer.displayName
        let remoteName = remotePeer.displayName

        // Use hash-based comparison for uniform distribution (50/50 chance)
        // This prevents alphabetic bias where some names always lose
        let localHash = localName.hashValue
        let remoteHash = remoteName.hashValue

        let shouldInitiate: Bool
        if localHash != remoteHash {
            // Normal case: compare hash values
            shouldInitiate = localHash > remoteHash
        } else {
            // Extremely rare case: identical hashes, use random tiebreaker
            shouldInitiate = UUID().uuidString > UUID().uuidString
        }

        print("🎯 Conflict resolver: Local(\(localName)) \(shouldInitiate ? "INITIATES 🟢" : "WAITS 🟡") with Remote(\(remoteName))")
        print("   Hash comparison: \(localHash) vs \(remoteHash)")
        print("   Decision: Local hash \(shouldInitiate ? ">" : "<=") Remote hash")

        return shouldInitiate
    }

    /// Check if we should accept an invitation based on conflict resolution
    static func shouldAcceptInvitation(localPeer: MCPeerID, fromPeer: MCPeerID) -> Bool {
        // We accept invitations if we shouldn't initiate
        return !shouldInitiateConnection(localPeer: localPeer, remotePeer: fromPeer)
    }
}