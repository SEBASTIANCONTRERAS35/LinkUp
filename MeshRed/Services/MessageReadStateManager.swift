//
//  MessageReadStateManager.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Manages read/unread state for simulated messages with JSON persistence
//

import Foundation
import Combine

/// Manages read state for all simulated group messages
class MessageReadStateManager: ObservableObject {
    static let shared = MessageReadStateManager()

    @Published private(set) var groupStates: [UUID: GroupReadState] = [:]

    private let userDefaults = UserDefaults.standard
    private let storageKey = "StadiumConnect.MessageReadStates"

    private init() {
        loadFromStorage()
    }

    // MARK: - Public API

    /// Mark a single message as read
    func markAsRead(groupId: UUID, memberId: String, messageId: UUID) {
        if groupStates[groupId] == nil {
            groupStates[groupId] = GroupReadState(groupId: groupId)
        }
        groupStates[groupId]?.markAsRead(memberId: memberId, messageId: messageId)
        saveToStorage()
        objectWillChange.send()
    }

    /// Mark all messages from a member as read
    func markAllAsRead(groupId: UUID, memberId: String, messageIds: [UUID]) {
        if groupStates[groupId] == nil {
            groupStates[groupId] = GroupReadState(groupId: groupId)
        }
        groupStates[groupId]?.markAllAsRead(memberId: memberId, messageIds: messageIds)
        saveToStorage()
        objectWillChange.send()
    }

    /// Mark all messages in a group as read (across all members)
    func markAllGroupMessagesAsRead(groupId: UUID, memberMessages: [String: [UUID]]) {
        if groupStates[groupId] == nil {
            groupStates[groupId] = GroupReadState(groupId: groupId)
        }

        for (memberId, messageIds) in memberMessages {
            groupStates[groupId]?.markAllAsRead(memberId: memberId, messageIds: messageIds)
        }

        saveToStorage()
        objectWillChange.send()
    }

    /// Check if a message is read
    func isRead(groupId: UUID, memberId: String, messageId: UUID) -> Bool {
        return groupStates[groupId]?.isRead(memberId: memberId, messageId: messageId) ?? false
    }

    /// Get unread count for a specific member
    func getUnreadCount(groupId: UUID, memberId: String, allMessageIds: [UUID]) -> Int {
        return groupStates[groupId]?.getUnreadCount(memberId: memberId, allMessageIds: allMessageIds) ?? allMessageIds.count
    }

    /// Get total unread count for entire group (across all members)
    func getTotalUnreadCount(groupId: UUID, memberMessages: [String: [SimulatedMessage]]) -> Int {
        var totalUnread = 0
        for (memberId, messages) in memberMessages {
            let messageIds = messages.map { $0.id }
            totalUnread += getUnreadCount(groupId: groupId, memberId: memberId, allMessageIds: messageIds)
        }
        return totalUnread
    }

    /// Reset all read states (useful for testing)
    func resetAll() {
        groupStates.removeAll()
        saveToStorage()
        objectWillChange.send()
    }

    /// Reset read state for specific group
    func resetGroup(groupId: UUID) {
        groupStates.removeValue(forKey: groupId)
        saveToStorage()
        objectWillChange.send()
    }

    // MARK: - Persistence

    private func saveToStorage() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(groupStates)
            userDefaults.set(data, forKey: storageKey)

            #if DEBUG
            print("💾 [MessageReadState] Saved \(groupStates.count) group states")
            #endif
        } catch {
            print("❌ [MessageReadState] Failed to save: \(error)")
        }
    }

    private func loadFromStorage() {
        guard let data = userDefaults.data(forKey: storageKey) else {
            print("📭 [MessageReadState] No saved state found")
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            groupStates = try decoder.decode([UUID: GroupReadState].self, from: data)

            #if DEBUG
            print("📬 [MessageReadState] Loaded \(groupStates.count) group states")
            #endif
        } catch {
            print("❌ [MessageReadState] Failed to load: \(error)")
            groupStates = [:]
        }
    }

    // MARK: - Debugging

    func printState(for groupId: UUID) {
        guard let state = groupStates[groupId] else {
            print("📊 [MessageReadState] No state for group \(groupId)")
            return
        }

        print("📊 [MessageReadState] Group \(groupId):")
        for (memberId, memberState) in state.memberStates {
            print("   - \(memberId): \(memberState.readMessageIds.count) messages read, last read: \(memberState.lastReadTimestamp)")
        }
    }
}
