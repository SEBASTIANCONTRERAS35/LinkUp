//
//  FamilyGroup.swift
//  MeshRed
//
//  Created by Claude for StadiumConnect Pro
//

import Foundation

/// Represents a family group for collaborative finding in stadium events
struct FamilyGroup: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String                    // e.g., "Familia Contreras"
    let code: FamilyGroupCode           // Unique shareable code
    let createdAt: Date
    var members: [FamilyMember]         // All family members
    let creatorPeerID: String           // Device that created the group

    init(
        id: UUID = UUID(),
        name: String,
        code: FamilyGroupCode,
        createdAt: Date = Date(),
        members: [FamilyMember] = [],
        creatorPeerID: String
    ) {
        self.id = id
        self.name = name
        self.code = code
        self.createdAt = createdAt
        self.members = members
        self.creatorPeerID = creatorPeerID
    }

    /// Create a new family group with creator as first member
    static func create(name: String, creatorPeerID: String, creatorNickname: String? = nil) -> FamilyGroup {
        let code = FamilyGroupCode.generate()
        let creatorMember = FamilyMember(
            peerID: creatorPeerID,
            nickname: creatorNickname,
            relationshipTag: nil,
            lastSeenDate: Date(),
            isCurrentDevice: true
        )

        return FamilyGroup(
            name: name,
            code: code,
            members: [creatorMember],
            creatorPeerID: creatorPeerID
        )
    }

    /// Add a new member to the group
    mutating func addMember(_ member: FamilyMember) {
        // Check if member already exists (by peerID)
        if let existingIndex = members.firstIndex(where: { $0.peerID == member.peerID }) {
            // Update existing member
            members[existingIndex] = member
        } else {
            // Add new member
            members.append(member)
        }
    }

    /// Remove a member from the group
    mutating func removeMember(withPeerID peerID: String) {
        members.removeAll { $0.peerID == peerID }
    }

    /// Update member's last seen timestamp
    mutating func updateMemberLastSeen(peerID: String) {
        if let index = members.firstIndex(where: { $0.peerID == peerID }) {
            members[index].updateLastSeen()
        }
    }

    /// Update member's location
    mutating func updateMemberLocation(peerID: String, location: UserLocation) {
        if let index = members.firstIndex(where: { $0.peerID == peerID }) {
            members[index].updateLocation(location)
        }
    }

    /// Get member by peerID
    func getMember(withPeerID peerID: String) -> FamilyMember? {
        return members.first { $0.peerID == peerID }
    }

    /// Check if a peer is a member of this family
    func hasMember(withPeerID peerID: String) -> Bool {
        return members.contains { $0.peerID == peerID }
    }

    /// Get current device's member info
    var currentDeviceMember: FamilyMember? {
        return members.first { $0.isCurrentDevice }
    }

    /// Get other family members (excluding current device)
    var otherMembers: [FamilyMember] {
        return members.filter { !$0.isCurrentDevice }
    }

    /// Count of family members
    var memberCount: Int {
        return members.count
    }

    /// Get members sorted by last seen (most recent first)
    var membersByLastSeen: [FamilyMember] {
        return members.sorted { (m1, m2) in
            guard let d1 = m1.lastSeenDate, let d2 = m2.lastSeenDate else {
                return m1.lastSeenDate != nil
            }
            return d1 > d2
        }
    }

    /// Get only recently seen members
    var recentlySeenMembers: [FamilyMember] {
        return members.filter { $0.isRecentlySeen }
    }

    /// Age of the group
    var age: TimeInterval {
        return Date().timeIntervalSince(createdAt)
    }

    static func == (lhs: FamilyGroup, rhs: FamilyGroup) -> Bool {
        return lhs.id == rhs.id && lhs.code == rhs.code
    }
}
