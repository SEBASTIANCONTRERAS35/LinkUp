//
//  MockLinkFenceData.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Mock data for linkfences and events for testing and demos
//

import Foundation
import CoreLocation
import SwiftUI

class MockLinkFenceData {
    // MARK: - Mock LinkFences (Places in CDMX)

    /// Mock linkfences representing real places in Mexico City
    static let mockLinkFences: [CustomLinkFence] = [
        // Estadio Azteca (500m radius for Mundial 2026)
        CustomLinkFence(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Estadio Azteca - Mundial 2026",
            center: CLLocationCoordinate2D(latitude: 19.302778, longitude: -99.150556),
            radius: 500,  // 500 meters to cover entire stadium complex
            createdAt: Date().addingTimeInterval(-86400 * 30), // Created 30 days ago
            creatorPeerID: "user-device",
            isActive: true,
            category: .stadium,
            colorHex: "006847",  // Mexico green
            isMonitoring: true
        ),

        // Foro Sol (Concert venue)
        CustomLinkFence(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Foro Sol",
            center: CLLocationCoordinate2D(latitude: 19.398889, longitude: -99.090833),
            radius: 250,
            createdAt: Date().addingTimeInterval(-86400 * 25),
            creatorPeerID: "user-device",
            isActive: true,
            category: .concert,
            colorHex: "CE1126",  // Red
            isMonitoring: false
        ),

        // Arena Ciudad de México
        CustomLinkFence(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            name: "Arena Ciudad de México",
            center: CLLocationCoordinate2D(latitude: 19.389722, longitude: -99.093889),
            radius: 200,
            createdAt: Date().addingTimeInterval(-86400 * 20),
            creatorPeerID: "user-device",
            isActive: true,
            category: .concert,
            colorHex: "CE1126",  // Red
            isMonitoring: true
        ),

        // Plaza Universidad (Shopping)
        CustomLinkFence(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            name: "Plaza Universidad",
            center: CLLocationCoordinate2D(latitude: 19.323611, longitude: -99.181389),
            radius: 150,
            createdAt: Date().addingTimeInterval(-86400 * 15),
            creatorPeerID: "user-device",
            isActive: true,
            category: .shopping,
            colorHex: "3C3B6E",  // Blue
            isMonitoring: true
        ),

        // Restaurante Casa Toño (Restaurant)
        CustomLinkFence(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            name: "Restaurante Casa Toño",
            center: CLLocationCoordinate2D(latitude: 19.432608, longitude: -99.133209),
            radius: 80,
            createdAt: Date().addingTimeInterval(-86400 * 10),
            creatorPeerID: "user-device",
            isActive: true,
            category: .restaurant,
            colorHex: "FF9500",  // Orange
            isMonitoring: false
        ),

        // Facultad de Ingeniería UNAM (School)
        CustomLinkFence(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            name: "Facultad de Ingeniería UNAM",
            center: CLLocationCoordinate2D(latitude: 19.331389, longitude: -99.184444),
            radius: 200,
            createdAt: Date().addingTimeInterval(-86400 * 60), // Created 60 days ago
            creatorPeerID: "user-device",
            isActive: true,
            category: .school,
            colorHex: "007AFF",  // Blue
            isMonitoring: true
        ),

        // Café de Tacuba (Custom)
        CustomLinkFence(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            name: "Café de Tacuba",
            center: CLLocationCoordinate2D(latitude: 19.434167, longitude: -99.141389),
            radius: 50,
            createdAt: Date().addingTimeInterval(-86400 * 5),
            creatorPeerID: "user-device",
            isActive: true,
            category: .custom,
            colorHex: "8E44AD",  // Purple
            isMonitoring: false
        ),

        // Parque México (Custom)
        CustomLinkFence(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            name: "Parque México",
            center: CLLocationCoordinate2D(latitude: 19.411944, longitude: -99.168611),
            radius: 180,
            createdAt: Date().addingTimeInterval(-86400 * 12),
            creatorPeerID: "user-device",
            isActive: true,
            category: .custom,
            colorHex: "27AE60",  // Green
            isMonitoring: false
        )
    ]

    // MARK: - Mock Events by LinkFence

    /// Generate mock events for testing
    static func generateMockEvents() -> [UUID: [LinkFenceEventMessage]] {
        var events: [UUID: [LinkFenceEventMessage]] = [:]

        // Estadio Azteca - 3 complete visits (entry + exit pairs)
        let estadioId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        events[estadioId] = [
            // Visit 1: 7 days ago
            createEvent(linkfenceId: estadioId, name: "Estadio Azteca", type: .entry, daysAgo: 7, hoursOffset: 0),
            createEvent(linkfenceId: estadioId, name: "Estadio Azteca", type: .exit, daysAgo: 7, hoursOffset: 2.5),

            // Visit 2: 3 days ago
            createEvent(linkfenceId: estadioId, name: "Estadio Azteca", type: .entry, daysAgo: 3, hoursOffset: 0),
            createEvent(linkfenceId: estadioId, name: "Estadio Azteca", type: .exit, daysAgo: 3, hoursOffset: 3.0),

            // Visit 3: Yesterday
            createEvent(linkfenceId: estadioId, name: "Estadio Azteca", type: .entry, daysAgo: 1, hoursOffset: 0),
            createEvent(linkfenceId: estadioId, name: "Estadio Azteca", type: .exit, daysAgo: 1, hoursOffset: 2.2)
        ]

        // Arena Ciudad de México - 2 visits
        let arenaId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        events[arenaId] = [
            // Visit 1: 5 days ago
            createEvent(linkfenceId: arenaId, name: "Arena Ciudad de México", type: .entry, daysAgo: 5, hoursOffset: 0),
            createEvent(linkfenceId: arenaId, name: "Arena Ciudad de México", type: .exit, daysAgo: 5, hoursOffset: 4.0),

            // Visit 2: 2 days ago (still inside - no exit)
            createEvent(linkfenceId: arenaId, name: "Arena Ciudad de México", type: .entry, daysAgo: 2, hoursOffset: 0)
        ]

        // Plaza Universidad - 5 visits (frequent shopper)
        let plazaId = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        events[plazaId] = [
            createEvent(linkfenceId: plazaId, name: "Plaza Universidad", type: .entry, daysAgo: 10, hoursOffset: 0),
            createEvent(linkfenceId: plazaId, name: "Plaza Universidad", type: .exit, daysAgo: 10, hoursOffset: 1.5),

            createEvent(linkfenceId: plazaId, name: "Plaza Universidad", type: .entry, daysAgo: 8, hoursOffset: 0),
            createEvent(linkfenceId: plazaId, name: "Plaza Universidad", type: .exit, daysAgo: 8, hoursOffset: 2.0),

            createEvent(linkfenceId: plazaId, name: "Plaza Universidad", type: .entry, daysAgo: 5, hoursOffset: 0),
            createEvent(linkfenceId: plazaId, name: "Plaza Universidad", type: .exit, daysAgo: 5, hoursOffset: 1.8),

            createEvent(linkfenceId: plazaId, name: "Plaza Universidad", type: .entry, daysAgo: 3, hoursOffset: 0),
            createEvent(linkfenceId: plazaId, name: "Plaza Universidad", type: .exit, daysAgo: 3, hoursOffset: 1.2),

            createEvent(linkfenceId: plazaId, name: "Plaza Universidad", type: .entry, daysAgo: 1, hoursOffset: 0),
            createEvent(linkfenceId: plazaId, name: "Plaza Universidad", type: .exit, daysAgo: 1, hoursOffset: 2.5)
        ]

        // Facultad de Ingeniería UNAM - Daily visits (school)
        let facultadId = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        events[facultadId] = [
            // Last week - 5 days of classes
            createEvent(linkfenceId: facultadId, name: "Facultad de Ingeniería UNAM", type: .entry, daysAgo: 7, hoursOffset: 0),
            createEvent(linkfenceId: facultadId, name: "Facultad de Ingeniería UNAM", type: .exit, daysAgo: 7, hoursOffset: 6.0),

            createEvent(linkfenceId: facultadId, name: "Facultad de Ingeniería UNAM", type: .entry, daysAgo: 6, hoursOffset: 0),
            createEvent(linkfenceId: facultadId, name: "Facultad de Ingeniería UNAM", type: .exit, daysAgo: 6, hoursOffset: 5.5),

            createEvent(linkfenceId: facultadId, name: "Facultad de Ingeniería UNAM", type: .entry, daysAgo: 5, hoursOffset: 0),
            createEvent(linkfenceId: facultadId, name: "Facultad de Ingeniería UNAM", type: .exit, daysAgo: 5, hoursOffset: 7.0),

            createEvent(linkfenceId: facultadId, name: "Facultad de Ingeniería UNAM", type: .entry, daysAgo: 4, hoursOffset: 0),
            createEvent(linkfenceId: facultadId, name: "Facultad de Ingeniería UNAM", type: .exit, daysAgo: 4, hoursOffset: 6.5),

            createEvent(linkfenceId: facultadId, name: "Facultad de Ingeniería UNAM", type: .entry, daysAgo: 3, hoursOffset: 0),
            createEvent(linkfenceId: facultadId, name: "Facultad de Ingeniería UNAM", type: .exit, daysAgo: 3, hoursOffset: 5.0),

            // This week - currently at school
            createEvent(linkfenceId: facultadId, name: "Facultad de Ingeniería UNAM", type: .entry, daysAgo: 0, hoursOffset: -2.0)  // 2 hours ago
        ]

        // Foro Sol - 1 concert visit
        let foroId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        events[foroId] = [
            createEvent(linkfenceId: foroId, name: "Foro Sol", type: .entry, daysAgo: 15, hoursOffset: 0),
            createEvent(linkfenceId: foroId, name: "Foro Sol", type: .exit, daysAgo: 15, hoursOffset: 5.0)
        ]

        // Restaurante Casa Toño - 2 visits
        let casaTonioId = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        events[casaTonioId] = [
            createEvent(linkfenceId: casaTonioId, name: "Restaurante Casa Toño", type: .entry, daysAgo: 4, hoursOffset: 0),
            createEvent(linkfenceId: casaTonioId, name: "Restaurante Casa Toño", type: .exit, daysAgo: 4, hoursOffset: 1.5),

            createEvent(linkfenceId: casaTonioId, name: "Restaurante Casa Toño", type: .entry, daysAgo: 2, hoursOffset: 0),
            createEvent(linkfenceId: casaTonioId, name: "Restaurante Casa Toño", type: .exit, daysAgo: 2, hoursOffset: 1.2)
        ]

        // Parque México - 1 visit
        let parqueId = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        events[parqueId] = [
            createEvent(linkfenceId: parqueId, name: "Parque México", type: .entry, daysAgo: 6, hoursOffset: 0),
            createEvent(linkfenceId: parqueId, name: "Parque México", type: .exit, daysAgo: 6, hoursOffset: 2.0)
        ]

        return events
    }

    // MARK: - Helper Methods

    /// Create a mock linkfence event
    static func createEvent(
        linkfenceId: UUID,
        name: String,
        type: LinkFenceEventType,
        daysAgo: Int,
        hoursOffset: Double
    ) -> LinkFenceEventMessage {
        let baseDate = Date().addingTimeInterval(-Double(daysAgo) * 86400)
        let timestamp = baseDate.addingTimeInterval(hoursOffset * 3600)

        // Create a mock linkfence for the event
        let mockLinkFence = mockLinkFences.first { $0.id == linkfenceId }!

        return LinkFenceEventMessage(
            senderId: "user-device",
            senderNickname: "Tú",
            linkfence: mockLinkFence,
            eventType: type,
            location: UserLocation(
                latitude: mockLinkFence.center.latitude,
                longitude: mockLinkFence.center.longitude,
                accuracy: 10.0,
                timestamp: timestamp
            ),
            familyGroupCode: FamilyGroupCode(rawCode: "FAM-DEM23")!
        )
    }

    /// Get all events flattened
    static var allMockEvents: [LinkFenceEventMessage] {
        return generateMockEvents().values.flatMap { $0 }
    }

    /// Generate mock linkfencing notifications (ONLY entry/exit - what CoreLocation actually provides)
    static func generateMockNotifications(for linkfenceId: UUID) -> [LinkFenceNotification] {
        let linkfence = mockLinkFences.first { $0.id == linkfenceId }
        guard let linkfence = linkfence else { return [] }

        // Mock family members
        let familyMembers = [
            ("Tú", "user-device"),
            ("María", "maria-iphone"),
            ("Carlos", "carlos-iphone"),
            ("Ana", "ana-iphone"),
            ("Pedro", "pedro-iphone")
        ]

        // Get actual entry/exit events from the history
        var baseEvents = generateMockEvents()[linkfenceId] ?? []

        // Generate events for other family members (simulate)
        var allEvents: [(LinkFenceEventMessage, String)] = baseEvents.map { ($0, "Tú") }

        // Add some events for other family members based on the linkfence
        if linkfenceId.uuidString == "11111111-1111-1111-1111-111111111111" { // Estadio Azteca
            // María and Carlos also went
            allEvents.append((createEvent(linkfenceId: linkfenceId, name: linkfence.name, type: .entry, daysAgo: 1, hoursOffset: 0.5), "María"))
            allEvents.append((createEvent(linkfenceId: linkfenceId, name: linkfence.name, type: .exit, daysAgo: 1, hoursOffset: 3.0), "María"))
            allEvents.append((createEvent(linkfenceId: linkfenceId, name: linkfence.name, type: .entry, daysAgo: 3, hoursOffset: 1.0), "Carlos"))
            allEvents.append((createEvent(linkfenceId: linkfenceId, name: linkfence.name, type: .exit, daysAgo: 3, hoursOffset: 3.5), "Carlos"))
        } else if linkfenceId.uuidString == "66666666-6666-6666-6666-666666666666" { // Facultad
            // Ana también va a la facultad
            allEvents.append((createEvent(linkfenceId: linkfenceId, name: linkfence.name, type: .entry, daysAgo: 0, hoursOffset: -3.0), "Ana"))
        } else if linkfenceId.uuidString == "44444444-4444-4444-4444-444444444444" { // Plaza
            // María de compras
            allEvents.append((createEvent(linkfenceId: linkfenceId, name: linkfence.name, type: .entry, daysAgo: 2, hoursOffset: 1.0), "María"))
            allEvents.append((createEvent(linkfenceId: linkfenceId, name: linkfence.name, type: .exit, daysAgo: 2, hoursOffset: 2.5), "María"))
        }

        // Convert to LinkFenceNotification (only entry/exit)
        return allEvents.map { (event, memberName) in
            let message: String
            let importance: LinkFenceNotification.NotificationImportance

            if event.eventType == .entry {
                message = "\(memberName) \(memberName == "Tú" ? "entraste" : "entró") a \(linkfence.name)"
                importance = .medium
            } else {
                message = "\(memberName) \(memberName == "Tú" ? "saliste" : "salió") de \(linkfence.name)"
                importance = .low
            }

            return LinkFenceNotification(
                id: UUID(),
                linkfenceId: linkfenceId,
                type: event.eventType == .entry ? .entry : .exit,
                message: message,
                timestamp: event.timestamp,
                importance: importance
            )
        }.sorted { $0.timestamp > $1.timestamp } // Most recent first
    }
}

// MARK: - LinkFence Notification Model
struct LinkFenceNotification: Identifiable, Codable {
    let id: UUID
    let linkfenceId: UUID
    let type: NotificationType
    let message: String
    let timestamp: Date
    let importance: NotificationImportance

    enum NotificationType: String, Codable {
        case entry = "entry"
        case exit = "exit"

        var icon: String {
            switch self {
            case .entry: return "arrow.right.circle.fill"
            case .exit: return "arrow.left.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .entry: return Mundial2026Colors.verde
            case .exit: return Mundial2026Colors.rojo
            }
        }
    }

    enum NotificationImportance: String, Codable {
        case low, medium, high
    }

    var timeAgo: String {
        let seconds = Int(Date().timeIntervalSince(timestamp))

        // Handle future dates (shouldn't happen, but just in case)
        if seconds < 0 {
            return "Ahora"
        }

        if seconds < 60 {
            return "Hace \(seconds)s"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "Hace \(minutes)min"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            return "Hace \(hours)h"
        } else {
            let days = seconds / 86400
            return "Hace \(days)d"
        }
    }
}
