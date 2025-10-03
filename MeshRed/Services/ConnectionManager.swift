//
//  ConnectionManager.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Manages manual peer connections with 5-connection limit
//

import Foundation
import MultipeerConnectivity
import Combine

class ConnectionManager: ObservableObject {
    // MARK: - Published Properties
    @Published var blockedPeers: Set<String> = []
    @Published var preferredPeers: Set<String> = []
    @Published var manuallyDisconnectedPeers: Set<String> = []

    // MARK: - Constants
    private let blockedPeersKey = "blockedPeers"
    private let preferredPeersKey = "preferredPeers"
    private let autoUnblockInterval: TimeInterval = 86400 // 24 hours

    // MARK: - Initialization
    init() {
        loadPersistedData()
        cleanupOldBlocks()
    }

    // MARK: - Public Methods

    /// Check if a peer is blocked from connecting
    func isPeerBlocked(_ peerID: String) -> Bool {
        return blockedPeers.contains(peerID)
    }

    /// Check if a peer is preferred
    func isPeerPreferred(_ peerID: String) -> Bool {
        return preferredPeers.contains(peerID)
    }

    /// Manually disconnect a peer (blocks future auto-reconnection)
    func manuallyDisconnectPeer(_ peerID: MCPeerID) {
        let peerKey = peerID.displayName

        blockedPeers.insert(peerKey)
        manuallyDisconnectedPeers.insert(peerKey)
        preferredPeers.remove(peerKey)

        persistData()

        print("🚫 ConnectionManager: Manually disconnected and blocked: \(peerKey)")
        print("   Total blocked peers: \(blockedPeers.count)")
    }

    /// Manually connect to a peer (unblocks and marks as preferred)
    func manuallyConnectPeer(_ peerID: MCPeerID) {
        let peerKey = peerID.displayName

        blockedPeers.remove(peerKey)
        manuallyDisconnectedPeers.remove(peerKey)
        preferredPeers.insert(peerKey)

        persistData()

        print("✅ ConnectionManager: Unblocked and connecting to: \(peerKey)")
        print("   Total preferred peers: \(preferredPeers.count)")
    }

    /// Unblock a peer without marking as preferred
    func unblockPeer(_ peerID: String) {
        blockedPeers.remove(peerID)
        manuallyDisconnectedPeers.remove(peerID)

        persistData()

        print("🔓 ConnectionManager: Unblocked: \(peerID)")
    }

    /// Unblock all peers
    func unblockAllPeers() {
        blockedPeers.removeAll()
        manuallyDisconnectedPeers.removeAll()

        persistData()

        print("🔓 ConnectionManager: Unblocked all peers")
    }

    /// Check if can connect to more peers based on limit
    func canAcceptMoreConnections(currentCount: Int, maxConnections: Int) -> Bool {
        return currentCount < maxConnections
    }

    /// Get suggested peers to disconnect (least preferred)
    func getSuggestedPeerToDisconnect(from connectedPeers: [MCPeerID]) -> MCPeerID? {
        // First, disconnect non-preferred peers
        for peer in connectedPeers {
            if !isPeerPreferred(peer.displayName) {
                return peer
            }
        }

        // If all are preferred, return the first one
        return connectedPeers.first
    }

    // MARK: - Persistence

    private func persistData() {
        UserDefaults.standard.set(Array(blockedPeers), forKey: blockedPeersKey)
        UserDefaults.standard.set(Array(preferredPeers), forKey: preferredPeersKey)

        // Save timestamps for auto-cleanup
        let timestamp = Date().timeIntervalSince1970
        UserDefaults.standard.set(timestamp, forKey: "lastBlockTimestamp")
    }

    private func loadPersistedData() {
        if let blocked = UserDefaults.standard.array(forKey: blockedPeersKey) as? [String] {
            blockedPeers = Set(blocked)
            print("📂 ConnectionManager: Loaded \(blocked.count) blocked peers")
        }

        if let preferred = UserDefaults.standard.array(forKey: preferredPeersKey) as? [String] {
            preferredPeers = Set(preferred)
            print("📂 ConnectionManager: Loaded \(preferred.count) preferred peers")
        }
    }

    /// Clean up blocks older than 24 hours
    private func cleanupOldBlocks() {
        guard let lastBlockTime = UserDefaults.standard.object(forKey: "lastBlockTimestamp") as? TimeInterval else {
            return
        }

        let currentTime = Date().timeIntervalSince1970
        let timeSinceLastBlock = currentTime - lastBlockTime

        if timeSinceLastBlock > autoUnblockInterval {
            print("🧹 ConnectionManager: Auto-cleaning blocks older than 24h")
            blockedPeers.removeAll()
            persistData()
        }
    }

    // MARK: - Debug Info

    func getDebugInfo() -> String {
        """
        ConnectionManager Status:
        - Blocked Peers: \(blockedPeers.count)
        - Preferred Peers: \(preferredPeers.count)
        - Manually Disconnected: \(manuallyDisconnectedPeers.count)

        Blocked: \(blockedPeers.joined(separator: ", "))
        Preferred: \(preferredPeers.joined(separator: ", "))
        """
    }
}
