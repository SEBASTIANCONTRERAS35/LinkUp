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

            // Vista de navegación UWB overlay
            if showUWBNavigation, let targetPeer = navigationTarget {
                if #available(iOS 14.0, *), let uwbManager = networkManager.uwbSessionManager {
                    UWBNavigationView(
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
        VStack(spacing: 0) {
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
                        hasActiveGeofence: networkManager.geofenceManager?.activeGeofence != nil
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
                        onConversationSelected: { summary in
                            recipientId = summary.defaultRecipientId
                            handleRecipientSelection(summary.defaultRecipientId)
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
                            handleRecipientSelection(newRecipient)
                        }
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }

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
            if let geofenceManager = networkManager.geofenceManager {
                FamilyGeofenceMapView(
                    geofenceManager: geofenceManager,
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

        networkManager.sendMessage(
            messageText,
            type: selectedMessageType,
            recipientId: recipientId,
            requiresAck: requiresAck
        )
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

        guard networkManager.familyGroupManager.isFamilyMember(peerID: newRecipient) else {
            if networkManager.messageStore.activeConversationId != ConversationIdentifier.public.rawValue {
                networkManager.messageStore.selectConversation(ConversationIdentifier.public.rawValue)
            }
            return
        }

        let displayName = networkManager.familyGroupManager.getMember(withPeerID: newRecipient)?.displayName ?? newRecipient
        let descriptor = MessageStore.ConversationDescriptor.familyChat(peerId: newRecipient, displayName: displayName)
        networkManager.messageStore.ensureConversation(descriptor)

        if networkManager.messageStore.activeConversationId != descriptor.id {
            networkManager.messageStore.selectConversation(descriptor.id)
        }
    }

    private func syncRecipientWithActiveConversation() {
        if let descriptor = networkManager.messageStore.descriptor(for: networkManager.messageStore.activeConversationId) {
            recipientId = descriptor.defaultRecipientId
            handleRecipientSelection(descriptor.defaultRecipientId)
        } else {
            recipientId = "broadcast"
            handleRecipientSelection("broadcast")
        }
    }

    private func startNavigation(for peer: MCPeerID) {
        // Check if we have an active UWB session
        if #available(iOS 14.0, *) {
            if let uwbManager = networkManager.uwbSessionManager,
               uwbManager.hasActiveSession(with: peer) {

                // Iniciar navegación - la vista obtendrá datos reactivamente
                navigationTarget = peer
                withAnimation {
                    showUWBNavigation = true
                }
                print("🧭 Starting UWB navigation to \(peer.displayName)")
                return
            }
        }

        // Si no hay sesión UWB activa, solicitar ubicación primero
        print("⚠️ No active UWB session for \(peer.displayName), requesting location first")
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
                    print("⚠️ UWB Session exists but no ranging data yet for \(peer.displayName)")
                    // Print detailed status for debugging
                    print(uwbManager.getUWBStatus(for: peer))
                }

                print("🔍 UWB Check for \(peer.displayName): Session=\(hasSession), Distance=\(distance?.description ?? "nil")")

                return hasSession && distance != nil
            } else {
                print("🔍 UWB Check: uwbSessionManager is nil")
            }
        } else {
            print("🔍 UWB Check: iOS < 14.0")
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

                    // Geofence Badge
                    Button(action: onOpenGeofenceMap) {
                        Label {
                            Text(hasActiveGeofence ? "Activo" : "Geofence")
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
    let onConversationSelected: (MessageStore.ConversationSummary) -> Void

    var body: some View {
        let messages = messageStore.messages
        SectionCard(
            title: "Mensajes",
            icon: "bubble.left.and.bubble.right",
            caption: messages.isEmpty
                ? "Selecciona una conversación para empezar a chatear."
                : "Historial de \(activeConversationTitle)"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                ConversationSelector(
                    summaries: messageStore.conversationSummaries,
                    activeConversationId: messageStore.activeConversationId,
                    onSelect: { summary in
                        onConversationSelected(summary)
                    }
                )

                if messages.isEmpty {
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
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(
                                message: message,
                                isFromLocal: message.sender == localDeviceName
                            )
                        }
                    }
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

                            // Other connected peers (not in family)
                            let nonFamilyPeers = connectedPeers.filter { peer in
                                !networkManager.familyGroupManager.isFamilyMember(peerID: peer.displayName)
                            }

                            if !nonFamilyPeers.isEmpty {
                                Section(header: Text("Otros dispositivos")) {
                                    ForEach(nonFamilyPeers, id: \.self) { peer in
                                        Text(peer.displayName).tag(peer.displayName)
                                    }
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: recipientId) { newValue in
                            if newValue != "broadcast" && networkManager.familyGroupManager.isFamilyMember(peerID: newValue) {
                                let displayName = networkManager.familyGroupManager.getMember(withPeerID: newValue)?.displayName ?? newValue
                                let descriptor = MessageStore.ConversationDescriptor.familyChat(peerId: newValue, displayName: displayName)
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
    let onSelect: (MessageStore.ConversationSummary) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(summaries) { summary in
                    Button(action: {
                        onSelect(summary)
                    }) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: summary.isFamily ? "person.2.fill" : "megaphone.fill")
                                    .font(.caption)
                                    .foregroundColor(summary.isFamily ? .orange : .blue)

                                Text(summary.title)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                            }

                            Text(summary.lastMessagePreview ?? "Sin mensajes todavía")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: 160, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(activeConversationId == summary.id ? Color.accentColor.opacity(0.2) : Color.meshRowBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(activeConversationId == summary.id ? Color.accentColor : Color.primary.opacity(0.05), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
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
                // UWB direct response - highest precision
                if let relative = response.relativeLocation {
                    HStack(spacing: 4) {
                        Image(systemName: "location.north.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                        Text("Ubicación UWB Precisa:")
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

                    Text("Precisión: ±\(String(format: "%.1f", relative.accuracy))m (UWB)")
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

struct MessageBubble: View {
    let message: Message
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

                Text(message.formattedTime)
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
            return Color.accentColor
        } else {
            return Color.meshRowBackground
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(NetworkManager())
}
