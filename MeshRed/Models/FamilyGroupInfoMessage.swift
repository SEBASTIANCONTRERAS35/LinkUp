//
//  FamilyGroupInfoMessage.swift
//  MeshRed
//
//  Created by Claude for StadiumConnect Pro
//

import Foundation

/// Response containing complete family group information
/// Sent back to requester when a peer has the matching group code
struct FamilyGroupInfoMessage: Codable, Identifiable {
    let id: UUID
    let requestId: UUID                         // ID of the original request
    let responderId: String                     // Peer responding with group info
    let groupCode: FamilyGroupCode              // Code of the group
    let groupName: String                       // Real name of the group
    let creatorPeerID: String                   // Creator of the group
    let memberCount: Int                        // Number of members
    let members: [SimplifiedMemberInfo]         // Info of all members
    let timestamp: Date

    init(
        id: UUID = UUID(),
        requestId: UUID,
        responderId: String,
        groupCode: FamilyGroupCode,
        groupName: String,
        creatorPeerID: String,
        memberCount: Int,
        members: [SimplifiedMemberInfo],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.requestId = requestId
        self.responderId = responderId
        self.groupCode = groupCode
        self.groupName = groupName
        self.creatorPeerID = creatorPeerID
        self.memberCount = memberCount
        self.members = members
        self.timestamp = timestamp
    }

    /// Simplified member information (subset of FamilyMember)
    struct SimplifiedMemberInfo: Codable, Identifiable {
        let id: UUID
        let peerID: String
        let nickname: String?
        let relationshipTag: String?

        init(id: UUID = UUID(), peerID: String, nickname: String?, relationshipTag: String?) {
            self.id = id
            self.peerID = peerID
            self.nickname = nickname
            self.relationshipTag = relationshipTag
        }

        /// Convert to full FamilyMember
        func toFamilyMember() -> FamilyMember {
            return FamilyMember(
                id: id,
                peerID: peerID,
                nickname: nickname,
                relationshipTag: relationshipTag,
                lastSeenDate: Date(),
                isCurrentDevice: false
            )
        }
    }

    /// Create group info message from a FamilyGroup
    static func create(from group: FamilyGroup, requestId: UUID, responderId: String) -> FamilyGroupInfoMessage {
        let members = group.members.map { member in
            SimplifiedMemberInfo(
                id: member.id,
                peerID: member.peerID,
                nickname: member.nickname,
                relationshipTag: member.relationshipTag
            )
        }

        return FamilyGroupInfoMessage(
            requestId: requestId,
            responderId: responderId,
            groupCode: group.code,
            groupName: group.name,
            creatorPeerID: group.creatorPeerID,
            memberCount: group.memberCount,
            members: members
        )
    }
}
