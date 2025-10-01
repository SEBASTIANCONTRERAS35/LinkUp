//
//  TopologyMessage.swift
//  MeshRed
//
//  Network topology discovery message for building routing tables
//

import Foundation

/// Message broadcasted periodically by each peer to announce its direct connections
/// This allows all peers to build a complete map of the network topology
struct TopologyMessage: Codable, Identifiable {
    let id: UUID
    let senderId: String
    let connectedPeers: [String]  // Direct connections of this peer
    let timestamp: Date
    let ttl: Int  // How many hops this topology message can travel
    var hopCount: Int
    var routePath: [String]  // Path this topology message has traveled

    init(
        senderId: String,
        connectedPeers: [String],
        ttl: Int = 5,
        hopCount: Int = 0,
        routePath: [String] = []
    ) {
        self.id = UUID()
        self.senderId = senderId
        self.connectedPeers = connectedPeers
        self.timestamp = Date()
        self.ttl = ttl
        self.hopCount = hopCount
        self.routePath = routePath
    }

    /// Check if this topology message can be relayed further
    func canHop() -> Bool {
        return hopCount < ttl
    }

    /// Check if this topology message has already visited a peer
    func hasVisited(_ peerId: String) -> Bool {
        return routePath.contains(peerId)
    }

    /// Add a hop to the route path
    mutating func addHop(_ peerId: String) {
        if !routePath.contains(peerId) {
            routePath.append(peerId)
        }
        hopCount += 1
    }

    /// Check if topology is stale (older than threshold)
    func isStale(threshold: TimeInterval = 30.0) -> Bool {
        return Date().timeIntervalSince(timestamp) > threshold
    }

    /// Age of this topology message in seconds
    var age: TimeInterval {
        return Date().timeIntervalSince(timestamp)
    }
}

/// Represents the network topology state for a single peer
struct PeerTopology: Codable {
    let peerId: String
    let connectedPeers: [String]
    let lastUpdate: Date

    /// Check if this topology entry is stale
    func isStale(threshold: TimeInterval = 30.0) -> Bool {
        return Date().timeIntervalSince(lastUpdate) > threshold
    }
}
