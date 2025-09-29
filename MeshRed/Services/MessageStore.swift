//
//  MessageStore.swift
//  MeshRed
//
//  Created by Emilio Contreras on 28/09/25.
//

import Foundation
import Combine

class MessageStore: ObservableObject {
    @Published var messages: [Message] = []

    private let maxMessages = 100
    private let userDefaultsKey = "MeshRedMessages"

    init() {
        loadMessages()
    }

    // MARK: - Public Methods

    func addMessage(_ message: Message) {
        DispatchQueue.main.async {
            self.messages.append(message)
            self.enforceMessageLimit()
            self.saveMessages()
            print("📱 MessageStore: Added message from \(message.sender): \(message.content)")
        }
    }

    func addMessages(_ newMessages: [Message]) {
        DispatchQueue.main.async {
            self.messages.append(contentsOf: newMessages)
            self.enforceMessageLimit()
            self.saveMessages()
            print("📱 MessageStore: Added \(newMessages.count) messages")
        }
    }

    func clearAllMessages() {
        DispatchQueue.main.async {
            self.messages.removeAll()
            self.saveMessages()
            print("📱 MessageStore: Cleared all messages")
        }
    }

    // MARK: - Private Methods

    private func loadMessages() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let savedMessages = try? JSONDecoder().decode([Message].self, from: data) else {
            print("📱 MessageStore: No saved messages found")
            return
        }

        DispatchQueue.main.async {
            self.messages = savedMessages
            print("📱 MessageStore: Loaded \(savedMessages.count) messages from storage")
        }
    }

    private func saveMessages() {
        do {
            let data = try JSONEncoder().encode(messages)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            print("📱 MessageStore: Saved \(messages.count) messages to storage")
        } catch {
            print("❌ MessageStore: Failed to save messages: \(error.localizedDescription)")
        }
    }

    private func enforceMessageLimit() {
        if messages.count > maxMessages {
            let excessCount = messages.count - maxMessages
            messages.removeFirst(excessCount)
            print("📱 MessageStore: Removed \(excessCount) old messages to maintain limit of \(maxMessages)")
        }
    }

    // MARK: - Computed Properties

    var messageCount: Int {
        return messages.count
    }

    var latestMessage: Message? {
        return messages.last
    }

    // Get messages sorted by timestamp (newest first for display)
    var sortedMessages: [Message] {
        return messages.sorted { $0.timestamp < $1.timestamp }
    }

    // Get messages from a specific sender
    func messages(from sender: String) -> [Message] {
        return messages.filter { $0.sender == sender }
    }

    // Get recent messages (last N messages)
    func recentMessages(count: Int) -> [Message] {
        let startIndex = max(0, messages.count - count)
        return Array(messages[startIndex...])
    }
}