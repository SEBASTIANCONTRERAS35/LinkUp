//
//  FamilyMember.swift
//  MeshRed
//
//  Created by Claude for StadiumConnect Pro
//

import Foundation
import CoreLocation

/// Represents an individual member of a family group
struct FamilyMember: Codable, Identifiable, Equatable {
    let id: UUID
    let peerID: String                      // MCPeerID displayName
    var nickname: String?                   // Optional friendly name
    var relationshipTag: String?            // "Mamá", "Papá", "Hijo", etc.
    var lastSeenDate: Date?                 // Last time seen on mesh
    var lastKnownLocation: UserLocation?    // Last known GPS location
    var isCurrentDevice: Bool               // Is this the current user's device?

    init(
        id: UUID = UUID(),
        peerID: String,
        nickname: String? = nil,
        relationshipTag: String? = nil,
        lastSeenDate: Date? = nil,
        lastKnownLocation: UserLocation? = nil,
        isCurrentDevice: Bool = false
    ) {
        self.id = id
        self.peerID = peerID
        self.nickname = nickname
        self.relationshipTag = relationshipTag
        self.lastSeenDate = lastSeenDate
        self.lastKnownLocation = lastKnownLocation
        self.isCurrentDevice = isCurrentDevice
    }

    /// Display name (nickname > peerID)
    var displayName: String {
        if let nickname = nickname, !nickname.isEmpty {
            return nickname
        }
        return peerID
    }

    /// Full display with relationship tag
    var displayNameWithRelation: String {
        if let tag = relationshipTag, !tag.isEmpty {
            return "\(displayName) (\(tag))"
        }
        return displayName
    }

    /// Whether member was recently seen (within last 5 minutes)
    var isRecentlySeen: Bool {
        guard let lastSeen = lastSeenDate else { return false }
        return Date().timeIntervalSince(lastSeen) < 300 // 5 minutes
    }

    /// Time since last seen
    var timeSinceLastSeen: String {
        guard let lastSeen = lastSeenDate else { return "Nunca" }

        let seconds = Int(Date().timeIntervalSince(lastSeen))

        if seconds < 60 {
            return "Hace \(seconds)s"
        } else if seconds < 3600 {
            return "Hace \(seconds / 60)m"
        } else if seconds < 86400 {
            return "Hace \(seconds / 3600)h"
        } else {
            return "Hace \(seconds / 86400)d"
        }
    }

    /// Update last seen timestamp
    mutating func updateLastSeen() {
        self.lastSeenDate = Date()
    }

    /// Update location
    mutating func updateLocation(_ location: UserLocation) {
        self.lastKnownLocation = location
        updateLastSeen()
    }

    static func == (lhs: FamilyMember, rhs: FamilyMember) -> Bool {
        return lhs.id == rhs.id && lhs.peerID == rhs.peerID
    }
}
