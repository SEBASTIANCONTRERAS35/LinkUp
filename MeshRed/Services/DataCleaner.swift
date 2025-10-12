//
//  DataCleaner.swift
//  MeshRed
//
//  Utility to clear all app data and cache
//

import Foundation

/// Centralized data cleaner for development and testing
class DataCleaner {

    /// Clear ALL app data including UserDefaults, caches, and documents
    static func clearAllData() {
        print("🗑️ DataCleaner: Starting complete data wipe...")

        // 1. Clear UserDefaults
        clearUserDefaults()

        // 2. Clear Documents directory
        clearDocumentsDirectory()

        // 3. Clear Caches directory
        clearCachesDirectory()

        // 4. Clear Temporary directory
        clearTemporaryDirectory()

        print("✅ DataCleaner: All data cleared successfully!")
    }

    /// Clear all UserDefaults keys
    private static func clearUserDefaults() {
        print("🗑️ Clearing UserDefaults...")

        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier!
        defaults.removePersistentDomain(forName: domain)
        defaults.synchronize()

        print("   ✓ UserDefaults cleared")
    }

    /// Clear Documents directory
    private static func clearDocumentsDirectory() {
        print("🗑️ Clearing Documents directory...")

        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("   ⚠️ Could not access Documents directory")
            return
        }

        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            for fileURL in fileURLs {
                try FileManager.default.removeItem(at: fileURL)
                print("   ✓ Deleted: \(fileURL.lastPathComponent)")
            }
        } catch {
            print("   ❌ Error clearing Documents: \(error.localizedDescription)")
        }
    }

    /// Clear Caches directory
    private static func clearCachesDirectory() {
        print("🗑️ Clearing Caches directory...")

        guard let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            print("   ⚠️ Could not access Caches directory")
            return
        }

        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: cachesURL, includingPropertiesForKeys: nil)
            for fileURL in fileURLs {
                try FileManager.default.removeItem(at: fileURL)
                print("   ✓ Deleted: \(fileURL.lastPathComponent)")
            }
        } catch {
            print("   ❌ Error clearing Caches: \(error.localizedDescription)")
        }
    }

    /// Clear Temporary directory
    private static func clearTemporaryDirectory() {
        print("🗑️ Clearing Temporary directory...")

        let tmpURL = FileManager.default.temporaryDirectory

        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: tmpURL, includingPropertiesForKeys: nil)
            for fileURL in fileURLs {
                try FileManager.default.removeItem(at: fileURL)
                print("   ✓ Deleted: \(fileURL.lastPathComponent)")
            }
        } catch {
            print("   ❌ Error clearing Temporary: \(error.localizedDescription)")
        }
    }

    /// Clear specific component data
    static func clearComponentData(component: AppComponent) {
        print("🗑️ DataCleaner: Clearing \(component.rawValue) data...")

        switch component {
        case .messages:
            clearMessagesData()
        case .connections:
            clearConnectionsData()
        case .geofences:
            clearGeofencesData()
        case .familyGroups:
            clearFamilyGroupsData()
        case .uwbSessions:
            clearUWBSessionsData()
        case .reputation:
            clearReputationData()
        }

        print("✅ \(component.rawValue) data cleared")
    }

    // MARK: - Component-Specific Clearing

    private static func clearMessagesData() {
        let keys = [
            "messages",
            "conversationMetadata",
            "lastReadTimestamps",
            "firstMessageSent",
            "activeConversations",
            "pendingFirstMessageRequests",
            "rejectedFirstMessageRequests",
            "deferredFirstMessageRequests"
        ]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    private static func clearConnectionsData() {
        let keys = [
            "blockedPeers",
            "preferredPeers",
            "lastSeenPeers"
        ]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    private static func clearGeofencesData() {
        let keys = [
            "savedGeofences",
            "geofenceEvents",
            "monitoredGeofenceIds"
        ]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    private static func clearFamilyGroupsData() {
        let keys = [
            "familyGroup",
            "familyGroupMembers"
        ]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    private static func clearUWBSessionsData() {
        let keys = [
            "uwbSessions",
            "uwbPriorities",
            "activeUWBTokens"
        ]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    private static func clearReputationData() {
        let keys = [
            "peerReputations",
            "reputationHistory"
        ]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }
}

// MARK: - App Components

enum AppComponent: String {
    case messages = "Messages"
    case connections = "Connections"
    case geofences = "Geofences"
    case familyGroups = "Family Groups"
    case uwbSessions = "UWB Sessions"
    case reputation = "Reputation System"
}
