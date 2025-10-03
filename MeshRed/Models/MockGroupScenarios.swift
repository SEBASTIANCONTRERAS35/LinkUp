//
//  MockGroupScenarios.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Pre-defined realistic group scenarios for demos
//

import Foundation
import CoreLocation

// MARK: - Mock Group Scenarios

/// Pre-defined scenarios for realistic demos
enum MockGroupScenarios {

    // MARK: - Scenario 1: Familia en el Partido

    /// Familia completa disfrutando del partido México vs Canadá
    static let familiaGonzalez = MockFamilyGroupData(
        id: UUID(uuidString: "FAM00000-0000-0000-0000-000000000001")!,
        name: "Familia González 🇲🇽",
        code: "MEX2026",
        createdAt: Date().addingTimeInterval(-7200), // Created 2 hours ago
        creatorPeerID: "papa-gonzalez",
        scenario: .familiaEnPartido,
        members: [
            // Papá - Creador del grupo
            MockGroupMember(
                peerID: "papa-gonzalez",
                nickname: "Roberto",
                relationshipTag: "Papá",
                location: estadioAztecaLocation(section: .section4B, row: 15, seat: 10),
                connectionStatus: .online,
                uwbDistance: 0.0, // Current device
                lastSeenMinutesAgo: 0,
                batteryLevel: 85,
                isCurrentDevice: true
            ),

            // Mamá - Conectada directamente
            MockGroupMember(
                peerID: "mama-gonzalez",
                nickname: "María",
                relationshipTag: "Mamá",
                location: estadioAztecaLocation(section: .banos, row: 0, seat: 0),
                connectionStatus: .online,
                uwbDistance: 18.5,
                lastSeenMinutesAgo: 2,
                batteryLevel: 72,
                recentMessages: [
                    SimulatedMessage.fromLegacy("Estoy en la fila del baño, sección B", senderId: "mama-gonzalez", minutesAgo: 3),
                    SimulatedMessage.fromLegacy("¿Me guardan el asiento?", senderId: "mama-gonzalez", minutesAgo: 4),
                    SimulatedMessage.fromLegacy("Ya casi regreso 🚶‍♀️", senderId: "mama-gonzalez", minutesAgo: 2)
                ]
            ),

            // Hija mayor - Online
            MockGroupMember(
                peerID: "sofia-gonzalez",
                nickname: "Sofía",
                relationshipTag: "Hija",
                location: estadioAztecaLocation(section: .concesiones, row: 0, seat: 0),
                connectionStatus: .online,
                uwbDistance: 24.8,
                lastSeenMinutesAgo: 3,
                batteryLevel: 45,
                recentMessages: [
                    SimulatedMessage.fromLegacy("Voy por hot dogs 🌭", senderId: "sofia-gonzalez", minutesAgo: 5),
                    SimulatedMessage.fromLegacy("¿Alguien quiere algo?", senderId: "sofia-gonzalez", minutesAgo: 4),
                    SimulatedMessage.fromLegacy("La fila está larguísima 😩", senderId: "sofia-gonzalez", minutesAgo: 3)
                ]
            ),

            // Hijo menor - Away (jugando)
            MockGroupMember(
                peerID: "luis-gonzalez",
                nickname: "Luis",
                relationshipTag: "Hijo",
                location: estadioAztecaLocation(section: .section4A, row: 8, seat: 5),
                connectionStatus: .away,
                uwbDistance: 12.3,
                lastSeenMinutesAgo: 8,
                batteryLevel: 92,
                recentMessages: [
                    SimulatedMessage.fromLegacy("Estoy con mis amigos en 4A", senderId: "luis-gonzalez", minutesAgo: 9),
                    SimulatedMessage.fromLegacy("Ya vengo al rato", senderId: "luis-gonzalez", minutesAgo: 8)
                ]
            ),

            // Abuela - Conexión indirecta
            MockGroupMember(
                peerID: "abuela-gonzalez",
                nickname: "Carmen",
                relationshipTag: "Abuela",
                location: estadioAztecaLocation(section: .section5B, row: 20, seat: 15),
                connectionStatus: .indirect,
                uwbDistance: nil, // No LinkFinder (too far)
                lastSeenMinutesAgo: 15,
                batteryLevel: 38,
                recentMessages: [
                    SimulatedMessage.fromLegacy("¿A qué hora es el medio tiempo?", senderId: "abuela-gonzalez", minutesAgo: 16),
                    SimulatedMessage.fromLegacy("Hace mucho calor aquí 🥵", senderId: "abuela-gonzalez", minutesAgo: 15)
                ]
            )
        ]
    )

    // MARK: - Scenario 2: Estudiantes Universidad

    /// Grupo de estudiantes de la Facultad de Ingeniería UNAM
    static let amigosUniversidad = MockFamilyGroupData(
        id: UUID(uuidString: "FAM00000-0000-0000-0000-000000000002")!,
        name: "Amigos Ingeniería 🎓",
        code: "UNAM2025",
        createdAt: Date().addingTimeInterval(-5400), // Created 1.5 hours ago
        creatorPeerID: "carlos-ing",
        scenario: .estudiantesUNAM,
        members: [
            // Carlos - Creador
            MockGroupMember(
                peerID: "carlos-ing",
                nickname: "Carlos",
                relationshipTag: "Compa",
                location: estadioAztecaLocation(section: .section4B, row: 22, seat: 8),
                connectionStatus: .online,
                uwbDistance: 0.0,
                lastSeenMinutesAgo: 0,
                batteryLevel: 78,
                isCurrentDevice: true
            ),

            // Ana - Ingeniera de Software
            MockGroupMember(
                peerID: "ana-sw",
                nickname: "Ana",
                relationshipTag: "Compa",
                location: estadioAztecaLocation(section: .section4B, row: 22, seat: 10),
                connectionStatus: .online,
                uwbDistance: 2.1,
                lastSeenMinutesAgo: 0,
                batteryLevel: 88,
                recentMessages: [
                    SimulatedMessage.fromLegacy("¡GOOOL! 🇲🇽⚽️", senderId: "ana-sw", minutesAgo: 2),
                    SimulatedMessage.fromLegacy("¿Vieron ese pase?", senderId: "ana-sw", minutesAgo: 3),
                    SimulatedMessage.fromLegacy("México va a ganar esto 🔥", senderId: "ana-sw", minutesAgo: 1)
                ]
            ),

            // Roberto - Ingeniero Civil
            MockGroupMember(
                peerID: "roberto-civil",
                nickname: "Beto",
                relationshipTag: "Compa",
                location: estadioAztecaLocation(section: .entradaNorte, row: 0, seat: 0),
                connectionStatus: .away,
                uwbDistance: nil,
                lastSeenMinutesAgo: 25,
                batteryLevel: 15, // Low battery!
                recentMessages: [
                    SimulatedMessage.fromLegacy("Mi batería está al 15% 🔋", senderId: "roberto-civil", minutesAgo: 26),
                    SimulatedMessage.fromLegacy("¿Alguien trae cargador?", senderId: "roberto-civil", minutesAgo: 25),
                    SimulatedMessage.fromLegacy("Estoy en la entrada norte", senderId: "roberto-civil", minutesAgo: 25)
                ]
            ),

            // Diana - Ingeniera Eléctrica
            MockGroupMember(
                peerID: "diana-elec",
                nickname: "Diana",
                relationshipTag: "Compa",
                location: estadioAztecaLocation(section: .section4C, row: 18, seat: 12),
                connectionStatus: .online,
                uwbDistance: 15.7,
                lastSeenMinutesAgo: 5,
                batteryLevel: 65,
                recentMessages: [
                    SimulatedMessage.fromLegacy("Me cambié de lugar", senderId: "diana-elec", minutesAgo: 7),
                    SimulatedMessage.fromLegacy("Encontré asientos mejores 😎", senderId: "diana-elec", minutesAgo: 6),
                    SimulatedMessage.fromLegacy("Vengan para acá", senderId: "diana-elec", minutesAgo: 5)
                ]
            )
        ]
    )

    // MARK: - Scenario 3: Emergencia Médica

    /// Familia con adulto mayor que necesita asistencia
    static let familiaEmergencia = MockFamilyGroupData(
        id: UUID(uuidString: "FAM00000-0000-0000-0000-000000000003")!,
        name: "Familia Martínez 🏥",
        code: "FAM911",
        createdAt: Date().addingTimeInterval(-3600), // Created 1 hour ago
        creatorPeerID: "pedro-martinez",
        scenario: .emergenciaMedica,
        members: [
            // Pedro - Hijo preocupado
            MockGroupMember(
                peerID: "pedro-martinez",
                nickname: "Pedro",
                relationshipTag: "Hijo",
                location: estadioAztecaLocation(section: .section6A, row: 10, seat: 5),
                connectionStatus: .online,
                uwbDistance: 0.0,
                lastSeenMinutesAgo: 0,
                batteryLevel: 92,
                isCurrentDevice: true,
                hasActiveEmergency: true
            ),

            // Padre mayor - En emergencia médica
            MockGroupMember(
                peerID: "don-jorge",
                nickname: "Don Jorge",
                relationshipTag: "Papá",
                location: estadioAztecaLocation(section: .section6A, row: 10, seat: 6),
                connectionStatus: .online,
                uwbDistance: 1.2,
                lastSeenMinutesAgo: 0,
                batteryLevel: 55,
                healthAlert: .elevatedHeartRate,
                recentMessages: [
                    SimulatedMessage.fromLegacy("Me siento mareado", senderId: "don-jorge", minutesAgo: 3),
                    SimulatedMessage.fromLegacy("Necesito sentarme", senderId: "don-jorge", minutesAgo: 2)
                ]
            ),

            // Hermana - Ayudando
            MockGroupMember(
                peerID: "laura-martinez",
                nickname: "Laura",
                relationshipTag: "Hija",
                location: estadioAztecaLocation(section: .section6A, row: 10, seat: 4),
                connectionStatus: .online,
                uwbDistance: 2.5,
                lastSeenMinutesAgo: 0,
                batteryLevel: 68,
                recentMessages: [
                    SimulatedMessage.fromLegacy("Ya llamé al personal médico", senderId: "laura-martinez", minutesAgo: 2),
                    SimulatedMessage.fromLegacy("Vienen en camino 🚑", senderId: "laura-martinez", minutesAgo: 1),
                    SimulatedMessage.fromLegacy("Papá mantente tranquilo", senderId: "laura-martinez", minutesAgo: 1)
                ]
            )
        ]
    )

    // MARK: - Scenario 4: Mundial 2026

    /// Familia grande para el Mundial FIFA 2026
    static let familiaMundial2026 = MockFamilyGroupData(
        id: UUID(uuidString: "FAM00000-0000-0000-0000-000000000004")!,
        name: "Familia Hernández ⚽️ Mundial 2026",
        code: "FIFA26",
        createdAt: Date().addingTimeInterval(-10800), // Created 3 hours ago
        creatorPeerID: "javier-hdz",
        scenario: .mundial2026,
        members: [
            // Javier - Padre, organizador
            MockGroupMember(
                peerID: "javier-hdz",
                nickname: "Javier",
                relationshipTag: "Papá",
                location: estadioAztecaLocation(section: .section3A, row: 12, seat: 15),
                connectionStatus: .online,
                uwbDistance: 0.0,
                lastSeenMinutesAgo: 0,
                batteryLevel: 88,
                isCurrentDevice: true
            ),

            // Esposa
            MockGroupMember(
                peerID: "patricia-hdz",
                nickname: "Patricia",
                relationshipTag: "Mamá",
                location: estadioAztecaLocation(section: .section3A, row: 12, seat: 16),
                connectionStatus: .online,
                uwbDistance: 1.1,
                lastSeenMinutesAgo: 0,
                batteryLevel: 75,
                recentMessages: [
                    SimulatedMessage.fromLegacy("¡Qué emoción! México vs Argentina 🇲🇽🇦🇷", senderId: "patricia-hdz", minutesAgo: 5),
                    SimulatedMessage.fromLegacy("Esto es histórico", senderId: "patricia-hdz", minutesAgo: 3),
                    SimulatedMessage.fromLegacy("Los niños están felices 😊", senderId: "patricia-hdz", minutesAgo: 1)
                ]
            ),

            // Hijo mayor
            MockGroupMember(
                peerID: "diego-hdz",
                nickname: "Diego",
                relationshipTag: "Hijo",
                location: estadioAztecaLocation(section: .section3B, row: 5, seat: 20),
                connectionStatus: .away,
                uwbDistance: 22.4,
                lastSeenMinutesAgo: 12,
                batteryLevel: 82,
                recentMessages: [
                    SimulatedMessage.fromLegacy("Me encontré a unos amigos", senderId: "diego-hdz", minutesAgo: 14),
                    SimulatedMessage.fromLegacy("Están en la sección 3B", senderId: "diego-hdz", minutesAgo: 13),
                    SimulatedMessage.fromLegacy("¿Puedo quedarme aquí?", senderId: "diego-hdz", minutesAgo: 12)
                ]
            ),

            // Hija - Tomando fotos
            MockGroupMember(
                peerID: "valeria-hdz",
                nickname: "Valeria",
                relationshipTag: "Hija",
                location: estadioAztecaLocation(section: .section3A, row: 15, seat: 10),
                connectionStatus: .online,
                uwbDistance: 8.3,
                lastSeenMinutesAgo: 3,
                batteryLevel: 42,
                recentMessages: [
                    SimulatedMessage.fromLegacy("¡Miren esta foto! 📸", senderId: "valeria-hdz", minutesAgo: 5),
                    SimulatedMessage.fromLegacy("El estadio se ve increíble", senderId: "valeria-hdz", minutesAgo: 4),
                    SimulatedMessage.fromLegacy("Voy a publicarla en Instagram", senderId: "valeria-hdz", minutesAgo: 3)
                ]
            ),

            // Hijo menor - ¡PERDIDO!
            MockGroupMember(
                peerID: "mateo-hdz",
                nickname: "Mateo",
                relationshipTag: "Hijo",
                location: estadioAztecaLocation(section: .section7C, row: 25, seat: 8),
                connectionStatus: .indirect,
                uwbDistance: nil,
                lastSeenMinutesAgo: 18,
                batteryLevel: 95,
                isLost: true,
                recentMessages: [
                    SimulatedMessage.fromLegacy("Papá no sé dónde estoy 😰", senderId: "mateo-hdz", minutesAgo: 19),
                    SimulatedMessage.fromLegacy("Hay mucha gente", senderId: "mateo-hdz", minutesAgo: 18),
                    SimulatedMessage.fromLegacy("Tengo miedo", senderId: "mateo-hdz", minutesAgo: 18)
                ]
            ),

            // Tío - Ayudando a buscar
            MockGroupMember(
                peerID: "ricardo-tio",
                nickname: "Ricardo",
                relationshipTag: "Tío",
                location: estadioAztecaLocation(section: .section5A, row: 18, seat: 12),
                connectionStatus: .online,
                uwbDistance: 28.5,
                lastSeenMinutesAgo: 5,
                batteryLevel: 70,
                recentMessages: [
                    SimulatedMessage.fromLegacy("Voy a buscar a Mateo", senderId: "ricardo-tio", minutesAgo: 7),
                    SimulatedMessage.fromLegacy("Estoy revisando la sección 5", senderId: "ricardo-tio", minutesAgo: 6),
                    SimulatedMessage.fromLegacy("Manden su ubicación LinkFinder", senderId: "ricardo-tio", minutesAgo: 5)
                ]
            )
        ]
    )

    // MARK: - Helper Methods

    /// Generate realistic location within Estadio Azteca
    private static func estadioAztecaLocation(
        section: EstadioSection,
        row: Int,
        seat: Int
    ) -> UserLocation {
        // Estadio Azteca: 19.302778, -99.150556
        let baseLatitude: Double = 19.302778
        let baseLongitude: Double = -99.150556

        // Calculate offset based on section and seat
        // Stadium is roughly 200m diameter, sections distributed around
        let (latOffset, lonOffset) = section.coordinateOffset(row: row, seat: seat)

        return UserLocation(
            latitude: baseLatitude + latOffset,
            longitude: baseLongitude + lonOffset,
            accuracy: 10.0,
            timestamp: Date()
        )
    }

    /// All available scenarios
    static var allScenarios: [MockFamilyGroupData] {
        return [
            familiaGonzalez,
            amigosUniversidad,
            familiaEmergencia,
            familiaMundial2026
        ]
    }

    /// Get scenario by type
    static func scenario(_ type: ScenarioType) -> MockFamilyGroupData {
        switch type {
        case .familiaEnPartido:
            return familiaGonzalez
        case .estudiantesUNAM:
            return amigosUniversidad
        case .emergenciaMedica:
            return familiaEmergencia
        case .mundial2026:
            return familiaMundial2026
        }
    }
}

// MARK: - Supporting Models

/// Stadium sections with coordinate mapping
enum EstadioSection {
    case section3A, section3B
    case section4A, section4B, section4C
    case section5A, section5B
    case section6A
    case section7C
    case banos
    case concesiones
    case entradaNorte

    /// Calculate coordinate offset from center based on section
    func coordinateOffset(row: Int, seat: Int) -> (lat: Double, lon: Double) {
        // Each degree of latitude ≈ 111km, longitude ≈ 85km at this latitude
        // Stadium radius ≈ 100m = 0.0009° lat, 0.00118° lon

        let rowOffset = Double(row) * 0.00003 // ~3.3m per row
        let seatOffset = Double(seat) * 0.00002 // ~1.7m per seat

        switch self {
        case .section3A:
            return (0.0004 + rowOffset, -0.0005 + seatOffset) // North section
        case .section3B:
            return (0.0004 + rowOffset, 0.0005 + seatOffset)
        case .section4A:
            return (0.0002 + rowOffset, -0.0007 + seatOffset) // Northwest
        case .section4B:
            return (0.0002 + rowOffset, -0.0003 + seatOffset)
        case .section4C:
            return (0.0002 + rowOffset, 0.0003 + seatOffset)
        case .section5A:
            return (-0.0002 + rowOffset, -0.0005 + seatOffset) // West
        case .section5B:
            return (-0.0002 + rowOffset, 0.0005 + seatOffset)
        case .section6A:
            return (-0.0005 + rowOffset, 0.0003 + seatOffset) // South
        case .section7C:
            return (-0.0007 + rowOffset, 0.0008 + seatOffset)
        case .banos:
            return (0.0001, -0.0009) // Bathrooms northwest
        case .concesiones:
            return (0.0001, 0.0009) // Concessions northeast
        case .entradaNorte:
            return (0.0008, 0.0000) // North entrance
        }
    }
}

/// Connection status for mock members
enum MockConnectionStatus: String, Codable {
    case online = "online"           // Connected via LinkFinder/MultipeerConnectivity
    case away = "away"               // Connected but not responding
    case indirect = "indirect"       // Reachable through mesh routing
    case offline = "offline"         // Not reachable
}

/// Health alerts
enum HealthAlert: String, Codable {
    case none
    case elevatedHeartRate
    case irregularHeartbeat
    case lowBloodPressure
    case fall
}

/// Scenario types
enum ScenarioType: String, CaseIterable, Identifiable {
    case familiaEnPartido = "Familia en el Partido"
    case estudiantesUNAM = "Estudiantes UNAM"
    case emergenciaMedica = "Emergencia Médica"
    case mundial2026 = "Mundial 2026"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .familiaEnPartido: return "person.3.fill"
        case .estudiantesUNAM: return "graduationcap.fill"
        case .emergenciaMedica: return "cross.case.fill"
        case .mundial2026: return "soccerball"
        }
    }

    var description: String {
        switch self {
        case .familiaEnPartido:
            return "Familia González disfrutando del partido México vs Canadá"
        case .estudiantesUNAM:
            return "Grupo de estudiantes de Ingeniería UNAM en el estadio"
        case .emergenciaMedica:
            return "Familia Martínez con emergencia médica (adulto mayor)"
        case .mundial2026:
            return "Familia Hernández en el Mundial FIFA 2026 - México vs Argentina"
        }
    }
}

// MARK: - Mock Family Group Data

/// Complete mock family group with all data
struct MockFamilyGroupData: Identifiable {
    let id: UUID
    let name: String
    let code: String
    let createdAt: Date
    let creatorPeerID: String
    let scenario: ScenarioType
    var members: [MockGroupMember]

    /// Convert to real FamilyGroup
    func toFamilyGroup() -> FamilyGroup {
        guard let groupCode = FamilyGroupCode(rawCode: code) else {
            fatalError("Invalid group code: \(code)")
        }

        let familyMembers = members.map { $0.toFamilyMember() }

        return FamilyGroup(
            id: id,
            name: name,
            code: groupCode,
            createdAt: createdAt,
            members: familyMembers,
            creatorPeerID: creatorPeerID
        )
    }

    /// Get online members count
    var onlineMembersCount: Int {
        members.filter { $0.connectionStatus == .online }.count
    }

    /// Get members needing help
    var membersNeedingHelp: [MockGroupMember] {
        members.filter { $0.isLost || $0.hasActiveEmergency || $0.healthAlert != .none }
    }
}

// MARK: - Mock Group Member

/// Individual mock member with complete data
struct MockGroupMember: Identifiable {
    let id: UUID
    let peerID: String
    let nickname: String
    let relationshipTag: String?
    var location: UserLocation
    var connectionStatus: MockConnectionStatus
    var uwbDistance: Float? // Distance in meters (nil if no LinkFinder)
    var lastSeenMinutesAgo: Int
    var batteryLevel: Int // 0-100
    var isCurrentDevice: Bool
    var hasActiveEmergency: Bool
    var healthAlert: HealthAlert
    var isLost: Bool
    var recentMessages: [SimulatedMessage]

    init(
        id: UUID = UUID(),
        peerID: String,
        nickname: String,
        relationshipTag: String?,
        location: UserLocation,
        connectionStatus: MockConnectionStatus,
        uwbDistance: Float?,
        lastSeenMinutesAgo: Int,
        batteryLevel: Int,
        isCurrentDevice: Bool = false,
        hasActiveEmergency: Bool = false,
        healthAlert: HealthAlert = .none,
        isLost: Bool = false,
        recentMessages: [SimulatedMessage] = []
    ) {
        self.id = id
        self.peerID = peerID
        self.nickname = nickname
        self.relationshipTag = relationshipTag
        self.location = location
        self.connectionStatus = connectionStatus
        self.uwbDistance = uwbDistance
        self.lastSeenMinutesAgo = lastSeenMinutesAgo
        self.batteryLevel = batteryLevel
        self.isCurrentDevice = isCurrentDevice
        self.hasActiveEmergency = hasActiveEmergency
        self.healthAlert = healthAlert
        self.isLost = isLost
        self.recentMessages = recentMessages
    }

    /// Convert to real FamilyMember
    func toFamilyMember() -> FamilyMember {
        let lastSeenDate = Date().addingTimeInterval(-Double(lastSeenMinutesAgo * 60))

        return FamilyMember(
            id: id,
            peerID: peerID,
            nickname: nickname,
            relationshipTag: relationshipTag,
            lastSeenDate: lastSeenDate,
            lastKnownLocation: location,
            isCurrentDevice: isCurrentDevice
        )
    }

    /// Display name
    var displayName: String {
        if let tag = relationshipTag {
            return "\(nickname) (\(tag))"
        }
        return nickname
    }

    /// Connection status icon
    var statusIcon: String {
        switch connectionStatus {
        case .online: return "circle.fill"
        case .away: return "moon.fill"
        case .indirect: return "circle.dotted"
        case .offline: return "circle"
        }
    }

    /// Status color name
    var statusColor: String {
        switch connectionStatus {
        case .online: return "green"
        case .away: return "orange"
        case .indirect: return "yellow"
        case .offline: return "gray"
        }
    }

    /// Needs attention
    var needsAttention: Bool {
        isLost || hasActiveEmergency || healthAlert != .none || batteryLevel < 20
    }
}
