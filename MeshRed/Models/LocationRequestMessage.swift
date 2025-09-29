//
//  LocationRequestMessage.swift
//  MeshRed
//
//  Created by Emilio Contreras on 29/09/25.
//

import Foundation

/// Request for location information from a specific peer
/// Can be fulfilled directly by target or via collaborative triangulation by intermediary
struct LocationRequestMessage: Codable, Identifiable {
    let id: UUID
    let requesterId: String              // Peer requesting location (A)
    let targetId: String                 // Peer whose location is requested (C)
    let timestamp: Date
    let allowCollaborativeTriangulation: Bool  // Allow intermediaries to respond with UWB data

    init(
        id: UUID = UUID(),
        requesterId: String,
        targetId: String,
        timestamp: Date = Date(),
        allowCollaborativeTriangulation: Bool = true
    ) {
        self.id = id
        self.requesterId = requesterId
        self.targetId = targetId
        self.timestamp = timestamp
        self.allowCollaborativeTriangulation = allowCollaborativeTriangulation
    }

    /// Check if this request is for a specific peer
    func isForPeer(_ peerId: String) -> Bool {
        return targetId == peerId
    }

    /// Age of the request in seconds
    var age: TimeInterval {
        return Date().timeIntervalSince(timestamp)
    }

    /// Whether the request has timed out (default 10 seconds)
    func hasTimedOut(timeout: TimeInterval = 10.0) -> Bool {
        return age > timeout
    }
}