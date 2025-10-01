//
//  FamilyJoinRequestMessage.swift
//  MeshRed
//
//  Created by Claude for StadiumConnect Pro
//

import Foundation

/// Request to join a family group by validating code with connected peers
/// Broadcast to all connected peers to find who has the matching group code
struct FamilyJoinRequestMessage: Codable, Identifiable {
    let id: UUID
    let requesterId: String                     // Peer requesting to join
    let groupCode: FamilyGroupCode              // Code of the group to join
    let memberInfo: FamilySyncMessage.FamilyMemberInfo  // Info of the requester
    let timestamp: Date

    init(
        id: UUID = UUID(),
        requesterId: String,
        groupCode: FamilyGroupCode,
        memberInfo: FamilySyncMessage.FamilyMemberInfo,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.requesterId = requesterId
        self.groupCode = groupCode
        self.memberInfo = memberInfo
        self.timestamp = timestamp
    }

    /// Age of the request in seconds
    var age: TimeInterval {
        return Date().timeIntervalSince(timestamp)
    }

    /// Whether the request has timed out (default 5 seconds)
    func hasTimedOut(timeout: TimeInterval = 5.0) -> Bool {
        return age > timeout
    }
}
