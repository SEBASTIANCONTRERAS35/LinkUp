//
//  GeofenceShareMessage.swift
//  MeshRed
//
//  Created by Claude for StadiumConnect Pro - Geofencing System
//

import Foundation

/// Represents a geofence being shared with family members via mesh
struct GeofenceShareMessage: Codable {
    let id: UUID
    let senderId: String                     // Who is sharing
    let geofence: CustomGeofence             // Complete geofence data
    let familyGroupCode: FamilyGroupCode     // Only family members receive this
    let timestamp: Date
    let message: String?                     // Optional message: "Nos vemos aquí"

    init(
        senderId: String,
        geofence: CustomGeofence,
        familyGroupCode: FamilyGroupCode,
        message: String? = nil
    ) {
        self.id = UUID()
        self.senderId = senderId
        self.geofence = geofence
        self.familyGroupCode = familyGroupCode
        self.timestamp = Date()
        self.message = message
    }

    /// Display text for notifications
    var displayText: String {
        return "\(senderId) compartió '\(geofence.name)'"
    }
}
