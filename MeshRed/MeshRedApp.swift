//
//  MeshRedApp.swift
//  MeshRed
//
//  Created by Emilio Contreras on 28/09/25.
//

import SwiftUI
import ActivityKit
import Combine
import os

@main
struct MeshRedApp: App {
    @StateObject private var networkManager = NetworkManager()
    @StateObject private var accessibilitySettings = AccessibilitySettingsManager.shared

    @Environment(\.scenePhase) private var scenePhase

    // Timer to detect definitive app closure
    @State private var backgroundTimer: Task<Void, Never>?

    // Observer for widget stop requests via App Group
    @State private var stopRequestObserver: AnyCancellable?

    var body: some Scene {
        WindowGroup {
            MainDashboardContainer()
                .environmentObject(networkManager)
                .environmentObject(accessibilitySettings)
                .withAccessibleTheme(AccessibleThemeColors(settings: accessibilitySettings))
                .preferredColorScheme(preferredColorScheme)
                .onAppear {
                    LoggingService.network.info("🚀 StadiumConnect Pro: App started with device: \(networkManager.localDeviceName)")
                    LoggingService.network.info("♿️ Accessibility: High Contrast = \(accessibilitySettings.enableHighContrast), Bold Text = \(accessibilitySettings.preferBoldText)")

                    // FORCE cleanup all Live Activities on app start
                    forceCleanupAllLiveActivities()

                    // Initialize Stadium Mode Manager with dependencies
                    StadiumModeManager.shared.setup(
                        networkManager: networkManager,
                        locationService: networkManager.locationService
                    )

                    // ✅ REMOVED automatic Live Activity start
                    // Live Activity is now ONLY managed by Stadium Mode
                    // User must manually enable Stadium Mode from Settings
                    LoggingService.network.info("💡 Live Activity will start when user enables Stadium Mode")

                    // Start observing widget stop requests
                    startObservingStopRequests()
                }
                .onChange(of: scenePhase) { newPhase in
                    handleScenePhaseChange(newPhase)
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    /// Computed property that converts string preference to ColorScheme
    private var preferredColorScheme: ColorScheme? {
        switch accessibilitySettings.preferredColorScheme {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil // system default
        }
    }

    // MARK: - Live Activity Management

    /// Start Live Activity if we have connected peers
    private func startLiveActivityIfNeeded() {
        #if !targetEnvironment(simulator)
        if #available(iOS 16.1, *) {
            // Wait for cleanup + connections to establish, then start
            // Increased delay to ensure cleanup completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                if !networkManager.connectedPeers.isEmpty && !networkManager.hasActiveLiveActivity {
                    LoggingService.network.info("⏰ Starting Live Activity after cleanup delay...")
                    networkManager.startLiveActivity()
                }
            }
        }
        #endif
    }

    /// Handle scene phase changes for Live Activity management
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        #if !targetEnvironment(simulator)
        if #available(iOS 16.1, *) {
            switch newPhase {
            case .active:
                LoggingService.network.info("📱 App became active")
                // Cancel background timer if app comes back
                backgroundTimer?.cancel()
                backgroundTimer = nil
                LoggingService.network.info("   ⏱️ Background timer cancelled - app is active")

                // ✅ SUSPENSION RECOVERY: Resume LinkFinder sessions if suspended
                // NISession suspends when app backgrounds - we need to restart it
                if #available(iOS 14.0, *), let uwbManager = networkManager.uwbSessionManager {
                    LoggingService.network.info("   🔄 Notifying LinkFinder manager of foreground transition...")
                    // Note: LinkFinderSessionManager also has its own UIApplication observer
                    // This is a backup call in case the notification doesn't fire
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        uwbManager.resumeSuspendedSessionsIfNeeded()
                    }
                }

            case .inactive:
                LoggingService.network.info("📱 App became inactive")
                // Keep Live Activity running to maintain background priority

            case .background:
                LoggingService.network.info("📱 App entered background")
                // Start timer to auto-stop Live Activity if user doesn't return
                startBackgroundTimer()

            @unknown default:
                break
            }
        }
        #endif
    }

    /// Start timer to auto-stop Live Activity after app is in background for extended time
    private func startBackgroundTimer() {
        #if !targetEnvironment(simulator)
        if #available(iOS 16.1, *) {
            // Cancel any existing timer
            backgroundTimer?.cancel()

            LoggingService.network.info("⏱️ Starting 30-second background timer...")
            LoggingService.network.info("   Live Activity will auto-stop if app doesn't return")

            backgroundTimer = Task {
                // Wait 30 seconds
                try? await Task.sleep(nanoseconds: 30_000_000_000)

                // Check if task was cancelled (user returned to app)
                guard !Task.isCancelled else {
                    LoggingService.network.info("⏱️ Background timer cancelled - user returned")
                    return
                }

                // Still in background after 30 seconds - stop Live Activity
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                LoggingService.network.info("⏱️ BACKGROUND TIMER EXPIRED (30s)")
                LoggingService.network.info("   App appears to be closed - stopping Live Activity")
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                await MainActor.run {
                    networkManager.stopLiveActivity(dismissalPolicy: .immediate)
                }
            }
        }
        #endif
    }

    /// Force cleanup all Live Activities on app start to prevent "invalid reuse" errors
    private func forceCleanupAllLiveActivities() {
        #if !targetEnvironment(simulator)
        if #available(iOS 16.1, *) {
            Task {
                let activities = Activity<MeshActivityAttributes>.activities

                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                LoggingService.network.info("🧹 FORCE CLEANUP ALL LIVE ACTIVITIES")
                LoggingService.network.info("   Found \(activities.count) existing activities")
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                for activity in activities {
                    LoggingService.network.info("   🗑️ Ending activity: \(activity.id)")
                    await activity.end(nil, dismissalPolicy: .immediate)
                }

                LoggingService.network.info("✅ All Live Activities cleaned up")
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            }
        }
        #endif
    }

    // MARK: - Widget Communication via App Group

    /// Start observing stop requests from widget via App Group UserDefaults
    private func startObservingStopRequests() {
        #if !targetEnvironment(simulator)
        if #available(iOS 16.1, *) {
            let appGroupName = "group.EmilioContreras.MeshRed"

            guard let sharedDefaults = UserDefaults(suiteName: appGroupName) else {
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                LoggingService.network.info("❌ OBSERVER SETUP FAILED")
                LoggingService.network.info("   Cannot access App Group: \(appGroupName)")
                LoggingService.network.info("   Stop button will NOT work!")
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                return
            }

            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            LoggingService.network.info("👂 OBSERVER SETUP SUCCESSFUL")
            LoggingService.network.info("   📂 App Group: \(appGroupName)")
            LoggingService.network.info("   ⏱️ Polling interval: 0.5 seconds")
            LoggingService.network.info("   🔍 Watching key: 'stop_live_activity'")

            // Clear any stale flags
            let initialValue = sharedDefaults.bool(forKey: "stop_live_activity")
            if initialValue {
                LoggingService.network.info("   🧹 Clearing stale stop flag from previous session")
                sharedDefaults.set(false, forKey: "stop_live_activity")
                sharedDefaults.synchronize()
            } else {
                LoggingService.network.info("   ✅ No stale flags detected")
            }

            LoggingService.network.info("   ✅ Observer ready - Stop button will work!")
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            var checkCount = 0

            // Poll every 0.5 seconds to check for stop flag
            // (UserDefaults doesn't have real-time change notifications across processes)
            stopRequestObserver = Timer.publish(every: 0.5, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    checkCount += 1

                    // Debug: LoggingService.network.info poll status every 10 checks (5 seconds)
                    if checkCount % 10 == 0 {
                        let flagValue = sharedDefaults.bool(forKey: "stop_live_activity")
                        LoggingService.network.info("👂 Observer check #\(checkCount): stop_live_activity = \(flagValue)")
                    }

                    if sharedDefaults.bool(forKey: "stop_live_activity") {
                        let timestamp = sharedDefaults.double(forKey: "stop_live_activity_timestamp")
                        let timestampDate = Date(timeIntervalSince1970: timestamp)
                        let timestampString = DateFormatter.localizedString(from: timestampDate, dateStyle: .none, timeStyle: .medium)

                        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        LoggingService.network.info("🛑 STOP REQUEST RECEIVED FROM WIDGET")
                        LoggingService.network.info("   ⏰ Widget timestamp: \(timestampString)")
                        LoggingService.network.info("   🔍 Current check #\(checkCount)")
                        LoggingService.network.info("   📱 Process: MAIN APP")
                        LoggingService.network.info("   🔄 Terminating Live Activity...")
                        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                        // Clear the flag IMMEDIATELY
                        sharedDefaults.set(false, forKey: "stop_live_activity")
                        let syncSuccess = sharedDefaults.synchronize()
                        LoggingService.network.info("   🧹 Cleared stop flag, synchronize() = \(syncSuccess)")

                        // Stop Live Activity
                        Task {
                            let activities = Activity<MeshActivityAttributes>.activities
                            LoggingService.network.info("   📊 Found \(activities.count) active Live Activities")

                            for activity in activities {
                                LoggingService.network.info("   🗑️  Ending activity ID: \(activity.id)")
                                await activity.end(nil, dismissalPolicy: .immediate)
                                LoggingService.network.info("      ✅ Activity ended successfully")
                            }

                            LoggingService.network.info("✅ ALL LIVE ACTIVITIES STOPPED")
                            LoggingService.network.info("   🎯 Triggered by: Widget Stop button")
                            LoggingService.network.info("   ⏱️ Total checks before detection: \(checkCount)")
                            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                            // Reset check count after successful stop
                            checkCount = 0
                        }
                    }
                }
        }
        #endif
    }

    // MARK: - Deep Link Handling

    /// Handle deep links from Live Activity Stop button
    private func handleDeepLink(_ url: URL) {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🔗 DEEP LINK RECEIVED")
        LoggingService.network.info("   📱 URL: \(url.absoluteString)")
        LoggingService.network.info("   🔍 Scheme: \(url.scheme ?? "none")")
        LoggingService.network.info("   🔍 Host: \(url.host ?? "none")")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        guard url.scheme == "meshred" else {
            LoggingService.network.info("   ❌ Unknown URL scheme: \(url.scheme ?? "nil")")
            return
        }

        if url.host == "stop-live-activity" || url.absoluteString.contains("stop-live-activity") {
            LoggingService.network.info("   ✅ STOP LIVE ACTIVITY COMMAND DETECTED")
            LoggingService.network.info("   🛑 Processing stop request immediately...")

            #if !targetEnvironment(simulator)
            if #available(iOS 16.1, *) {
                Task {
                    let activities = Activity<MeshActivityAttributes>.activities
                    LoggingService.network.info("   📊 Found \(activities.count) active Live Activities")

                    for activity in activities {
                        LoggingService.network.info("   🗑️  Ending activity ID: \(activity.id)")
                        await activity.end(nil, dismissalPolicy: .immediate)
                        LoggingService.network.info("      ✅ Activity ended successfully")
                    }

                    LoggingService.network.info("✅ ALL LIVE ACTIVITIES STOPPED VIA DEEP LINK")
                    LoggingService.network.info("   🎯 Triggered by: Dynamic Island Stop button")
                    LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                    // Minimize app after a brief delay to allow stop to complete
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

                    await MainActor.run {
                        // Request to minimize app (return to home screen)
                        LoggingService.network.info("📱 Attempting to minimize app...")

                        // Note: There's no official API to programmatically minimize the app
                        // The app will remain in foreground, but Live Activity will be stopped
                        // User can manually swipe up to dismiss
                    }
                }
            }
            #endif
        } else {
            LoggingService.network.info("   ❌ Unknown deep link host: \(url.host ?? "nil")")
        }
    }
}
