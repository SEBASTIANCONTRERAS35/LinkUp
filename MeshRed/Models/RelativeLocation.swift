//
//  RelativeLocation.swift
//  MeshRed
//
//  Created by Emilio Contreras on 29/09/25.
//

import Foundation
import simd

/// Represents a location measured relative to an intermediary peer using UWB
/// Example: "C is 15.3m northeast of B"
struct RelativeLocation: Codable, Equatable {
    let intermediaryId: String           // ID of the peer that measured (B)
    let intermediaryLocation: UserLocation  // GPS location of intermediary (B's position)
    let targetDistance: Float            // Distance from intermediary to target in meters
    let targetDirection: DirectionVector? // Direction vector (can be nil if only distance available)
    let accuracy: Float                  // Measurement accuracy in meters
    let timestamp: Date

    init(
        intermediaryId: String,
        intermediaryLocation: UserLocation,
        targetDistance: Float,
        targetDirection: DirectionVector? = nil,
        accuracy: Float,
        timestamp: Date = Date()
    ) {
        self.intermediaryId = intermediaryId
        self.intermediaryLocation = intermediaryLocation
        self.targetDistance = targetDistance
        self.targetDirection = targetDirection
        self.accuracy = accuracy
        self.timestamp = timestamp
    }

    /// Human-readable distance string
    var distanceString: String {
        if targetDistance < 1.0 {
            return String(format: "%.1fcm", targetDistance * 100)
        } else {
            return String(format: "%.1fm", targetDistance)
        }
    }

    /// Human-readable direction string
    var directionString: String? {
        guard let direction = targetDirection else { return nil }
        return direction.cardinalDirection
    }

    /// Full description
    var description: String {
        var desc = "A \(distanceString)"
        if let dir = directionString {
            desc += " hacia el \(dir)"
        }
        desc += " de \(intermediaryId)"
        return desc
    }
}

/// Represents a 3D direction vector from UWB ranging
struct DirectionVector: Codable, Equatable {
    let x: Float
    let y: Float
    let z: Float

    init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// Initialize from SIMD3<Float>
    init(from simd: SIMD3<Float>) {
        self.x = simd.x
        self.y = simd.y
        self.z = simd.z
    }

    /// Convert to SIMD3<Float>
    func toSIMD() -> SIMD3<Float> {
        return SIMD3<Float>(x: x, y: y, z: z)
    }

    /// Calculate bearing in degrees (0° = North, 90° = East)
    /// Uses horizontal plane projection (x, z) ignoring vertical component (y)
    /// In Apple's coordinate system: +x = right, -z = forward (north)
    var bearing: Double {
        // For horizontal navigation, use x (east-west) and z (north-south)
        // Note: -z is forward/north in Apple's coordinate system
        let radians = atan2(Double(x), Double(-z))
        let degrees = radians * 180.0 / .pi
        // atan2 gives us angle from north, normalize to 0-360°
        let normalizedBearing = degrees >= 0 ? degrees : degrees + 360.0

        // 🔍 DEBUG: Log bearing calculation
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🧭 BEARING CALCULATION")
        print("   Direction Vector: x=\(x), y=\(y), z=\(z)")
        print("   atan2(x=\(x), -z=\(-z)) = \(radians) rad")
        print("   Degrees: \(degrees)°")
        print("   Normalized: \(normalizedBearing)°")
        print("   Cardinal: \(cardinalDirection)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        return normalizedBearing
    }

    /// Get cardinal direction (N, NE, E, SE, S, SW, W, NW)
    var cardinalDirection: String {
        let b = bearing

        switch b {
        case 337.5..<360.0, 0..<22.5:
            return "Norte"
        case 22.5..<67.5:
            return "Noreste"
        case 67.5..<112.5:
            return "Este"
        case 112.5..<157.5:
            return "Sureste"
        case 157.5..<202.5:
            return "Sur"
        case 202.5..<247.5:
            return "Suroeste"
        case 247.5..<292.5:
            return "Oeste"
        case 292.5..<337.5:
            return "Noroeste"
        default:
            return "Desconocido"
        }
    }
}