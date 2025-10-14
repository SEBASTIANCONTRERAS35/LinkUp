//
//  DataCleaner.swift
//  MeshRed
//
//  Utility to clear all app data and cache
//

import Foundation
import os

/// Centralized data cleaner for development and testing
class DataCleaner {

    /// Clear ALL app data including UserDefaults, caches, and documents
    static func clearAllData() {
        LoggingService.network.info("🗑️ DataCleaner: Starting complete data wipe...")

        // 1. Clear UserDefaults
        clearUserDefaults()

        // 2. Clear Documents directory
        clearDocumentsDirectory()

        // 3. Clear Caches directory
        clearCachesDirectory()

        // 4. Clear Temporary directory
        clearTemporaryDirectory()

        LoggingService.network.info("✅ DataCleaner: All data cleared successfully!")
    }

    /// Clear all UserDefaults keys
    private static func clearUserDefaults() {
        LoggingService.network.info("🗑️ Clearing UserDefaults...")

        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier!
        defaults.removePersistentDomain(forName: domain)
        defaults.synchronize()

        LoggingService.network.info("   ✓ UserDefaults cleared")
    }

    /// Clear Documents directory
    private static func clearDocumentsDirectory() {
        LoggingService.network.info("🗑️ Clearing Documents directory...")

        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            LoggingService.network.info("   ⚠️ Could not access Documents directory")
            return
        }

        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            for fileURL in fileURLs {
                try FileManager.default.removeItem(at: fileURL)
                LoggingService.network.info("   ✓ Deleted: \(fileURL.lastPathComponent)")
            }
        } catch {
            LoggingService.network.info("   ❌ Error clearing Documents: \(error.localizedDescription)")
        }
    }

    /// Clear Caches directory
    private static func clearCachesDirectory() {
        LoggingService.network.info("🗑️ Clearing Caches directory...")

        guard let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            LoggingService.network.info("   ⚠️ Could not access Caches directory")
            return
        }

        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: cachesURL, includingPropertiesForKeys: nil)
            for fileURL in fileURLs {
                try FileManager.default.removeItem(at: fileURL)
                LoggingService.network.info("   ✓ Deleted: \(fileURL.lastPathComponent)")
            }
        } catch {
            LoggingService.network.info("   ❌ Error clearing Caches: \(error.localizedDescription)")
        }
    }

    /// Clear Temporary directory
    private static func clearTemporaryDirectory() {
        LoggingService.network.info("🗑️ Clearing Temporary directory...")

        let tmpURL = FileManager.default.temporaryDirectory

        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: tmpURL, includingPropertiesForKeys: nil)
            for fileURL in fileURLs {
                try FileManager.default.removeItem(at: fileURL)
                LoggingService.network.info("   ✓ Deleted: \(fileURL.lastPathComponent)")
            }
        } catch {
            LoggingService.network.info("   ❌ Error clearing Temporary: \(error.localizedDescription)")
        }
    }

    /// Clear specific component data
    static func clearComponentData(component: AppComponent) {
        LoggingService.network.info("🗑️ DataCleaner: Clearing \(component.rawValue) data...")

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

        LoggingService.network.info("✅ \(component.rawValue) data cleared")
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
