//
//  NavigationCalculator.swift
//  MeshRed
//
//  Created by Emilio Contreras on 30/09/25.
//

import Foundation
import CoreLocation

/// Advanced navigation calculations for hybrid GPS + UWB navigation
struct NavigationCalculator {

    // MARK: - Relative Bearing Calculation

    /// Calculate relative bearing from user to target, adjusted for user's current heading
    /// - Parameters:
    ///   - from: User's current GPS location
    ///   - to: Target peer's GPS location
    ///   - userHeading: User's compass heading in degrees (0° = North)
    /// - Returns: Relative bearing in degrees (0° = straight ahead, 90° = right, -90° = left)
    static func calculateRelativeBearing(
        from: UserLocation,
        to: UserLocation,
        userHeading: Double
    ) -> Double {
        // Calculate absolute bearing from user to target
        let absoluteBearing = LocationCalculator.bearing(from: from, to: to)

        // Calculate relative bearing (target bearing relative to user's heading)
        var relativeBearing = absoluteBearing - userHeading

        // Normalize to -180 to +180 range
        while relativeBearing > 180 {
            relativeBearing -= 360
        }
        while relativeBearing < -180 {
            relativeBearing += 360
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🧭 RELATIVE BEARING CALCULATION")
        print("   User location: \(from.coordinateString)")
        print("   Target location: \(to.coordinateString)")
        print("   Absolute bearing: \(String(format: "%.1f", absoluteBearing))° (\(LocationCalculator.cardinalDirection(from: absoluteBearing)))")
        print("   User heading: \(String(format: "%.1f", userHeading))°")
        print("   Relative bearing: \(String(format: "%.1f", relativeBearing))°")
        print("   Direction: \(relativeDirectionDescription(relativeBearing))")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        return relativeBearing
    }

    /// Get human-readable description of relative direction
    private static func relativeDirectionDescription(_ bearing: Double) -> String {
        switch abs(bearing) {
        case 0..<15:
            return "Straight ahead"
        case 15..<45:
            return bearing > 0 ? "Slightly right" : "Slightly left"
        case 45..<90:
            return bearing > 0 ? "Right" : "Left"
        case 90..<135:
            return bearing > 0 ? "Sharp right" : "Sharp left"
        case 135..<180:
            return "Behind you"
        default:
            return "Behind you"
        }
    }

    // MARK: - Walking Triangulation

    /// Represents a single triangulation reading (position + distance)
    struct TriangulationReading {
        let userLocation: UserLocation      // GPS position when reading was taken
        let distanceToTarget: Float         // UWB distance to target at this position
        let timestamp: Date

        var coordinateString: String {
            return userLocation.coordinateString + " (d=\(String(format: "%.2f", distanceToTarget))m)"
        }
    }

    /// Calculate target position using two triangulation readings (circle-circle intersection)
    /// - Parameters:
    ///   - reading1: First position + distance reading
    ///   - reading2: Second position + distance reading
    /// - Returns: Estimated target GPS coordinates, or nil if calculation fails
    static func calculateTriangulatedPosition(
        reading1: TriangulationReading,
        reading2: TriangulationReading
    ) -> CLLocationCoordinate2D? {

        let loc1 = reading1.userLocation.toCLLocation().coordinate
        let loc2 = reading2.userLocation.toCLLocation().coordinate
        let r1 = Double(reading1.distanceToTarget)
        let r2 = Double(reading2.distanceToTarget)

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📐 TRIANGULATION CALCULATION")
        print("   Reading 1: \(reading1.coordinateString)")
        print("   Reading 2: \(reading2.coordinateString)")

        // Calculate distance between two reading positions
        let d = CLLocation(latitude: loc1.latitude, longitude: loc1.longitude)
            .distance(from: CLLocation(latitude: loc2.latitude, longitude: loc2.longitude))

        print("   Distance between readings: \(String(format: "%.2f", d))m")

        // Check if circles intersect
        guard d <= r1 + r2 && d >= abs(r1 - r2) && d > 0 else {
            print("   ❌ Circles don't intersect or readings too close")
            print("   Condition: d(\(String(format: "%.2f", d))) should be between \(String(format: "%.2f", abs(r1 - r2))) and \(String(format: "%.2f", r1 + r2))")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            return nil
        }

        // Calculate intersection points using circle-circle intersection formula
        // a = (r1² - r2² + d²) / (2d)
        let a = (r1 * r1 - r2 * r2 + d * d) / (2 * d)

        // h² = r1² - a²
        let hSquared = r1 * r1 - a * a
        guard hSquared >= 0 else {
            print("   ❌ No valid intersection (h² < 0)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            return nil
        }

        let h = sqrt(hSquared)

        // Calculate point P2 (midpoint along line between centers)
        // P2 = P1 + (a/d) * (P2 - P1)
        let lat1Rad = loc1.latitude * .pi / 180.0
        let lon1Rad = loc1.longitude * .pi / 180.0
        let lat2Rad = loc2.latitude * .pi / 180.0
        let lon2Rad = loc2.longitude * .pi / 180.0

        // Bearing from loc1 to loc2
        let bearing = atan2(
            sin(lon2Rad - lon1Rad) * cos(lat2Rad),
            cos(lat1Rad) * sin(lat2Rad) - sin(lat1Rad) * cos(lat2Rad) * cos(lon2Rad - lon1Rad)
        )

        // Calculate P2 (point along line between centers at distance 'a')
        let p2 = calculateDestination(from: loc1, bearing: bearing * 180.0 / .pi, distance: a)

        // Calculate two possible intersection points
        // perpendicular bearing (±90°)
        let perpendicularBearing1 = (bearing * 180.0 / .pi) + 90.0
        let perpendicularBearing2 = (bearing * 180.0 / .pi) - 90.0

        let intersection1 = calculateDestination(from: p2, bearing: perpendicularBearing1, distance: h)
        let intersection2 = calculateDestination(from: p2, bearing: perpendicularBearing2, distance: h)

        print("   ✅ Two possible positions:")
        print("      Option 1: \(String(format: "%.6f, %.6f", intersection1.latitude, intersection1.longitude))")
        print("      Option 2: \(String(format: "%.6f, %.6f", intersection2.latitude, intersection2.longitude))")

        // If readings are very close in time, choose the intersection point closer to the midpoint
        // (more likely to be the actual position)
        let midpoint = CLLocationCoordinate2D(
            latitude: (loc1.latitude + loc2.latitude) / 2.0,
            longitude: (loc1.longitude + loc2.longitude) / 2.0
        )

        let dist1 = CLLocation(latitude: intersection1.latitude, longitude: intersection1.longitude)
            .distance(from: CLLocation(latitude: midpoint.latitude, longitude: midpoint.longitude))
        let dist2 = CLLocation(latitude: intersection2.latitude, longitude: intersection2.longitude)
            .distance(from: CLLocation(latitude: midpoint.latitude, longitude: midpoint.longitude))

        let selectedIntersection = dist1 < dist2 ? intersection1 : intersection2

        print("   📍 Selected position: \(String(format: "%.6f, %.6f", selectedIntersection.latitude, selectedIntersection.longitude))")
        print("      (closer to midpoint)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        return selectedIntersection
    }

    // MARK: - Helper Methods

    /// Calculate destination coordinate given start point, bearing, and distance
    /// Uses Haversine formula (same as LocationCalculator but made accessible here)
    private static func calculateDestination(
        from start: CLLocationCoordinate2D,
        bearing: Double,
        distance: Double
    ) -> CLLocationCoordinate2D {
        let earthRadiusMeters: Double = 6371000.0

        let lat1 = start.latitude * .pi / 180.0
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

        let latitude = lat2 * 180.0 / .pi
        let longitude = lon2 * 180.0 / .pi

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Validate if two triangulation readings are suitable for calculation
    /// - Parameters:
    ///   - reading1: First reading
    ///   - reading2: Second reading
    /// - Returns: Validation result with error message if invalid
    static func validateTriangulationReadings(
        reading1: TriangulationReading,
        reading2: TriangulationReading
    ) -> (isValid: Bool, errorMessage: String?) {

        // Check 1: Readings should not be too close together
        let distanceBetween = reading1.userLocation.distance(to: reading2.userLocation)

        guard distanceBetween >= 5.0 else {
            return (false, "Las lecturas están muy cerca. Camina al menos 5 metros antes de tomar la segunda lectura.")
        }

        // Check 2: Circles should intersect
        let r1 = Double(reading1.distanceToTarget)
        let r2 = Double(reading2.distanceToTarget)

        guard distanceBetween <= r1 + r2 else {
            return (false, "Las lecturas están muy separadas. El objetivo debe estar dentro del alcance de ambas posiciones.")
        }

        guard distanceBetween >= abs(r1 - r2) else {
            return (false, "Una lectura está completamente dentro de la otra. Camina en dirección perpendicular.")
        }

        // Check 3: Readings should be reasonably recent (within 2 minutes)
        let timeDifference = abs(reading1.timestamp.timeIntervalSince(reading2.timestamp))
        guard timeDifference < 120.0 else {
            return (false, "Las lecturas están muy separadas en el tiempo (\(Int(timeDifference))s). El objetivo puede haberse movido.")
        }

        return (true, nil)
    }

    /// Calculate estimated accuracy of triangulated position
    /// - Parameters:
    ///   - reading1: First reading
    ///   - reading2: Second reading
    /// - Returns: Estimated accuracy in meters
    static func estimateTriangulationAccuracy(
        reading1: TriangulationReading,
        reading2: TriangulationReading
    ) -> Double {
        // Accuracy depends on:
        // 1. GPS accuracy of both readings
        // 2. UWB accuracy (typically ±0.5m)
        // 3. Geometry (angle between readings - better if closer to 90°)

        let gpsAccuracy1 = reading1.userLocation.accuracy
        let gpsAccuracy2 = reading2.userLocation.accuracy
        let uwbAccuracy = 0.5  // UWB typical accuracy

        // Combined accuracy (conservative estimate)
        let combinedAccuracy = max(gpsAccuracy1, gpsAccuracy2) + uwbAccuracy + 2.0

        return combinedAccuracy
    }
}
