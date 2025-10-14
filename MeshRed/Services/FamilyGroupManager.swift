//
//  FamilyGroupManager.swift
//  MeshRed
//
//  Created by Claude for StadiumConnect Pro
//

import Foundation
import Combine
import os

/// Manages family groups with UserDefaults persistence
/// Similar pattern to MessageStore but for family groups
class FamilyGroupManager: ObservableObject {
    // MARK: - Published Properties
    @Published var currentGroup: FamilyGroup?
    @Published var hasActiveGroup: Bool = false

    // MARK: - Private Properties
    private let userDefaultsKey = "StadiumConnect.FamilyGroup"
    private let historicalMembersKey = "StadiumConnect.FamilyGroup.HistoricalMembers"
    private let queue = DispatchQueue(label: "com.meshred.familygroup", qos: .userInitiated)
    private var historicalMemberPeerIDs: Set<String> = []

    // MARK: - Initialization
    init() {
        loadHistoricalMembers()
        loadGroup()
    }

    // MARK: - Public Methods

    /// Create a new family group
    func createGroup(name: String, creatorPeerID: String, creatorNickname: String? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let group = FamilyGroup.create(
                name: name,
                creatorPeerID: creatorPeerID,
                creatorNickname: creatorNickname
            )

            DispatchQueue.main.async {
                self.currentGroup = group
                self.hasActiveGroup = true
                self.saveGroup()

                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                LoggingService.network.info("👨‍👩‍👧‍👦 FAMILY GROUP CREATED")
                LoggingService.network.info("   Name: \(group.name)")
                LoggingService.network.info("   Code: \(group.code.displayCode)")
                LoggingService.network.info("   Creator: \(creatorPeerID)")
                LoggingService.network.info("   Members: \(group.memberCount)")
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            }
        }
    }

    /// Join an existing family group
    func joinGroup(code: FamilyGroupCode, groupName: String, memberPeerID: String, memberNickname: String? = nil, relationshipTag: String? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let member = FamilyMember(
                peerID: memberPeerID,
                nickname: memberNickname,
                relationshipTag: relationshipTag,
                lastSeenDate: Date(),
                isCurrentDevice: true
            )

            var group = FamilyGroup(
                name: groupName,
                code: code,
                members: [member],
                creatorPeerID: memberPeerID  // Not the real creator, but we don't know it yet
            )

            DispatchQueue.main.async {
                self.currentGroup = group
                self.hasActiveGroup = true
                self.saveGroup()

                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                LoggingService.network.info("👨‍👩‍👧‍👦 JOINED FAMILY GROUP")
                LoggingService.network.info("   Code: \(code.displayCode)")
                LoggingService.network.info("   Member: \(memberPeerID)")
                LoggingService.network.info("   Nickname: \(memberNickname ?? "N/A")")
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            }
        }
    }

    /// Join group with complete information received from network
    func joinGroupWithFullInfo(
        code: FamilyGroupCode,
        groupName: String,
        creatorPeerID: String,
        members: [FamilyGroupInfoMessage.SimplifiedMemberInfo],
        currentPeerID: String,
        currentNickname: String?,
        currentRelationshipTag: String?
    ) {
        queue.async { [weak self] in
            guard let self = self else { return }

            // Create current member
            let currentMember = FamilyMember(
                peerID: currentPeerID,
                nickname: currentNickname,
                relationshipTag: currentRelationshipTag,
                lastSeenDate: Date(),
                isCurrentDevice: true
            )

            // Convert received members
            var allMembers = members.map { info in
                info.toFamilyMember()
            }

            // Add current member
            allMembers.append(currentMember)

            // Create group
            let group = FamilyGroup(
                name: groupName,
                code: code,
                members: allMembers,
                creatorPeerID: creatorPeerID
            )

            DispatchQueue.main.async {
                self.currentGroup = group
                self.hasActiveGroup = true
                self.saveGroup()

                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                LoggingService.network.info("✅ JOINED FAMILY GROUP WITH FULL INFO")
                LoggingService.network.info("   Name: \(groupName)")
                LoggingService.network.info("   Code: \(code.displayCode)")
                LoggingService.network.info("   Members: \(allMembers.count)")
                LoggingService.network.info("   Creator: \(creatorPeerID)")
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            }
        }
    }

    /// Leave current family group
    func leaveGroup() {
        queue.async { [weak self] in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.currentGroup = nil
                self.hasActiveGroup = false
                self.saveGroup()

                LoggingService.network.info("👨‍👩‍👧‍👦 Left family group")
            }
        }
    }

    /// Handle received family sync message from a peer
    func handleFamilySync(_ syncMessage: FamilySyncMessage) {
        queue.async { [weak self] in
            guard let self = self,
                  var group = self.currentGroup else {
                LoggingService.network.info("⚠️ FamilyGroupManager: No active group, ignoring sync")
                return
            }

            // Check if codes match
            guard group.code == syncMessage.groupCode else {
                LoggingService.network.info("⚠️ FamilyGroupManager: Code mismatch - \(group.code.displayCode) != \(syncMessage.groupCode.displayCode)")
                return
            }

            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            LoggingService.network.info("🤝 FAMILY SYNC RECEIVED")
            LoggingService.network.info("   From: \(syncMessage.senderId)")
            LoggingService.network.info("   Code Match: ✅")
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            // Convert sync message to family member
            let member = syncMessage.memberInfo.toFamilyMember(peerID: syncMessage.senderId)

            // Add or update member
            group.addMember(member)

            DispatchQueue.main.async {
                self.currentGroup = group
                self.saveGroup()

                LoggingService.network.info("✅ Family member added/updated: \(syncMessage.senderId)")
                LoggingService.network.info("   Total members: \(group.memberCount)")
            }
        }
    }

    /// Check if a peer is a family member
    func isFamilyMember(peerID: String) -> Bool {
        return currentGroup?.hasMember(withPeerID: peerID) ?? false
    }

    /// Check if a peer was ever a family member (historical)
    func wasEverFamilyMember(peerID: String) -> Bool {
        return historicalMemberPeerIDs.contains(peerID)
    }

    /// Update member's last seen timestamp
    func updateMemberLastSeen(peerID: String) {
        queue.async { [weak self] in
            guard let self = self,
                  var group = self.currentGroup else { return }

            group.updateMemberLastSeen(peerID: peerID)

            DispatchQueue.main.async {
                self.currentGroup = group
                self.saveGroup()
            }
        }
    }

    /// Update member's location
    func updateMemberLocation(peerID: String, location: UserLocation) {
        queue.async { [weak self] in
            guard let self = self,
                  var group = self.currentGroup else { return }

            group.updateMemberLocation(peerID: peerID, location: location)

            DispatchQueue.main.async {
                self.currentGroup = group
                self.saveGroup()
            }
        }
    }

    /// Get family member info
    func getMember(withPeerID peerID: String) -> FamilyMember? {
        return currentGroup?.getMember(withPeerID: peerID)
    }

    /// Update current device's nickname
    func updateCurrentNickname(_ nickname: String, currentPeerID: String) {
        queue.async { [weak self] in
            guard let self = self,
                  var group = self.currentGroup,
                  let memberIndex = group.members.firstIndex(where: { $0.peerID == currentPeerID }) else {
                return
            }

            group.members[memberIndex].nickname = nickname

            DispatchQueue.main.async {
                self.currentGroup = group
                self.saveGroup()
            }
        }
    }

    /// Update current device's relationship tag
    func updateCurrentRelationshipTag(_ tag: String, currentPeerID: String) {
        queue.async { [weak self] in
            guard let self = self,
                  var group = self.currentGroup,
                  let memberIndex = group.members.firstIndex(where: { $0.peerID == currentPeerID }) else {
                return
            }

            group.members[memberIndex].relationshipTag = tag

            DispatchQueue.main.async {
                self.currentGroup = group
                self.saveGroup()
            }
        }
    }

    // MARK: - Private Methods

    private func loadGroup() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let group = try? JSONDecoder().decode(FamilyGroup.self, from: data) else {
            LoggingService.network.info("👨‍👩‍👧‍👦 FamilyGroupManager: No saved family group found")
            DispatchQueue.main.async {
                self.currentGroup = nil
                self.hasActiveGroup = false
            }
            return
        }

        DispatchQueue.main.async {
            self.currentGroup = group
            self.hasActiveGroup = true
            LoggingService.network.info("👨‍👩‍👧‍👦 FamilyGroupManager: Loaded family group '\(group.name)' with \(group.memberCount) members")
        }
    }

    private func saveGroup() {
        do {
            if let group = currentGroup {
                let data = try JSONEncoder().encode(group)
                UserDefaults.standard.set(data, forKey: userDefaultsKey)
                LoggingService.network.info("💾 FamilyGroupManager: Saved family group '\(group.name)'")

                // Update historical members
                for member in group.members {
                    historicalMemberPeerIDs.insert(member.peerID)
                }
                saveHistoricalMembers()
            } else {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
                LoggingService.network.info("💾 FamilyGroupManager: Cleared family group")
            }
        } catch {
            LoggingService.network.info("❌ FamilyGroupManager: Failed to save group: \(error.localizedDescription)")
        }
    }

    private func loadHistoricalMembers() {
        if let data = UserDefaults.standard.data(forKey: historicalMembersKey),
           let memberIDs = try? JSONDecoder().decode(Set<String>.self, from: data) {
            historicalMemberPeerIDs = memberIDs
            LoggingService.network.info("📚 FamilyGroupManager: Loaded \(memberIDs.count) historical members")
        }
    }

    private func saveHistoricalMembers() {
        do {
            let data = try JSONEncoder().encode(historicalMemberPeerIDs)
            UserDefaults.standard.set(data, forKey: historicalMembersKey)
            LoggingService.network.info("💾 FamilyGroupManager: Saved \(self.historicalMemberPeerIDs.count, privacy: .public) historical members")
        } catch {
            LoggingService.network.info("❌ FamilyGroupManager: Failed to save historical members: \(error.localizedDescription)")
        }
    }

    // MARK: - Computed Properties

    var familyMemberPeerIDs: [String] {
        return currentGroup?.members.map { $0.peerID } ?? []
    }

    var otherFamilyMembers: [FamilyMember] {
        return currentGroup?.otherMembers ?? []
    }

    var memberCount: Int {
        return currentGroup?.memberCount ?? 0
    }

    var groupCode: FamilyGroupCode? {
        return currentGroup?.code
    }

    var groupName: String? {
        return currentGroup?.name
    }
}
