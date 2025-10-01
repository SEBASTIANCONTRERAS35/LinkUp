//
//  FamilySyncMessage.swift
//  MeshRed
//
//  Created by Claude for StadiumConnect Pro
//

import Foundation

/// Message exchanged between peers to synchronize family group membership
/// Automatically sent when two peers connect for the first time
struct FamilySyncMessage: Codable {
    let senderId: String                    // Peer sending the sync
    let groupCode: FamilyGroupCode          // Family group code
    let memberInfo: FamilyMemberInfo        // Sender's member information
    let timestamp: Date

    init(
        senderId: String,
        groupCode: FamilyGroupCode,
        memberInfo: FamilyMemberInfo,
        timestamp: Date = Date()
    ) {
        self.senderId = senderId
        self.groupCode = groupCode
        self.memberInfo = memberInfo
        self.timestamp = timestamp
    }

    /// Create sync message from a family group and current device info
    static func create(from group: FamilyGroup, currentPeerID: String) -> FamilySyncMessage? {
        guard let currentMember = group.members.first(where: { $0.peerID == currentPeerID }) else {
            return nil
        }

        let memberInfo = FamilyMemberInfo(
            nickname: currentMember.nickname,
            relationshipTag: currentMember.relationshipTag
        )

        return FamilySyncMessage(
            senderId: currentPeerID,
            groupCode: group.code,
            memberInfo: memberInfo
        )
    }

    /// Lightweight member info to share (doesn't include location or timestamps)
    struct FamilyMemberInfo: Codable {
        let nickname: String?
        let relationshipTag: String?

        /// Convert to full FamilyMember
        func toFamilyMember(peerID: String) -> FamilyMember {
            return FamilyMember(
                peerID: peerID,
                nickname: nickname,
                relationshipTag: relationshipTag,
                lastSeenDate: Date(),
                isCurrentDevice: false
            )
        }
    }
}
