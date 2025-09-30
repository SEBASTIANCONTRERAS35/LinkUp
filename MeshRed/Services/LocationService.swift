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
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var isMonitoring: Bool = false
    @Published var locationError: LocationError?

    // MARK: - Private Properties
    private let locationManager = CLLocationManager()
    private var locationContinuations: [CheckedContinuation<UserLocation?, Error>] = []

    // MARK: - Configuration
    private let desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    private let distanceFilter: CLLocationDistance = 10.0  // Update every 10 meters

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
        self.authorizationStatus = locationManager.authorizationStatus
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = desiredAccuracy
        locationManager.distanceFilter = distanceFilter

        print("📍 LocationService: Initialized with status: \(authorizationStatus.description)")
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
        return status
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        print("📍 LocationService: Authorization changed: \(authorizationStatus.description) -> \(newStatus.description)")

        DispatchQueue.main.async {
            self.authorizationStatus = newStatus

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