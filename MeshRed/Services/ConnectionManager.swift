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
import os

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

        LoggingService.network.info("🚫 ConnectionManager: Manually disconnected and blocked: \(peerKey)")
        LoggingService.network.info("   Total blocked peers: \(self.blockedPeers.count, privacy: .public)")
    }

    /// Manually connect to a peer (unblocks and marks as preferred)
    func manuallyConnectPeer(_ peerID: MCPeerID) {
        let peerKey = peerID.displayName

        blockedPeers.remove(peerKey)
        manuallyDisconnectedPeers.remove(peerKey)
        preferredPeers.insert(peerKey)

        persistData()

        LoggingService.network.info("✅ ConnectionManager: Unblocked and connecting to: \(peerKey)")
        LoggingService.network.info("   Total preferred peers: \(self.preferredPeers.count, privacy: .public)")
    }

    /// Unblock a peer without marking as preferred
    func unblockPeer(_ peerID: String) {
        blockedPeers.remove(peerID)
        manuallyDisconnectedPeers.remove(peerID)

        persistData()

        LoggingService.network.info("🔓 ConnectionManager: Unblocked: \(peerID)")
    }

    /// Unblock all peers
    func unblockAllPeers() {
        blockedPeers.removeAll()
        manuallyDisconnectedPeers.removeAll()

        persistData()

        LoggingService.network.info("🔓 ConnectionManager: Unblocked all peers")
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
            LoggingService.network.info("📂 ConnectionManager: Loaded \(blocked.count) blocked peers")
        }

        if let preferred = UserDefaults.standard.array(forKey: preferredPeersKey) as? [String] {
            preferredPeers = Set(preferred)
            LoggingService.network.info("📂 ConnectionManager: Loaded \(preferred.count) preferred peers")
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
            LoggingService.network.info("🧹 ConnectionManager: Auto-cleaning blocks older than 24h")
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

    // MARK: - Development Helpers

    /// Clear all blocks for development (useful when testing Simulator-Device connections)
    /// Call this in DEBUG builds to reset connection state
    func clearAllBlocksForDevelopment() {
        #if DEBUG
        let blockedCount = blockedPeers.count
        if blockedCount > 0 {
            LoggingService.network.info("🧹 [DEV] Clearing \(blockedCount) blocked peers for development:")
            for peer in blockedPeers {
                LoggingService.network.info("   - \(peer)")
            }
            unblockAllPeers()
        }
        #endif
    }
}
