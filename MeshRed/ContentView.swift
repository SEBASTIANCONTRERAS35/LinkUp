//
//  ContentView.swift
//  MeshRed
//
//  Created by Emilio Contreras on 28/09/25.
//

import SwiftUI
import MultipeerConnectivity
import CoreLocation

struct ContentView: View {
    @EnvironmentObject var networkManager: NetworkManager
    @State private var messageText = ""
    @State private var selectedMessageType: MessageType = .chat
    @State private var requiresAck = false
    @State private var recipientId = "broadcast"
    @State private var showAdvancedOptions = false
    @State private var showLocationPermissionAlert = false
    @State private var showUWBNavigation = false
    @State private var navigationTarget: MCPeerID? = nil
    @State private var showUWBPermissionAlert = false
    @State private var uwbDeniedPeer: String = ""
    @State private var showFamilyGroup = false
    @State private var showGeofenceMap = false

    var body: some View {
        ZStack {
            mainContent

            // Vista de navegación LinkFinder overlay
            if showUWBNavigation, let targetPeer = navigationTarget {
                if #available(iOS 14.0, *), let uwbManager = networkManager.uwbSessionManager {
                    LinkFinderNavigationView(
                        targetName: targetPeer.displayName,
                        targetPeerID: targetPeer,
                        uwbManager: uwbManager,
                        locationService: networkManager.locationService,
                        peerLocationTracker: networkManager.peerLocationTracker,
                        networkManager: networkManager,
                        onDismiss: {
                            showUWBNavigation = false
                            navigationTarget = nil
                        }
                    )
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
        }
    }

    private var mainContent: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                StatusOverviewCard(
                    deviceName: networkManager.localDeviceName,
                    statusText: connectionStatusText,
                    statusColor: connectionStatusColor,
                    connectionQuality: networkManager.connectionQuality,
                    relayingMessage: networkManager.relayingMessage,
                    availablePeers: networkManager.availablePeers.count,
                    connectedPeers: networkManager.connectedPeers.count,
                    pendingAcks: networkManager.pendingAcksCount,
                    blockedPeers: networkManager.networkStats.blocked,
                    locationStatusText: locationStatusText,
                    locationStatusColor: locationStatusColor,
                    onRequestPermissions: networkManager.locationService.authorizationStatus == .notDetermined ? {
                        networkManager.locationService.requestPermissions()
                    } : nil,
                    onOpenFamilyGroup: { showFamilyGroup = true },
                    hasFamilyGroup: networkManager.familyGroupManager.hasActiveGroup,
                    familyMemberCount: networkManager.familyGroupManager.memberCount,
                    onOpenGeofenceMap: { showGeofenceMap = true },
                    hasActiveGeofence: networkManager.linkfenceManager?.activeGeofence != nil
                )

                DeviceSection(
                    localDeviceName: networkManager.localDeviceName,
                    availablePeers: networkManager.availablePeers,
                    connectedPeers: networkManager.connectedPeers,
                    locationResponseProvider: { peerId in
                        networkManager.locationRequestManager.getResponse(for: peerId)
                    },
                    uwbSessionChecker: { peer in
                        hasUWBSession(with: peer)
                    },
                    isFamilyMember: { peer in
                        networkManager.familyGroupManager.isFamilyMember(peerID: peer.displayName)
                    },
                    reachableFamilyMembers: getReachableFamilyMembers(),
                    onRequestLocation: requestLocation,
                    onNavigate: startNavigation,
                    onReconnectTap: networkManager.restartServicesIfNeeded,
                    onStartChat: startChat(with:)
                )

                MessagesSection(
                    messageStore: networkManager.messageStore,
                    localDeviceName: networkManager.localDeviceName,
                    connectedPeers: networkManager.connectedPeers,
                    onConversationSelected: { summary in
                        // Directly select conversation without going through handleRecipientSelection
                        // to avoid unwanted redirections
                        recipientId = summary.defaultRecipientId
                        if networkManager.messageStore.activeConversationId != summary.id {
                            networkManager.messageStore.selectConversation(summary.id)
                        }
                    }
                )

                AdvancedControlsCard(
                    showAdvancedOptions: $showAdvancedOptions,
                    selectedMessageType: $selectedMessageType,
                    requiresAck: $requiresAck,
                    recipientId: $recipientId,
                    connectedPeers: networkManager.connectedPeers,
                    networkStats: networkManager.networkStats,
                    locationStatusText: locationStatusText,
                    locationStatusColor: locationStatusColor,
                    authorizationStatus: networkManager.locationService.authorizationStatus,
                    networkManager: networkManager,
                    messageStore: networkManager.messageStore,
                    onRequestPermissions: {
                        networkManager.locationService.requestPermissions()
                    },
                    onClearConnections: clearConnections,
                    onRecipientChange: { newRecipient in
                        // Only change conversation if we're selecting a different recipient
                        if newRecipient != recipientId {
                            recipientId = newRecipient
                            handleRecipientSelection(newRecipient)
                        }
                    }
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MessageComposerBar(
                messageText: $messageText,
                canSend: !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !networkManager.connectedPeers.isEmpty,
                accentColor: priorityColor(for: selectedMessageType),
                sendAction: sendMessage,
                conversationTitle: networkManager.messageStore.descriptor(for: networkManager.messageStore.activeConversationId)?.title ?? "todos"
            )
            .background(inputBackgroundColor)
        }
        .background(appBackgroundColor.ignoresSafeArea())
        .onAppear {
            syncRecipientWithActiveConversation()
        }
        .onChange(of: networkManager.messageStore.activeConversationId) { oldValue, newValue in
            // CRITICAL: Sync recipientId whenever the active conversation changes
            syncRecipientWithActiveConversation()
            print("🔄 Active conversation changed to: \(newValue)")
            print("   Synced recipientId to: \(recipientId)")
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UWBPermissionDenied"))) { notification in
            if let userInfo = notification.userInfo,
               let peerId = userInfo["peerId"] as? String {
                uwbDeniedPeer = peerId
                showUWBPermissionAlert = true
            }
        }
        .alert("Permiso de Nearby Interaction Requerido", isPresented: $showUWBPermissionAlert) {
            Button("Abrir Ajustes") {
                openSettings()
            }
            Button("Más Tarde", role: .cancel) {}
        } message: {
            Text("Para usar la navegación precisa con \(uwbDeniedPeer), autoriza Nearby Interaction en Ajustes > Privacidad y Seguridad > Nearby Interaction.")
        }
        .sheet(isPresented: $showFamilyGroup) {
            FamilyGroupView(familyGroupManager: networkManager.familyGroupManager)
                .environmentObject(networkManager)
        }
        .sheet(isPresented: $showGeofenceMap) {
            if let linkfenceManager = networkManager.linkfenceManager {
                FamilyLinkFenceMapView(
                    linkfenceManager: linkfenceManager,
                    familyGroupManager: networkManager.familyGroupManager,
                    locationService: networkManager.locationService,
                    networkManager: networkManager
                )
            }
        }
    }

    private var appBackgroundColor: Color {
        #if os(iOS)
        Color(.systemGroupedBackground)
        #else
        Color(NSColor.windowBackgroundColor)
        #endif
    }

    private var inputBackgroundColor: Color {
        #if os(iOS)
        Color(.systemBackground)
        #else
        Color(NSColor.controlBackgroundColor)
        #endif
    }

    private var connectionStatusColor: Color {
        switch networkManager.connectionStatus {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected:
            return .red
        }
    }

    private var connectionStatusText: String {
        switch networkManager.connectionStatus {
        case .connected:
            return "Conectado"
        case .connecting:
            return "Conectando..."
        case .disconnected:
            return "Desconectado"
        }
    }

    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        guard !networkManager.connectedPeers.isEmpty else {
            return
        }

        // CRITICAL FIX: Always send to the active conversation's recipient
        // Get the descriptor of the currently active conversation
        if let activeDescriptor = networkManager.messageStore.descriptor(for: networkManager.messageStore.activeConversationId) {
            let actualRecipient = activeDescriptor.defaultRecipientId

            print("📤 ContentView.sendMessage:")
            print("   Active conversation: \(networkManager.messageStore.activeConversationId)")
            print("   Active descriptor recipient: \(actualRecipient)")
            print("   Current recipientId state: \(recipientId)")

            // Sync recipientId to match active conversation
            if recipientId != actualRecipient {
                print("   ⚠️ MISMATCH DETECTED - Syncing recipientId to active conversation")
                recipientId = actualRecipient
            }

            networkManager.sendMessage(
                messageText,
                type: selectedMessageType,
                recipientId: actualRecipient,  // Use active conversation's recipient
                requiresAck: requiresAck
            )
        } else {
            // Fallback to broadcast if no active conversation descriptor
            print("⚠️ No active conversation descriptor - defaulting to broadcast")
            networkManager.sendMessage(
                messageText,
                type: selectedMessageType,
                recipientId: "broadcast",
                requiresAck: requiresAck
            )
        }

        messageText = ""
    }

    private func priorityColor(for type: MessageType) -> Color {
        switch type.defaultPriority {
        case 0: return .red
        case 1: return .orange
        case 2: return .yellow
        case 3: return .blue
        default: return .gray
        }
    }

    private func clearConnections() {
        networkManager.resetConnectionState()
    }

    private func requestLocation(for peer: MCPeerID) {
        // Check if we have location permissions
        let authStatus = networkManager.locationService.authorizationStatus

        if authStatus != .authorizedWhenInUse && authStatus != .authorizedAlways {
            showLocationPermissionAlert = true
            return
        }

        print("📍 User requested location for \(peer.displayName)")
        networkManager.sendLocationRequest(to: peer.displayName)
    }

    private func startChat(with peer: MCPeerID) {
        recipientId = peer.displayName
        handleRecipientSelection(peer.displayName)
    }

    private func handleRecipientSelection(_ newRecipient: String) {
        if newRecipient == "broadcast" {
            if networkManager.messageStore.activeConversationId != ConversationIdentifier.public.rawValue {
                networkManager.messageStore.selectConversation(ConversationIdentifier.public.rawValue)
            }
            return
        }

        // Check if conversation already exists (could be family OR direct)
        let familyConversationId = ConversationIdentifier.family(peerId: newRecipient).rawValue
        let directConversationId = ConversationIdentifier.direct(peerId: newRecipient).rawValue

        // Try family conversation first
        if let descriptor = networkManager.messageStore.descriptor(for: familyConversationId) {
            // Family conversation exists - select it
            if networkManager.messageStore.activeConversationId != descriptor.id {
                networkManager.messageStore.selectConversation(descriptor.id)
            }
            recipientId = newRecipient
            return
        }

        // Try direct conversation second
        if let descriptor = networkManager.messageStore.descriptor(for: directConversationId) {
            // Direct conversation exists - select it
            if networkManager.messageStore.activeConversationId != descriptor.id {
                networkManager.messageStore.selectConversation(descriptor.id)
            }
            recipientId = newRecipient
            return
        }

        // No existing conversation - determine type and create
        let displayName = networkManager.familyGroupManager.getMember(withPeerID: newRecipient)?.displayName ?? newRecipient
        let isFamilyMember = networkManager.familyGroupManager.isFamilyMember(peerID: newRecipient)
        let wasEverFamilyMember = networkManager.familyGroupManager.wasEverFamilyMember(peerID: newRecipient)

        let descriptor: MessageStore.ConversationDescriptor
        if isFamilyMember || wasEverFamilyMember {
            // Create family conversation
            descriptor = .familyChat(peerId: newRecipient, displayName: displayName)
        } else {
            // Create direct (non-family) conversation
            descriptor = .directChat(peerId: newRecipient, displayName: displayName)
        }

        networkManager.messageStore.ensureConversation(descriptor)

        if networkManager.messageStore.activeConversationId != descriptor.id {
            networkManager.messageStore.selectConversation(descriptor.id)
        }
        recipientId = newRecipient
    }

    private func syncRecipientWithActiveConversation() {
        if let descriptor = networkManager.messageStore.descriptor(for: networkManager.messageStore.activeConversationId) {
            recipientId = descriptor.defaultRecipientId
            // Don't call handleRecipientSelection here - it can change the active conversation
            // Just sync the recipientId for the message composer
        } else {
            recipientId = "broadcast"
        }
    }

    private func startNavigation(for peer: MCPeerID) {
        // Check if we have an active LinkFinder session
        if #available(iOS 14.0, *) {
            if let uwbManager = networkManager.uwbSessionManager,
               uwbManager.hasActiveSession(with: peer) {

                // Iniciar navegación - la vista obtendrá datos reactivamente
                navigationTarget = peer
                withAnimation {
                    showUWBNavigation = true
                }
                print("🧭 Starting LinkFinder navigation to \(peer.displayName)")
                return
            }
        }

        // Si no hay sesión LinkFinder activa, solicitar ubicación primero
        print("⚠️ No active LinkFinder session for \(peer.displayName), requesting location first")
        requestLocation(for: peer)
    }

    // MARK: - Permission Helpers

    private var needsLocationPermissions: Bool {
        let status = networkManager.locationService.authorizationStatus
        return status == .notDetermined || status == .denied || status == .restricted
    }

    private var locationPermissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: networkManager.locationService.authorizationStatus == .notDetermined ? "location.circle" : "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text(networkManager.locationService.authorizationStatus == .notDetermined ? "Permisos de ubicación requeridos" : "Permisos de ubicación denegados")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text(networkManager.locationService.authorizationStatus == .notDetermined ? "Necesarios para compartir tu ubicación" : "Ve a Ajustes para autorizar")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.9))
            }

            Spacer()

            Button(action: {
                if networkManager.locationService.authorizationStatus == .notDetermined {
                    networkManager.locationService.requestPermissions()
                } else {
                    openSettings()
                }
            }) {
                Text(networkManager.locationService.authorizationStatus == .notDetermined ? "Autorizar" : "Abrir Ajustes")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(networkManager.locationService.authorizationStatus == .notDetermined ? .yellow : .red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white)
                    .cornerRadius(6)
            }
        }
        .padding()
        .background(networkManager.locationService.authorizationStatus == .notDetermined ? Color.orange : Color.red)
        .alert("Permisos de Ubicación Requeridos", isPresented: $showLocationPermissionAlert) {
            Button("Cancelar", role: .cancel) {}

            if networkManager.locationService.authorizationStatus == .notDetermined {
                Button("Autorizar Ahora") {
                    networkManager.locationService.requestPermissions()
                }
            } else {
                Button("Abrir Ajustes") {
                    openSettings()
                }
            }
        } message: {
            Text("Para solicitar la ubicación de otros dispositivos, necesitas autorizar el acceso a tu ubicación.")
        }
    }

    private func openSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #else
        // macOS Settings deep link
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    private var locationStatusText: String {
        switch networkManager.locationService.authorizationStatus {
        case .notDetermined:
            return "No configurado"
        case .restricted:
            return "Restringido"
        case .denied:
            return "Denegado"
        case .authorizedAlways, .authorizedWhenInUse:
            return "Autorizado"
        @unknown default:
            return "Desconocido"
        }
    }

    private var locationStatusColor: Color {
        switch networkManager.locationService.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return .green
        case .denied, .restricted:
            return .red
        default:
            return .orange
        }
    }

    private func hasUWBSession(with peer: MCPeerID) -> Bool {
        if #available(iOS 14.0, *) {
            if let uwbManager = networkManager.uwbSessionManager {
                let hasSession = uwbManager.hasActiveSession(with: peer)
                let distance = uwbManager.getDistance(to: peer)

                // Log detailed status every check when session exists but no ranging
                if hasSession && distance == nil {
                    print("⚠️ LinkFinder Session exists but no ranging data yet for \(peer.displayName)")
                    // Print detailed status for debugging
                    print(uwbManager.getUWBStatus(for: peer))
                }

                print("🔍 LinkFinder Check for \(peer.displayName): Session=\(hasSession), Distance=\(distance?.description ?? "nil")")

                return hasSession && distance != nil
            } else {
                print("🔍 LinkFinder Check: uwbSessionManager is nil")
            }
        } else {
            print("🔍 LinkFinder Check: iOS < 14.0")
        }
        return false
    }

    /// Get family members that are reachable indirectly (not directly connected)
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

// MARK: - Main Sections

private struct StatusOverviewCard: View {
    let deviceName: String
    let statusText: String
    let statusColor: Color
    let connectionQuality: ConnectionQuality
    let relayingMessage: Bool
    let availablePeers: Int
    let connectedPeers: Int
    let pendingAcks: Int
    let blockedPeers: Int
    let locationStatusText: String
    let locationStatusColor: Color
    let onRequestPermissions: (() -> Void)?
    let onOpenFamilyGroup: () -> Void
    let hasFamilyGroup: Bool
    let familyMemberCount: Int
    let onOpenGeofenceMap: () -> Void
    let hasActiveGeofence: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 12, height: 12)

                        Text(deviceName)
                            .font(.headline)
                            .foregroundColor(.white)
                    }

                    Text(statusText)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.9))
                }

                Spacer()

                if relayingMessage {
                    Label("Reenviando", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Capsule())
                        .foregroundColor(.white)
                }
            }

            HStack(spacing: 12) {
                qualityBadge

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    // Family Group Badge
                    Button(action: onOpenFamilyGroup) {
                        Label {
                            Text(hasFamilyGroup ? "\(familyMemberCount)" : "Grupo")
                                .font(.caption)
                                .fontWeight(.semibold)
                        } icon: {
                            Image(systemName: hasFamilyGroup ? "person.3.fill" : "person.3")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(hasFamilyGroup ? Color.green.opacity(0.2) : Color.white.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(hasFamilyGroup ? Color.green.opacity(0.7) : Color.white.opacity(0.3), lineWidth: 1)
                        )
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)

                    // LinkFence Badge
                    Button(action: onOpenGeofenceMap) {
                        Label {
                            Text(hasActiveGeofence ? "Activo" : "LinkFence")
                                .font(.caption)
                                .fontWeight(.semibold)
                        } icon: {
                            Image(systemName: hasActiveGeofence ? "map.circle.fill" : "map.circle")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(hasActiveGeofence ? Color.blue.opacity(0.2) : Color.white.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(hasActiveGeofence ? Color.blue.opacity(0.7) : Color.white.opacity(0.3), lineWidth: 1)
                        )
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)

                    locationBadge

                    if let onRequestPermissions {
                        Button(action: onRequestPermissions) {
                            Text("Permitir")
                                .font(.caption.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.white)
                                .foregroundColor(statusColor)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.2))

            HStack(spacing: 16) {
                StatusMetric(
                    title: "Conectados",
                    value: "\(connectedPeers)",
                    icon: "link",
                    tint: .white
                )

                StatusMetric(
                    title: "Disponibles",
                    value: "\(availablePeers)",
                    icon: "antenna.radiowaves.left.and.right",
                    tint: .white.opacity(0.85)
                )

                StatusMetric(
                    title: "ACKs",
                    value: "\(pendingAcks)",
                    icon: "clock.arrow.circlepath",
                    tint: pendingAcks > 0 ? .yellow : .white.opacity(0.85)
                )
            }

            if blockedPeers > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text("\(blockedPeers) bloqueados por estabilidad de red")
                        .font(.caption)
                }
                .foregroundColor(.white.opacity(0.9))
            }
        }
        .padding(20)
        .background(gradientBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: statusColor.opacity(0.25), radius: 12, x: 0, y: 6)
    }

    private var gradientBackground: LinearGradient {
        LinearGradient(
            colors: [statusColor.opacity(0.9), accentColor.opacity(0.75)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var accentColor: Color {
        switch connectionQuality {
        case .excellent: return .blue
        case .good: return .teal
        case .poor: return .red
        case .unknown: return .gray
        }
    }

    private var qualityBadge: some View {
        HStack(spacing: 8) {
            Text(connectionQuality.rawValue)
                .font(.title3)

            Text(connectionQuality.displayName)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .foregroundColor(.white)
        .background(Color.white.opacity(0.15))
        .clipShape(Capsule())
    }

    private var locationBadge: some View {
        Label {
            Text(locationStatusText)
                .font(.caption)
                .fontWeight(.semibold)
        } icon: {
            Image(systemName: "location.circle")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.12))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(locationStatusColor.opacity(0.7), lineWidth: 1)
        )
        .foregroundColor(.white)
    }
}

private struct DeviceSection: View {
    let localDeviceName: String
    let availablePeers: [MCPeerID]
    let connectedPeers: [MCPeerID]
    let locationResponseProvider: (String) -> LocationResponseMessage?
    let uwbSessionChecker: (MCPeerID) -> Bool
    let isFamilyMember: (MCPeerID) -> Bool
    let reachableFamilyMembers: [(peerID: String, displayName: String, route: [String])]
    let onRequestLocation: (MCPeerID) -> Void
    let onNavigate: (MCPeerID) -> Void
    let onReconnectTap: () -> Void
    let onStartChat: (MCPeerID) -> Void

    var body: some View {
        SectionCard(
            title: "Dispositivos",
            icon: "antenna.radiowaves.left.and.right",
            caption: connectedPeers.isEmpty
                ? "Conéctate a un dispositivo cercano para empezar a enviar mensajes."
                : "Gestiona tus conexiones activas y descubre quién está a tu alcance."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionSubtitle(text: "Conectados", color: .green)

                    if connectedPeers.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "network.slash")
                                .font(.title3)
                                .foregroundColor(.secondary)

                            Text("No hay dispositivos conectados")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Button(action: onReconnectTap) {
                                Label("Reconectar", systemImage: "arrow.clockwise")
                                    .font(.footnote.bold())
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color.accentColor.opacity(0.15))
                                    .foregroundColor(.accentColor)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.meshRowBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        VStack(spacing: 12) {
                            ForEach(sortedConnectedPeers, id: \.self) { peer in
                                ConnectedPeerRow(
                                    peer: peer,
                                    locationResponse: locationResponseProvider(peer.displayName),
                                    hasUWBSession: uwbSessionChecker(peer),
                                    isFamilyMember: isFamilyMember(peer),
                                    localDeviceName: localDeviceName,
                                    onRequestLocation: onRequestLocation,
                                    onNavigate: onNavigate,
                                    onStartChat: onStartChat
                                )
                            }
                        }
                    }
                }

                // Familia alcanzable indirectamente
                if !reachableFamilyMembers.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        SectionSubtitle(text: "Familia en red (indirecta)", color: .orange)

                        ForEach(reachableFamilyMembers, id: \.peerID) { member in
                            HStack(spacing: 12) {
                                Circle()
                                    .stroke(Color.orange, lineWidth: 2)
                                    .fill(Color.orange.opacity(0.2))
                                    .frame(width: 8, height: 8)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(member.displayName)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)

                                        Image(systemName: "person.3.fill")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }

                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.triangle.branch")
                                            .font(.caption2)
                                        Text("Via \(member.route.joined(separator: ", "))")
                                            .font(.caption2)
                                    }
                                    .foregroundColor(.orange)
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            .background(Color.meshRowBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    SectionSubtitle(text: "Detectados", color: .blue)

                    if availablePeers.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Buscando dispositivos...")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        ForEach(availablePeers, id: \.self) { peer in
                            AvailablePeerRow(peer: peer)
                        }
                    }
                }
            }
        }
    }

    // Sort connected peers: family members first
    private var sortedConnectedPeers: [MCPeerID] {
        connectedPeers.sorted { peer1, peer2 in
            let isFamily1 = isFamilyMember(peer1)
            let isFamily2 = isFamilyMember(peer2)

            if isFamily1 && !isFamily2 {
                return true
            } else if !isFamily1 && isFamily2 {
                return false
            } else {
                return peer1.displayName < peer2.displayName
            }
        }
    }
}

private struct MessagesSection: View {
    @ObservedObject var messageStore: MessageStore
    let localDeviceName: String
    let connectedPeers: [MCPeerID]
    let onConversationSelected: (MessageStore.ConversationSummary) -> Void

    var body: some View {
        let messages = messageStore.messages
        let summaries = messageStore.conversationSummaries

        let _ = print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        let _ = print("📨 MessagesSection RENDERING")
        let _ = print("   Total summaries: \(summaries.count)")
        let _ = print("   Active messages: \(messages.count)")
        let _ = print("   Active conversation: \(messageStore.activeConversationId)")
        let _ = print("   Connected peers: \(connectedPeers.map { $0.displayName })")
        let _ = summaries.forEach { summary in
            let isConnected = summary.participantId == nil || connectedPeers.contains { $0.displayName == summary.participantId }
            print("   • \(summary.title) - Connected: \(isConnected), Messages: \(messageStore.messages(for: summary.id).count)")
        }
        let _ = print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        return SectionCard(
            title: "Mensajes",
            icon: "bubble.left.and.bubble.right",
            caption: messages.isEmpty
                ? "Selecciona una conversación para empezar a chatear."
                : "Historial de \(activeConversationTitle)"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                ConversationSelector(
                    summaries: summaries,
                    activeConversationId: messageStore.activeConversationId,
                    connectedPeers: connectedPeers,
                    messageStore: messageStore,
                    onSelect: { summary in
                        onConversationSelected(summary)
                    }
                )

                if messages.isEmpty {
                    let _ = print("⚠️ MessagesSection: No messages to display for active conversation")
                    VStack(spacing: 12) {
                        Image(systemName: "text.bubble")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text("Cuando envíes un mensaje aparecerá aquí.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    let _ = print("💬 MessagesSection: Rendering \(messages.count) message bubbles")
                    let _ = messages.forEach { msg in
                        print("   • [\(msg.id)] \(msg.sender): \(msg.content.prefix(30))...")
                    }

                    MessageListView(messages: messages, localDeviceName: localDeviceName)
                }
            }
        }
    }

    private var activeConversationTitle: String {
        if let descriptor = messageStore.descriptor(for: messageStore.activeConversationId) {
            return descriptor.title
        }
        return "la sala seleccionada"
    }
}

private struct AdvancedControlsCard: View {
    @Binding var showAdvancedOptions: Bool
    @Binding var selectedMessageType: MessageType
    @Binding var requiresAck: Bool
    @Binding var recipientId: String

    let connectedPeers: [MCPeerID]
    let networkStats: (attempts: Int, blocked: Int, active: Int)
    let locationStatusText: String
    let locationStatusColor: Color
    let authorizationStatus: CLAuthorizationStatus
    let networkManager: NetworkManager
    let messageStore: MessageStore
    let onRequestPermissions: () -> Void
    let onClearConnections: () -> Void
    let onRecipientChange: (String) -> Void

    var body: some View {
        SectionCard(
            title: "Controles Avanzados",
            icon: "slider.horizontal.3",
            caption: "Personaliza el envío y revisa la salud de la red."
        ) {
            DisclosureGroup(isExpanded: $showAdvancedOptions) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tipo de mensaje")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("Tipo de mensaje", selection: $selectedMessageType) {
                            ForEach(MessageType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    HStack(spacing: 10) {
                        Label("Prioridad", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Circle()
                            .fill(priorityColor(for: selectedMessageType))
                            .frame(width: 10, height: 10)

                        Text("Nivel \(selectedMessageType.defaultPriority)")
                            .font(.caption)
                            .foregroundColor(priorityColor(for: selectedMessageType))

                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Destinatario")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("Destinatario", selection: $recipientId) {
                            Text("Broadcast (todos)").tag("broadcast")

                            // Family members section
                            if networkManager.familyGroupManager.hasActiveGroup,
                               let familyMembers = networkManager.familyGroupManager.currentGroup?.members {
                                Section(header: Text("Familia")) {
                                    ForEach(Array(familyMembers), id: \.peerID) { member in
                                        if member.peerID != networkManager.localDeviceName {
                                            HStack {
                                                Text(member.displayName)
                                                Spacer()
                                                // Show network status indicator
                                                if networkManager.connectedPeers.contains(where: { $0.displayName == member.peerID }) {
                                                    Image(systemName: "circlebadge.fill")
                                                        .font(.caption2)
                                                        .foregroundColor(.green)
                                                } else if networkManager.routingTable.isReachable(member.peerID) {
                                                    Image(systemName: "circle.dotted")
                                                        .font(.caption2)
                                                        .foregroundColor(.orange)
                                                } else {
                                                    Image(systemName: "circle")
                                                        .font(.caption2)
                                                        .foregroundColor(.gray)
                                                }
                                            }
                                            .tag(member.peerID)
                                        }
                                    }
                                }
                            }

                            // Other peers with conversations (connected or disconnected)
                            // IMPORTANT: Show ALL peers we have conversations with, not just connected ones
                            // This prevents SwiftUI from auto-changing the Picker selection when a peer disconnects
                            let peersWithConversations = messageStore.conversationSummaries
                                .filter { summary in
                                    // Filter: has a participantId (not public chat) AND not in family
                                    guard let participantId = summary.participantId else { return false }
                                    return !networkManager.familyGroupManager.isFamilyMember(peerID: participantId)
                                }
                                .map { $0.participantId! }

                            if !peersWithConversations.isEmpty {
                                Section(header: Text("Otros dispositivos")) {
                                    ForEach(peersWithConversations, id: \.self) { peerId in
                                        HStack {
                                            Text(peerId)
                                            Spacer()
                                            // Show connection status indicator
                                            if connectedPeers.contains(where: { $0.displayName == peerId }) {
                                                Image(systemName: "circlebadge.fill")
                                                    .font(.caption2)
                                                    .foregroundColor(.green)
                                            } else if networkManager.routingTable.isReachable(peerId) {
                                                Image(systemName: "circle.dotted")
                                                    .font(.caption2)
                                                    .foregroundColor(.orange)
                                            } else {
                                                Image(systemName: "circle")
                                                    .font(.caption2)
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                        .tag(peerId)
                                    }
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: recipientId) { oldValue, newValue in
                            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                            print("⚠️ PICKER: recipientId changed")
                            print("   Old value: \(oldValue)")
                            print("   New value: \(newValue)")
                            print("   Active conversation: \(messageStore.activeConversationId)")
                            print("   Was triggered by: \(oldValue == newValue ? "programmatic (same)" : "user interaction or SwiftUI invalidation")")

                            // Check if the new value is valid
                            let allAvailableRecipients: [String] = {
                                var recipients = ["broadcast"]

                                // Add family members
                                if let familyMembers = networkManager.familyGroupManager.currentGroup?.members {
                                    recipients.append(contentsOf: familyMembers
                                        .filter { $0.peerID != networkManager.localDeviceName }
                                        .map { $0.peerID })
                                }

                                // Add peers with conversations
                                recipients.append(contentsOf: messageStore.conversationSummaries
                                    .compactMap { $0.participantId }
                                    .filter { !networkManager.familyGroupManager.isFamilyMember(peerID: $0) })

                                return recipients
                            }()

                            print("   Available recipients: \(allAvailableRecipients)")
                            print("   Is new value valid: \(allAvailableRecipients.contains(newValue))")

                            // CRITICAL FIX: Prevent unwanted conversation switching
                            // If the change is from a specific peer to "broadcast" AND we're viewing a private conversation,
                            // this is likely SwiftUI invalidation (peer disconnected). Don't change the active conversation.
                            let isLikelySwiftUIInvalidation = (
                                newValue == "broadcast" &&
                                oldValue != "broadcast" &&
                                messageStore.activeConversationId != ConversationIdentifier.public.rawValue
                            )

                            if isLikelySwiftUIInvalidation {
                                print("   🛡️ PREVENTED: Automatic switch to broadcast (likely SwiftUI invalidation)")
                                print("   Keeping active conversation: \(messageStore.activeConversationId)")
                                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                                // Don't call onRecipientChange - just keep the current state
                                return
                            }

                            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                            if newValue != "broadcast" {
                                // Create private conversation (family or direct)
                                let displayName = networkManager.familyGroupManager.getMember(withPeerID: newValue)?.displayName ?? newValue
                                let isFamilyMember = networkManager.familyGroupManager.isFamilyMember(peerID: newValue)

                                let descriptor: MessageStore.ConversationDescriptor
                                if isFamilyMember {
                                    descriptor = .familyChat(peerId: newValue, displayName: displayName)
                                } else {
                                    descriptor = .directChat(peerId: newValue, displayName: displayName)
                                }
                                messageStore.ensureConversation(descriptor)
                            }
                            onRecipientChange(newValue)
                        }

                        if recipientId != "broadcast" {
                            let isDirectlyConnected = connectedPeers.contains(where: { $0.displayName == recipientId })
                            let isReachableIndirectly = !isDirectlyConnected && networkManager.routingTable.isReachable(recipientId)

                            if isDirectlyConnected {
                                Label("Conexión directa", systemImage: "arrow.right.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            } else if isReachableIndirectly {
                                if let nextHops = networkManager.routingTable.getNextHops(to: recipientId) {
                                    Label("Ruta multi-hop via \(nextHops.joined(separator: ", "))", systemImage: "arrow.triangle.branch")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            } else {
                                Label("Destinatario fuera de rango - broadcast", systemImage: "wifi.slash")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }
                        }
                    }

                    Toggle(isOn: $requiresAck) {
                        Label("Requerir confirmación (ACK)", systemImage: "checkmark.seal")
                            .font(.caption)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .blue))

                    Divider()

                    StatsGrid(networkStats: networkStats)

                    HStack(spacing: 10) {
                        Label(locationStatusText, systemImage: "location.circle")
                            .font(.caption)
                            .foregroundColor(locationStatusColor)

                        Spacer()

                        if authorizationStatus == .notDetermined {
                            Button("Solicitar permisos", action: onRequestPermissions)
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundColor(.accentColor)
                                .clipShape(Capsule())
                                .buttonStyle(.plain)
                        }
                    }

                    Button(action: onClearConnections) {
                        Label("Limpiar conexiones", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
                .padding(.top, 12)
            } label: {
                HStack(spacing: 8) {
                    Text(selectedMessageType.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Capsule()
                        .fill(priorityColor(for: selectedMessageType).opacity(0.2))
                        .frame(width: 6, height: 6)

                    Spacer()

                    if requiresAck {
                        Label("ACK", systemImage: "checkmark.seal")
                            .font(.caption2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func priorityColor(for type: MessageType) -> Color {
        switch type.defaultPriority {
        case 0: return .red
        case 1: return .orange
        case 2: return .yellow
        case 3: return .blue
        default: return .gray
        }
    }
}

// MARK: - Subcomponents

private struct ConversationSelector: View {
    let summaries: [MessageStore.ConversationSummary]
    let activeConversationId: String
    let connectedPeers: [MCPeerID]
    @ObservedObject var messageStore: MessageStore
    let onSelect: (MessageStore.ConversationSummary) -> Void
    @State private var showDeleteAlert = false
    @State private var conversationToDelete: MessageStore.ConversationSummary?

    private func isConnected(_ participantId: String?) -> Bool {
        guard let participantId = participantId else { return true } // Public chat is always "connected"
        return connectedPeers.contains { $0.displayName == participantId }
    }

    var body: some View {
        let _ = print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        let _ = print("🎨 ConversationSelector RENDERING")
        let _ = print("   Total summaries: \(summaries.count)")
        let _ = print("   Active conversation ID: \(activeConversationId)")
        let _ = summaries.enumerated().forEach { index, summary in
            let connected = isConnected(summary.participantId)
            print("   [\(index)] \(summary.title)")
            print("       ID: \(summary.id)")
            print("       Active: \(activeConversationId == summary.id)")
            print("       Connected: \(connected)")
            print("       ParticipantID: \(summary.participantId ?? "nil")")
        }
        let _ = print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(summaries) { summary in
                    ConversationCard(
                        summary: summary,
                        isActive: activeConversationId == summary.id,
                        isConnected: isConnected(summary.participantId),
                        onSelect: { onSelect(summary) },
                        onDelete: {
                            conversationToDelete = summary
                            showDeleteAlert = true
                        }
                    )
                }
            }
            .padding(.horizontal, 2)
        }
        .id(summaries.map { $0.id }.joined(separator: "-"))  // Force rebuild when summaries change
        .alert("Eliminar conversación", isPresented: $showDeleteAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar", role: .destructive) {
                if let conversation = conversationToDelete {
                    messageStore.deleteConversation(conversation.id)
                }
            }
        } message: {
            if let conversation = conversationToDelete {
                Text("¿Estás seguro de que quieres eliminar la conversación con \(conversation.title)? Esta acción no se puede deshacer.")
            }
        }
    }
}

private struct ConversationCard: View {
    let summary: MessageStore.ConversationSummary
    let isActive: Bool
    let isConnected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var showDeleteButton = false

    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete button background
            if showDeleteButton && summary.id != ConversationIdentifier.public.rawValue {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        offset = 0
                        showDeleteButton = false
                    }
                    onDelete()
                }) {
                    VStack {
                        Image(systemName: "trash.fill")
                            .font(.caption)
                            .foregroundColor(.white)
                        Text("Eliminar")
                            .font(.caption2)
                            .foregroundColor(.white)
                    }
                    .frame(width: 60, height: 54)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // Main card
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        // Connection status indicator
                        Circle()
                            .fill(isConnected ? Color.green : Color.gray)
                            .frame(width: 6, height: 6)

                        // Icon based on conversation type
                        Image(systemName: conversationIcon(for: summary))
                            .font(.caption)
                            .foregroundColor(conversationColor(for: summary))

                        Text(summary.title)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 4) {
                        if !isConnected && summary.participantId != nil {
                            Text("Desconectado")
                                .font(.caption2)
                                .foregroundColor(.red)
                        } else {
                            Text(summary.lastMessagePreview ?? "Sin mensajes todavía")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .lineLimit(1)
                }
                .frame(width: 160, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(isActive ? Color.accentColor.opacity(0.2) : Color.meshRowBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isActive ? Color.accentColor : Color.primary.opacity(0.05), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .offset(x: offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Only allow swipe for non-public conversations
                        if summary.id != ConversationIdentifier.public.rawValue {
                            if value.translation.width < 0 {
                                // Swiping left
                                offset = max(value.translation.width, -60)
                            } else if showDeleteButton {
                                // Swiping right when delete button is shown
                                offset = min(value.translation.width - 60, 0)
                            }
                        }
                    }
                    .onEnded { value in
                        if summary.id != ConversationIdentifier.public.rawValue {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if value.translation.width < -30 {
                                    // Show delete button
                                    offset = -60
                                    showDeleteButton = true
                                } else {
                                    // Hide delete button
                                    offset = 0
                                    showDeleteButton = false
                                }
                            }
                        }
                    }
            )
        }
    }

    // MARK: - Helper Functions

    private func conversationIcon(for summary: MessageStore.ConversationSummary) -> String {
        if summary.isFamily {
            return "person.2.fill"  // Family group icon
        } else if summary.isDirect {
            return "person.fill"     // Direct/individual icon
        } else {
            return "megaphone.fill"  // Public broadcast icon
        }
    }

    private func conversationColor(for summary: MessageStore.ConversationSummary) -> Color {
        if summary.isFamily {
            return .orange  // Family = orange
        } else if summary.isDirect {
            return .purple  // Direct = purple
        } else {
            return .blue    // Public = blue
        }
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    let caption: String?
    @ViewBuilder var content: Content

    init(title: String, icon: String, caption: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.headline)
                Spacer(minLength: 0)
            }

            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            content
        }
        .padding(20)
        .background(Color.meshCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct SectionSubtitle: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color.opacity(0.9))
                .frame(width: 6, height: 6)

            Text(text.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
}

private struct StatusMetric: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(tint.opacity(0.85))
                Text(title.uppercased())
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }

            Text(value)
                .font(.title3.weight(.bold))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ConnectedPeerRow: View {
    let peer: MCPeerID
    let locationResponse: LocationResponseMessage?
    let hasUWBSession: Bool
    let isFamilyMember: Bool
    let localDeviceName: String
    let onRequestLocation: (MCPeerID) -> Void
    let onNavigate: (MCPeerID) -> Void
    let onStartChat: (MCPeerID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(peer.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        if isFamilyMember {
                            Image(systemName: "person.3.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }

                    Text("Conectado")
                        .font(.caption2)
                        .foregroundColor(.green)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Button(action: { onStartChat(peer) }) {
                        Label("Mensaje", systemImage: "bubble.left.and.bubble.right.fill")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    if hasUWBSession {
                        Button(action: { onNavigate(peer) }) {
                            Label("Navegar", systemImage: "arrow.triangle.turn.up.right.diamond")
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.cyan.opacity(0.2))
                                .foregroundColor(.cyan)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: { onRequestLocation(peer) }) {
                            Label("Ubicar", systemImage: "location.circle")
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundColor(.accentColor)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let response = locationResponse {
                LocationResponseView(response: response, localDeviceName: localDeviceName)
            }
        }
        .padding(14)
        .background(Color.meshRowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct AvailablePeerRow: View {
    let peer: MCPeerID

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "iphone")
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(peer.displayName)
                    .font(.subheadline)

                Text("Disponible")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.meshRowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct StatsGrid: View {
    let networkStats: (attempts: Int, blocked: Int, active: Int)

    var body: some View {
        HStack(spacing: 16) {
            StatsItem(
                title: "Intentos",
                value: networkStats.attempts,
                icon: "bolt.horizontal.circle"
            )

            StatsItem(
                title: "Bloqueados",
                value: networkStats.blocked,
                icon: "shield.slash"
            )

            StatsItem(
                title: "Activos",
                value: networkStats.active,
                icon: "wave.3.right"
            )
        }
    }
}

private struct StatsItem: View {
    let title: String
    let value: Int
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption2)
                .foregroundColor(.secondary)

            Text("\(value)")
                .font(.headline)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MessageComposerBar: View {
    @Binding var messageText: String
    let canSend: Bool
    let accentColor: Color
    let sendAction: () -> Void
    let conversationTitle: String

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .foregroundColor(.secondary)

                    TextField("Mensaje para \(conversationTitle)", text: $messageText)
                        .onSubmit(sendAction)
                        .textFieldStyle(.plain)
                        #if os(iOS)
                        .textInputAutocapitalization(.sentences)
                        .disableAutocorrection(false)
                        #endif
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.meshRowBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button(action: sendAction) {
                    Image(systemName: "paperplane.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(canSend ? accentColor : Color.secondary.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Helpers

private extension Color {
    static var meshCardBackground: Color {
        #if os(iOS)
        return Color(.secondarySystemBackground)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }

    static var meshRowBackground: Color {
        #if os(iOS)
        return Color(.tertiarySystemBackground)
        #else
        return Color(NSColor.windowBackgroundColor).opacity(0.7)
        #endif
    }
}

// MARK: - Location Response View

struct LocationResponseView: View {
    let response: LocationResponseMessage
    let localDeviceName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch response.responseType {
            case .uwbDirect:
                // LinkFinder direct response - highest precision
                if let relative = response.relativeLocation {
                    HStack(spacing: 4) {
                        Image(systemName: "location.north.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                        Text("Ubicación LinkFinder Precisa:")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }

                    HStack(spacing: 6) {
                        // Distance
                        Text(relative.distanceString)
                            .font(.caption.bold())
                            .foregroundColor(.green)

                        // Direction if available
                        if let dir = relative.directionString {
                            Image(systemName: "arrow.up")
                                .font(.caption2)
                                .foregroundColor(.green)
                            Text(dir)
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }

                    Text("Precisión: ±\(String(format: "%.1f", relative.accuracy))m (LinkFinder)")
                        .font(.caption2)
                        .foregroundColor(.green.opacity(0.8))
                }

            case .direct:
                // GPS fallback
                if let location = response.directLocation {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        Text("Ubicación GPS:")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }

                    Text(location.coordinateString)
                        .font(.caption2.monospaced())

                    Text("Precisión: \(location.accuracyString)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

            case .triangulated:
                // Deprecated - should not appear anymore
                if let relative = response.relativeLocation {
                    HStack(spacing: 4) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Text("Ubicación triangulada:")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }

                    Text(relative.description)
                        .font(.caption2)

                    Text("Precisión: ±\(String(format: "%.1f", relative.accuracy))m")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

            case .unavailable:
                HStack(spacing: 4) {
                    Image(systemName: "location.slash")
                        .font(.caption2)
                        .foregroundColor(.red)
                    Text("Ubicación no disponible")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Text("Hace \(timeAgo(from: response.timestamp))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        #if os(iOS)
        .background(Color(.systemGray6))
        #else
        .background(Color(NSColor.controlBackgroundColor))
        #endif
        .cornerRadius(8)
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))

        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            return "\(seconds / 60)m"
        } else {
            return "\(seconds / 3600)h"
        }
    }
}

// MARK: - Message List with Auto-Scroll

private struct MessageListView: View {
    let messages: [Message]
    let localDeviceName: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                messageListContent
                    .padding(.horizontal, 4)
            }
            .onChange(of: messages.count) { oldCount, newCount in
                scrollToBottom(proxy: proxy)
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private var messageListContent: some View {
        LazyVStack(spacing: 4) {
            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                messageRow(for: message, at: index)
            }
        }
    }

    private func messageRow(for message: Message, at index: Int) -> some View {
        VStack(spacing: 4) {
            if shouldShowDateDivider(for: message, at: index) {
                DateDivider(dateLabel: message.dateGroupLabel)
                    .padding(.vertical, 8)
                    .transition(.opacity)
            }

            MessageBubble(
                message: message,
                isFromLocal: message.sender == localDeviceName,
                showSenderName: shouldShowSenderName(for: message, at: index)
            )
            .id(message.id)
            .transition(.scale(scale: 0.5).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: message.id)
        }
    }

    private func shouldShowDateDivider(for message: Message, at index: Int) -> Bool {
        guard index > 0 else { return true }
        return !message.isSameDay(as: messages[index - 1])
    }

    private func shouldShowSenderName(for message: Message, at index: Int) -> Bool {
        guard index > 0 else { return true }
        return !message.shouldGroupWith(messages[index - 1])
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastMessage = messages.last else { return }
        withAnimation {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: Message
    let isFromLocal: Bool
    let showSenderName: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isFromLocal {
                Spacer(minLength: 0)
            }

            VStack(alignment: isFromLocal ? .trailing : .leading, spacing: 2) {
                // Show sender name only if showSenderName is true and not from local
                if !isFromLocal && showSenderName {
                    Text(message.sender)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.leading, 12)
                        .padding(.top, 4)
                }

                // For local messages: time on top
                if isFromLocal {
                    Text(message.formattedTime)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.trailing, 12)
                        .padding(.bottom, 2)
                }

                // Message bubble
                HStack(alignment: .bottom, spacing: 4) {
                    Text(message.content)
                        .font(.body)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(bubbleColor)
                        .foregroundColor(isFromLocal ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    // Time stamp next to bubble for received messages only
                    if !isFromLocal {
                        Text(message.formattedTime)
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
            }
            .frame(maxWidth: 280, alignment: isFromLocal ? .trailing : .leading)

            if !isFromLocal {
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 1)
    }

    private var bubbleColor: Color {
        if isFromLocal {
            return Color.accentColor
        } else {
            // WhatsApp-style gray for received messages
            return Color(UIColor.systemGray5)
        }
    }
}

// MARK: - Date Divider Component

struct DateDivider: View {
    let dateLabel: String

    var body: some View {
        HStack {
            VStack { Divider() }
            Text(dateLabel)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.meshCardBackground)
                .clipShape(Capsule())
            VStack { Divider() }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
        .environmentObject(NetworkManager())
}
