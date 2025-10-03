//
//  UserDisplayNameSettings.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  User display name configuration
//

import Foundation

/// User display name configuration
struct UserDisplayNameSettings: Codable {
    /// Public name shown to strangers/unknown users
    var publicName: String

    /// Friendly name shown to family members and known contacts
    var familyName: String

    /// Use device name as fallback
    var useDeviceNameAsPublic: Bool

    init(
        publicName: String = "",
        familyName: String = "",
        useDeviceNameAsPublic: Bool = true
    ) {
        self.publicName = publicName
        self.familyName = familyName
        self.useDeviceNameAsPublic = useDeviceNameAsPublic
    }

    /// Get effective public name (with fallback to device name)
    func getPublicName(deviceName: String) -> String {
        if useDeviceNameAsPublic || publicName.trimmingCharacters(in: .whitespaces).isEmpty {
            return deviceName
        }
        return publicName
    }

    /// Get effective family name (with fallback to public name or device name)
    func getFamilyName(deviceName: String) -> String {
        let trimmedFamilyName = familyName.trimmingCharacters(in: .whitespaces)
        if !trimmedFamilyName.isEmpty {
            return trimmedFamilyName
        }
        return getPublicName(deviceName: deviceName)
    }

    /// Check if names are configured
    var isConfigured: Bool {
        return !publicName.trimmingCharacters(in: .whitespaces).isEmpty ||
               !familyName.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// Context for determining which name to show
enum DisplayNameContext {
    case publicPeer        // Unknown peer in network
    case familyMember      // Member of your family group
    case knownContact      // Saved/known contact
    case broadcast         // Broadcast messages

    var shouldUseFamilyName: Bool {
        switch self {
        case .familyMember, .knownContact:
            return true
        case .publicPeer, .broadcast:
            return false
        }
    }
}
