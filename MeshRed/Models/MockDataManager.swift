//
//  MockDataManager.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Provides mock data for demos and testing
//

import Foundation
import MultipeerConnectivity

// MARK: - Mock Data Manager
class MockDataManager {
    static let shared = MockDataManager()

    // MARK: - Mock Family Groups
    static let mockFamilyGroups: [MockFamilyGroup] = [
        MockFamilyGroup(
            id: UUID().uuidString,
            name: "Familia González",
            memberCount: 4,
            members: [
                MockMember(name: "María", status: .online),
                MockMember(name: "Pedro", status: .online),
                MockMember(name: "Sofía", status: .away),
                MockMember(name: "Luis", status: .online)
            ],
            lastMessage: "Nos vemos en la entrada",
            lastMessageTime: Date().addingTimeInterval(-300), // 5 min ago
            unreadCount: 2
        ),
        MockFamilyGroup(
            id: UUID().uuidString,
            name: "Amigos Sección 4B",
            memberCount: 3,
            members: [
                MockMember(name: "Carlos", status: .online),
                MockMember(name: "Ana", status: .online),
                MockMember(name: "Roberto", status: .offline)
            ],
            lastMessage: "¡Qué golazo! 🇲🇽",
            lastMessageTime: Date().addingTimeInterval(-120), // 2 min ago
            unreadCount: 5
        )
    ]

    // MARK: - Mock Individual Chats
    static let mockIndividualChats: [MockChatItem] = [
        MockChatItem(
            id: UUID().uuidString,
            name: "María González",
            status: .online,
            lastMessage: "Estoy en la fila del baño, sección B",
            lastMessageTime: Date().addingTimeInterval(-180), // 3 min ago
            unreadCount: 1,
            avatar: "👩🏻"
        ),
        MockChatItem(
            id: UUID().uuidString,
            name: "Carlos Pérez",
            status: .online,
            lastMessage: "¿Dónde están? Ya casi empieza",
            lastMessageTime: Date().addingTimeInterval(-600), // 10 min ago
            unreadCount: 3,
            avatar: "👨🏽"
        ),
        MockChatItem(
            id: UUID().uuidString,
            name: "Ana López",
            status: .away,
            lastMessage: "Llegué a la entrada norte 🚶‍♀️",
            lastMessageTime: Date().addingTimeInterval(-900), // 15 min ago
            unreadCount: 0,
            avatar: "👩🏼"
        ),
        MockChatItem(
            id: UUID().uuidString,
            name: "Roberto Martínez",
            status: .offline,
            lastMessage: "Ok, nos vemos ahí",
            lastMessageTime: Date().addingTimeInterval(-3600), // 1 hour ago
            unreadCount: 0,
            avatar: "👨🏻"
        )
    ]

    // MARK: - Mock Broadcast Messages
    static let mockBroadcastMessages: [MockMessage] = [
        MockMessage(
            id: UUID().uuidString,
            sender: "Sistema Estadio",
            content: "🏟️ Bienvenidos al Estadio Azteca. Partido México 🇲🇽 vs Canadá 🇨🇦",
            timestamp: Date().addingTimeInterval(-7200), // 2 hours ago
            type: .system
        ),
        MockMessage(
            id: UUID().uuidString,
            sender: "Alertas",
            content: "⚽️ ¡El partido iniciará en 10 minutos! Por favor diríganse a sus asientos",
            timestamp: Date().addingTimeInterval(-600), // 10 min ago
            type: .alert
        ),
        MockMessage(
            id: UUID().uuidString,
            sender: "Fan México",
            content: "🇲🇽 ¡GOOOL DE MÉXICO! ¡Vamos por más!",
            timestamp: Date().addingTimeInterval(-240), // 4 min ago
            type: .broadcast
        ),
        MockMessage(
            id: UUID().uuidString,
            sender: "Seguridad",
            content: "🚨 Manténganse en sus asientos. Eviten obstruir pasillos",
            timestamp: Date().addingTimeInterval(-180), // 3 min ago
            type: .system
        )
    ]

    // MARK: - Mock Conversation Messages
    static func mockConversationMessages(for chatId: String) -> [MockMessage] {
        // Mensajes específicos por conversación
        switch chatId {
        case let id where id.contains("María"):
            return [
                MockMessage(id: UUID().uuidString, sender: "María González", content: "¿Ya llegaron al estadio?", timestamp: Date().addingTimeInterval(-900), type: .received),
                MockMessage(id: UUID().uuidString, sender: "Tú", content: "Sí, estamos en la sección 4B", timestamp: Date().addingTimeInterval(-840), type: .sent),
                MockMessage(id: UUID().uuidString, sender: "María González", content: "Perfecto, voy para allá", timestamp: Date().addingTimeInterval(-720), type: .received),
                MockMessage(id: UUID().uuidString, sender: "María González", content: "Estoy en la fila del baño, sección B", timestamp: Date().addingTimeInterval(-180), type: .received)
            ]

        case let id where id.contains("Carlos"):
            return [
                MockMessage(id: UUID().uuidString, sender: "Carlos Pérez", content: "¿Dónde se sentaron?", timestamp: Date().addingTimeInterval(-1200), type: .received),
                MockMessage(id: UUID().uuidString, sender: "Tú", content: "Sección 4B, fila 15", timestamp: Date().addingTimeInterval(-1140), type: .sent),
                MockMessage(id: UUID().uuidString, sender: "Carlos Pérez", content: "Ok, voy en camino", timestamp: Date().addingTimeInterval(-1080), type: .received),
                MockMessage(id: UUID().uuidString, sender: "Carlos Pérez", content: "¿Dónde están? Ya casi empieza", timestamp: Date().addingTimeInterval(-600), type: .received)
            ]

        case let id where id.contains("Ana"):
            return [
                MockMessage(id: UUID().uuidString, sender: "Tú", content: "¿A qué hora llegas?", timestamp: Date().addingTimeInterval(-1800), type: .sent),
                MockMessage(id: UUID().uuidString, sender: "Ana López", content: "En 15 minutos estoy ahí", timestamp: Date().addingTimeInterval(-1740), type: .received),
                MockMessage(id: UUID().uuidString, sender: "Ana López", content: "Llegué a la entrada norte 🚶‍♀️", timestamp: Date().addingTimeInterval(-900), type: .received)
            ]

        default:
            return [
                MockMessage(id: UUID().uuidString, sender: "Tú", content: "Hola!", timestamp: Date().addingTimeInterval(-300), type: .sent),
                MockMessage(id: UUID().uuidString, sender: "Usuario", content: "¿Qué tal?", timestamp: Date().addingTimeInterval(-240), type: .received)
            ]
        }
    }

    // MARK: - Time Formatting Helper
    static func formatTimeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)

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
}

// MARK: - Mock Models

struct MockFamilyGroup: Identifiable {
    let id: String
    let name: String
    let memberCount: Int
    let members: [MockMember]
    let lastMessage: String
    let lastMessageTime: Date
    let unreadCount: Int
}

struct MockChatItem: Identifiable {
    let id: String
    let name: String
    let status: UserStatus
    let lastMessage: String
    let lastMessageTime: Date
    let unreadCount: Int
    let avatar: String
}

struct MockMember {
    let name: String
    let status: UserStatus
}

struct MockMessage: Identifiable {
    let id: String
    let sender: String
    let content: String
    let timestamp: Date
    let type: MessageMockType

    enum MessageMockType {
        case sent
        case received
        case broadcast
        case system
        case alert
    }
}

enum UserStatus {
    case online
    case away
    case offline

    var displayText: String {
        switch self {
        case .online: return "En línea"
        case .away: return "Ausente"
        case .offline: return "Desconectado"
        }
    }

    var color: String {
        switch self {
        case .online: return "green"
        case .away: return "orange"
        case .offline: return "gray"
        }
    }
}
