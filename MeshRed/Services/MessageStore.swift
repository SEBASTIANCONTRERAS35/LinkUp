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
            print("🔔 MessageStore.messages CHANGED")
            print("   Old count: \(oldValue.count)")
            print("   New count: \(messages.count)")
            print("   For conversation: \(activeConversationId)")
        }
    }

    @Published private(set) var activeConversationId: String {
        didSet {
            print("🔔 MessageStore.activeConversationId CHANGED")
            print("   Old: \(oldValue)")
            print("   New: \(activeConversationId)")
        }
    }

    @Published private(set) var conversationSummaries: [ConversationSummary] = [] {
        didSet {
            print("🔔 MessageStore.conversationSummaries CHANGED")
            print("   Old count: \(oldValue.count)")
            print("   New count: \(conversationSummaries.count)")
            conversationSummaries.forEach { summary in
                print("   • \(summary.title) (\(summary.id))")
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
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📨 MessageStore.addMessage() CALLED")
        print("   Thread: \(Thread.isMainThread ? "MAIN" : "BACKGROUND")")
        print("   Message ID: \(message.id)")
        print("   Sender: \(message.sender)")
        print("   Content: \"\(message.content)\"")
        print("   Conversation: \(context.id)")
        print("   AutoSwitch: \(autoSwitch)")
        print("   Current Active Conv: \(activeConversationId)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Trigger haptic feedback for incoming messages (not for our own messages)
        // Use the localDeviceName parameter if provided, otherwise get device name
        let currentDeviceName = localDeviceName ?? ProcessInfo.processInfo.hostName
        if !message.isFromLocalDevice(deviceName: currentDeviceName) {
            // Coordinated haptic feedback + Live Activity update
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("📱 NEW MESSAGE NOTIFICATION")
            print("   From: \(message.sender)")
            print("   Preview: \(String(message.content.prefix(50)))")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            // Strong haptic pattern for incoming messages
            HapticManager.shared.play(.heavy, priority: .notification)

            // Second haptic after short delay for emphasis
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                HapticManager.shared.play(.success, priority: .notification)
            }

            print("📳 Strong vibration triggered")
            print("🏝️ Live Activity will update automatically via observer")
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
            print("📱 MessageStore: Trimmed \(excess) messages for conversation \(descriptor.id)")
        }

        conversations[descriptor.id] = threadMessages

        // CRITICAL: Auto-mark own messages as read immediately
        if let localName = localDeviceName, message.sender == localName {
            readMessageIds.insert(message.id)
            saveReadState()
            print("   ✅ Auto-marked own message as read (sender: \(message.sender))")
        }

        print("   ✅ Message added to internal storage")
        print("   Previous count: \(previousCount), New count: \(threadMessages.count)")

        // CRITICAL FIX: Auto-switch to conversation when incoming message arrives
        // Only if autoSwitch is enabled and it's a different conversation
        let isNewConversation = descriptor.id != activeConversationId

        if autoSwitch && isNewConversation {
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("🔄 AUTO-SWITCHING TO NEW CONVERSATION")
            print("   From: \(activeConversationId)")
            print("   To: \(descriptor.id)")
            print("   Reason: Incoming message from \(message.sender)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            activeConversationId = descriptor.id
            UserDefaults.standard.set(activeConversationId, forKey: activeKey)
        }

        print("   🔄 Calling saveConversations()...")
        saveConversations()
        print("   🔄 Calling refreshPublishedState()...")
        refreshPublishedState()
        print("   🔄 Calling calculateUnreadCount()...")
        calculateUnreadCount()

        // CRITICAL FIX: Force additional refresh when it's the first message
        // This ensures UI updates correctly for new conversations
        if previousCount == 0 && threadMessages.count == 1 {
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("🆕 FIRST MESSAGE IN CONVERSATION DETECTED")
            print("   Forcing additional UI refresh with delay...")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                print("   🔄 Executing forced refresh for first message...")
                self.refreshPublishedState()

                // Double-check the conversation is selected
                if self.activeConversationId != descriptor.id {
                    print("   ⚠️ Conversation mismatch detected - selecting correct conversation")
                    self.selectConversation(descriptor.id)
                }
            }
        }

        print("✅ MessageStore.addMessage() COMPLETE")
        print("   Conversation: \(descriptor.title)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    func selectConversation(_ conversationId: String) {
        guard conversationId != activeConversationId else {
            print("⚠️ MessageStore.selectConversation: Already on \(conversationId), skipping")
            return
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔄 SWITCHING CONVERSATION")
        print("   From: \(activeConversationId)")
        print("   To: \(conversationId)")
        print("   Previous message count: \(conversations[activeConversationId]?.count ?? 0)")
        print("   New message count: \(conversations[conversationId]?.count ?? 0)")

        // Mark all messages in current conversation as read before switching
        markConversationAsRead(conversationId: activeConversationId)

        activeConversationId = conversationId
        UserDefaults.standard.set(conversationId, forKey: activeKey)

        // Mark new conversation as read too
        markConversationAsRead(conversationId: conversationId)

        refreshPublishedState()

        print("   ✅ Conversation switched")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
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
            print("⚠️ MessageStore: Cannot delete public conversation")
            return
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🗑️ DELETING CONVERSATION")
        print("   Conversation ID: \(conversationId)")
        print("   Message count: \(conversations[conversationId]?.count ?? 0)")
        print("   Was active: \(activeConversationId == conversationId)")

        // Remove conversation messages and metadata
        conversations.removeValue(forKey: conversationId)
        metadata.removeValue(forKey: conversationId)

        // If the deleted conversation was active, switch to public chat
        if activeConversationId == conversationId {
            print("   → Switching to public chat")
            activeConversationId = ConversationIdentifier.public.rawValue
            UserDefaults.standard.set(activeConversationId, forKey: activeKey)
        }

        saveConversations()
        refreshPublishedState()
        calculateUnreadCount()

        print("   ✅ Conversation deleted")
        print("   Remaining conversations: \(metadata.count)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
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

                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("💾 LOADED CONVERSATIONS FROM STORAGE")
                print("   Total conversations: \(payload.messages.count)")
                print("   Total metadata entries: \(payload.metadata.count)")
                for (id, descriptor) in payload.metadata {
                    let msgCount = payload.messages[id]?.count ?? 0
                    print("   • \(descriptor.title): \(msgCount) messages")
                }
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
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

            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("💾 SAVING CONVERSATIONS TO STORAGE")
            print("   Total conversations: \(conversations.count)")
            print("   Total metadata entries: \(metadata.count)")
            for (id, descriptor) in metadata {
                let msgCount = conversations[id]?.count ?? 0
                print("   • \(descriptor.title): \(msgCount) messages")
            }
            print("   Active conversation: \(activeConversationId)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
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

    func refreshPublishedState() {
        // Capture current state before dispatching to main thread
        let currentActiveId = activeConversationId
        let currentMessages = conversations[activeConversationId] ?? []
        let currentSummaries = buildConversationSummaries()

        print("🔄 MessageStore.refreshPublishedState() - Preparing UI update")
        print("   Active conversation: \(currentActiveId)")
        print("   Messages to publish: \(currentMessages.count)")
        print("   Summaries to publish: \(currentSummaries.count)")

        // CRITICAL: Always update @Published properties on main thread to ensure SwiftUI updates
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            print("   🎯 ON MAIN THREAD - About to update @Published properties")
            print("      Current messages.count: \(self.messages.count)")
            print("      New messages.count: \(currentMessages.count)")
            print("      Current summaries.count: \(self.conversationSummaries.count)")
            print("      New summaries.count: \(currentSummaries.count)")

            // FORCE SwiftUI to re-render by sending objectWillChange notification
            // This is critical for immediate UI updates when messages arrive via MultipeerConnectivity
            print("   📢 Sending objectWillChange.send()...")
            self.objectWillChange.send()

            print("   🔄 Updating @Published var messages...")
            self.messages = currentMessages

            print("   🔄 Updating @Published var conversationSummaries...")
            self.conversationSummaries = currentSummaries

            print("   ✅ Published state updated on main thread")
            print("      - messages.count: \(self.messages.count)")
            print("      - conversationSummaries.count: \(self.conversationSummaries.count)")
            print("   🎬 SwiftUI should re-render NOW!")
        }
    }

    private func buildConversationSummaries() -> [ConversationSummary] {
        var summaries: [ConversationSummary] = []

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📊 BUILDING CONVERSATION SUMMARIES")
        print("   Metadata count: \(metadata.count)")
        print("   Conversations count: \(conversations.count)")

        for (conversationId, descriptor) in metadata {
            let threadMessages = conversations[conversationId] ?? []
            let lastMessage = threadMessages.last

            print("   • \(descriptor.title) (\(conversationId))")
            print("     Messages: \(threadMessages.count)")
            print("     Type: \(descriptor.conversationType)")
            print("     IsFamily: \(descriptor.isFamily)")
            print("     IsDirect: \(descriptor.isDirect)")
            print("     ParticipantID: \(descriptor.participantId ?? "nil")")

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

        print("   Total summaries created: \(summaries.count)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

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

        print("📬 MessageStore: Marked all messages as read in conversation \(conversationId)")
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
        print("📊 MessageStore: Unread count updated to \(total)")
        print("   Read messages: \(readMessageIds.count)")
        print("   Total messages: \(conversations.values.flatMap { $0 }.count)")
    }

    // MARK: - Read State Persistence

    private func loadReadState() {
        // Load read message IDs
        if let data = UserDefaults.standard.data(forKey: readMessagesKey),
           let uuidStrings = try? JSONDecoder().decode([String].self, from: data) {
            readMessageIds = Set(uuidStrings.compactMap { UUID(uuidString: $0) })
            print("📬 MessageStore: Loaded \(readMessageIds.count) read message IDs")
        }

        // Load last read timestamps
        if let data = UserDefaults.standard.data(forKey: lastReadKey),
           let timestamps = try? JSONDecoder().decode([String: Date].self, from: data) {
            lastReadTimestamps = timestamps
            print("📬 MessageStore: Loaded \(timestamps.count) last read timestamps")
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
}

