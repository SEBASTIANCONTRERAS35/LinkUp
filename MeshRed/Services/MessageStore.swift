//
//  MessageStore.swift
//  MeshRed
//
//  Created by Emilio Contreras on 28/09/25.
//  Updated to support conversation-based persistence with family and public threads.
//

import Foundation
import Combine
import os

class MessageStore: ObservableObject {
    // MARK: - Shared Instance
    static let shared = MessageStore()

    // MARK: - Nested Types

    struct ConversationDescriptor: Codable, Identifiable, Equatable {
        var id: String
        var title: String
        var isFamily: Bool
        var isDirect: Bool  // New: indicates direct (non-family) conversation
        var participantId: String?
        var defaultRecipientId: String

        static func publicChat() -> ConversationDescriptor {
            ConversationDescriptor(
                id: ConversationIdentifier.public.rawValue,
                title: "Chat General",
                isFamily: false,
                isDirect: false,
                participantId: nil,
                defaultRecipientId: "broadcast"
            )
        }

        static func familyChat(peerId: String, displayName: String?) -> ConversationDescriptor {
            ConversationDescriptor(
                id: ConversationIdentifier.family(peerId: peerId).rawValue,
                title: displayName ?? peerId,
                isFamily: true,
                isDirect: false,
                participantId: peerId,
                defaultRecipientId: peerId
            )
        }

        static func directChat(peerId: String, displayName: String?) -> ConversationDescriptor {
            ConversationDescriptor(
                id: ConversationIdentifier.direct(peerId: peerId).rawValue,
                title: displayName ?? peerId,
                isFamily: false,
                isDirect: true,
                participantId: peerId,
                defaultRecipientId: peerId
            )
        }

        /// Computed property: true for any private conversation (family or direct)
        var isPrivate: Bool {
            return isFamily || isDirect
        }

        /// Display type for UI
        var conversationType: String {
            if isFamily { return "Familia" }
            if isDirect { return "Directo" }
            return "Público"
        }
    }

    struct ConversationSummary: Identifiable, Equatable {
        let id: String
        let title: String
        let isFamily: Bool
        let isDirect: Bool  // New: indicates direct (non-family) conversation
        let participantId: String?
        let defaultRecipientId: String
        let lastMessagePreview: String?
        let lastMessageDate: Date?

        /// Computed property: true for any private conversation (family or direct)
        var isPrivate: Bool {
            return isFamily || isDirect
        }

        /// Display type for UI
        var conversationType: String {
            if isFamily { return "Familia" }
            if isDirect { return "Directo" }
            return "Público"
        }

        // Equatable helps SwiftUI detect changes in ForEach
        static func == (lhs: ConversationSummary, rhs: ConversationSummary) -> Bool {
            lhs.id == rhs.id &&
            lhs.title == rhs.title &&
            lhs.isFamily == rhs.isFamily &&
            lhs.isDirect == rhs.isDirect &&
            lhs.participantId == rhs.participantId &&
            lhs.defaultRecipientId == rhs.defaultRecipientId &&
            lhs.lastMessagePreview == rhs.lastMessagePreview &&
            lhs.lastMessageDate == rhs.lastMessageDate
        }
    }

    private struct StoredPayload: Codable {
        let messages: [String: [Message]]
        let metadata: [String: ConversationDescriptor]
    }

    // MARK: - Published State

    @Published private(set) var messages: [Message] = [] {
        didSet {
            LoggingService.network.info("🔔 MessageStore.messages CHANGED")
            LoggingService.network.info("   Old count: \(oldValue.count)")
            LoggingService.network.info("   New count: \(self.messages.count)")
            LoggingService.network.info("   For conversation: \(self.activeConversationId)")
        }
    }

    @Published private(set) var activeConversationId: String {
        didSet {
            LoggingService.network.info("🔔 MessageStore.activeConversationId CHANGED")
            LoggingService.network.info("   Old: \(oldValue)")
            LoggingService.network.info("   New: \(self.activeConversationId)")
        }
    }

    @Published private(set) var conversationSummaries: [ConversationSummary] = [] {
        didSet {
            LoggingService.network.info("🔔 MessageStore.conversationSummaries CHANGED")
            LoggingService.network.info("   Old count: \(oldValue.count)")
            LoggingService.network.info("   New count: \(self.conversationSummaries.count)")
            conversationSummaries.forEach { summary in
                LoggingService.network.info("   • \(summary.title) (\(summary.id))")
            }
        }
    }

    @Published private(set) var unreadCount: Int = 0

    // MARK: - Private Properties

    private var conversations: [String: [Message]] = [:]
    private var metadata: [String: ConversationDescriptor] = [:]
    private var readMessageIds: Set<UUID> = []
    private var lastReadTimestamps: [String: Date] = [:]

    private let maxMessagesPerConversation = 200
    private let storageKey = "MeshRed.Conversations.v1"
    private let legacyKey = "MeshRedMessages"  // Backward compatibility
    private let activeKey = "MeshRed.ActiveConversation"
    private let readMessagesKey = "MeshRed.ReadMessageIds"
    private let lastReadKey = "MeshRed.LastReadTimestamps"

    // MARK: - Initialization

    init() {
        let storedActiveConversation = UserDefaults.standard.string(forKey: activeKey)
        self.activeConversationId = storedActiveConversation ?? ConversationIdentifier.public.rawValue

        loadConversations()
        loadReadState()
        ensurePublicConversationExists()

        if metadata[activeConversationId] == nil {
            activeConversationId = ConversationIdentifier.public.rawValue
        }

        refreshPublishedState()
        calculateUnreadCount()
    }

    // MARK: - Public API

    func addMessage(_ message: Message, context: ConversationDescriptor, autoSwitch: Bool = false, localDeviceName: String? = nil) {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("📨 MessageStore.addMessage() CALLED")
        LoggingService.network.info("   Thread: \(Thread.isMainThread ? "MAIN" : "BACKGROUND")")
        LoggingService.network.info("   Message ID: \(message.id)")
        LoggingService.network.info("   Sender: \(message.sender)")
        LoggingService.network.info("   Content: \"\(message.content)\"")
        LoggingService.network.info("   Conversation: \(context.id)")
        LoggingService.network.info("   AutoSwitch: \(autoSwitch)")
        LoggingService.network.info("   Current Active Conv: \(self.activeConversationId)")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Trigger haptic feedback for incoming messages (not for our own messages)
        // Use the localDeviceName parameter if provided, otherwise get device name
        let currentDeviceName = localDeviceName ?? ProcessInfo.processInfo.hostName
        if !message.isFromLocalDevice(deviceName: currentDeviceName) {
            // Coordinated haptic feedback + Live Activity update
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            LoggingService.network.info("📱 NEW MESSAGE NOTIFICATION")
            LoggingService.network.info("   From: \(message.sender)")
            LoggingService.network.info("   Preview: \(String(message.content.prefix(50)))")
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            // Strong haptic pattern for incoming messages
            HapticManager.shared.play(.heavy, priority: .notification)

            // Second haptic after short delay for emphasis
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                HapticManager.shared.play(.success, priority: .notification)
            }

            LoggingService.network.info("📳 Strong vibration triggered")
            LoggingService.network.info("🏝️ Live Activity will update automatically via observer")
        }

        var descriptor = context

        if let existing = metadata[descriptor.id] {
            descriptor.title = descriptor.title.isEmpty ? existing.title : descriptor.title
            descriptor.isFamily = existing.isFamily || descriptor.isFamily
            descriptor.isDirect = existing.isDirect || descriptor.isDirect
            descriptor.participantId = descriptor.participantId ?? existing.participantId
            if descriptor.defaultRecipientId.isEmpty {
                descriptor.defaultRecipientId = existing.defaultRecipientId
            }
        }

        metadata[descriptor.id] = descriptor

        var threadMessages = conversations[descriptor.id] ?? []
        let previousCount = threadMessages.count
        threadMessages.append(message)
        threadMessages.sort { $0.timestamp < $1.timestamp }

        if threadMessages.count > maxMessagesPerConversation {
            let excess = threadMessages.count - maxMessagesPerConversation
            threadMessages.removeFirst(excess)
            LoggingService.network.info("📱 MessageStore: Trimmed \(excess) messages for conversation \(descriptor.id)")
        }

        conversations[descriptor.id] = threadMessages

        // CRITICAL: Auto-mark own messages as read immediately
        if let localName = localDeviceName, message.sender == localName {
            readMessageIds.insert(message.id)
            saveReadState()
            LoggingService.network.info("   ✅ Auto-marked own message as read (sender: \(message.sender))")
        }

        LoggingService.network.info("   ✅ Message added to internal storage")
        LoggingService.network.info("   Previous count: \(previousCount), New count: \(threadMessages.count)")

        // CRITICAL FIX: Auto-switch to conversation when incoming message arrives
        // Only if autoSwitch is enabled and it's a different conversation
        let isNewConversation = descriptor.id != activeConversationId

        if autoSwitch && isNewConversation {
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            LoggingService.network.info("🔄 AUTO-SWITCHING TO NEW CONVERSATION")
            LoggingService.network.info("   From: \(self.activeConversationId)")
            LoggingService.network.info("   To: \(descriptor.id)")
            LoggingService.network.info("   Reason: Incoming message from \(message.sender)")
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            activeConversationId = descriptor.id
            UserDefaults.standard.set(activeConversationId, forKey: activeKey)
        }

        LoggingService.network.info("   🔄 Calling saveConversations()...")
        saveConversations()
        LoggingService.network.info("   🔄 Calling refreshPublishedState()...")
        refreshPublishedState()
        LoggingService.network.info("   🔄 Calling calculateUnreadCount()...")
        calculateUnreadCount()

        // CRITICAL FIX: Force additional refresh when it's the first message
        // This ensures UI updates correctly for new conversations
        if previousCount == 0 && threadMessages.count == 1 {
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            LoggingService.network.info("🆕 FIRST MESSAGE IN CONVERSATION DETECTED")
            LoggingService.network.info("   Forcing additional UI refresh with delay...")
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                LoggingService.network.info("   🔄 Executing forced refresh for first message...")
                self.refreshPublishedState()

                // Double-check the conversation is selected
                if self.activeConversationId != descriptor.id {
                    LoggingService.network.info("   ⚠️ Conversation mismatch detected - selecting correct conversation")
                    self.selectConversation(descriptor.id)
                }
            }
        }

        LoggingService.network.info("✅ MessageStore.addMessage() COMPLETE")
        LoggingService.network.info("   Conversation: \(descriptor.title)")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    func selectConversation(_ conversationId: String) {
        guard conversationId != activeConversationId else {
            LoggingService.network.info("⚠️ MessageStore.selectConversation: Already on \(conversationId), skipping")
            return
        }

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🔄 SWITCHING CONVERSATION")
        LoggingService.network.info("   From: \(self.activeConversationId)")
        LoggingService.network.info("   To: \(conversationId)")
        LoggingService.network.info("   Previous message count: \(self.conversations[self.activeConversationId]?.count ?? 0)")
        LoggingService.network.info("   New message count: \(self.conversations[conversationId]?.count ?? 0)")

        // Mark all messages in current conversation as read before switching
        markConversationAsRead(conversationId: activeConversationId)

        activeConversationId = conversationId
        UserDefaults.standard.set(conversationId, forKey: activeKey)

        // Mark new conversation as read too
        markConversationAsRead(conversationId: conversationId)

        refreshPublishedState()

        LoggingService.network.info("   ✅ Conversation switched")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
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
            if descriptor.isDirect {
                stored.isDirect = true
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

    func hasConversation(withId conversationId: String) -> Bool {
        return metadata[conversationId] != nil && !(conversations[conversationId] ?? []).isEmpty
    }

    func deleteConversation(_ conversationId: String) {
        // Don't allow deleting the public conversation
        guard conversationId != ConversationIdentifier.public.rawValue else {
            LoggingService.network.info("⚠️ MessageStore: Cannot delete public conversation")
            return
        }

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🗑️ DELETING CONVERSATION")
        LoggingService.network.info("   Conversation ID: \(conversationId)")
        LoggingService.network.info("   Message count: \(self.conversations[conversationId]?.count ?? 0)")
        LoggingService.network.info("   Was active: \(self.activeConversationId == conversationId)")

        // Remove conversation messages and metadata
        conversations.removeValue(forKey: conversationId)
        metadata.removeValue(forKey: conversationId)

        // If the deleted conversation was active, switch to public chat
        if activeConversationId == conversationId {
            LoggingService.network.info("   → Switching to public chat")
            activeConversationId = ConversationIdentifier.public.rawValue
            UserDefaults.standard.set(activeConversationId, forKey: activeKey)
        }

        saveConversations()
        refreshPublishedState()
        calculateUnreadCount()

        LoggingService.network.info("   ✅ Conversation deleted")
        LoggingService.network.info("   Remaining conversations: \(self.metadata.count)")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    func clearAllMessages() {
        conversations.removeAll()
        metadata.removeAll()
        ensurePublicConversationExists()
        saveConversations()
        refreshPublishedState()
        LoggingService.network.info("📱 MessageStore: Cleared all conversations")
    }

    func messages(for conversationId: String) -> [Message] {
        return conversations[conversationId] ?? []
    }

    // Alias para compatibilidad con el nuevo código
    func getMessages(for conversationId: String) -> [Message] {
        return messages(for: conversationId)
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

    // MARK: - Last Message Helpers (for chat list preview)

    /// Get the last message for a specific peer (checks both direct and family conversations)
    func getLastMessage(forPeerID peerID: String) -> Message? {
        // Try direct conversation first
        let directConvId = ConversationIdentifier.direct(peerId: peerID).rawValue
        if let directMessages = conversations[directConvId], let last = directMessages.last {
            return last
        }

        // Try family conversation
        let familyConvId = ConversationIdentifier.family(peerId: peerID).rawValue
        if let familyMessages = conversations[familyConvId], let last = familyMessages.last {
            return last
        }

        return nil
    }

    /// Format last message preview with "Tú:" prefix if from local device (WhatsApp-style)
    func formatLastMessagePreview(message: Message?, localDeviceName: String) -> String {
        guard let message = message else {
            return "Sin mensajes"
        }

        if message.sender == localDeviceName {
            return "Tú: \(message.content)"
        } else {
            return message.content
        }
    }

    /// Get unread count for a specific peer (checks both direct and family conversations)
    func getUnreadCount(forPeerID peerID: String) -> Int {
        // Try direct conversation first
        let directConvId = ConversationIdentifier.direct(peerId: peerID).rawValue
        let directUnread = getUnreadCount(for: directConvId)

        // Try family conversation
        let familyConvId = ConversationIdentifier.family(peerId: peerID).rawValue
        let familyUnread = getUnreadCount(for: familyConvId)

        // Return the sum (only one should have messages, but sum handles edge cases)
        return directUnread + familyUnread
    }

    // MARK: - Persistence

    private func loadConversations() {
        if let data = UserDefaults.standard.data(forKey: storageKey) {
            do {
                let payload = try JSONDecoder().decode(StoredPayload.self, from: data)
                conversations = payload.messages
                metadata = payload.metadata

                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                LoggingService.network.info("💾 LOADED CONVERSATIONS FROM STORAGE")
                LoggingService.network.info("   Total conversations: \(payload.messages.count)")
                LoggingService.network.info("   Total metadata entries: \(payload.metadata.count)")
                for (id, descriptor) in payload.metadata {
                    let msgCount = payload.messages[id]?.count ?? 0
                    LoggingService.network.info("   • \(descriptor.title): \(msgCount) messages")
                }
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                return
            } catch {
                LoggingService.network.info("❌ MessageStore: Failed to load conversations: \(error.localizedDescription)")
            }
        }

        // Fallback to legacy single-thread storage
        if let legacyData = UserDefaults.standard.data(forKey: legacyKey),
           let legacyMessages = try? JSONDecoder().decode([Message].self, from: legacyData) {
            conversations[ConversationIdentifier.public.rawValue] = legacyMessages.sorted { $0.timestamp < $1.timestamp }
            metadata[ConversationIdentifier.public.rawValue] = .publicChat()
            UserDefaults.standard.removeObject(forKey: legacyKey)
            LoggingService.network.info("📱 MessageStore: Migrated \(legacyMessages.count) legacy messages to public conversation")
        }
    }

    private func saveConversations() {
        do {
            let payload = StoredPayload(messages: conversations, metadata: metadata)
            let data = try JSONEncoder().encode(payload)
            UserDefaults.standard.set(data, forKey: storageKey)
            UserDefaults.standard.set(activeConversationId, forKey: activeKey)

            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            LoggingService.network.info("💾 SAVING CONVERSATIONS TO STORAGE")
            LoggingService.network.info("   Total conversations: \(self.conversations.count)")
            LoggingService.network.info("   Total metadata entries: \(self.metadata.count)")
            for (id, descriptor) in metadata {
                let msgCount = conversations[id]?.count ?? 0
                LoggingService.network.info("   • \(descriptor.title): \(msgCount) messages")
            }
            LoggingService.network.info("   Active conversation: \(self.activeConversationId)")
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        } catch {
            LoggingService.network.info("❌ MessageStore: Failed to save conversations: \(error.localizedDescription)")
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

    func refreshPublishedState() {
        // Capture current state before dispatching to main thread
        let currentActiveId = activeConversationId
        let currentMessages = conversations[activeConversationId] ?? []
        let currentSummaries = buildConversationSummaries()

        LoggingService.network.info("🔄 MessageStore.refreshPublishedState() - Preparing UI update")
        LoggingService.network.info("   Active conversation: \(currentActiveId)")
        LoggingService.network.info("   Messages to publish: \(currentMessages.count)")
        LoggingService.network.info("   Summaries to publish: \(currentSummaries.count)")

        // CRITICAL: Always update @Published properties on main thread to ensure SwiftUI updates
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            LoggingService.network.info("   🎯 ON MAIN THREAD - About to update @Published properties")
            LoggingService.network.info("      Current messages.count: \(self.messages.count)")
            LoggingService.network.info("      New messages.count: \(currentMessages.count)")
            LoggingService.network.info("      Current summaries.count: \(self.conversationSummaries.count)")
            LoggingService.network.info("      New summaries.count: \(currentSummaries.count)")

            // FORCE SwiftUI to re-render by sending objectWillChange notification
            // This is critical for immediate UI updates when messages arrive via MultipeerConnectivity
            LoggingService.network.info("   📢 Sending objectWillChange.send()...")
            self.objectWillChange.send()

            LoggingService.network.info("   🔄 Updating @Published var messages...")
            self.messages = currentMessages

            LoggingService.network.info("   🔄 Updating @Published var conversationSummaries...")
            self.conversationSummaries = currentSummaries

            LoggingService.network.info("   ✅ Published state updated on main thread")
            LoggingService.network.info("      - messages.count: \(self.messages.count)")
            LoggingService.network.info("      - conversationSummaries.count: \(self.conversationSummaries.count)")
            LoggingService.network.info("   🎬 SwiftUI should re-render NOW!")
        }
    }

    private func buildConversationSummaries() -> [ConversationSummary] {
        var summaries: [ConversationSummary] = []

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("📊 BUILDING CONVERSATION SUMMARIES")
        LoggingService.network.info("   Metadata count: \(self.metadata.count)")
        LoggingService.network.info("   Conversations count: \(self.conversations.count)")

        for (conversationId, descriptor) in metadata {
            let threadMessages = conversations[conversationId] ?? []
            let lastMessage = threadMessages.last

            LoggingService.network.info("   • \(descriptor.title) (\(conversationId))")
            LoggingService.network.info("     Messages: \(threadMessages.count)")
            LoggingService.network.info("     Type: \(descriptor.conversationType)")
            LoggingService.network.info("     IsFamily: \(descriptor.isFamily)")
            LoggingService.network.info("     IsDirect: \(descriptor.isDirect)")
            LoggingService.network.info("     ParticipantID: \(descriptor.participantId ?? "nil")")

            summaries.append(
                ConversationSummary(
                    id: descriptor.id,
                    title: descriptor.title,
                    isFamily: descriptor.isFamily,
                    isDirect: descriptor.isDirect,
                    participantId: descriptor.participantId,
                    defaultRecipientId: descriptor.defaultRecipientId,
                    lastMessagePreview: lastMessage?.content,
                    lastMessageDate: lastMessage?.timestamp
                )
            )
        }

        LoggingService.network.info("   Total summaries created: \(summaries.count)")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

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

    // MARK: - Read State Management

    /// Mark a single message as read
    func markAsRead(messageId: UUID) {
        readMessageIds.insert(messageId)
        saveReadState()
        calculateUnreadCount()
    }

    /// Mark all messages in a conversation as read
    func markConversationAsRead(conversationId: String) {
        guard let messages = conversations[conversationId] else { return }

        for message in messages {
            readMessageIds.insert(message.id)
        }

        lastReadTimestamps[conversationId] = Date()
        saveReadState()
        calculateUnreadCount()

        LoggingService.network.info("📬 MessageStore: Marked all messages as read in conversation \(conversationId)")
    }

    /// Check if a message is read
    func isMessageRead(_ messageId: UUID) -> Bool {
        return readMessageIds.contains(messageId)
    }

    /// Get unread count for specific conversation
    func getUnreadCount(for conversationId: String) -> Int {
        guard let messages = conversations[conversationId] else { return 0 }
        return messages.filter { !readMessageIds.contains($0.id) }.count
    }

    /// Calculate total unread messages across all conversations
    private func calculateUnreadCount() {
        var total = 0
        for (_, messages) in conversations {
            // Count ALL unread messages, including active conversation
            // This ensures Dynamic Island always shows accurate count
            total += messages.filter { !readMessageIds.contains($0.id) }.count
        }
        unreadCount = total
        LoggingService.network.info("📊 MessageStore: Unread count updated to \(total)")
        LoggingService.network.info("   Read messages: \(self.readMessageIds.count)")
        LoggingService.network.info("   Total messages: \(self.conversations.values.flatMap { $0 }.count)")
    }

    // MARK: - Read State Persistence

    private func loadReadState() {
        // Load read message IDs
        if let data = UserDefaults.standard.data(forKey: readMessagesKey),
           let uuidStrings = try? JSONDecoder().decode([String].self, from: data) {
            readMessageIds = Set(uuidStrings.compactMap { UUID(uuidString: $0) })
            LoggingService.network.info("📬 MessageStore: Loaded \(self.readMessageIds.count) read message IDs")
        }

        // Load last read timestamps
        if let data = UserDefaults.standard.data(forKey: lastReadKey),
           let timestamps = try? JSONDecoder().decode([String: Date].self, from: data) {
            lastReadTimestamps = timestamps
            LoggingService.network.info("📬 MessageStore: Loaded \(timestamps.count) last read timestamps")
        }
    }

    private func saveReadState() {
        // Save read message IDs
        let uuidStrings = readMessageIds.map { $0.uuidString }
        if let data = try? JSONEncoder().encode(uuidStrings) {
            UserDefaults.standard.set(data, forKey: readMessagesKey)
        }

        // Save last read timestamps
        if let data = try? JSONEncoder().encode(lastReadTimestamps) {
            UserDefaults.standard.set(data, forKey: lastReadKey)
        }
    }

    // MARK: - First Message Tracking Support

    /// Check if a conversation has received any replies from a specific peer
    /// - Parameters:
    ///   - peerID: The peer's identifier to check
    ///   - localDeviceName: The local device name to distinguish sent vs received messages
    /// - Returns: True if the peer has sent at least one message
    func hasReceivedReply(from peerID: String, localDeviceName: String) -> Bool {
        // Check both direct and family conversations
        let conversationIds = [
            ConversationIdentifier.direct(peerId: peerID).rawValue,
            ConversationIdentifier.family(peerId: peerID).rawValue
        ]

        for conversationId in conversationIds {
            if let messages = conversations[conversationId] {
                // Check if there's at least one message from the peer (not from us)
                let hasReply = messages.contains { (message: Message) in
                    // Message is from the peer (not from us)
                    return message.sender == peerID && !message.isFromLocalDevice(deviceName: localDeviceName)
                }

                if hasReply {
                    LoggingService.network.info("✅ MessageStore: Found reply from \(peerID) in conversation \(conversationId)")
                    return true
                }
            }
        }

        LoggingService.network.info("❌ MessageStore: No replies found from \(peerID)")
        return false
    }

    /// Get the first message sent to a peer
    /// - Parameters:
    ///   - peerID: The peer's identifier
    ///   - localDeviceName: The local device name to identify sent messages
    /// - Returns: The first message sent to this peer, if any
    func getFirstMessageSent(to peerID: String, localDeviceName: String) -> Message? {
        // Check both direct and family conversations
        let conversationIds = [
            ConversationIdentifier.direct(peerId: peerID).rawValue,
            ConversationIdentifier.family(peerId: peerID).rawValue
        ]

        var firstMessage: Message? = nil

        for conversationId in conversationIds {
            if let messages = conversations[conversationId] {
                // Find the first message sent by us to this peer
                let ourMessages = messages.filter { $0.isFromLocalDevice(deviceName: localDeviceName) }
                if let earliest = ourMessages.min(by: { $0.timestamp < $1.timestamp }) {
                    if firstMessage == nil || earliest.timestamp < firstMessage!.timestamp {
                        firstMessage = earliest
                    }
                }
            }
        }

        return firstMessage
    }
}

