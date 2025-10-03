//
//  RadarCalculator.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Radar positioning calculations for multi-peer LinkFinder visualization
//

import Foundation
import CoreGraphics
import CoreLocation
import SwiftUI
import Combine

class RadarCalculator: ObservableObject {
    // MARK: - Configuration

    let maxRadarRadius: CGFloat
    let maxDisplayDistance: Float  // Maximum distance in meters

    init(maxRadarRadius: CGFloat = 150.0, maxDisplayDistance: Float = 10.0) {
        self.maxRadarRadius = maxRadarRadius
        self.maxDisplayDistance = maxDisplayDistance
    }

    // MARK: - Position Calculation

    /// Calculate precise position from LinkFinder direction + distance
    /// - Parameters:
    ///   - direction: LinkFinder direction vector
    ///   - distance: Distance in meters
    ///   - deviceHeading: Current device compass heading (optional)
    ///   - mode: Radar mode (absolute or relative)
    /// - Returns: CGPoint position in radar coordinates
    func calculatePrecisePosition(
        direction: DirectionVector,
        distance: Float,
        deviceHeading: Double?,
        mode: RadarMode
    ) -> CGPoint {
        // Get bearing from direction vector (0-360°, relative to device)
        let uwbBearing = direction.bearing

        // Convert to absolute bearing if in absolute mode
        let absoluteBearing: Double
        if mode == .absolute, let heading = deviceHeading {
            // Combine LinkFinder bearing with device heading for absolute position
            absoluteBearing = (uwbBearing + heading)
                .truncatingRemainder(dividingBy: 360)
        } else {
            // Use relative bearing
            absoluteBearing = uwbBearing
        }

        // Convert bearing to radians
        let angle = absoluteBearing * .pi / 180.0

        // Normalize distance to radar radius
        let radius = normalizeDistance(distance)

        // Calculate x,y coordinates
        // Note: In SwiftUI, Y increases downward, so we negate cos
        let x = radius * CGFloat(sin(angle))
        let y = -radius * CGFloat(cos(angle))  // -y because Y increases down in SwiftUI

        return CGPoint(x: x, y: y)
    }

    /// Calculate position for peer with GPS location
    func calculateGPSPosition(
        from userLocation: UserLocation,
        to peerLocation: UserLocation,
        deviceHeading: Double?,
        mode: RadarMode
    ) -> CGPoint {
        // Create coordinates from UserLocation
        let fromCoord = CLLocationCoordinate2D(latitude: userLocation.latitude, longitude: userLocation.longitude)
        let toCoord = CLLocationCoordinate2D(latitude: peerLocation.latitude, longitude: peerLocation.longitude)

        // Calculate bearing between two GPS coordinates
        let bearing = calculateBearing(
            from: fromCoord,
            to: toCoord
        )

        // Calculate distance between coordinates
        let distance = calculateDistance(
            from: fromCoord,
            to: toCoord
        )

        // Adjust bearing based on mode
        let finalBearing: Double
        if mode == .absolute {
            // GPS bearing is already absolute (respecto al norte)
            finalBearing = bearing
        } else if let heading = deviceHeading {
            // Convert to relative bearing (respecto al dispositivo)
            finalBearing = (bearing - heading)
                .truncatingRemainder(dividingBy: 360)
        } else {
            finalBearing = bearing
        }

        // Convert to radians and calculate position
        let angle = finalBearing * .pi / 180.0
        let radius = normalizeDistance(Float(distance))

        let x = radius * CGFloat(sin(angle))
        let y = -radius * CGFloat(cos(angle))

        return CGPoint(x: x, y: y)
    }

    /// Distribute peers with only distance (no direction) evenly around a ring
    func calculateRingPositions(
        peersWithDistance: [(peer: String, distance: Float)],
        startAngle: Double = 0
    ) -> [(peer: String, position: CGPoint)] {
        guard !peersWithDistance.isEmpty else { return [] }

        // Distribute evenly around the circle
        let angleStep = 360.0 / Double(peersWithDistance.count)

        return peersWithDistance.enumerated().map { index, peerData in
            let angle = (startAngle + Double(index) * angleStep) * .pi / 180.0
            let radius = normalizeDistance(peerData.distance)

            let x = radius * CGFloat(sin(angle))
            let y = -radius * CGFloat(cos(angle))

            return (peer: peerData.peer, position: CGPoint(x: x, y: y))
        }
    }

    // MARK: - Distance Normalization

    /// Normalize distance to radar radius with logarithmic scale for better visualization
    func normalizeDistance(_ distance: Float) -> CGFloat {
        // Clamp to max display distance
        let clamped = min(distance, maxDisplayDistance)

        // Linear normalization (0.0 - 1.0)
        let normalized = clamped / maxDisplayDistance

        // Apply slight curve for better visual distribution
        // Close objects get more space, far objects compressed
        let curved = pow(normalized, 0.7)

        return CGFloat(curved) * maxRadarRadius
    }

    /// Get display distance string
    func distanceString(for distance: Float) -> String {
        if distance < 1.0 {
            return String(format: "%.0fcm", distance * 100)
        } else {
            return String(format: "%.1fm", distance)
        }
    }

    // MARK: - GPS Calculations

    /// Calculate bearing between two GPS coordinates
    func calculateBearing(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let lon2 = to.longitude * .pi / 180

        let dLon = lon2 - lon1

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x)

        // Convert to degrees and normalize to 0-360
        var degrees = bearing * 180 / .pi
        degrees = degrees >= 0 ? degrees : degrees + 360

        return degrees
    }

    /// Calculate distance between two GPS coordinates (in meters)
    func calculateDistance(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) -> Double {
        let R: Double = 6371000  // Earth's radius in meters

        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let lon2 = to.longitude * .pi / 180

        let dLat = lat2 - lat1
        let dLon = lon2 - lon1

        let a = sin(dLat/2) * sin(dLat/2) +
                cos(lat1) * cos(lat2) *
                sin(dLon/2) * sin(dLon/2)

        let c = 2 * atan2(sqrt(a), sqrt(1-a))

        return R * c
    }
}

// MARK: - Radar Mode

enum RadarMode {
    case absolute      // Fixed to north (with compass)
    case relative      // Fixed to device (without compass)
    case hybrid        // Automatic based on availability

    var displayName: String {
        switch self {
        case .absolute: return "Absoluto (Norte)"
        case .relative: return "Relativo (Dispositivo)"
        case .hybrid: return "Híbrido"
        }
    }

    var icon: String {
        switch self {
        case .absolute: return "location.north.circle.fill"
        case .relative: return "arrow.up.circle.fill"
        case .hybrid: return "arrow.triangle.2.circlepath.circle.fill"
        }
    }
}

// MARK: - Peer Radar Data

struct PeerRadarData: Identifiable {
    let id: String
    let peer: String
    let position: RadarPosition
    let dataSource: DataSource
    let distance: Float?

    enum RadarPosition: Equatable {
        case exact(x: CGFloat, y: CGFloat)           // LinkFinder with direction
        case ring(distance: Float, x: CGFloat, y: CGFloat)  // LinkFinder distance only
        case gps(x: CGFloat, y: CGFloat)            // GPS calculated
        case unknown                                 // No location data

        var point: CGPoint? {
            switch self {
            case .exact(let x, let y): return CGPoint(x: x, y: y)
            case .ring(_, let x, let y): return CGPoint(x: x, y: y)
            case .gps(let x, let y): return CGPoint(x: x, y: y)
            case .unknown: return nil
            }
        }
    }

    enum DataSource {
        case uwbPrecise    // LinkFinder distance + direction
        case uwbDistance   // LinkFinder distance only
        case gps          // GPS shared
        case none         // No location data

        var displayName: String {
            switch self {
            case .uwbPrecise: return "LinkFinder Preciso"
            case .uwbDistance: return "LinkFinder Distancia"
            case .gps: return "GPS"
            case .none: return "Sin datos"
            }
        }

        var color: Color {
            switch self {
            case .uwbPrecise: return Mundial2026Colors.verde
            case .uwbDistance: return Color.orange
            case .gps: return Mundial2026Colors.azul
            case .none: return Color.gray
            }
        }
    }
}
