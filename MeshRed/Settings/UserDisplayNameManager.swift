//
//  UserDisplayNameManager.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Manages user display names with persistence
//

import Foundation
import Combine

/// Manages user display name configuration
class UserDisplayNameManager: ObservableObject {
    static let shared = UserDisplayNameManager()

    @Published var settings: UserDisplayNameSettings

    private let userDefaults = UserDefaults.standard
    private let storageKey = "StadiumConnect.UserDisplayNames"

    private init() {
        // Load from storage
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(UserDisplayNameSettings.self, from: data) {
            self.settings = decoded
            print("📱 [DisplayName] Loaded: public='\(decoded.publicName)', family='\(decoded.familyName)'")
        } else {
            self.settings = UserDisplayNameSettings()
            print("📱 [DisplayName] No saved settings, using defaults")
        }
    }

    // MARK: - Public API

    /// Update public name
    func updatePublicName(_ name: String) {
        settings.publicName = name
        saveSettings()
    }

    /// Update family name
    func updateFamilyName(_ name: String) {
        settings.familyName = name
        saveSettings()
    }

    /// Update device name preference
    func updateUseDeviceNameAsPublic(_ enabled: Bool) {
        settings.useDeviceNameAsPublic = enabled
        saveSettings()
    }

    /// Get display name for a specific context
    func getDisplayName(for context: DisplayNameContext, deviceName: String) -> String {
        if context.shouldUseFamilyName {
            return settings.getFamilyName(deviceName: deviceName)
        } else {
            return settings.getPublicName(deviceName: deviceName)
        }
    }

    /// Get current public name (for MultipeerConnectivity)
    func getCurrentPublicName(deviceName: String) -> String {
        return settings.getPublicName(deviceName: deviceName)
    }

    /// Get current family name
    func getCurrentFamilyName(deviceName: String) -> String {
        return settings.getFamilyName(deviceName: deviceName)
    }

    /// Reset to defaults
    func resetToDefaults() {
        settings = UserDisplayNameSettings()
        saveSettings()
    }

    // MARK: - Persistence

    private func saveSettings() {
        do {
            let encoded = try JSONEncoder().encode(settings)
            userDefaults.set(encoded, forKey: storageKey)
            print("💾 [DisplayName] Saved: public='\(settings.publicName)', family='\(settings.familyName)'")
            objectWillChange.send()
        } catch {
            print("❌ [DisplayName] Failed to save: \(error)")
        }
    }
}
