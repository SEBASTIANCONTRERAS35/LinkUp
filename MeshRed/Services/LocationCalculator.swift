//
//  LocationCalculator.swift
//  MeshRed
//
//  Created by Emilio Contreras on 29/09/25.
//

import Foundation
import CoreLocation

/// Utility for calculating positions from triangulated location data
struct LocationCalculator {

    // Earth's radius in meters (for bearing/distance calculations)
    private static let earthRadiusMeters: Double = 6371000.0

    /// Calculate approximate location of target using intermediary's GPS and UWB data
    /// - Parameters:
    ///   - intermediaryLocation: GPS location of intermediary (B)
    ///   - distance: Distance from intermediary to target in meters
    ///   - direction: Optional direction vector from intermediary to target
    /// - Returns: Approximate GPS location of target, or nil if calculation fails
    static func calculateTargetLocation(
        from intermediaryLocation: UserLocation,
        distance: Float,
        direction: DirectionVector?
    ) -> UserLocation? {
        guard let direction = direction else {
            // Without direction, we can't calculate specific location
            // Return intermediary location with accuracy = distance (circle of uncertainty)
            return UserLocation(
                latitude: intermediaryLocation.latitude,
                longitude: intermediaryLocation.longitude,
                accuracy: Double(distance),
                timestamp: Date()
            )
        }

        // Calculate bearing from direction vector
        let bearing = direction.bearing

        // Calculate destination coordinates using bearing and distance
        let destination = calculateDestination(
            from: intermediaryLocation.toCLLocation().coordinate,
            bearing: bearing,
            distance: Double(distance)
        )

        // Calculate combined accuracy
        // Accuracy = intermediary GPS accuracy + UWB accuracy + calculation error
        let combinedAccuracy = intermediaryLocation.accuracy + 0.5 + 1.0  // Conservative estimate

        return UserLocation(
            latitude: destination.latitude,
            longitude: destination.longitude,
            accuracy: combinedAccuracy,
            timestamp: Date()
        )
    }

    /// Calculate destination coordinate given start point, bearing, and distance
    /// Uses Haversine formula
    private static func calculateDestination(
        from start: CLLocationCoordinate2D,
        bearing: Double,
        distance: Double
    ) -> CLLocationCoordinate2D {
        let lat1 = start.latitude * .pi / 180.0  // Convert to radians
        let lon1 = start.longitude * .pi / 180.0
        let bearingRadians = bearing * .pi / 180.0

        let angularDistance = distance / earthRadiusMeters

        let lat2 = asin(
            sin(lat1) * cos(angularDistance) +
            cos(lat1) * sin(angularDistance) * cos(bearingRadians)
        )

        let lon2 = lon1 + atan2(
            sin(bearingRadians) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(lat2)
        )

        // Convert back to degrees
        let latitude = lat2 * 180.0 / .pi
        let longitude = lon2 * 180.0 / .pi

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Calculate distance between two locations in meters
    static func distance(from location1: UserLocation, to location2: UserLocation) -> Double {
        return location1.distance(to: location2)
    }

    /// Calculate bearing from one location to another in degrees (0° = North, 90° = East)
    static func bearing(from location1: UserLocation, to location2: UserLocation) -> Double {
        let lat1 = location1.latitude * .pi / 180.0
        let lat2 = location2.latitude * .pi / 180.0
        let lon1 = location1.longitude * .pi / 180.0
        let lon2 = location2.longitude * .pi / 180.0

        let dLon = lon2 - lon1

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)

        let bearingRadians = atan2(y, x)
        let bearingDegrees = bearingRadians * 180.0 / .pi

        // Normalize to 0-360
        return bearingDegrees >= 0 ? bearingDegrees : bearingDegrees + 360.0
    }

    /// Format distance for display
    static func formatDistance(_ distance: Double) -> String {
        if distance < 1.0 {
            return String(format: "%.0fcm", distance * 100)
        } else if distance < 10.0 {
            return String(format: "%.1fm", distance)
        } else if distance < 1000.0 {
            return String(format: "%.0fm", distance)
        } else {
            return String(format: "%.2fkm", distance / 1000.0)
        }
    }

    /// Get cardinal direction from bearing
    static func cardinalDirection(from bearing: Double) -> String {
        switch bearing {
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