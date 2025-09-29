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

    init(sender: String, content: String) {
        self.id = UUID()
        self.sender = sender
        self.content = content
        self.timestamp = Date()
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