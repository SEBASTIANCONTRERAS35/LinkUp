//
//  LinkFenceShareMessage.swift
//  MeshRed
//
//  Created by Claude for StadiumConnect Pro - Geofencing System
//

import Foundation

/// Represents a linkfence being shared with family members via mesh
struct LinkFenceShareMessage: Codable {
    let id: UUID
    let senderId: String                     // Who is sharing
    let linkfence: CustomLinkFence             // Complete linkfence data
    let familyGroupCode: FamilyGroupCode     // Only family members receive this
    let timestamp: Date
    let message: String?                     // Optional message: "Nos vemos aquí"

    init(
        senderId: String,
        linkfence: CustomLinkFence,
        familyGroupCode: FamilyGroupCode,
        message: String? = nil
    ) {
        self.id = UUID()
        self.senderId = senderId
        self.linkfence = linkfence
        self.familyGroupCode = familyGroupCode
        self.timestamp = Date()
        self.message = message
    }

    /// Display text for notifications
    var displayText: String {
        return "\(senderId) compartió '\(linkfence.name)'"
    }
}
