//
//  MessagingDashboardView.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//

import SwiftUI
import MultipeerConnectivity
import Combine

struct MessagingDashboardView: View {
    @EnvironmentObject var networkManager: NetworkManager
    @Binding var hideBottomBar: Bool

    // MARK: - State
    @State private var showBroadcastComposer = false
    @State private var showFamilyGroupOptions = false
    @State private var showSimulationControl = false
    @State private var navigationPath = NavigationPath()
    @StateObject private var mockGroupsManager = MockFamilyGroupsManager.shared
    @StateObject private var readStateManager = MessageReadStateManager.shared

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                // Top bar (like home view)
                topBar

                // Chat list
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        // Family groups section
                        if networkManager.familyGroupManager.hasActiveGroup {
                            familyGroupsSection
                        }

                        // Individual chats section
                        individualChatsSection

                        // Extra spacing for bottom nav (increased to account for bottom bar)
                        Color.clear.frame(height: 100)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }

                Spacer()
            }
            .background(appBackgroundColor.ignoresSafeArea())
            .navigationDestination(for: ChatItem.self) { chat in
                ChatConversationView(chat: chat, networkManager: networkManager)
                    .onAppear {
                        withAnimation {
                            hideBottomBar = true
                        }
                    }
                    .onDisappear {
                        withAnimation {
                            hideBottomBar = false
                        }
                    }
            }
            .onChange(of: navigationPath) { oldPath, newPath in
                // Hide bottom bar when navigating to a conversation
                withAnimation {
                    hideBottomBar = !newPath.isEmpty
                }
            }
            .sheet(isPresented: $showBroadcastComposer) {
                BroadcastMessageComposer(networkManager: networkManager)
            }
            .sheet(isPresented: $showFamilyGroupOptions) {
                FamilyGroupEmptyStateView(
                    familyGroupManager: networkManager.familyGroupManager,
                    localPeerID: networkManager.localDeviceName
                )
                .environmentObject(networkManager)
            }
            .sheet(isPresented: $showSimulationControl) {
                SimulationControlPanelView()
                    .environmentObject(networkManager)
            }
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mensajes")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(Mundial2026Colors.textPrimary)
                Text("\(networkManager.connectedPeers.count) conectados")
                    .font(.subheadline)
                    .foregroundColor(Mundial2026Colors.textSecondary)
            }

            Spacer()

            HStack(spacing: 12) {
                // Broadcast button
                Button(action: { showBroadcastComposer = true }) {
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(Mundial2026Colors.rojo)
                        )
                        .shadow(color: Mundial2026Colors.rojo.opacity(0.25), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(.plain)

                // Create group button (circle like in home)
                Button(action: { showFamilyGroupOptions = true }) {
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundColor(Mundial2026Colors.azul)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.95))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    // MARK: - Family Groups Section
    private var familyGroupsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let familyGroup = networkManager.familyGroupManager.currentGroup {
                let chatItem = ChatItem(
                    id: "family-\(familyGroup.id)",
                    type: .familyGroup,
                    title: familyGroup.name,
                    subtitle: "\(familyGroup.members.count) miembros",
                    peerID: nil
                )

                NavigationLink(value: chatItem) {
                    ChatRowItemView(
                        icon: "person.3.fill",
                        title: familyGroup.name,
                        subtitle: "\(familyGroup.members.count) miembros",
                        iconColor: .white,
                        backgroundColor: Mundial2026Colors.verde,
                        showBadge: false
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Individual Chats Section
    private var individualChatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Mock family groups (now includes simulated groups if active)
            ForEach(MockDataManager.getMockFamilyGroups()) { group in
                let chatItem = ChatItem(
                    id: group.id,
                    type: .familyGroup,
                    title: group.name,
                    subtitle: group.lastMessage,
                    peerID: nil
                )

                NavigationLink(value: chatItem) {
                    ChatRowItemView(
                        icon: "person.3.fill",
                        title: group.name,
                        subtitle: group.lastMessage,
                        iconColor: .white,
                        backgroundColor: Mundial2026Colors.verde,
                        showBadge: group.unreadCount > 0,
                        badgeCount: group.unreadCount,
                        lastMessageTime: group.lastMessageTime
                    )
                }
                .buttonStyle(.plain)
            }

            // Mock individual chats
            ForEach(MockDataManager.mockIndividualChats) { chat in
                let chatItem = ChatItem(
                    id: chat.id,
                    type: .individual,
                    title: chat.name,
                    subtitle: chat.lastMessage,
                    peerID: nil
                )

                NavigationLink(value: chatItem) {
                    ChatRowItemView(
                        icon: "person.circle.fill",
                        title: chat.name,
                        subtitle: chat.lastMessage,
                        iconColor: .white,
                        backgroundColor: Mundial2026Colors.azul,
                        showBadge: chat.unreadCount > 0,
                        badgeCount: chat.unreadCount,
                        lastMessageTime: chat.lastMessageTime
                    )
                }
                .buttonStyle(.plain)
            }

            // Connected peers (if any) - show below mock data
            ForEach(networkManager.connectedPeers, id: \.self) { peer in
                let isFamilyMember = networkManager.familyGroupManager.isFamilyMember(peerID: peer.displayName)
                let displayName = isFamilyMember ?
                    (networkManager.familyGroupManager.getMember(withPeerID: peer.displayName)?.displayName ?? peer.displayName) :
                    peer.displayName

                let chatItem = ChatItem(
                    id: peer.displayName,
                    type: .individual,
                    title: displayName,
                    subtitle: "Conectado",
                    peerID: peer
                )

                NavigationLink(value: chatItem) {
                    ChatRowItemView(
                        icon: "person.circle.fill",
                        title: displayName,
                        subtitle: isFamilyMember ? "Familia • Conectado" : "Conectado ✅",
                        iconColor: .white,
                        backgroundColor: isFamilyMember ? Mundial2026Colors.verde : Color.purple,
                        showBadge: false
                    )
                }
                .buttonStyle(.plain)
            }

            // Reachable family members (indirect connection)
            let reachableMembers = getReachableFamilyMembers()
            ForEach(reachableMembers, id: \.peerID) { member in
                let chatItem = ChatItem(
                    id: member.peerID,
                    type: .individual,
                    title: member.displayName,
                    subtitle: "Indirecto",
                    peerID: nil
                )

                NavigationLink(value: chatItem) {
                    ChatRowItemView(
                        icon: "person.circle.fill",
                        title: member.displayName,
                        subtitle: "Familia • Via \(member.route.first ?? "red")",
                        iconColor: .white,
                        backgroundColor: Color.pink.opacity(0.5),
                        showBadge: false
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers
    private var appBackgroundColor: Color {
        Color(red: 0.98, green: 0.98, blue: 0.99)
    }

    private func getReachableFamilyMembers() -> [(peerID: String, displayName: String, route: [String])] {
        guard let familyGroup = networkManager.familyGroupManager.currentGroup else {
            return []
        }

        var reachable: [(peerID: String, displayName: String, route: [String])] = []

        for member in familyGroup.members {
            // Skip self
            if member.peerID == networkManager.localDeviceName {
                continue
            }

            // Skip directly connected
            if networkManager.connectedPeers.contains(where: { $0.displayName == member.peerID }) {
                continue
            }

            // Check if reachable indirectly
            if networkManager.routingTable.isReachable(member.peerID),
               let nextHops = networkManager.routingTable.getNextHops(to: member.peerID) {
                reachable.append((
                    peerID: member.peerID,
                    displayName: member.displayName,
                    route: nextHops
                ))
            }
        }

        return reachable
    }
}

// MARK: - Chat Row Item Component
struct ChatRowItemView: View {
    let icon: String
    let title: String
    let subtitle: String
    let iconColor: Color
    let backgroundColor: Color
    var showBadge: Bool = false
    var badgeCount: Int = 0
    var lastMessageTime: Date? = nil

    var body: some View {
            HStack(spacing: 16) {
                // Icon circle
                ZStack {
                    Circle()
                        .fill(backgroundColor)
                        .frame(width: 56, height: 56)

                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundColor(iconColor)
                }

                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)

                        Spacer()

                        // Timestamp
                        if let time = lastMessageTime {
                            Text(MockDataManager.formatTimeAgo(from: time))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }

                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // Badge
                if showBadge && badgeCount > 0 {
                    Circle()
                        .fill(Mundial2026Colors.rojo)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Text("\(badgeCount)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
            )
    }
}

// MARK: - Chat Item Model
struct ChatItem: Identifiable, Hashable {
    let id: String
    let type: ChatType
    let title: String
    let subtitle: String
    let peerID: MCPeerID?

    enum ChatType: Hashable {
        case familyGroup
        case individual
        case broadcast
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ChatItem, rhs: ChatItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Broadcast Message Composer
struct BroadcastMessageComposer: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var networkManager: NetworkManager
    @State private var messageText = ""
    @State private var selectedType: MessageType = .chat

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Message type picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tipo de mensaje")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Picker("Tipo", selection: $selectedType) {
                        ForEach(MessageType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Message input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mensaje")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextEditor(text: $messageText)
                        .frame(height: 150)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                }

                // Connected peers count
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(.blue)
                    Text("\(networkManager.connectedPeers.count) dispositivos conectados")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }

                Spacer()

                // Send button
                Button(action: sendBroadcast) {
                    HStack {
                        Image(systemName: "paperplane.fill")
                        Text("Enviar a todos")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(messageText.isEmpty ? Color.gray : Mundial2026Colors.verde)
                    )
                }
                .disabled(messageText.isEmpty)
                .buttonStyle(.plain)
            }
            .padding(20)
            .navigationTitle("Mensaje Broadcast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func sendBroadcast() {
        guard !messageText.isEmpty else { return }

        networkManager.sendMessage(
            messageText,
            type: selectedType,
            recipientId: "broadcast",
            requiresAck: false
        )

        messageText = ""
        dismiss()
    }
}

// MARK: - Chat Conversation View
struct ChatConversationView: View {
    let chat: ChatItem
    @ObservedObject var networkManager: NetworkManager
    @State private var messageText = ""
    @State private var showUWBNavigation = false
    @StateObject private var readStateManager = MessageReadStateManager.shared
    @StateObject private var mockGroupsManager = MockFamilyGroupsManager.shared

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Show mock messages for demo
                ForEach(MockDataManager.mockConversationMessages(for: chat.id)) { mockMsg in
                    MockMessageBubble(
                        message: mockMsg,
                        isFromLocal: mockMsg.type == .sent
                    )
                }

                // Show simulated messages if this is a simulated group
                if chat.type == .familyGroup, let groupData = mockGroupsManager.activeGroupData {
                    ForEach(groupData.members.filter { !$0.recentMessages.isEmpty }, id: \.peerID) { member in
                        ForEach(member.recentMessages) { simMsg in
                            SimulatedMessageBubble(
                                message: simMsg,
                                senderName: member.nickname,
                                isFromLocal: simMsg.senderId == networkManager.localDeviceName
                            )
                        }
                    }
                }

                // Show real messages if peer is connected
                if chat.peerID != nil {
                    ForEach(filteredMessages) { message in
                        MessageBubble(
                            message: message,
                            isFromLocal: message.sender == networkManager.localDeviceName,
                            showSenderName: true
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 12) {
                TextField("Mensaje...", text: $messageText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(24)
                    .submitLabel(.send)
                    .onSubmit {
                        sendMessage()
                    }

                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(messageText.isEmpty ? Color.gray : Mundial2026Colors.verde))
                }
                .disabled(messageText.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Color.white
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: -2)
            )
        }
        .onAppear {
            markMessagesAsRead()
        }
        .navigationTitle(chat.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if chat.type == .individual, chat.peerID != nil {
                    Button(action: {
                        openUWBNavigation()
                    }) {
                        Image(systemName: "location.fill")
                            .foregroundColor(Mundial2026Colors.azul)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showUWBNavigation) {
            if let peerID = chat.peerID,
               let uwbManager = networkManager.uwbSessionManager {
                LinkFinderNavigationView(
                    targetName: chat.title,
                    targetPeerID: peerID,
                    uwbManager: uwbManager,
                    locationService: networkManager.locationService,
                    peerLocationTracker: networkManager.peerLocationTracker,
                    networkManager: networkManager,
                    onDismiss: {
                        showUWBNavigation = false
                    }
                )
            } else {
                // Fallback: LinkFinder not available
                UWBNotAvailableView(onDismiss: {
                    showUWBNavigation = false
                })
            }
        }
    }

    private var filteredMessages: [Message] {
        switch chat.type {
        case .familyGroup:
            // Show family group messages
            return networkManager.messageStore.messages.filter { message in
                // This would need proper family group message filtering
                true
            }
        case .individual:
            // Show messages from specific peer
            guard let peerID = chat.peerID else { return [] }
            return networkManager.messageStore.messages.filter { message in
                message.sender == peerID.displayName ||
                (message.sender == networkManager.localDeviceName && message.recipientId == peerID.displayName)
            }
        case .broadcast:
            return networkManager.messageStore.messages.filter { $0.recipientId == "broadcast" }
        }
    }

    private func sendMessage() {
        guard !messageText.isEmpty else { return }

        let recipientId: String
        switch chat.type {
        case .familyGroup:
            recipientId = "broadcast" // Would need proper family group handling
        case .individual:
            recipientId = chat.peerID?.displayName ?? "broadcast"
        case .broadcast:
            recipientId = "broadcast"
        }

        networkManager.sendMessage(
            messageText,
            type: .chat,
            recipientId: recipientId,
            requiresAck: false
        )

        messageText = ""
    }

    private func openUWBNavigation() {
        guard let peerID = chat.peerID else {
            print("❌ No peer ID available for navigation")
            return
        }

        // Ensure LinkFinder session exists
        if let uwbManager = networkManager.uwbSessionManager {
            // Check if LinkFinder is supported
            guard uwbManager.isLinkFinderSupported else {
                print("⚠️ LinkFinder not supported on this device")
                showUWBNavigation = true  // Will show fallback view
                return
            }

            // Ensure LinkFinder session is active with this peer
            if !uwbManager.hasActiveSession(with: peerID) {
                print("📡 Starting LinkFinder session for navigation with \(peerID.displayName)")
                // LinkFinder session will be started automatically by NetworkManager
                // when peer is connected
            }

            showUWBNavigation = true
        } else {
            print("⚠️ LinkFinder Manager not initialized")
            showUWBNavigation = true  // Will show fallback view
        }
    }

    private func markMessagesAsRead() {
        print("🔍 [MarkAsRead] Called - chat.type: \(chat.type), chat.id: \(chat.id)")

        // Only mark messages as read for simulated groups
        guard chat.type == .familyGroup else {
            print("⚠️ [MarkAsRead] Not a family group, skipping")
            return
        }

        guard let groupData = mockGroupsManager.activeGroupData else {
            print("⚠️ [MarkAsRead] No active group data, skipping")
            return
        }

        // Use the actual group ID from the active simulation
        let groupId = groupData.id
        print("📋 [MarkAsRead] Group ID: \(groupId), Name: \(groupData.name)")

        // Build dictionary of member messages
        var memberMessages: [String: [UUID]] = [:]
        for member in groupData.members {
            if !member.recentMessages.isEmpty {
                memberMessages[member.peerID] = member.recentMessages.map { $0.id }
                print("   - \(member.nickname): \(member.recentMessages.count) messages")
            }
        }

        let totalMessages = memberMessages.values.flatMap { $0 }.count
        print("📊 [MarkAsRead] Total messages to mark: \(totalMessages)")

        // Mark all as read
        readStateManager.markAllGroupMessagesAsRead(
            groupId: groupId,
            memberMessages: memberMessages
        )

        print("✅ [MarkAsRead] Marked \(totalMessages) messages as read for group \(groupId)")

        // Force refresh of parent view
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("🔄 [MarkAsRead] Triggering UI refresh...")
            self.mockGroupsManager.objectWillChange.send()
        }
    }
}

// MARK: - Simulated Message Bubble
struct SimulatedMessageBubble: View {
    let message: SimulatedMessage
    let senderName: String
    let isFromLocal: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if isFromLocal {
                Spacer(minLength: 0)
            }

            VStack(alignment: isFromLocal ? .trailing : .leading, spacing: 6) {
                if !isFromLocal {
                    Text(senderName)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }

                Text(message.content)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleColor)
                    .foregroundColor(isFromLocal ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text(message.timeAgo)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: 260, alignment: isFromLocal ? .trailing : .leading)

            if !isFromLocal {
                Spacer(minLength: 0)
            }
        }
    }

    private var bubbleColor: Color {
        if isFromLocal {
            return Mundial2026Colors.verde
        } else {
            return Color.gray.opacity(0.2)
        }
    }
}

// MARK: - LinkFinder Not Available View
struct UWBNotAvailableView: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                // Icon
                Image(systemName: "location.slash.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.orange)

                // Title
                Text("Navegación LinkFinder No Disponible")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                // Message
                VStack(spacing: 12) {
                    Text("La navegación precisa LinkFinder requiere:")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.8))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("iPhone 11 o posterior con chip U1/U2")
                                .font(.subheadline)
                        }

                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Dispositivo físico (no simulador)")
                                .font(.subheadline)
                        }

                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Permisos de localización activos")
                                .font(.subheadline)
                        }
                    }
                    .foregroundColor(.white.opacity(0.9))
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding(.horizontal)

                // Info
                Text("Puedes seguir usando la mensajería mesh sin LinkFinder")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                // Close button
                Button(action: onDismiss) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("Cerrar")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(Mundial2026Colors.azul)
                    .cornerRadius(12)
                }
                .padding(.bottom, 40)
            }
            .padding()
        }
    }
}

// MARK: - Mock Message Bubble
struct MockMessageBubble: View {
    let message: MockMessage
    let isFromLocal: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if isFromLocal {
                Spacer(minLength: 0)
            }

            VStack(alignment: isFromLocal ? .trailing : .leading, spacing: 6) {
                if !isFromLocal {
                    Text(message.sender)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }

                Text(message.content)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleColor)
                    .foregroundColor(isFromLocal ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text(MockDataManager.formatTimeAgo(from: message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: 260, alignment: isFromLocal ? .trailing : .leading)

            if !isFromLocal {
                Spacer(minLength: 0)
            }
        }
    }

    private var bubbleColor: Color {
        if isFromLocal {
            return Mundial2026Colors.verde
        } else {
            return Color.gray.opacity(0.2)
        }
    }
}

// MARK: - Preview
#Preview {
    MessagingDashboardView(hideBottomBar: .constant(false))
        .environmentObject(NetworkManager())
}
