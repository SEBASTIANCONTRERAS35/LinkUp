//
//  LocationService.swift
//  MeshRed
//
//  Created by Emilio Contreras on 29/09/25.
//

import Foundation
import CoreLocation
import Combine
import os

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

        LoggingService.network.info("📍 LocationService: Initialized, waiting for authorization status from delegate...")
    }

    // MARK: - Public Methods

    /// Request location permissions from user
    func requestPermissions() {
        switch authorizationStatus {
        case .notDetermined:
            LoggingService.network.info("📍 LocationService: Requesting location permissions...")
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            LoggingService.network.info("📍 LocationService: Already authorized")
        case .denied, .restricted:
            LoggingService.network.info("📍 LocationService: Permission denied or restricted")
            locationError = .permissionDenied
        @unknown default:
            LoggingService.network.info("📍 LocationService: Unknown authorization status")
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
                    LoggingService.network.info("⏱️ LocationService: Location request timed out")
                    cont.resume(throwing: LocationError.timeout)
                }
            }
        }
    }

    /// Start continuous location monitoring
    func startMonitoring() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            LoggingService.network.info("❌ LocationService: Cannot start monitoring - not authorized")
            locationError = .permissionDenied
            return
        }

        locationManager.startUpdatingLocation()
        isMonitoring = true
        LoggingService.network.info("📍 LocationService: Started continuous monitoring")
    }

    /// Stop continuous location monitoring
    func stopMonitoring() {
        locationManager.stopUpdatingLocation()
        isMonitoring = false
        LoggingService.network.info("📍 LocationService: Stopped continuous monitoring")
    }

    /// Start continuous heading (compass) monitoring
    func startMonitoringHeading() {
        guard CLLocationManager.headingAvailable() else {
            LoggingService.network.info("❌ LocationService: Heading not available on this device")
            return
        }

        locationManager.headingFilter = headingFilter
        locationManager.startUpdatingHeading()
        isMonitoringHeading = true
        LoggingService.network.info("🧭 LocationService: Started heading monitoring")
    }

    /// Stop continuous heading monitoring
    func stopMonitoringHeading() {
        locationManager.stopUpdatingHeading()
        isMonitoringHeading = false
        currentHeading = nil
        LoggingService.network.info("🧭 LocationService: Stopped heading monitoring")
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
    /// This extends background execution time significantly (1-2 hours via automotive navigation)
    func enableStadiumMode() {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🏟️ LocationService: Enabling Stadium Mode (Automotive Navigation)")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Enable background location updates
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true  // Show blue bar (transparency)

        // AGGRESSIVE: Automotive navigation mode for maximum background time (1-2 hours)
        // This tells iOS we're a GPS navigation app like Waze/Google Maps
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation  // Maximum GPS precision

        // FIXED: Añadir filtro de 5 metros para evitar updates redundantes
        // Antes: kCLDistanceFilterNone causaba 60+ updates/sec con misma coordenada → ANR
        // Ahora: Solo actualizar si el usuario se movió >5m (suficiente para navegación en estadio)
        locationManager.distanceFilter = 5.0  // Update every 5 meters minimum

        locationManager.activityType = .automotiveNavigation  // GPS car navigation mode (highest priority)

        // Start continuous updates if not already monitoring
        if !isMonitoring {
            startMonitoring()
        }

        LoggingService.network.info("✅ Background location updates enabled (AGGRESSIVE MODE)")
        LoggingService.network.info("   Accuracy: BestForNavigation (GPS max)")
        LoggingService.network.info("   Pause: Disabled (NEVER pauses)")
        LoggingService.network.info("   Filter: 5 meters (prevents redundant updates)")
        LoggingService.network.info("   Activity: Automotive Navigation (highest priority)")
        LoggingService.network.info("   Background Indicator: Visible (blue bar)")
        LoggingService.network.info("   Estimated Extension: 1-2 HOURS")
        LoggingService.network.info("   ⚠️  Battery: ~15-20% per hour (reduced by filter)")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    /// Disable Stadium Mode and revert to normal settings
    func disableStadiumMode() {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🏟️ LocationService: Disabling Stadium Mode")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Revert to normal settings
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.showsBackgroundLocationIndicator = false

        // Less aggressive settings
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 100  // Update every 100 meters
        locationManager.activityType = .other

        LoggingService.network.info("✅ Reverted to normal mode")
        LoggingService.network.info("   Accuracy: 100m")
        LoggingService.network.info("   Pause: Enabled")
        LoggingService.network.info("   Filter: 100m")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
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
                LoggingService.network.info("📍 LocationService: Initial authorization: \(newStatus.description)")
            } else {
                LoggingService.network.info("📍 LocationService: Authorization changed: \(oldStatus.description) -> \(newStatus.description)")
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
            LoggingService.network.info("⚠️ LocationService: Poor accuracy (\(clLocation.horizontalAccuracy)m), waiting for better...")
            return
        }

        let userLocation = UserLocation(from: clLocation)

        DispatchQueue.main.async {
            self.currentLocation = userLocation
            self.locationError = nil

            LoggingService.network.info("📍 LocationService: Location updated: \(userLocation.coordinateString) (\(userLocation.accuracyString))")
        }

        // Resume all pending continuations
        let continuations = locationContinuations
        locationContinuations.removeAll()

        for continuation in continuations {
            continuation.resume(returning: userLocation)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        LoggingService.network.info("❌ LocationService: Failed to get location: \(error.localizedDescription)")

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
            LoggingService.network.info("⚠️ LocationService: Invalid heading accuracy (\(newHeading.headingAccuracy))")
            return
        }

        DispatchQueue.main.async {
            self.currentHeading = newHeading

            // Log heading updates (using trueHeading if available, magneticHeading otherwise)
            let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
            let headingType = newHeading.trueHeading >= 0 ? "true" : "magnetic"
            LoggingService.network.info("🧭 LocationService: Heading updated: \(String(format: "%.1f", heading))° (\(headingType), accuracy: ±\(String(format: "%.1f", newHeading.headingAccuracy))°)")
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