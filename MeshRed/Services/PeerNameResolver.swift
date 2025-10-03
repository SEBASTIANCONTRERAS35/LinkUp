//
//  PeerNameResolver.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Resolves peer display names based on context (family vs public)
//

import Foundation
import MultipeerConnectivity

/// Resolves display names for peers based on relationship context
class PeerNameResolver {
    static let shared = PeerNameResolver()

    private let displayNameManager = UserDisplayNameManager.shared

    private init() {}

    // MARK: - Current User Names

    /// Get the display name for the current user in a given context
    func getCurrentUserName(
        for context: DisplayNameContext,
        deviceName: String,
        isInFamilyGroup: Bool = false
    ) -> String {
        // If in family group or context requires family name, use family name
        if isInFamilyGroup || context.shouldUseFamilyName {
            return displayNameManager.getCurrentFamilyName(deviceName: deviceName)
        }

        // Otherwise use public name
        return displayNameManager.getCurrentPublicName(deviceName: deviceName)
    }

    /// Get nickname for current user when joining/creating family group
    func getCurrentUserFamilyNickname(deviceName: String) -> String {
        return displayNameManager.getCurrentFamilyName(deviceName: deviceName)
    }

    // MARK: - Remote Peer Names

    /// Get display name for a remote peer
    /// - Parameters:
    ///   - peer: The MCPeerID of the peer
    ///   - familyGroupManager: Family group manager to check membership
    ///   - Returns: Display name (uses FamilyMember nickname if in group, otherwise MCPeerID displayName)
    func getDisplayName(
        for peer: MCPeerID,
        in familyGroupManager: FamilyGroupManager
    ) -> String {
        // Check if peer is in current family group
        if let member = familyGroupManager.getMember(withPeerID: peer.displayName) {
            // Use member's display name (which prefers nickname over peerID)
            return member.displayName
        }

        // Not in family group, use MCPeerID displayName (their public name)
        return peer.displayName
    }

    /// Get display name for a peer by peerID string
    func getDisplayName(
        forPeerID peerID: String,
        in familyGroupManager: FamilyGroupManager
    ) -> String {
        // Check if peer is in current family group
        if let member = familyGroupManager.getMember(withPeerID: peerID) {
            // Use member's display name (which prefers nickname over peerID)
            return member.displayName
        }

        // Not in family group, use peerID as-is (their public name)
        return peerID
    }

    /// Check if a peer is in a family group
    func isInFamilyGroup(
        peerID: String,
        familyGroupManager: FamilyGroupManager
    ) -> Bool {
        return familyGroupManager.isFamilyMember(peerID: peerID)
    }

    /// Get context for a peer
    func getContext(
        for peer: MCPeerID,
        in familyGroupManager: FamilyGroupManager
    ) -> DisplayNameContext {
        if familyGroupManager.isFamilyMember(peerID: peer.displayName) {
            return .familyMember
        }
        return .publicPeer
    }
}
