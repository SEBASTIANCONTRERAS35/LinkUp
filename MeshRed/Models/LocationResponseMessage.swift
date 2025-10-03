//
//  LocationResponseMessage.swift
//  MeshRed
//
//  Created by Emilio Contreras on 29/09/25.
//

import Foundation

/// Response to a location request
/// Can be either direct (target responds with their GPS) or triangulated (intermediary responds with relative position)
struct LocationResponseMessage: Codable, Identifiable {
    let id: UUID                         // Response ID
    let requestId: UUID                  // ID of the original request
    let responderId: String              // Peer responding (can be target or intermediary)
    let targetId: String                 // Original target of the request
    let responseType: ResponseType
    let timestamp: Date

    // For direct responses
    let directLocation: UserLocation?

    // For triangulated responses
    let relativeLocation: RelativeLocation?

    init(
        id: UUID = UUID(),
        requestId: UUID,
        responderId: String,
        targetId: String,
        responseType: ResponseType,
        timestamp: Date = Date(),
        directLocation: UserLocation? = nil,
        relativeLocation: RelativeLocation? = nil
    ) {
        self.id = id
        self.requestId = requestId
        self.responderId = responderId
        self.targetId = targetId
        self.responseType = responseType
        self.timestamp = timestamp
        self.directLocation = directLocation
        self.relativeLocation = relativeLocation
    }

    /// Create a direct response (target responds with their GPS)
    static func directResponse(
        requestId: UUID,
        targetId: String,
        location: UserLocation
    ) -> LocationResponseMessage {
        return LocationResponseMessage(
            requestId: requestId,
            responderId: targetId,
            targetId: targetId,
            responseType: .direct,
            directLocation: location
        )
    }

    /// Create a LinkFinder direct response (target responds with LinkFinder distance/direction to requester)
    static func uwbDirectResponse(
        requestId: UUID,
        targetId: String,
        distance: Float,
        direction: DirectionVector?,
        accuracy: Float = 0.5
    ) -> LocationResponseMessage {
        // Create a RelativeLocation without intermediary GPS (using zeros as placeholder)
        let placeholderLocation = UserLocation(latitude: 0, longitude: 0, accuracy: 0)
        let relativeLocation = RelativeLocation(
            intermediaryId: targetId,  // Target is reporting their own position
            intermediaryLocation: placeholderLocation,
            targetDistance: distance,
            targetDirection: direction,
            accuracy: accuracy
        )

        return LocationResponseMessage(
            requestId: requestId,
            responderId: targetId,
            targetId: targetId,
            responseType: .uwbDirect,
            relativeLocation: relativeLocation
        )
    }

    /// Create a triangulated response (intermediary responds with relative position) - DEPRECATED
    static func triangulatedResponse(
        requestId: UUID,
        intermediaryId: String,
        targetId: String,
        relativeLocation: RelativeLocation
    ) -> LocationResponseMessage {
        return LocationResponseMessage(
            requestId: requestId,
            responderId: intermediaryId,
            targetId: targetId,
            responseType: .triangulated,
            relativeLocation: relativeLocation
        )
    }

    /// Create an unavailable response (location cannot be determined)
    static func unavailableResponse(
        requestId: UUID,
        responderId: String,
        targetId: String,
        reason: String? = nil
    ) -> LocationResponseMessage {
        return LocationResponseMessage(
            requestId: requestId,
            responderId: responderId,
            targetId: targetId,
            responseType: .unavailable
        )
    }

    enum ResponseType: String, Codable {
        case direct = "direct"              // Target responded with their GPS
        case uwbDirect = "uwbDirect"        // Target responded with LinkFinder distance/direction to requester
        case triangulated = "triangulated"  // Intermediary responded with LinkFinder-based relative position (deprecated)
        case unavailable = "unavailable"    // Location unavailable (permission denied, GPS off, etc.)
    }

    /// Human-readable description of the response
    var description: String {
        switch responseType {
        case .direct:
            if let loc = directLocation {
                return "Ubicación directa: \(loc.coordinateString) (\(loc.accuracyString))"
            }
            return "Ubicación directa (sin datos)"

        case .uwbDirect:
            if let rel = relativeLocation {
                return "Ubicación LinkFinder: \(rel.distanceString) \(rel.directionString ?? "sin dirección") (±\(String(format: "%.1f", rel.accuracy))m)"
            }
            return "Ubicación LinkFinder (sin datos)"

        case .triangulated:
            if let rel = relativeLocation {
                return "Ubicación triangulada: \(rel.description)"
            }
            return "Ubicación triangulada (sin datos)"

        case .unavailable:
            return "Ubicación no disponible"
        }
    }
}