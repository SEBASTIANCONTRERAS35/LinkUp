//
//  FallbackDirectionService.swift
//  MeshRed
//
//  Fallback direction calculation for devices without UWB
//  Uses compass, GPS, and motion sensors to provide approximate direction
//

import Foundation
import CoreLocation
import CoreMotion
import Combine
import MultipeerConnectivity
import NearbyInteraction
import os

/// Service that provides approximate direction to peers when UWB is not available
class FallbackDirectionService: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var currentHeading: CLHeading?
    @Published var currentLocation: CLLocation?
    @Published var isCompassAvailable: Bool = false
    @Published var fallbackDirections: [String: FallbackDirection] = [:] // PeerID -> Direction

    // MARK: - Private Properties
    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    private var peerLocations: [String: CLLocation] = [:]
    private let updateQueue = DispatchQueue(label: "fallback.direction", qos: .userInteractive)

    // MARK: - Initialization
    override init() {
        super.init()
        setupLocationManager()
        checkCompassAvailability()
    }

    // FIXED: Add deinit to ensure resources are freed
    deinit {
        LoggingService.network.info("🧹 FallbackDirectionService: deinit - cleaning up resources")

        // Stop all tracking
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        locationManager.delegate = nil

        motionManager.stopDeviceMotionUpdates()

        // Clear all data
        peerLocations.removeAll()
        fallbackDirections.removeAll()

        LoggingService.network.info("✅ FallbackDirectionService: Resources freed")
    }

    // MARK: - Setup
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.headingFilter = 5.0 // Update every 5 degrees
        locationManager.distanceFilter = 1.0 // Update every 1 meter

        // Request authorization
        locationManager.requestWhenInUseAuthorization()
    }

    private func checkCompassAvailability() {
        isCompassAvailable = CLLocationManager.headingAvailable()

        if isCompassAvailable {
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            LoggingService.network.info("🧭 FALLBACK DIRECTION SERVICE")
            LoggingService.network.info("   Compass: ✅ Available")
            LoggingService.network.info("   GPS: \(CLLocationManager.locationServicesEnabled() ? "✅ Available" : "❌ Not available")")
            LoggingService.network.info("   Motion: \(self.motionManager.isDeviceMotionAvailable ? "✅ Available" : "❌ Not available", privacy: .public)")
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        } else {
            LoggingService.network.info("⚠️ FallbackDirectionService: Compass not available on this device")
        }
    }

    // MARK: - Public Methods

    /// Start fallback direction tracking
    func startTracking() {
        guard isCompassAvailable else {
            LoggingService.network.info("❌ FallbackDirectionService: Cannot start - compass not available")
            return
        }

        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()

        // Start motion updates for device orientation
        if motionManager.isDeviceMotionAvailable {
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
                if let motion = motion {
                    self?.processDeviceMotion(motion)
                }
            }
        }

        LoggingService.network.info("🧭 FallbackDirectionService: Started tracking")
    }

    /// Stop fallback direction tracking
    func stopTracking() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        motionManager.stopDeviceMotionUpdates()

        LoggingService.network.info("🧭 FallbackDirectionService: Stopped tracking")
    }

    /// Update peer's location for direction calculation
    func updatePeerLocation(_ location: CLLocation, for peerId: String) {
        updateQueue.async { [weak self] in
            self?.peerLocations[peerId] = location
            self?.calculateFallbackDirection(for: peerId)
        }
    }

    /// Calculate approximate direction to peer using GPS and compass
    private func calculateFallbackDirection(for peerId: String) {
        guard let myLocation = currentLocation,
              let peerLocation = peerLocations[peerId],
              let heading = currentHeading else {
            return
        }

        // Calculate bearing from my location to peer location
        let bearing = calculateBearing(from: myLocation, to: peerLocation)

        // Calculate relative direction based on device heading
        let relativeDirection = normalizeAngle(bearing - heading.trueHeading)

        // Calculate distance
        let distance = myLocation.distance(from: peerLocation)

        // Create fallback direction
        let fallbackDirection = FallbackDirection(
            peerId: peerId,
            bearing: bearing,
            relativeDirection: relativeDirection,
            distance: Float(distance),
            accuracy: determineAccuracy(distance: distance),
            method: .compassGPS,
            timestamp: Date()
        )

        DispatchQueue.main.async {
            self.fallbackDirections[peerId] = fallbackDirection

            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            LoggingService.network.info("🧭 FALLBACK DIRECTION CALCULATED")
            LoggingService.network.info("   Peer: \(peerId)")
            LoggingService.network.info("   Distance: \(String(format: "%.1f", distance))m")
            LoggingService.network.info("   Bearing: \(String(format: "%.0f", bearing))°")
            LoggingService.network.info("   Relative: \(self.describeRelativeDirection(relativeDirection))")
            LoggingService.network.info("   Accuracy: ±\(String(format: "%.0f", fallbackDirection.accuracy))°")
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        }
    }

    /// Calculate bearing between two locations
    private func calculateBearing(from: CLLocation, to: CLLocation) -> Double {
        let lat1 = from.coordinate.latitude.toRadians()
        let lat2 = to.coordinate.latitude.toRadians()
        let deltaLon = (to.coordinate.longitude - from.coordinate.longitude).toRadians()

        let x = sin(deltaLon) * cos(lat2)
        let y = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)

        var bearing = atan2(x, y).toDegrees()

        // Normalize to 0-360
        if bearing < 0 {
            bearing += 360
        }

        return bearing
    }

    /// Normalize angle to -180 to 180 range
    private func normalizeAngle(_ angle: Double) -> Double {
        var normalized = angle
        while normalized > 180 {
            normalized -= 360
        }
        while normalized < -180 {
            normalized += 360
        }
        return normalized
    }

    /// Determine accuracy based on distance
    private func determineAccuracy(distance: Double) -> Double {
        // Further away = less accurate direction
        if distance < 10 {
            return 15.0 // ±15° for close range
        } else if distance < 50 {
            return 30.0 // ±30° for medium range
        } else {
            return 45.0 // ±45° for long range
        }
    }

    /// Describe relative direction in human terms
    func describeRelativeDirection(_ angle: Double) -> String {
        let absAngle = abs(angle)

        if absAngle < 22.5 {
            return "Adelante"
        } else if absAngle < 67.5 {
            return angle > 0 ? "Adelante-Derecha" : "Adelante-Izquierda"
        } else if absAngle < 112.5 {
            return angle > 0 ? "Derecha" : "Izquierda"
        } else if absAngle < 157.5 {
            return angle > 0 ? "Atrás-Derecha" : "Atrás-Izquierda"
        } else {
            return "Atrás"
        }
    }

    /// Process device motion for orientation compensation
    private func processDeviceMotion(_ motion: CMDeviceMotion) {
        // Use motion data to compensate for device tilt
        // This improves accuracy when device is not held level
    }

    /// Get visual arrow for direction (for UI)
    func getDirectionArrow(for peerId: String) -> String {
        guard let direction = fallbackDirections[peerId] else {
            return "?"
        }

        let angle = direction.relativeDirection
        let absAngle = abs(angle)

        if absAngle < 22.5 {
            return "↑"
        } else if absAngle < 67.5 {
            return angle > 0 ? "↗" : "↖"
        } else if absAngle < 112.5 {
            return angle > 0 ? "→" : "←"
        } else if absAngle < 157.5 {
            return angle > 0 ? "↘" : "↙"
        } else {
            return "↓"
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension FallbackDirectionService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        currentLocation = location

        // Recalculate all peer directions with new location
        updateQueue.async { [weak self] in
            guard let self = self else { return }
            for peerId in self.peerLocations.keys {
                self.calculateFallbackDirection(for: peerId)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        currentHeading = newHeading

        // Recalculate all peer directions with new heading
        updateQueue.async { [weak self] in
            guard let self = self else { return }
            for peerId in self.peerLocations.keys {
                self.calculateFallbackDirection(for: peerId)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        LoggingService.network.info("❌ FallbackDirectionService: Location error - \(error.localizedDescription)")
    }
}

// MARK: - Supporting Types
struct FallbackDirection {
    let peerId: String
    let bearing: Double           // Absolute bearing to peer (0-360)
    let relativeDirection: Double // Relative to device heading (-180 to 180)
    let distance: Float           // Distance in meters
    let accuracy: Double          // Accuracy in degrees
    let method: DirectionMethod
    let timestamp: Date
}

enum DirectionMethod {
    case compassGPS       // Using compass + GPS
    case gpsOnly         // GPS only (no compass)
    case bluetoothRSSI   // Bluetooth signal strength
    case userInput       // Manual user indication
}

// MARK: - Extensions
extension Double {
    func toRadians() -> Double {
        return self * .pi / 180
    }

    func toDegrees() -> Double {
        return self * 180 / .pi
    }
}

// MARK: - Integration with LinkFinderSessionManager
@available(iOS 14.0, *)
extension LinkFinderSessionManager {
    /// Get direction using fallback method when UWB is not available
    func getFallbackDirection(to peerID: MCPeerID, using fallbackService: FallbackDirectionService) -> (arrow: String, description: String)? {
        let peerId = peerID.displayName

        // Check if we have UWB direction first
        if let uwbDirection = getDirection(to: peerID) {
            // Convert SIMD3 to arrow (UWB is precise)
            return convertUWBDirection(uwbDirection)
        }

        // Check if peer has UWB (from capabilities)
        if let peerCaps = peerCapabilities[peerId],
           let localCaps = localDeviceCapabilities {

            let compatibility = localCaps.isCompatibleWith(peerCaps)

            if !compatibility.direction {
                // Use fallback if direction not compatible
                if let fallbackDirection = fallbackService.fallbackDirections[peerId] {
                    return (
                        arrow: fallbackService.getDirectionArrow(for: peerId),
                        description: "~\(fallbackService.describeRelativeDirection(fallbackDirection.relativeDirection))"
                    )
                }
            }
        }

        return nil
    }

    private func convertUWBDirection(_ direction: SIMD3<Float>) -> (arrow: String, description: String) {
        // Convert UWB SIMD3 to arrow and description
        let angle = atan2(Double(direction.x), Double(direction.z)) * 180 / .pi

        let arrow: String
        let description: String

        if abs(angle) < 22.5 {
            arrow = "↑"
            description = "Adelante"
        } else if abs(angle) < 67.5 {
            arrow = angle > 0 ? "↗" : "↖"
            description = angle > 0 ? "Adelante-Derecha" : "Adelante-Izquierda"
        } else if abs(angle) < 112.5 {
            arrow = angle > 0 ? "→" : "←"
            description = angle > 0 ? "Derecha" : "Izquierda"
        } else if abs(angle) < 157.5 {
            arrow = angle > 0 ? "↘" : "↙"
            description = angle > 0 ? "Atrás-Derecha" : "Atrás-Izquierda"
        } else {
            arrow = "↓"
            description = "Atrás"
        }

        return (arrow: arrow, description: description)
    }
}