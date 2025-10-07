//
//  MeshRedApp.swift
//  MeshRed
//
//  Created by Emilio Contreras on 28/09/25.
//

import SwiftUI

@main
struct MeshRedApp: App {
    @StateObject private var networkManager = NetworkManager()
    @StateObject private var accessibilitySettings = AccessibilitySettingsManager.shared

    @Environment(\.scenePhase) private var scenePhase

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

                    // Initialize Stadium Mode Manager with dependencies
                    StadiumModeManager.shared.setup(
                        networkManager: networkManager,
                        locationService: networkManager.locationService
                    )

                    // Start Live Activity when app appears if we have connections
                    startLiveActivityIfNeeded()
                }
                .onChange(of: scenePhase) { newPhase in
                    handleScenePhaseChange(newPhase)
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
            // Wait a bit for connections to establish, then start
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if !networkManager.connectedPeers.isEmpty && !networkManager.hasActiveLiveActivity {
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
                // Start Live Activity if we have connections and none is running
                if !networkManager.connectedPeers.isEmpty && !networkManager.hasActiveLiveActivity {
                    networkManager.startLiveActivity()
                }

            case .inactive:
                print("📱 App became inactive")
                // Keep Live Activity running to maintain background priority

            case .background:
                print("📱 App entered background")
                // Live Activity keeps MultipeerConnectivity alive longer
                // Don't stop it - this is the whole point!

            @unknown default:
                break
            }
        }
        #endif
    }
}
