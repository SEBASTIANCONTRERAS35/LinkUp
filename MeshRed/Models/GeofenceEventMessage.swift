//
//  GeofenceEventMessage.swift
//  MeshRed
//
//  Created by Claude for StadiumConnect Pro - Geofencing System
//

import Foundation

/// Represents a geofence entry/exit event sent to family members via mesh
struct GeofenceEventMessage: Codable, Identifiable {
    let id: UUID
    let senderId: String                     // PeerID of device that crossed boundary
    let senderNickname: String?              // Display name: "Mamá", "Papá"
    let geofenceId: UUID                     // Which geofence was crossed
    let geofenceName: String                 // Name of the place: "Estadio Azteca"
    let eventType: GeofenceEventType         // Entry or exit
    let timestamp: Date
    let location: UserLocation               // Current GPS location
    let familyGroupCode: FamilyGroupCode     // Only family members can see this

    init(
        senderId: String,
        senderNickname: String?,
        geofence: CustomGeofence,
        eventType: GeofenceEventType,
        location: UserLocation,
        familyGroupCode: FamilyGroupCode
    ) {
        self.id = UUID()
        self.senderId = senderId
        self.senderNickname = senderNickname
        self.geofenceId = geofence.id
        self.geofenceName = geofence.name
        self.eventType = eventType
        self.timestamp = Date()
        self.location = location
        self.familyGroupCode = familyGroupCode
    }

    /// Display text for notifications
    var displayText: String {
        let action = eventType == .entry ? "entró a" : "salió de"
        let name = senderNickname ?? senderId
        return "\(name) \(action) \(geofenceName)"
    }

    /// Emoji for notification
    var emoji: String {
        return eventType == .entry ? "✅" : "⚠️"
    }
}

enum GeofenceEventType: String, Codable {
    case entry = "entry"
    case exit = "exit"

    var displayName: String {
        switch self {
        case .entry: return "Entrada"
        case .exit: return "Salida"
        }
    }
}
