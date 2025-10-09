//
//  StadiumModeManager.swift
//  MeshRed
//
//  Created by Claude for StadiumConnect Pro - Background Survival Coordinator
//

import Foundation
import Combine
import CoreLocation

/// Coordinates all background survival techniques for extended MultipeerConnectivity
/// Combines: Live Activities + Location Updates + Keep-Alive Pings
class StadiumModeManager: ObservableObject {
    // MARK: - Singleton

    static let shared = StadiumModeManager()

    // MARK: - Published Properties

    @Published var isActive: Bool = false
    @Published var startTime: Date?
    @Published var estimatedBackgroundTime: TimeInterval = 0  // Estimated minutes
    @Published var batteryImpact: BatteryImpact = .low

    // MARK: - Dependencies

    private weak var networkManager: NetworkManager?
    private weak var locationService: LocationService?
    private let keepAliveManager = KeepAliveManager()

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private var uptimeTimer: Timer?

    // MARK: - Initialization

    private init() {
        print("🏟️ StadiumModeManager: Initialized")
    }

    // MARK: - Setup

    /// Set required dependencies
    func setup(networkManager: NetworkManager, locationService: LocationService) {
        self.networkManager = networkManager
        self.locationService = locationService
        self.keepAliveManager.setNetworkManager(networkManager)

        print("🏟️ StadiumModeManager: Dependencies configured")
    }

    // MARK: - Public Methods

    /// Enable Stadium Mode (Extended Background Survival)
    func enable() {
        guard !isActive else {
            print("⚠️ Stadium Mode already active")
            return
        }

        guard let networkManager = networkManager,
              let locationService = locationService else {
            print("❌ Stadium Mode: Dependencies not set")
            return
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🏟️ ENABLING STADIUM MODE")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Layer 1: Start Live Activity (UI visibility)
        if #available(iOS 16.1, *) {
            if !networkManager.hasActiveLiveActivity {
                networkManager.startLiveActivity()
                print("✅ Layer 1: Live Activity started")
            } else {
                print("✅ Layer 1: Live Activity already running")
            }
        }

        // Layer 2: Enable continuous location updates (background time extension)
        enableContinuousLocationUpdates()
        print("✅ Layer 2: Continuous location updates enabled")

        // Layer 3: Start keep-alive pings (network stability)
        keepAliveManager.start()
        print("✅ Layer 3: Keep-alive pings started")

        // Update state
        isActive = true
        startTime = Date()
        batteryImpact = .high  // Updated: automotive navigation uses more battery
        estimatedBackgroundTime = 90 * 60  // ~90 minutes (1.5 hours) with automotive navigation

        // Start uptime counter
        startUptimeTimer()

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🏟️ STADIUM MODE ACTIVE (AUTOMOTIVE NAVIGATION)")
        print("   Estimated Background Time: 1-2 HOURS")
        print("   Battery Impact: High (~20%/hour)")
        print("   Layers: Live Activity + GPS Navigation + Keep-Alive")
        print("   ⚠️  Blue bar will be visible (iOS transparency)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Send notification to user
        sendStadiumModeNotification(enabled: true)
    }

    /// Disable Stadium Mode
    func disable() {
        guard isActive else {
            print("⚠️ Stadium Mode already inactive")
            return
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🏟️ DISABLING STADIUM MODE")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Layer 3: Stop keep-alive pings
        keepAliveManager.stop()
        print("✅ Layer 3: Keep-alive pings stopped")

        // Layer 2: Disable continuous location updates
        disableContinuousLocationUpdates()
        print("✅ Layer 2: Continuous location updates disabled")

        // Layer 1: Keep Live Activity running (user can dismiss manually)
        // We don't stop Live Activity to maintain visibility
        print("✅ Layer 1: Live Activity kept running (user can dismiss)")

        // Update state
        isActive = false
        batteryImpact = .low
        estimatedBackgroundTime = 0

        // Stop uptime timer
        uptimeTimer?.invalidate()
        uptimeTimer = nil

        if let duration = getUptime() {
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("🏟️ STADIUM MODE DISABLED")
            print("   Total Duration: \(formatDuration(duration))")
            print("   Keep-Alive Pings: \(keepAliveManager.pingCount)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        }

        startTime = nil

        // Send notification to user
        sendStadiumModeNotification(enabled: false)
    }

    /// Toggle Stadium Mode
    func toggle() {
        if isActive {
            disable()
        } else {
            enable()
        }
    }

    // MARK: - Location Management

    private func enableContinuousLocationUpdates() {
        guard let locationService = networkManager?.locationService else { return }

        // Use LocationService's Stadium Mode methods
        locationService.enableStadiumMode()

        print("📍 Location: Stadium Mode enabled via LocationService")
    }

    private func disableContinuousLocationUpdates() {
        guard let locationService = networkManager?.locationService else { return }

        // Use LocationService's Stadium Mode methods
        locationService.disableStadiumMode()

        print("📍 Location: Stadium Mode disabled via LocationService")
    }

    // MARK: - Statistics & Monitoring

    /// Get current uptime if active
    func getUptime() -> TimeInterval? {
        guard let start = startTime else { return nil }
        return Date().timeIntervalSince(start)
    }

    /// Get formatted uptime string
    func getFormattedUptime() -> String {
        guard let uptime = getUptime() else { return "Inactive" }
        return formatDuration(uptime)
    }

    /// Get stadium mode statistics
    func getStats() -> StadiumModeStats {
        return StadiumModeStats(
            isActive: isActive,
            uptime: getUptime() ?? 0,
            keepAlivePings: keepAliveManager.pingCount,
            batteryImpact: batteryImpact,
            estimatedBackgroundTime: estimatedBackgroundTime,
            layersActive: [
                "Live Activity": networkManager?.hasActiveLiveActivity ?? false,
                "Location Updates": isActive,
                "Keep-Alive": keepAliveManager.isActive
            ]
        )
    }

    // MARK: - Private Helpers

    private func startUptimeTimer() {
        uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isActive else { return }
            // Could update UI here if needed
            self.objectWillChange.send()
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration / 3600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))

        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    private func sendStadiumModeNotification(enabled: Bool) {
        // Could send local notification to inform user
        // For now, just log
        let status = enabled ? "ACTIVADO" : "DESACTIVADO"
        print("📢 Notificación: Modo Estadio \(status)")
    }

    // MARK: - Battery Impact Enum

    enum BatteryImpact: String {
        case low = "Bajo (~5%/2hr)"
        case medium = "Medio (~10-15%/2hr)"
        case high = "Alto (~20-25%/2hr)"

        var color: String {
            switch self {
            case .low: return "green"
            case .medium: return "yellow"
            case .high: return "red"
            }
        }
    }
}

// MARK: - Statistics

struct StadiumModeStats {
    let isActive: Bool
    let uptime: TimeInterval
    let keepAlivePings: Int
    let batteryImpact: StadiumModeManager.BatteryImpact
    let estimatedBackgroundTime: TimeInterval
    let layersActive: [String: Bool]

    var formattedUptime: String {
        let minutes = Int(uptime / 60)
        let seconds = Int(uptime.truncatingRemainder(dividingBy: 60))
        return "\(minutes)m \(seconds)s"
    }

    var estimatedMinutes: Int {
        return Int(estimatedBackgroundTime / 60)
    }
}
