//
//  SimulatedMessage.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Individual simulated message with read state tracking
//

import Foundation

/// Represents a single simulated message with read state
struct SimulatedMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let content: String
    let timestamp: Date
    let senderId: String  // peerID of sender
    var isRead: Bool

    init(
        id: UUID = UUID(),
        content: String,
        timestamp: Date = Date(),
        senderId: String,
        isRead: Bool = false
    ) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.senderId = senderId
        self.isRead = isRead
    }

    /// Create from legacy string message
    static func fromLegacy(_ content: String, senderId: String, minutesAgo: Int = 5) -> SimulatedMessage {
        return SimulatedMessage(
            content: content,
            timestamp: Date().addingTimeInterval(-Double(minutesAgo * 60)),
            senderId: senderId,
            isRead: false
        )
    }

    /// Time ago display
    var timeAgo: String {
        let interval = Date().timeIntervalSince(timestamp)

        if interval < 60 {
            return "Ahora"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "Hace \(minutes)min"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "Hace \(hours)h"
        } else {
            let days = Int(interval / 86400)
            return "Hace \(days)d"
        }
    }

    static func == (lhs: SimulatedMessage, rhs: SimulatedMessage) -> Bool {
        lhs.id == rhs.id
    }
}

/// Message read state for a specific member in a group
struct MemberReadState: Codable {
    let memberId: String
    var lastReadTimestamp: Date
    var readMessageIds: Set<UUID>

    init(memberId: String) {
        self.memberId = memberId
        self.lastReadTimestamp = Date()
        self.readMessageIds = []
    }

    mutating func markAsRead(_ messageId: UUID) {
        readMessageIds.insert(messageId)
        lastReadTimestamp = Date()
    }

    mutating func markAllAsRead(_ messageIds: [UUID]) {
        readMessageIds.formUnion(messageIds)
        lastReadTimestamp = Date()
    }

    func isRead(_ messageId: UUID) -> Bool {
        readMessageIds.contains(messageId)
    }
}

/// Group read state tracking
struct GroupReadState: Codable {
    let groupId: UUID
    var memberStates: [String: MemberReadState]  // memberId -> state

    init(groupId: UUID) {
        self.groupId = groupId
        self.memberStates = [:]
    }

    mutating func markAsRead(memberId: String, messageId: UUID) {
        if memberStates[memberId] == nil {
            memberStates[memberId] = MemberReadState(memberId: memberId)
        }
        memberStates[memberId]?.markAsRead(messageId)
    }

    mutating func markAllAsRead(memberId: String, messageIds: [UUID]) {
        if memberStates[memberId] == nil {
            memberStates[memberId] = MemberReadState(memberId: memberId)
        }
        memberStates[memberId]?.markAllAsRead(messageIds)
    }

    func isRead(memberId: String, messageId: UUID) -> Bool {
        memberStates[memberId]?.isRead(messageId) ?? false
    }

    func getUnreadCount(memberId: String, allMessageIds: [UUID]) -> Int {
        guard let memberState = memberStates[memberId] else {
            return allMessageIds.count
        }
        return allMessageIds.filter { !memberState.isRead($0) }.count
    }
}
