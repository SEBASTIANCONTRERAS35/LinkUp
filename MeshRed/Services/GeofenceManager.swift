//
//  GeofenceManager.swift
//  MeshRed
//
//  Created by Claude for StadiumConnect Pro - Geofencing System
//

import Foundation
import CoreLocation
import Combine
import UserNotifications

/// Manages custom geofences with entry/exit monitoring and mesh network notifications
class GeofenceManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var activeGeofence: CustomGeofence?
    @Published var sharedGeofences: [CustomGeofence] = []  // Geofences from family
    @Published var recentEvents: [GeofenceEventMessage] = []
    @Published var memberLocations: [String: UserLocation] = [:]  // PeerID -> Location

    // MARK: - Dependencies
    private let locationService: LocationService
    private let familyGroupManager: FamilyGroupManager
    private let locationManager = CLLocationManager()
    private weak var networkManager: NetworkManager?  // Weak to avoid retain cycle

    // MARK: - Private Properties
    private let userDefaultsKey = "StadiumConnect.ActiveGeofence"
    private let queue = DispatchQueue(label: "com.meshred.geofence", qos: .userInitiated)
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization
    init(
        locationService: LocationService,
        familyGroupManager: FamilyGroupManager
    ) {
        self.locationService = locationService
        self.familyGroupManager = familyGroupManager
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest

        loadActiveGeofence()
        setupNotifications()

        print("🔷 GeofenceManager: Initialized")
    }

    /// Set network manager reference (called after NetworkManager initializes)
    func setNetworkManager(_ networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

    // MARK: - Public Methods

    /// Create and activate a new geofence
    func createGeofence(
        name: String,
        center: CLLocationCoordinate2D,
        radius: CLLocationDistance,
        shareWithFamily: Bool = true
    ) {
        let geofence = CustomGeofence(
            id: UUID(),
            name: name,
            center: center,
            radius: radius,
            createdAt: Date(),
            creatorPeerID: networkManager?.localDeviceName ?? "unknown",
            isActive: true
        )

        // Activate monitoring
        activateGeofence(geofence)

        // Share with family if requested
        if shareWithFamily, let familyCode = familyGroupManager.groupCode {
            shareGeofence(geofence, code: familyCode)
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔷 GEOFENCE CREATED")
        print("   Name: \(name)")
        print("   Center: \(center.latitude), \(center.longitude)")
        print("   Radius: \(Int(radius))m")
        print("   Shared: \(shareWithFamily)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    /// Activate monitoring for a geofence
    func activateGeofence(_ geofence: CustomGeofence) {
        // Request Always authorization if needed
        let authStatus = locationService.authorizationStatus
        if authStatus != .authorizedAlways {
            print("⚠️ GeofenceManager: Always authorization required for geofencing")
            if authStatus == .authorizedWhenInUse {
                locationManager.requestAlwaysAuthorization()
            }
        }

        // Stop monitoring previous geofence
        if let previousGeofence = activeGeofence {
            let previousRegion = previousGeofence.toCLCircularRegion()
            locationManager.stopMonitoring(for: previousRegion)
        }

        // Start monitoring new geofence
        var activatedGeofence = geofence
        activatedGeofence.isActive = true

        let region = activatedGeofence.toCLCircularRegion()
        locationManager.startMonitoring(for: region)

        // Check initial state
        locationManager.requestState(for: region)

        DispatchQueue.main.async {
            self.activeGeofence = activatedGeofence
            self.saveActiveGeofence()
        }

        print("🔷 GeofenceManager: Activated monitoring for '\(geofence.name)'")
    }

    /// Deactivate current geofence
    func deactivateGeofence() {
        guard let geofence = activeGeofence else { return }

        let region = geofence.toCLCircularRegion()
        locationManager.stopMonitoring(for: region)

        DispatchQueue.main.async {
            self.activeGeofence = nil
            self.saveActiveGeofence()
        }

        print("🔷 GeofenceManager: Deactivated monitoring")
    }

    /// Share geofence with family via mesh
    func shareGeofence(_ geofence: CustomGeofence, code: FamilyGroupCode, message: String? = nil) {
        let shareMessage = GeofenceShareMessage(
            senderId: networkManager?.localDeviceName ?? "unknown",
            geofence: geofence,
            familyGroupCode: code,
            message: message
        )

        // Send via NetworkManager
        networkManager?.sendGeofenceShare(shareMessage)

        print("🔷 GeofenceManager: Shared geofence '\(geofence.name)' with family")
    }

    /// Handle received geofence share from family
    func handleGeofenceShare(_ shareMessage: GeofenceShareMessage) {
        // Verify family code matches
        guard let myCode = familyGroupManager.groupCode,
              myCode == shareMessage.familyGroupCode else {
            print("⚠️ GeofenceManager: Geofence share code mismatch")
            return
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔷 GEOFENCE SHARED RECEIVED")
        print("   From: \(shareMessage.senderId)")
        print("   Name: \(shareMessage.geofence.name)")
        if let msg = shareMessage.message {
            print("   Message: \(msg)")
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Add to shared geofences
        DispatchQueue.main.async {
            // Check if already exists
            if !self.sharedGeofences.contains(where: { $0.id == shareMessage.geofence.id }) {
                self.sharedGeofences.append(shareMessage.geofence)
            }
        }

        // Show notification
        showLocalNotification(
            title: "Geofence compartido",
            body: "\(shareMessage.senderId) compartió '\(shareMessage.geofence.name)'"
        )

        // Auto-activate if no active geofence
        if activeGeofence == nil {
            activateGeofence(shareMessage.geofence)
        }
    }

    /// Handle received geofence event from family
    func handleGeofenceEvent(_ eventMessage: GeofenceEventMessage) {
        // Verify family code matches
        guard let myCode = familyGroupManager.groupCode,
              myCode == eventMessage.familyGroupCode else {
            print("⚠️ GeofenceManager: Event code mismatch")
            return
        }

        // Skip own events
        guard eventMessage.senderId != networkManager?.localDeviceName else {
            return
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔷 GEOFENCE EVENT RECEIVED")
        print("   From: \(eventMessage.senderNickname ?? eventMessage.senderId)")
        print("   Event: \(eventMessage.eventType.rawValue)")
        print("   Place: \(eventMessage.geofenceName)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Update member location
        DispatchQueue.main.async {
            self.memberLocations[eventMessage.senderId] = eventMessage.location
            self.recentEvents.insert(eventMessage, at: 0)

            // Keep only last 20 events
            if self.recentEvents.count > 20 {
                self.recentEvents = Array(self.recentEvents.prefix(20))
            }
        }

        // Show notification
        showLocalNotification(
            title: "\(eventMessage.emoji) \(eventMessage.displayText)",
            body: "Toca para ver en el mapa"
        )
    }

    /// Check if a peer is currently inside the active geofence
    func isInsideGeofence(peerID: String) -> Bool? {
        guard let location = memberLocations[peerID],
              let geofence = activeGeofence else {
            return nil
        }
        return geofence.contains(location)
    }

    /// Get all geofences (active + shared)
    var allGeofences: [CustomGeofence] {
        var geofences: [CustomGeofence] = []
        if let active = activeGeofence {
            geofences.append(active)
        }
        geofences.append(contentsOf: sharedGeofences)
        return geofences
    }

    // MARK: - Private Methods

    private func sendGeofenceEvent(type: GeofenceEventType, geofence: CustomGeofence) {
        guard let currentLocation = locationService.currentLocation,
              let familyCode = familyGroupManager.groupCode,
              let currentMember = familyGroupManager.currentGroup?.currentDeviceMember else {
            print("⚠️ GeofenceManager: Cannot send event - missing data")
            return
        }

        let eventMessage = GeofenceEventMessage(
            senderId: networkManager?.localDeviceName ?? "unknown",
            senderNickname: currentMember.displayName,
            geofence: geofence,
            eventType: type,
            location: currentLocation,
            familyGroupCode: familyCode
        )

        // Send via NetworkManager
        networkManager?.sendGeofenceEvent(eventMessage)

        print("🔷 GeofenceManager: Sent \(type.rawValue) event for '\(geofence.name)'")
    }

    private func showLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // Immediate
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to show notification: \(error)")
            }
        }
    }

    private func setupNotifications() {
        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("🔷 GeofenceManager: Notification permission granted")
            } else if let error = error {
                print("❌ GeofenceManager: Notification permission error: \(error)")
            }
        }
    }

    private func loadActiveGeofence() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let geofence = try? JSONDecoder().decode(CustomGeofence.self, from: data) else {
            print("🔷 GeofenceManager: No saved geofence found")
            return
        }

        // Reactivate monitoring
        activateGeofence(geofence)

        print("🔷 GeofenceManager: Loaded saved geofence '\(geofence.name)'")
    }

    private func saveActiveGeofence() {
        do {
            if let geofence = activeGeofence {
                let data = try JSONEncoder().encode(geofence)
                UserDefaults.standard.set(data, forKey: userDefaultsKey)
                print("💾 GeofenceManager: Saved geofence '\(geofence.name)'")
            } else {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
                print("💾 GeofenceManager: Cleared geofence")
            }
        } catch {
            print("❌ GeofenceManager: Failed to save: \(error)")
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension GeofenceManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion,
              let geofence = activeGeofence,
              circularRegion.identifier == geofence.id.uuidString else {
            return
        }

        print("✅ GeofenceManager: ENTERED '\(geofence.name)'")

        // Audio announcement
        AudioManager.shared.announceZoneTransition(entered: true, zoneName: geofence.name)

        // Send event to family
        sendGeofenceEvent(type: .entry, geofence: geofence)

        // Local notification
        showLocalNotification(
            title: "✅ Entraste a \(geofence.name)",
            body: "Tu familia será notificada"
        )
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion,
              let geofence = activeGeofence,
              circularRegion.identifier == geofence.id.uuidString else {
            return
        }

        print("⚠️ GeofenceManager: EXITED '\(geofence.name)'")

        // Audio announcement
        AudioManager.shared.announceZoneTransition(entered: false, zoneName: geofence.name)

        // Send event to family
        sendGeofenceEvent(type: .exit, geofence: geofence)

        // Local notification
        showLocalNotification(
            title: "⚠️ Saliste de \(geofence.name)",
            body: "Tu familia será notificada"
        )
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion,
              let geofence = activeGeofence,
              circularRegion.identifier == geofence.id.uuidString else {
            return
        }

        switch state {
        case .inside:
            print("🔷 GeofenceManager: Initial state - INSIDE '\(geofence.name)'")
        case .outside:
            print("🔷 GeofenceManager: Initial state - OUTSIDE '\(geofence.name)'")
        case .unknown:
            print("🔷 GeofenceManager: Initial state - UNKNOWN")
        }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        print("❌ GeofenceManager: Monitoring failed: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Use the published property from locationService instead of direct access
        let status = locationService.authorizationStatus
        print("🔷 GeofenceManager: Authorization changed to \(status)")

        // If we got Always authorization and have a geofence, restart monitoring
        if status == .authorizedAlways, let geofence = activeGeofence {
            let region = geofence.toCLCircularRegion()
            locationManager.startMonitoring(for: region)
            locationManager.requestState(for: region)
        }
    }
}
