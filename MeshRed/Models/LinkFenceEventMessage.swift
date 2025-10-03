//
//  LinkFenceEventMessage.swift
//  MeshRed
//
//  Created by Claude for StadiumConnect Pro - Geofencing System
//

import Foundation

/// Represents a linkfence entry/exit event sent to family members via mesh
struct LinkFenceEventMessage: Codable, Identifiable {
    let id: UUID
    let senderId: String                     // PeerID of device that crossed boundary
    let senderNickname: String?              // Display name: "Mamá", "Papá"
    let linkfenceId: UUID                     // Which linkfence was crossed
    let linkfenceName: String                 // Name of the place: "Estadio Azteca"
    let eventType: LinkFenceEventType         // Entry or exit
    let timestamp: Date
    let location: UserLocation               // Current GPS location
    let familyGroupCode: FamilyGroupCode     // Only family members can see this

    init(
        senderId: String,
        senderNickname: String?,
        linkfence: CustomLinkFence,
        eventType: LinkFenceEventType,
        location: UserLocation,
        familyGroupCode: FamilyGroupCode
    ) {
        self.id = UUID()
        self.senderId = senderId
        self.senderNickname = senderNickname
        self.linkfenceId = linkfence.id
        self.linkfenceName = linkfence.name
        self.eventType = eventType
        self.timestamp = location.timestamp  // Use location's timestamp, not current time
        self.location = location
        self.familyGroupCode = familyGroupCode
    }

    /// Display text for notifications
    var displayText: String {
        let action = eventType == .entry ? "entró a" : "salió de"
        let name = senderNickname ?? senderId
        return "\(name) \(action) \(linkfenceName)"
    }

    /// Emoji for notification
    var emoji: String {
        return eventType == .entry ? "✅" : "⚠️"
    }
}

enum LinkFenceEventType: String, Codable {
    case entry = "entry"
    case exit = "exit"

    var displayName: String {
        switch self {
        case .entry: return "Entrada"
        case .exit: return "Salida"
        }
    }
}
