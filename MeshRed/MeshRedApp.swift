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
}
