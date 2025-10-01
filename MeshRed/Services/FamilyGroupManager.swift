//
//  FamilyGroupManager.swift
//  MeshRed
//
//  Created by Claude for StadiumConnect Pro
//

import Foundation
import Combine

/// Manages family groups with UserDefaults persistence
/// Similar pattern to MessageStore but for family groups
class FamilyGroupManager: ObservableObject {
    // MARK: - Published Properties
    @Published var currentGroup: FamilyGroup?
    @Published var hasActiveGroup: Bool = false

    // MARK: - Private Properties
    private let userDefaultsKey = "StadiumConnect.FamilyGroup"
    private let queue = DispatchQueue(label: "com.meshred.familygroup", qos: .userInitiated)

    // MARK: - Initialization
    init() {
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

                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("👨‍👩‍👧‍👦 FAMILY GROUP CREATED")
                print("   Name: \(group.name)")
                print("   Code: \(group.code.displayCode)")
                print("   Creator: \(creatorPeerID)")
                print("   Members: \(group.memberCount)")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
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

                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("👨‍👩‍👧‍👦 JOINED FAMILY GROUP")
                print("   Code: \(code.displayCode)")
                print("   Member: \(memberPeerID)")
                print("   Nickname: \(memberNickname ?? "N/A")")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
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

                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("✅ JOINED FAMILY GROUP WITH FULL INFO")
                print("   Name: \(groupName)")
                print("   Code: \(code.displayCode)")
                print("   Members: \(allMembers.count)")
                print("   Creator: \(creatorPeerID)")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
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

                print("👨‍👩‍👧‍👦 Left family group")
            }
        }
    }

    /// Handle received family sync message from a peer
    func handleFamilySync(_ syncMessage: FamilySyncMessage) {
        queue.async { [weak self] in
            guard let self = self,
                  var group = self.currentGroup else {
                print("⚠️ FamilyGroupManager: No active group, ignoring sync")
                return
            }

            // Check if codes match
            guard group.code == syncMessage.groupCode else {
                print("⚠️ FamilyGroupManager: Code mismatch - \(group.code.displayCode) != \(syncMessage.groupCode.displayCode)")
                return
            }

            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("🤝 FAMILY SYNC RECEIVED")
            print("   From: \(syncMessage.senderId)")
            print("   Code Match: ✅")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            // Convert sync message to family member
            let member = syncMessage.memberInfo.toFamilyMember(peerID: syncMessage.senderId)

            // Add or update member
            group.addMember(member)

            DispatchQueue.main.async {
                self.currentGroup = group
                self.saveGroup()

                print("✅ Family member added/updated: \(syncMessage.senderId)")
                print("   Total members: \(group.memberCount)")
            }
        }
    }

    /// Check if a peer is a family member
    func isFamilyMember(peerID: String) -> Bool {
        return currentGroup?.hasMember(withPeerID: peerID) ?? false
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
            print("👨‍👩‍👧‍👦 FamilyGroupManager: No saved family group found")
            DispatchQueue.main.async {
                self.currentGroup = nil
                self.hasActiveGroup = false
            }
            return
        }

        DispatchQueue.main.async {
            self.currentGroup = group
            self.hasActiveGroup = true
            print("👨‍👩‍👧‍👦 FamilyGroupManager: Loaded family group '\(group.name)' with \(group.memberCount) members")
        }
    }

    private func saveGroup() {
        do {
            if let group = currentGroup {
                let data = try JSONEncoder().encode(group)
                UserDefaults.standard.set(data, forKey: userDefaultsKey)
                print("💾 FamilyGroupManager: Saved family group '\(group.name)'")
            } else {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
                print("💾 FamilyGroupManager: Cleared family group")
            }
        } catch {
            print("❌ FamilyGroupManager: Failed to save group: \(error.localizedDescription)")
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
