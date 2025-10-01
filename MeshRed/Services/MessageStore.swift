//
//  MessageStore.swift
//  MeshRed
//
//  Created by Emilio Contreras on 28/09/25.
//  Updated to support conversation-based persistence with family and public threads.
//

import Foundation
import Combine

class MessageStore: ObservableObject {
    // MARK: - Nested Types

    struct ConversationDescriptor: Codable, Identifiable, Equatable {
        var id: String
        var title: String
        var isFamily: Bool
        var participantId: String?
        var defaultRecipientId: String

        static func publicChat() -> ConversationDescriptor {
            ConversationDescriptor(
                id: ConversationIdentifier.public.rawValue,
                title: "Chat General",
                isFamily: false,
                participantId: nil,
                defaultRecipientId: "broadcast"
            )
        }

        static func familyChat(peerId: String, displayName: String?) -> ConversationDescriptor {
            ConversationDescriptor(
                id: ConversationIdentifier.family(peerId: peerId).rawValue,
                title: displayName ?? peerId,
                isFamily: true,
                participantId: peerId,
                defaultRecipientId: peerId
            )
        }
    }

    struct ConversationSummary: Identifiable {
        let id: String
        let title: String
        let isFamily: Bool
        let participantId: String?
        let defaultRecipientId: String
        let lastMessagePreview: String?
        let lastMessageDate: Date?
    }

    private struct StoredPayload: Codable {
        let messages: [String: [Message]]
        let metadata: [String: ConversationDescriptor]
    }

    // MARK: - Published State

    @Published private(set) var messages: [Message] = []
    @Published private(set) var activeConversationId: String
    @Published private(set) var conversationSummaries: [ConversationSummary] = []

    // MARK: - Private Properties

    private var conversations: [String: [Message]] = [:]
    private var metadata: [String: ConversationDescriptor] = [:]

    private let maxMessagesPerConversation = 200
    private let storageKey = "MeshRed.Conversations.v1"
    private let legacyKey = "MeshRedMessages"  // Backward compatibility
    private let activeKey = "MeshRed.ActiveConversation"

    // MARK: - Initialization

    init() {
        let storedActiveConversation = UserDefaults.standard.string(forKey: activeKey)
        self.activeConversationId = storedActiveConversation ?? ConversationIdentifier.public.rawValue

        loadConversations()
        ensurePublicConversationExists()

        if metadata[activeConversationId] == nil {
            activeConversationId = ConversationIdentifier.public.rawValue
        }

        refreshPublishedState()
    }

    // MARK: - Public API

    func addMessage(_ message: Message, context: ConversationDescriptor) {
        var descriptor = context

        if let existing = metadata[descriptor.id] {
            descriptor.title = descriptor.title.isEmpty ? existing.title : descriptor.title
            descriptor.isFamily = existing.isFamily || descriptor.isFamily
            descriptor.participantId = descriptor.participantId ?? existing.participantId
            if descriptor.defaultRecipientId.isEmpty {
                descriptor.defaultRecipientId = existing.defaultRecipientId
            }
        }

        metadata[descriptor.id] = descriptor

        var threadMessages = conversations[descriptor.id] ?? []
        threadMessages.append(message)
        threadMessages.sort { $0.timestamp < $1.timestamp }

        if threadMessages.count > maxMessagesPerConversation {
            let excess = threadMessages.count - maxMessagesPerConversation
            threadMessages.removeFirst(excess)
            print("📱 MessageStore: Trimmed \(excess) messages for conversation \(descriptor.id)")
        }

        conversations[descriptor.id] = threadMessages

        saveConversations()
        refreshPublishedState()

        print("📱 MessageStore: Added message to conversation \(descriptor.id) - Title: \(descriptor.title)")
    }

    func selectConversation(_ conversationId: String) {
        guard conversationId != activeConversationId else { return }

        activeConversationId = conversationId
        UserDefaults.standard.set(conversationId, forKey: activeKey)
        refreshPublishedState()

        print("💬 MessageStore: Active conversation switched to \(conversationId)")
    }

    func ensureConversation(_ descriptor: ConversationDescriptor) {
        if metadata[descriptor.id] == nil {
            metadata[descriptor.id] = descriptor
        } else {
            // Preserve stored descriptor but update title if new one provides more context
            var stored = metadata[descriptor.id]!
            if descriptor.isFamily {
                stored.isFamily = true
            }
            if let participant = descriptor.participantId {
                stored.participantId = participant
            }
            if !descriptor.title.isEmpty {
                stored.title = descriptor.title
            }
            stored.defaultRecipientId = descriptor.defaultRecipientId
            metadata[descriptor.id] = stored
        }

        if conversations[descriptor.id] == nil {
            conversations[descriptor.id] = []
        }

        saveConversations()
        refreshPublishedState()
    }

    func descriptor(for conversationId: String) -> ConversationDescriptor? {
        return metadata[conversationId]
    }

    func clearAllMessages() {
        conversations.removeAll()
        metadata.removeAll()
        ensurePublicConversationExists()
        saveConversations()
        refreshPublishedState()
        print("📱 MessageStore: Cleared all conversations")
    }

    func messages(for conversationId: String) -> [Message] {
        return conversations[conversationId] ?? []
    }

    var sortedMessages: [Message] {
        return messages
    }

    var messageCount: Int {
        return messages.count
    }

    var latestMessage: Message? {
        return messages.last
    }

    // MARK: - Persistence

    private func loadConversations() {
        if let data = UserDefaults.standard.data(forKey: storageKey) {
            do {
                let payload = try JSONDecoder().decode(StoredPayload.self, from: data)
                conversations = payload.messages
                metadata = payload.metadata
                print("📱 MessageStore: Loaded \(payload.messages.count) conversations from storage")
                return
            } catch {
                print("❌ MessageStore: Failed to load conversations: \(error.localizedDescription)")
            }
        }

        // Fallback to legacy single-thread storage
        if let legacyData = UserDefaults.standard.data(forKey: legacyKey),
           let legacyMessages = try? JSONDecoder().decode([Message].self, from: legacyData) {
            conversations[ConversationIdentifier.public.rawValue] = legacyMessages.sorted { $0.timestamp < $1.timestamp }
            metadata[ConversationIdentifier.public.rawValue] = .publicChat()
            UserDefaults.standard.removeObject(forKey: legacyKey)
            print("📱 MessageStore: Migrated \(legacyMessages.count) legacy messages to public conversation")
        }
    }

    private func saveConversations() {
        do {
            let payload = StoredPayload(messages: conversations, metadata: metadata)
            let data = try JSONEncoder().encode(payload)
            UserDefaults.standard.set(data, forKey: storageKey)
            UserDefaults.standard.set(activeConversationId, forKey: activeKey)
            print("📱 MessageStore: Saved \(conversations.count) conversations to storage")
        } catch {
            print("❌ MessageStore: Failed to save conversations: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func ensurePublicConversationExists() {
        if metadata[ConversationIdentifier.public.rawValue] == nil {
            metadata[ConversationIdentifier.public.rawValue] = .publicChat()
        }

        if conversations[ConversationIdentifier.public.rawValue] == nil {
            conversations[ConversationIdentifier.public.rawValue] = []
        }
    }

    private func refreshPublishedState() {
        messages = conversations[activeConversationId] ?? []
        conversationSummaries = buildConversationSummaries()
    }

    private func buildConversationSummaries() -> [ConversationSummary] {
        var summaries: [ConversationSummary] = []

        for (conversationId, descriptor) in metadata {
            let threadMessages = conversations[conversationId] ?? []
            let lastMessage = threadMessages.last

            summaries.append(
                ConversationSummary(
                    id: descriptor.id,
                    title: descriptor.title,
                    isFamily: descriptor.isFamily,
                    participantId: descriptor.participantId,
                    defaultRecipientId: descriptor.defaultRecipientId,
                    lastMessagePreview: lastMessage?.content,
                    lastMessageDate: lastMessage?.timestamp
                )
            )
        }

        // Always ensure public conversation is first
        summaries.sort { summaryA, summaryB in
            if summaryA.id == ConversationIdentifier.public.rawValue {
                return true
            }

            if summaryB.id == ConversationIdentifier.public.rawValue {
                return false
            }

            let dateA = summaryA.lastMessageDate ?? .distantPast
            let dateB = summaryB.lastMessageDate ?? .distantPast
            return dateA > dateB
        }

        return summaries
    }
}

