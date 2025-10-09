//
//  Message.swift
//  MeshRed
//
//  Created by Emilio Contreras on 28/09/25.
//

import Foundation

struct Message: Identifiable, Codable, Equatable {
    let id: UUID
    let sender: String
    let content: String
    let timestamp: Date
    let recipientId: String?
    let conversationId: String
    let conversationName: String?

    init(
        sender: String,
        content: String,
        recipientId: String? = nil,
        conversationId: String,
        conversationName: String? = nil
    ) {
        self.id = UUID()
        self.sender = sender
        self.content = content
        self.timestamp = Date()
        self.recipientId = recipientId
        self.conversationId = conversationId
        self.conversationName = conversationName
    }

    init(
        id: UUID,
        sender: String,
        content: String,
        timestamp: Date,
        recipientId: String?,
        conversationId: String,
        conversationName: String?
    ) {
        self.id = id
        self.sender = sender
        self.content = content
        self.timestamp = timestamp
        self.recipientId = recipientId
        self.conversationId = conversationId
        self.conversationName = conversationName
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sender
        case content
        case timestamp
        case recipientId
        case conversationId
        case conversationName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.sender = try container.decode(String.self, forKey: .sender)
        self.content = try container.decode(String.self, forKey: .content)
        self.timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        self.recipientId = try container.decodeIfPresent(String.self, forKey: .recipientId)

        if let storedConversationId = try container.decodeIfPresent(String.self, forKey: .conversationId) {
            self.conversationId = storedConversationId
        } else {
            // Legacy fallback: treat as public conversation
            self.conversationId = ConversationIdentifier.public.rawValue
        }

        self.conversationName = try container.decodeIfPresent(String.self, forKey: .conversationName)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(sender, forKey: .sender)
        try container.encode(content, forKey: .content)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(recipientId, forKey: .recipientId)
        try container.encode(conversationId, forKey: .conversationId)
        try container.encodeIfPresent(conversationName, forKey: .conversationName)
    }

    // For JSON serialization over the network
    func toData() -> Data? {
        return try? JSONEncoder().encode(self)
    }

    // For JSON deserialization from the network
    static func fromData(_ data: Data) -> Message? {
        return try? JSONDecoder().decode(Message.self, from: data)
    }

    // Helper for formatting timestamp for display
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    // Helper to check if message is from current device
    func isFromLocalDevice(deviceName: String) -> Bool {
        return sender == deviceName
    }

    // MARK: - WhatsApp-style Date Helpers

    /// Returns a user-friendly date string ("Hoy", "Ayer", or formatted date)
    var dateGroupLabel: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let messageDate = calendar.startOfDay(for: timestamp)

        if messageDate == today {
            return "Hoy"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  messageDate == yesterday {
            return "Ayer"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM/yyyy"
            return formatter.string(from: timestamp)
        }
    }

    /// Check if this message is on the same day as another message
    func isSameDay(as other: Message) -> Bool {
        let calendar = Calendar.current
        return calendar.isDate(timestamp, inSameDayAs: other.timestamp)
    }

    /// Check if this message is from the same sender and within 2 minutes of another
    func shouldGroupWith(_ other: Message) -> Bool {
        guard sender == other.sender else { return false }
        let timeDifference = abs(timestamp.timeIntervalSince(other.timestamp))
        return timeDifference < 120 // 2 minutes
    }
}

// Extension for UserDefaults persistence
extension Message {
    static let userDefaultsKey = "MeshRedMessages"

    static func saveMessages(_ messages: [Message]) {
        if let data = try? JSONEncoder().encode(messages) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    static func loadMessages() -> [Message] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let messages = try? JSONDecoder().decode([Message].self, from: data) else {
            return []
        }
        return messages
    }

    static func clearMessages() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}
