//
//  RoutingTable.swift
//  MeshRed
//
//  Dynamic routing table for LinkMesh network topology management
//

import Foundation
import MultipeerConnectivity
import Combine

/// Manages network topology and calculates optimal routes to peers
class RoutingTable: ObservableObject {
    /// Network topology: peerId -> list of directly connected peers
    @Published private(set) var topology: [String: PeerTopology] = [:]

    /// Cached routes: targetPeerId -> list of next hops to reach target
    @Published private(set) var routes: [String: [String]] = [:]

    /// Peers that are reachable (directly or indirectly)
    @Published private(set) var reachablePeers: Set<String> = []

    private let localPeerID: String
    private let staleThreshold: TimeInterval = 30.0  // 30 seconds
    private var cleanupTimer: Timer?

    init(localPeerID: String) {
        self.localPeerID = localPeerID
        startCleanupTimer()
    }

    deinit {
        cleanupTimer?.invalidate()
    }

    // MARK: - Topology Updates

    /// Update topology from received TopologyMessage
    func updateTopology(_ topologyMessage: TopologyMessage) {
        let peerId = topologyMessage.senderId

        // Update topology entry
        topology[peerId] = PeerTopology(
            peerId: peerId,
            connectedPeers: topologyMessage.connectedPeers,
            lastUpdate: topologyMessage.timestamp
        )

        // Recalculate routes
        recalculateRoutes()

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🗺️ TOPOLOGY UPDATED")
        print("   Peer: \(peerId)")
        print("   Connections: \(topologyMessage.connectedPeers.joined(separator: ", "))")
        print("   Reachable Peers: \(reachablePeers.count)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    /// Update topology for local peer's direct connections
    func updateLocalTopology(connectedPeers: [MCPeerID]) {
        let peerNames = connectedPeers.map { $0.displayName }

        topology[localPeerID] = PeerTopology(
            peerId: localPeerID,
            connectedPeers: peerNames,
            lastUpdate: Date()
        )

        recalculateRoutes()
    }

    /// Remove a peer from topology (when disconnected)
    func removePeer(_ peerId: String) {
        topology.removeValue(forKey: peerId)

        // Also remove from others' connection lists (will be updated by their topology broadcasts)
        recalculateRoutes()

        print("🗺️ Removed \(peerId) from topology")
    }

    // MARK: - Route Calculation (BFS)

    /// Recalculate all routes using Breadth-First Search
    private func recalculateRoutes() {
        routes.removeAll()
        reachablePeers.removeAll()

        // BFS to find shortest path to each peer
        var visited: Set<String> = [localPeerID]
        var queue: [(peer: String, path: [String])] = []

        // Start with direct connections
        if let localTopology = topology[localPeerID] {
            for directPeer in localTopology.connectedPeers {
                queue.append((peer: directPeer, path: [directPeer]))
                visited.insert(directPeer)
                routes[directPeer] = [directPeer]  // Direct connection
                reachablePeers.insert(directPeer)
            }
        }

        // BFS for indirect connections
        while !queue.isEmpty {
            let (currentPeer, currentPath) = queue.removeFirst()

            guard let currentTopology = topology[currentPeer] else { continue }

            for neighborPeer in currentTopology.connectedPeers {
                if !visited.contains(neighborPeer) {
                    visited.insert(neighborPeer)
                    let newPath = currentPath + [neighborPeer]

                    // Store only the FIRST hop (next peer to send to)
                    routes[neighborPeer] = [currentPath.first!]
                    reachablePeers.insert(neighborPeer)

                    queue.append((peer: neighborPeer, path: newPath))
                }
            }
        }

        print("🗺️ Routes recalculated: \(routes.count) peers reachable")
    }

    // MARK: - Route Queries

    /// Get next hops to reach a target peer (returns direct connections to send message through)
    func getNextHops(to targetPeerId: String) -> [String]? {
        return routes[targetPeerId]
    }

    /// Check if a peer is reachable (directly or indirectly)
    func isReachable(_ peerId: String) -> Bool {
        return reachablePeers.contains(peerId)
    }

    /// Get all reachable peers through a specific next hop
    func getPeersReachableThrough(nextHop: String) -> [String] {
        return routes.filter { $0.value.contains(nextHop) }.map { $0.key }
    }

    /// Check if peer is directly connected
    func isDirectlyConnected(_ peerId: String) -> Bool {
        guard let localTopology = topology[localPeerID] else { return false }
        return localTopology.connectedPeers.contains(peerId)
    }

    // MARK: - Cleanup

    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.removeStaleTopologies()
        }
    }

    /// Remove stale topology entries
    private func removeStaleTopologies() {
        let stalePeers = topology.filter { $0.value.isStale(threshold: staleThreshold) }.map { $0.key }

        if !stalePeers.isEmpty {
            print("🗺️ Removing \(stalePeers.count) stale topology entries")
            for peerId in stalePeers {
                topology.removeValue(forKey: peerId)
            }
            recalculateRoutes()
        }
    }

    /// Clear all topology data
    func clear() {
        topology.removeAll()
        routes.removeAll()
        reachablePeers.removeAll()
        print("🗺️ Routing table cleared")
    }

    // MARK: - Diagnostics

    func getTopologyDiagnostics() -> String {
        var diag = "=== ROUTING TABLE DIAGNOSTICS ===\n"
        diag += "Local Peer: \(localPeerID)\n"
        diag += "Known Peers: \(topology.count)\n"
        diag += "Reachable Peers: \(reachablePeers.count)\n"
        diag += "Calculated Routes: \(routes.count)\n\n"

        diag += "Topology:\n"
        for (peerId, peerTopology) in topology.sorted(by: { $0.key < $1.key }) {
            let age = Int(Date().timeIntervalSince(peerTopology.lastUpdate))
            diag += "  \(peerId): [\(peerTopology.connectedPeers.joined(separator: ", "))] (age: \(age)s)\n"
        }

        diag += "\nRoutes:\n"
        for (targetPeer, nextHops) in routes.sorted(by: { $0.key < $1.key }) {
            diag += "  \(targetPeer) → [\(nextHops.joined(separator: ", "))]\n"
        }

        diag += "================================\n"
        return diag
    }

    func printTopology() {
        print(getTopologyDiagnostics())
    }
}
