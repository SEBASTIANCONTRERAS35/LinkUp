//
//  SOSType.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Types of SOS emergencies for stadium events
//

import Foundation
import SwiftUI

// MARK: - SOS Type
enum SOSType: String, CaseIterable, Identifiable {
    case emergenciaMedica = "Emergencia Médica"
    case asistencia = "Asistencia"
    case perdido = "Me Perdí"
    case seguridad = "Seguridad"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .emergenciaMedica:
            return "cross.case.fill"
        case .asistencia:
            return "hand.raised.fill"
        case .perdido:
            return "location.slash.fill"
        case .seguridad:
            return "shield.fill"
        }
    }

    var color: Color {
        switch self {
        case .emergenciaMedica:
            return Mundial2026Colors.rojo
        case .asistencia:
            return Mundial2026Colors.azul
        case .perdido:
            return Mundial2026Colors.verde
        case .seguridad:
            return Color.orange
        }
    }

    var description: String {
        switch self {
        case .emergenciaMedica:
            return "Requiero atención médica urgente"
        case .asistencia:
            return "Necesito ayuda o información"
        case .perdido:
            return "No encuentro a mi grupo"
        case .seguridad:
            return "Situación de riesgo o peligro"
        }
    }

    var priority: Int {
        switch self {
        case .emergenciaMedica:
            return 0 // Máxima prioridad
        case .seguridad:
            return 1
        case .perdido:
            return 2
        case .asistencia:
            return 3
        }
    }
}

// MARK: - SOS Alert Model
struct SOSAlert: Identifiable, Codable {
    let id: UUID
    let type: SOSType
    let senderID: String
    let senderName: String
    let location: UserLocation?
    let timestamp: Date
    let message: String?
    var status: SOSStatus

    init(
        id: UUID = UUID(),
        type: SOSType,
        senderID: String,
        senderName: String,
        location: UserLocation? = nil,
        timestamp: Date = Date(),
        message: String? = nil,
        status: SOSStatus = .pending
    ) {
        self.id = id
        self.type = type
        self.senderID = senderID
        self.senderName = senderName
        self.location = location
        self.timestamp = timestamp
        self.message = message
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case id, senderID, senderName, location, timestamp, message, status
        case typeRawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let typeRaw = try container.decode(String.self, forKey: .typeRawValue)
        type = SOSType(rawValue: typeRaw) ?? .asistencia
        senderID = try container.decode(String.self, forKey: .senderID)
        senderName = try container.decode(String.self, forKey: .senderName)
        location = try container.decodeIfPresent(UserLocation.self, forKey: .location)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        status = try container.decode(SOSStatus.self, forKey: .status)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type.rawValue, forKey: .typeRawValue)
        try container.encode(senderID, forKey: .senderID)
        try container.encode(senderName, forKey: .senderName)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encode(status, forKey: .status)
    }
}

// MARK: - SOS Status
enum SOSStatus: String, Codable {
    case pending = "Pendiente"
    case acknowledged = "Reconocida"
    case responding = "En Camino"
    case resolved = "Resuelta"
    case cancelled = "Cancelada"

    var color: Color {
        switch self {
        case .pending:
            return .orange
        case .acknowledged:
            return .blue
        case .responding:
            return .purple
        case .resolved:
            return .green
        case .cancelled:
            return .gray
        }
    }
}
