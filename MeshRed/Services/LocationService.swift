//
//  LocationService.swift
//  MeshRed
//
//  Created by Emilio Contreras on 29/09/25.
//

import Foundation
import CoreLocation
import Combine

/// Service for managing GPS location requests and permissions
class LocationService: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var currentLocation: UserLocation?
    @Published var currentHeading: CLHeading?
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var isMonitoring: Bool = false
    @Published var isMonitoringHeading: Bool = false
    @Published var locationError: LocationError?

    // MARK: - Private Properties
    private let locationManager = CLLocationManager()
    private var locationContinuations: [CheckedContinuation<UserLocation?, Error>] = []

    // MARK: - Configuration
    private let desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    private let distanceFilter: CLLocationDistance = 10.0  // Update every 10 meters
    private let headingFilter: CLLocationDegrees = 5.0  // Update every 5 degrees

    // MARK: - Errors
    enum LocationError: LocalizedError {
        case permissionDenied
        case locationUnavailable
        case timeout
        case accuracyReduced

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Permisos de ubicación denegados"
            case .locationUnavailable:
                return "Ubicación no disponible"
            case .timeout:
                return "Tiempo de espera agotado para obtener ubicación"
            case .accuracyReduced:
                return "Precisión de ubicación reducida"
            }
        }
    }

    // MARK: - Initialization
    override init() {
        // Initialize with notDetermined, delegate will update with actual status
        self.authorizationStatus = .notDetermined
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = desiredAccuracy
        locationManager.distanceFilter = distanceFilter

        print("📍 LocationService: Initialized, waiting for authorization status from delegate...")
    }

    // MARK: - Public Methods

    /// Request location permissions from user
    func requestPermissions() {
        switch authorizationStatus {
        case .notDetermined:
            print("📍 LocationService: Requesting location permissions...")
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            print("📍 LocationService: Already authorized")
        case .denied, .restricted:
            print("📍 LocationService: Permission denied or restricted")
            locationError = .permissionDenied
        @unknown default:
            print("📍 LocationService: Unknown authorization status")
        }
    }

    /// Get current location once (one-shot request)
    func getCurrentLocation() async throws -> UserLocation? {
        // Check permissions first
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            throw LocationError.permissionDenied
        }

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuations.append(continuation)

            // Request location
            locationManager.requestLocation()

            // Set timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                guard let self = self else { return }

                // Check if continuation is still pending
                if let index = self.locationContinuations.firstIndex(where: { _ in true }) {
                    let cont = self.locationContinuations.remove(at: index)
                    print("⏱️ LocationService: Location request timed out")
                    cont.resume(throwing: LocationError.timeout)
                }
            }
        }
    }

    /// Start continuous location monitoring
    func startMonitoring() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            print("❌ LocationService: Cannot start monitoring - not authorized")
            locationError = .permissionDenied
            return
        }

        locationManager.startUpdatingLocation()
        isMonitoring = true
        print("📍 LocationService: Started continuous monitoring")
    }

    /// Stop continuous location monitoring
    func stopMonitoring() {
        locationManager.stopUpdatingLocation()
        isMonitoring = false
        print("📍 LocationService: Stopped continuous monitoring")
    }

    /// Start continuous heading (compass) monitoring
    func startMonitoringHeading() {
        guard CLLocationManager.headingAvailable() else {
            print("❌ LocationService: Heading not available on this device")
            return
        }

        locationManager.headingFilter = headingFilter
        locationManager.startUpdatingHeading()
        isMonitoringHeading = true
        print("🧭 LocationService: Started heading monitoring")
    }

    /// Stop continuous heading monitoring
    func stopMonitoringHeading() {
        locationManager.stopUpdatingHeading()
        isMonitoringHeading = false
        currentHeading = nil
        print("🧭 LocationService: Stopped heading monitoring")
    }

    /// Check if location services are available
    var isLocationAvailable: Bool {
        return CLLocationManager.locationServicesEnabled() &&
               (authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways)
    }

    /// Check if we have a recent location (< 30 seconds old)
    var hasRecentLocation: Bool {
        guard let location = currentLocation else { return false }
        return Date().timeIntervalSince(location.timestamp) < 30.0
    }

    /// Check if heading is available on this device
    var isHeadingAvailable: Bool {
        return CLLocationManager.headingAvailable()
    }

    /// Get current heading value (true heading if available, magnetic otherwise)
    var headingValue: Double? {
        guard let heading = currentHeading else { return nil }
        return heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
    }

    /// Get detailed diagnostic status for debugging
    func getDetailedStatus() -> String {
        var status = "Location Service Status:\n"
        status += "  Authorization: \(authorizationStatus.description)\n"
        status += "  Services Enabled: \(CLLocationManager.locationServicesEnabled())\n"
        status += "  Is Monitoring: \(isMonitoring)\n"
        status += "  Current Location: \(currentLocation?.coordinateString ?? "none")\n"
        status += "  Last Error: \(locationError?.localizedDescription ?? "none")\n"
        status += "  Has Recent Location: \(hasRecentLocation)\n"
        status += "  Location Available: \(isLocationAvailable)\n"
        status += "\nHeading Service Status:\n"
        status += "  Heading Available: \(isHeadingAvailable)\n"
        status += "  Is Monitoring Heading: \(isMonitoringHeading)\n"
        if let heading = currentHeading {
            let headingVal = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
            let headingType = heading.trueHeading >= 0 ? "true" : "magnetic"
            status += "  Current Heading: \(String(format: "%.1f", headingVal))° (\(headingType))\n"
            status += "  Heading Accuracy: ±\(String(format: "%.1f", heading.headingAccuracy))°\n"
        } else {
            status += "  Current Heading: none\n"
        }
        return status
    }

    // MARK: - Stadium Mode Support

    /// Enable continuous background location updates for Stadium Mode
    /// This extends background execution time significantly (~15-30 min)
    func enableStadiumMode() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🏟️ LocationService: Enabling Stadium Mode")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Enable background location updates
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true  // Show blue bar (transparency)

        // More aggressive settings for background survival
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10  // Update every 10 meters
        locationManager.activityType = .otherNavigation

        // Start continuous updates if not already monitoring
        if !isMonitoring {
            startMonitoring()
        }

        print("✅ Background location updates enabled")
        print("   Accuracy: Best")
        print("   Pause: Disabled")
        print("   Filter: 10m")
        print("   Background Indicator: Visible")
        print("   Estimated Extension: ~15-30 min")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    /// Disable Stadium Mode and revert to normal settings
    func disableStadiumMode() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🏟️ LocationService: Disabling Stadium Mode")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Revert to normal settings
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.showsBackgroundLocationIndicator = false

        // Less aggressive settings
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 100  // Update every 100 meters
        locationManager.activityType = .other

        print("✅ Reverted to normal mode")
        print("   Accuracy: 100m")
        print("   Pause: Enabled")
        print("   Filter: 100m")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus

        DispatchQueue.main.async {
            let oldStatus = self.authorizationStatus
            self.authorizationStatus = newStatus

            // Log initial status or changes
            if oldStatus == .notDetermined {
                print("📍 LocationService: Initial authorization: \(newStatus.description)")
            } else {
                print("📍 LocationService: Authorization changed: \(oldStatus.description) -> \(newStatus.description)")
            }

            switch newStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.locationError = nil
            case .denied, .restricted:
                self.locationError = .permissionDenied
            default:
                break
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let clLocation = locations.last else { return }

        // Check accuracy
        guard clLocation.horizontalAccuracy >= 0 && clLocation.horizontalAccuracy <= 100 else {
            print("⚠️ LocationService: Poor accuracy (\(clLocation.horizontalAccuracy)m), waiting for better...")
            return
        }

        let userLocation = UserLocation(from: clLocation)

        DispatchQueue.main.async {
            self.currentLocation = userLocation
            self.locationError = nil

            print("📍 LocationService: Location updated: \(userLocation.coordinateString) (\(userLocation.accuracyString))")
        }

        // Resume all pending continuations
        let continuations = locationContinuations
        locationContinuations.removeAll()

        for continuation in continuations {
            continuation.resume(returning: userLocation)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ LocationService: Failed to get location: \(error.localizedDescription)")

        DispatchQueue.main.async {
            self.locationError = .locationUnavailable
        }

        // Resume all pending continuations with error
        let continuations = locationContinuations
        locationContinuations.removeAll()

        for continuation in continuations {
            continuation.resume(throwing: LocationError.locationUnavailable)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Validate heading accuracy
        guard newHeading.headingAccuracy >= 0 else {
            print("⚠️ LocationService: Invalid heading accuracy (\(newHeading.headingAccuracy))")
            return
        }

        DispatchQueue.main.async {
            self.currentHeading = newHeading

            // Log heading updates (using trueHeading if available, magneticHeading otherwise)
            let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
            let headingType = newHeading.trueHeading >= 0 ? "true" : "magnetic"
            print("🧭 LocationService: Heading updated: \(String(format: "%.1f", heading))° (\(headingType), accuracy: ±\(String(format: "%.1f", newHeading.headingAccuracy))°)")
        }
    }
}

// MARK: - CLAuthorizationStatus Extension
extension CLAuthorizationStatus {
    var description: String {
        switch self {
        case .notDetermined:
            return "Not Determined"
        case .restricted:
            return "Restricted"
        case .denied:
            return "Denied"
        case .authorizedAlways:
            return "Authorized Always"
        case .authorizedWhenInUse:
            return "Authorized When In Use"
        @unknown default:
            return "Unknown"
        }
    }
}