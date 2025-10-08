//
//  MeshRedApp.swift
//  MeshRed
//
//  Created by Emilio Contreras on 28/09/25.
//

import SwiftUI
import ActivityKit
import Combine

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
                    print("🚀 StadiumConnect Pro: App started with device: \(networkManager.localDeviceName)")
                    print("♿️ Accessibility: High Contrast = \(accessibilitySettings.enableHighContrast), Bold Text = \(accessibilitySettings.preferBoldText)")

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
                    print("💡 Live Activity will start when user enables Stadium Mode")

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
                    print("⏰ Starting Live Activity after cleanup delay...")
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
                print("📱 App became active")
                // Cancel background timer if app comes back
                backgroundTimer?.cancel()
                backgroundTimer = nil
                print("   ⏱️ Background timer cancelled - app is active")

            case .inactive:
                print("📱 App became inactive")
                // Keep Live Activity running to maintain background priority

            case .background:
                print("📱 App entered background")
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

            print("⏱️ Starting 30-second background timer...")
            print("   Live Activity will auto-stop if app doesn't return")

            backgroundTimer = Task {
                // Wait 30 seconds
                try? await Task.sleep(nanoseconds: 30_000_000_000)

                // Check if task was cancelled (user returned to app)
                guard !Task.isCancelled else {
                    print("⏱️ Background timer cancelled - user returned")
                    return
                }

                // Still in background after 30 seconds - stop Live Activity
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("⏱️ BACKGROUND TIMER EXPIRED (30s)")
                print("   App appears to be closed - stopping Live Activity")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

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

                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("🧹 FORCE CLEANUP ALL LIVE ACTIVITIES")
                print("   Found \(activities.count) existing activities")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                for activity in activities {
                    print("   🗑️ Ending activity: \(activity.id)")
                    await activity.end(nil, dismissalPolicy: .immediate)
                }

                print("✅ All Live Activities cleaned up")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
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
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("❌ OBSERVER SETUP FAILED")
                print("   Cannot access App Group: \(appGroupName)")
                print("   Stop button will NOT work!")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                return
            }

            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("👂 OBSERVER SETUP SUCCESSFUL")
            print("   📂 App Group: \(appGroupName)")
            print("   ⏱️ Polling interval: 0.5 seconds")
            print("   🔍 Watching key: 'stop_live_activity'")

            // Clear any stale flags
            let initialValue = sharedDefaults.bool(forKey: "stop_live_activity")
            if initialValue {
                print("   🧹 Clearing stale stop flag from previous session")
                sharedDefaults.set(false, forKey: "stop_live_activity")
                sharedDefaults.synchronize()
            } else {
                print("   ✅ No stale flags detected")
            }

            print("   ✅ Observer ready - Stop button will work!")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            var checkCount = 0

            // Poll every 0.5 seconds to check for stop flag
            // (UserDefaults doesn't have real-time change notifications across processes)
            stopRequestObserver = Timer.publish(every: 0.5, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    checkCount += 1

                    // Debug: print poll status every 10 checks (5 seconds)
                    if checkCount % 10 == 0 {
                        let flagValue = sharedDefaults.bool(forKey: "stop_live_activity")
                        print("👂 Observer check #\(checkCount): stop_live_activity = \(flagValue)")
                    }

                    if sharedDefaults.bool(forKey: "stop_live_activity") {
                        let timestamp = sharedDefaults.double(forKey: "stop_live_activity_timestamp")
                        let timestampDate = Date(timeIntervalSince1970: timestamp)
                        let timestampString = DateFormatter.localizedString(from: timestampDate, dateStyle: .none, timeStyle: .medium)

                        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        print("🛑 STOP REQUEST RECEIVED FROM WIDGET")
                        print("   ⏰ Widget timestamp: \(timestampString)")
                        print("   🔍 Current check #\(checkCount)")
                        print("   📱 Process: MAIN APP")
                        print("   🔄 Terminating Live Activity...")
                        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                        // Clear the flag IMMEDIATELY
                        sharedDefaults.set(false, forKey: "stop_live_activity")
                        let syncSuccess = sharedDefaults.synchronize()
                        print("   🧹 Cleared stop flag, synchronize() = \(syncSuccess)")

                        // Stop Live Activity
                        Task {
                            let activities = Activity<MeshActivityAttributes>.activities
                            print("   📊 Found \(activities.count) active Live Activities")

                            for activity in activities {
                                print("   🗑️  Ending activity ID: \(activity.id)")
                                await activity.end(nil, dismissalPolicy: .immediate)
                                print("      ✅ Activity ended successfully")
                            }

                            print("✅ ALL LIVE ACTIVITIES STOPPED")
                            print("   🎯 Triggered by: Widget Stop button")
                            print("   ⏱️ Total checks before detection: \(checkCount)")
                            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

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
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔗 DEEP LINK RECEIVED")
        print("   📱 URL: \(url.absoluteString)")
        print("   🔍 Scheme: \(url.scheme ?? "none")")
        print("   🔍 Host: \(url.host ?? "none")")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        guard url.scheme == "meshred" else {
            print("   ❌ Unknown URL scheme: \(url.scheme ?? "nil")")
            return
        }

        if url.host == "stop-live-activity" || url.absoluteString.contains("stop-live-activity") {
            print("   ✅ STOP LIVE ACTIVITY COMMAND DETECTED")
            print("   🛑 Processing stop request immediately...")

            #if !targetEnvironment(simulator)
            if #available(iOS 16.1, *) {
                Task {
                    let activities = Activity<MeshActivityAttributes>.activities
                    print("   📊 Found \(activities.count) active Live Activities")

                    for activity in activities {
                        print("   🗑️  Ending activity ID: \(activity.id)")
                        await activity.end(nil, dismissalPolicy: .immediate)
                        print("      ✅ Activity ended successfully")
                    }

                    print("✅ ALL LIVE ACTIVITIES STOPPED VIA DEEP LINK")
                    print("   🎯 Triggered by: Dynamic Island Stop button")
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                    // Minimize app after a brief delay to allow stop to complete
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

                    await MainActor.run {
                        // Request to minimize app (return to home screen)
                        print("📱 Attempting to minimize app...")

                        // Note: There's no official API to programmatically minimize the app
                        // The app will remain in foreground, but Live Activity will be stopped
                        // User can manually swipe up to dismiss
                    }
                }
            }
            #endif
        } else {
            print("   ❌ Unknown deep link host: \(url.host ?? "nil")")
        }
    }
}
