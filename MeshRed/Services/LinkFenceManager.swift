//
//  LinkFenceManager.swift
//  MeshRed
//
//  Created by Claude for StadiumConnect Pro - Geofencing System
//

import Foundation
import CoreLocation
import Combine
import UserNotifications

/// Manages custom linkfences with entry/exit monitoring and LinkMesh network notifications
class LinkFenceManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var activeGeofence: CustomLinkFence?  // Legacy: kept for backward compatibility
    @Published var sharedGeofences: [CustomLinkFence] = []  // Geofences from family
    @Published var recentEvents: [LinkFenceEventMessage] = []  // Legacy: all events mixed
    @Published var memberLocations: [String: UserLocation] = [:]  // PeerID -> Location

    // MARK: - Multiple Geofences Support
    @Published var myGeofences: [CustomLinkFence] = []  // All my saved linkfences
    @Published var activeGeofences: [UUID: CustomLinkFence] = [:]  // Currently monitoring (max 20)
    @Published var linkfenceHistory: [UUID: [LinkFenceEventMessage]] = [:]  // Events organized by linkfence ID

    // MARK: - Dependencies
    private let locationService: LocationService
    private let familyGroupManager: FamilyGroupManager
    private let locationManager = CLLocationManager()
    private weak var networkManager: NetworkManager?  // Weak to avoid retain cycle

    // MARK: - Private Properties
    private let userDefaultsKey = "StadiumConnect.ActiveGeofence"  // Legacy
    private let myGeofencesKey = "StadiumConnect.MyGeofences"
    private let linkfenceHistoryKey = "StadiumConnect.GeofenceHistory"
    private let activeGeofencesKey = "StadiumConnect.ActiveGeofences"
    private let queue = DispatchQueue(label: "com.meshred.linkfence", qos: .userInitiated)
    private var cancellables = Set<AnyCancellable>()

    // Maximum number of linkfences iOS allows monitoring simultaneously
    static let maxMonitoredGeofences = 20

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

        loadActiveGeofence()  // Legacy
        loadMyGeofences()
        loadGeofenceHistory()
        loadActiveGeofences()
        setupNotifications()

        print("🔷 LinkFenceManager: Initialized")
        print("   My Geofences: \(myGeofences.count)")
        print("   Active Monitoring: \(activeGeofences.count)/\(Self.maxMonitoredGeofences)")
    }

    /// Set network manager reference (called after NetworkManager initializes)
    func setNetworkManager(_ networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

    // MARK: - Public Methods

    /// Create and activate a new linkfence (migrated to multiple linkfences system)
    func createGeofence(
        name: String,
        center: CLLocationCoordinate2D,
        radius: CLLocationDistance,
        shareWithFamily: Bool = true,
        category: LinkFenceCategory = .custom
    ) {
        let linkfence = CustomLinkFence(
            id: UUID(),
            name: name,
            center: center,
            radius: radius,
            createdAt: Date(),
            creatorPeerID: networkManager?.localDeviceName ?? "unknown",
            isActive: true,
            category: category,
            colorHex: category.defaultColorHex,
            isMonitoring: false  // Will be activated below
        )

        // Add to my linkfences
        addGeofence(linkfence)

        // Activate monitoring if under limit
        if activeGeofences.count < Self.maxMonitoredGeofences {
            startMonitoringGeofence(linkfence)
        } else {
            print("⚠️ LinkFenceManager: Cannot auto-activate - at \(Self.maxMonitoredGeofences) limit")
        }

        // Maintain legacy compatibility: set as activeGeofence
        DispatchQueue.main.async {
            self.activeGeofence = linkfence
            self.saveActiveGeofence()
        }

        // Share with family if requested
        if shareWithFamily, let familyCode = familyGroupManager.groupCode {
            shareGeofence(linkfence, code: familyCode)
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔷 GEOFENCE CREATED")
        print("   Name: \(name)")
        print("   Center: \(center.latitude), \(center.longitude)")
        print("   Radius: \(Int(radius))m")
        print("   Category: \(category.rawValue)")
        print("   Shared: \(shareWithFamily)")
        print("   Monitoring: \(activeGeofences.count)/\(Self.maxMonitoredGeofences)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    /// Activate monitoring for a linkfence
    func activateGeofence(_ linkfence: CustomLinkFence) {
        // Request Always authorization if needed
        let authStatus = locationService.authorizationStatus
        if authStatus != .authorizedAlways {
            print("⚠️ LinkFenceManager: Always authorization required for linkfencing")
            if authStatus == .authorizedWhenInUse {
                locationManager.requestAlwaysAuthorization()
            }
        }

        // Stop monitoring previous linkfence
        if let previousGeofence = activeGeofence {
            let previousRegion = previousGeofence.toCLCircularRegion()
            locationManager.stopMonitoring(for: previousRegion)
        }

        // Start monitoring new linkfence
        var activatedGeofence = linkfence
        activatedGeofence.isActive = true

        let region = activatedGeofence.toCLCircularRegion()
        locationManager.startMonitoring(for: region)

        // Check initial state
        locationManager.requestState(for: region)

        DispatchQueue.main.async {
            self.activeGeofence = activatedGeofence
            self.saveActiveGeofence()
        }

        print("🔷 LinkFenceManager: Activated monitoring for '\(linkfence.name)'")
    }

    /// Deactivate current linkfence
    func deactivateGeofence() {
        guard let linkfence = activeGeofence else { return }

        let region = linkfence.toCLCircularRegion()
        locationManager.stopMonitoring(for: region)

        DispatchQueue.main.async {
            self.activeGeofence = nil
            self.saveActiveGeofence()
        }

        print("🔷 LinkFenceManager: Deactivated monitoring")
    }

    /// Share linkfence with family via mesh
    func shareGeofence(_ linkfence: CustomLinkFence, code: FamilyGroupCode, message: String? = nil) {
        let shareMessage = LinkFenceShareMessage(
            senderId: networkManager?.localDeviceName ?? "unknown",
            linkfence: linkfence,
            familyGroupCode: code,
            message: message
        )

        // Send via NetworkManager
        networkManager?.sendGeofenceShare(shareMessage)

        print("🔷 LinkFenceManager: Shared linkfence '\(linkfence.name)' with family")
    }

    /// Handle received linkfence share from family
    func handleGeofenceShare(_ shareMessage: LinkFenceShareMessage) {
        // Verify family code matches
        guard let myCode = familyGroupManager.groupCode,
              myCode == shareMessage.familyGroupCode else {
            print("⚠️ LinkFenceManager: LinkFence share code mismatch")
            return
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔷 GEOFENCE SHARED RECEIVED")
        print("   From: \(shareMessage.senderId)")
        print("   Name: \(shareMessage.linkfence.name)")
        if let msg = shareMessage.message {
            print("   Message: \(msg)")
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Add to shared linkfences
        DispatchQueue.main.async {
            // Check if already exists
            if !self.sharedGeofences.contains(where: { $0.id == shareMessage.linkfence.id }) {
                self.sharedGeofences.append(shareMessage.linkfence)
            }
        }

        // Show notification
        showLocalNotification(
            title: "LinkFence compartido",
            body: "\(shareMessage.senderId) compartió '\(shareMessage.linkfence.name)'"
        )

        // Auto-activate if no active linkfence
        if activeGeofence == nil {
            activateGeofence(shareMessage.linkfence)
        }
    }

    /// Handle received linkfence event from family
    func handleGeofenceEvent(_ eventMessage: LinkFenceEventMessage) {
        // Verify family code matches
        guard let myCode = familyGroupManager.groupCode,
              myCode == eventMessage.familyGroupCode else {
            print("⚠️ LinkFenceManager: Event code mismatch")
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
        print("   Place: \(eventMessage.linkfenceName)")
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

    /// Check if a peer is currently inside the active linkfence
    func isInsideGeofence(peerID: String) -> Bool? {
        guard let location = memberLocations[peerID],
              let linkfence = activeGeofence else {
            return nil
        }
        return linkfence.contains(location)
    }

    /// Get all linkfences (active + shared)
    var allGeofences: [CustomLinkFence] {
        var linkfences: [CustomLinkFence] = []
        if let active = activeGeofence {
            linkfences.append(active)
        }
        linkfences.append(contentsOf: sharedGeofences)
        return linkfences
    }

    // MARK: - Multiple Geofences Management

    /// Add a new linkfence to my saved linkfences
    func addGeofence(_ linkfence: CustomLinkFence) {
        DispatchQueue.main.async {
            // Check if already exists
            if !self.myGeofences.contains(where: { $0.id == linkfence.id }) {
                self.myGeofences.append(linkfence)
                self.saveMyGeofences()
                print("🔷 LinkFenceManager: Added linkfence '\(linkfence.name)' to my linkfences")
            }
        }
    }

    /// Remove a linkfence from my saved linkfences
    func removeGeofence(_ linkfenceId: UUID) {
        // Stop monitoring if active
        if activeGeofences[linkfenceId] != nil {
            stopMonitoringGeofence(linkfenceId)
        }

        DispatchQueue.main.async {
            self.myGeofences.removeAll { $0.id == linkfenceId }
            self.linkfenceHistory.removeValue(forKey: linkfenceId)
            self.saveMyGeofences()
            self.saveGeofenceHistory()
            print("🔷 LinkFenceManager: Removed linkfence \(linkfenceId)")
        }
    }

    /// Start monitoring a linkfence (if under iOS 20 limit)
    func startMonitoringGeofence(_ linkfence: CustomLinkFence) {
        guard activeGeofences.count < Self.maxMonitoredGeofences else {
            print("⚠️ LinkFenceManager: Cannot monitor - already at \(Self.maxMonitoredGeofences) limit")
            return
        }

        // Request Always authorization if needed
        let authStatus = locationService.authorizationStatus
        if authStatus != .authorizedAlways {
            print("⚠️ LinkFenceManager: Always authorization required for linkfencing")
            if authStatus == .authorizedWhenInUse {
                locationManager.requestAlwaysAuthorization()
            }
            return
        }

        let region = linkfence.toCLCircularRegion()
        locationManager.startMonitoring(for: region)
        locationManager.requestState(for: region)

        DispatchQueue.main.async {
            var updatedGeofence = linkfence
            updatedGeofence.isMonitoring = true
            self.activeGeofences[linkfence.id] = updatedGeofence

            // Update in myGeofences array
            if let index = self.myGeofences.firstIndex(where: { $0.id == linkfence.id }) {
                self.myGeofences[index].isMonitoring = true
            }

            self.saveActiveGeofences()
            self.saveMyGeofences()
        }

        print("🔷 LinkFenceManager: Started monitoring '\(linkfence.name)' (\(activeGeofences.count + 1)/\(Self.maxMonitoredGeofences))")
    }

    /// Stop monitoring a linkfence
    func stopMonitoringGeofence(_ linkfenceId: UUID) {
        guard let linkfence = activeGeofences[linkfenceId] else {
            print("⚠️ LinkFenceManager: LinkFence \(linkfenceId) is not being monitored")
            return
        }

        let region = linkfence.toCLCircularRegion()
        locationManager.stopMonitoring(for: region)

        DispatchQueue.main.async {
            self.activeGeofences.removeValue(forKey: linkfenceId)

            // Update in myGeofences array
            if let index = self.myGeofences.firstIndex(where: { $0.id == linkfenceId }) {
                self.myGeofences[index].isMonitoring = false
            }

            self.saveActiveGeofences()
            self.saveMyGeofences()
        }

        print("🔷 LinkFenceManager: Stopped monitoring '\(linkfence.name)' (\(activeGeofences.count - 1)/\(Self.maxMonitoredGeofences))")
    }

    /// Toggle monitoring for a linkfence
    func toggleMonitoring(for linkfenceId: UUID) {
        if activeGeofences[linkfenceId] != nil {
            stopMonitoringGeofence(linkfenceId)
        } else if let linkfence = myGeofences.first(where: { $0.id == linkfenceId }) {
            startMonitoringGeofence(linkfence)
        }
    }

    /// Get events for a specific linkfence
    func getEvents(for linkfenceId: UUID) -> [LinkFenceEventMessage] {
        return linkfenceHistory[linkfenceId] ?? []
    }

    /// Get statistics for a specific linkfence
    func getStatistics(for linkfenceId: UUID) -> LinkFenceStats? {
        guard let linkfence = myGeofences.first(where: { $0.id == linkfenceId }) else {
            return nil
        }

        let events = getEvents(for: linkfenceId)
        return LinkFenceStats(
            linkfenceId: linkfence.id,
            linkfenceName: linkfence.name,
            events: events
        )
    }

    /// Add an event to the history
    func addEvent(_ event: LinkFenceEventMessage) {
        DispatchQueue.main.async {
            // Add to history organized by linkfence
            if self.linkfenceHistory[event.linkfenceId] != nil {
                self.linkfenceHistory[event.linkfenceId]?.insert(event, at: 0)

                // Keep only last 100 events per linkfence
                if let count = self.linkfenceHistory[event.linkfenceId]?.count, count > 100 {
                    self.linkfenceHistory[event.linkfenceId] = Array(self.linkfenceHistory[event.linkfenceId]!.prefix(100))
                }
            } else {
                self.linkfenceHistory[event.linkfenceId] = [event]
            }

            // Also add to legacy recentEvents
            self.recentEvents.insert(event, at: 0)
            if self.recentEvents.count > 20 {
                self.recentEvents = Array(self.recentEvents.prefix(20))
            }

            self.saveGeofenceHistory()
        }
    }

    /// Load mock data for testing
    func loadMockData() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔷 LOADING MOCK GEOFENCE DATA")

        DispatchQueue.main.async {
            self.myGeofences = MockLinkFenceData.mockLinkFences
            self.linkfenceHistory = MockLinkFenceData.generateMockEvents()

            // Auto-activate monitoring for linkfences marked as isMonitoring
            for linkfence in self.myGeofences where linkfence.isMonitoring {
                if self.activeGeofences.count < Self.maxMonitoredGeofences {
                    self.activeGeofences[linkfence.id] = linkfence
                    let region = linkfence.toCLCircularRegion()
                    self.locationManager.startMonitoring(for: region)
                    self.locationManager.requestState(for: region)
                }
            }

            self.saveMyGeofences()
            self.saveGeofenceHistory()
            self.saveActiveGeofences()
        }

        print("   Loaded \(myGeofences.count) linkfences")
        print("   Loaded \(linkfenceHistory.values.flatMap { $0 }.count) events")
        print("   Monitoring \(activeGeofences.count) linkfences")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    // MARK: - Private Methods

    private func handleGeofenceEntry(_ linkfence: CustomLinkFence) {
        print("✅ LinkFenceManager: ENTERED '\(linkfence.name)'")

        // Audio announcement
        AudioManager.shared.announceZoneTransition(entered: true, zoneName: linkfence.name)

        // Haptic feedback with category-specific pattern
        HapticManager.shared.playGeofenceTransition(.entry, category: linkfence.category)

        // Send event to family
        sendGeofenceEvent(type: .entry, linkfence: linkfence)

        // Local notification
        showLocalNotification(
            title: "✅ Entraste a \(linkfence.name)",
            body: "Tu familia será notificada"
        )
    }

    private func handleGeofenceExit(_ linkfence: CustomLinkFence) {
        print("⚠️ LinkFenceManager: EXITED '\(linkfence.name)'")

        // Audio announcement
        AudioManager.shared.announceZoneTransition(entered: false, zoneName: linkfence.name)

        // Haptic feedback with category-specific pattern
        HapticManager.shared.playGeofenceTransition(.exit, category: linkfence.category)

        // Send event to family
        sendGeofenceEvent(type: .exit, linkfence: linkfence)

        // Local notification
        showLocalNotification(
            title: "⚠️ Saliste de \(linkfence.name)",
            body: "Tu familia será notificada"
        )
    }

    private func sendGeofenceEvent(type: LinkFenceEventType, linkfence: CustomLinkFence) {
        guard let currentLocation = locationService.currentLocation,
              let familyCode = familyGroupManager.groupCode,
              let currentMember = familyGroupManager.currentGroup?.currentDeviceMember else {
            print("⚠️ LinkFenceManager: Cannot send event - missing data")
            return
        }

        let eventMessage = LinkFenceEventMessage(
            senderId: networkManager?.localDeviceName ?? "unknown",
            senderNickname: currentMember.displayName,
            linkfence: linkfence,
            eventType: type,
            location: currentLocation,
            familyGroupCode: familyCode
        )

        // Send via NetworkManager
        networkManager?.sendGeofenceEvent(eventMessage)

        print("🔷 LinkFenceManager: Sent \(type.rawValue) event for '\(linkfence.name)'")
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
                print("🔷 LinkFenceManager: Notification permission granted")
            } else if let error = error {
                print("❌ LinkFenceManager: Notification permission error: \(error)")
            }
        }
    }

    private func loadActiveGeofence() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let linkfence = try? JSONDecoder().decode(CustomLinkFence.self, from: data) else {
            print("🔷 LinkFenceManager: No saved linkfence found")
            return
        }

        // Reactivate monitoring
        activateGeofence(linkfence)

        print("🔷 LinkFenceManager: Loaded saved linkfence '\(linkfence.name)'")
    }

    private func saveActiveGeofence() {
        do {
            if let linkfence = activeGeofence {
                let data = try JSONEncoder().encode(linkfence)
                UserDefaults.standard.set(data, forKey: userDefaultsKey)
                print("💾 LinkFenceManager: Saved linkfence '\(linkfence.name)'")
            } else {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
                print("💾 LinkFenceManager: Cleared linkfence")
            }
        } catch {
            print("❌ LinkFenceManager: Failed to save: \(error)")
        }
    }

    // MARK: - Persistence for Multiple Geofences

    private func loadMyGeofences() {
        guard let data = UserDefaults.standard.data(forKey: myGeofencesKey),
              let linkfences = try? JSONDecoder().decode([CustomLinkFence].self, from: data) else {
            print("🔷 LinkFenceManager: No saved linkfences found")
            return
        }

        self.myGeofences = linkfences
        print("🔷 LinkFenceManager: Loaded \(linkfences.count) saved linkfences")
    }

    private func saveMyGeofences() {
        do {
            let data = try JSONEncoder().encode(myGeofences)
            UserDefaults.standard.set(data, forKey: myGeofencesKey)
            print("💾 LinkFenceManager: Saved \(myGeofences.count) linkfences")
        } catch {
            print("❌ LinkFenceManager: Failed to save linkfences: \(error)")
        }
    }

    private func loadGeofenceHistory() {
        guard let data = UserDefaults.standard.data(forKey: linkfenceHistoryKey),
              let history = try? JSONDecoder().decode([UUID: [LinkFenceEventMessage]].self, from: data) else {
            print("🔷 LinkFenceManager: No event history found")
            return
        }

        self.linkfenceHistory = history
        let totalEvents = history.values.flatMap { $0 }.count
        print("🔷 LinkFenceManager: Loaded \(totalEvents) events across \(history.count) linkfences")
    }

    private func saveGeofenceHistory() {
        do {
            let data = try JSONEncoder().encode(linkfenceHistory)
            UserDefaults.standard.set(data, forKey: linkfenceHistoryKey)
            let totalEvents = linkfenceHistory.values.flatMap { $0 }.count
            print("💾 LinkFenceManager: Saved \(totalEvents) events")
        } catch {
            print("❌ LinkFenceManager: Failed to save history: \(error)")
        }
    }

    private func loadActiveGeofences() {
        guard let data = UserDefaults.standard.data(forKey: activeGeofencesKey),
              let active = try? JSONDecoder().decode([UUID: CustomLinkFence].self, from: data) else {
            print("🔷 LinkFenceManager: No active linkfences to restore")
            return
        }

        // Restore monitoring for each active linkfence
        for (_, linkfence) in active {
            if activeGeofences.count < Self.maxMonitoredGeofences {
                let region = linkfence.toCLCircularRegion()
                locationManager.startMonitoring(for: region)
                locationManager.requestState(for: region)
                activeGeofences[linkfence.id] = linkfence
            }
        }

        print("🔷 LinkFenceManager: Restored monitoring for \(activeGeofences.count) linkfences")
    }

    private func saveActiveGeofences() {
        do {
            let data = try JSONEncoder().encode(activeGeofences)
            UserDefaults.standard.set(data, forKey: activeGeofencesKey)
            print("💾 LinkFenceManager: Saved \(activeGeofences.count) active linkfences")
        } catch {
            print("❌ LinkFenceManager: Failed to save active linkfences: \(error)")
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension LinkFenceManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion,
              let linkfenceId = UUID(uuidString: circularRegion.identifier),
              let linkfence = activeGeofences[linkfenceId] else {
            // Legacy support: check activeGeofence
            if let circularRegion = region as? CLCircularRegion,
               let legacyGeofence = activeGeofence,
               circularRegion.identifier == legacyGeofence.id.uuidString {
                handleGeofenceEntry(legacyGeofence)
            }
            return
        }

        handleGeofenceEntry(linkfence)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion,
              let linkfenceId = UUID(uuidString: circularRegion.identifier),
              let linkfence = activeGeofences[linkfenceId] else {
            // Legacy support: check activeGeofence
            if let circularRegion = region as? CLCircularRegion,
               let legacyGeofence = activeGeofence,
               circularRegion.identifier == legacyGeofence.id.uuidString {
                handleGeofenceExit(legacyGeofence)
            }
            return
        }

        handleGeofenceExit(linkfence)
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion,
              let linkfenceId = UUID(uuidString: circularRegion.identifier),
              let linkfence = activeGeofences[linkfenceId] ?? activeGeofence else {
            return
        }

        switch state {
        case .inside:
            print("🔷 LinkFenceManager: Initial state - INSIDE '\(linkfence.name)'")
        case .outside:
            print("🔷 LinkFenceManager: Initial state - OUTSIDE '\(linkfence.name)'")
        case .unknown:
            print("🔷 LinkFenceManager: Initial state - UNKNOWN for '\(linkfence.name)'")
        }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        print("❌ LinkFenceManager: Monitoring failed: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Use the published property from locationService instead of direct access
        let status = locationService.authorizationStatus
        print("🔷 LinkFenceManager: Authorization changed to \(status)")

        // If we got Always authorization and have a linkfence, restart monitoring
        if status == .authorizedAlways, let linkfence = activeGeofence {
            let region = linkfence.toCLCircularRegion()
            locationManager.startMonitoring(for: region)
            locationManager.requestState(for: region)
        }
    }
}
