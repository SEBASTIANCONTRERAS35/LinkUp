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
                        } : nil
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
                        onRequestLocation: requestLocation,
                        onNavigate: startNavigation,
                        onReconnectTap: networkManager.restartServicesIfNeeded
                    )

                    MessagesSection(
                        messages: networkManager.messageStore.sortedMessages,
                        localDeviceName: networkManager.localDeviceName
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
                        onRequestPermissions: {
                            networkManager.locationService.requestPermissions()
                        },
                        onClearConnections: clearConnections
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
                sendAction: sendMessage
            )
            .background(inputBackgroundColor)
        }
        .background(appBackgroundColor.ignoresSafeArea())
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
    let onRequestLocation: (MCPeerID) -> Void
    let onNavigate: (MCPeerID) -> Void
    let onReconnectTap: () -> Void

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
                            ForEach(connectedPeers, id: \.self) { peer in
                                ConnectedPeerRow(
                                    peer: peer,
                                    locationResponse: locationResponseProvider(peer.displayName),
                                    hasUWBSession: uwbSessionChecker(peer),
                                    localDeviceName: localDeviceName,
                                    onRequestLocation: onRequestLocation,
                                    onNavigate: onNavigate
                                )
                            }
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
}

private struct MessagesSection: View {
    let messages: [Message]
    let localDeviceName: String

    var body: some View {
        SectionCard(
            title: "Mensajes",
            icon: "bubble.left.and.bubble.right",
            caption: messages.isEmpty
                ? "Aún no hay mensajes en esta sesión."
                : "Historial reciente de la conversación."
        ) {
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
    let onRequestPermissions: () -> Void
    let onClearConnections: () -> Void

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
                            ForEach(connectedPeers, id: \.self) { peer in
                                Text(peer.displayName).tag(peer.displayName)
                            }
                        }
                        .pickerStyle(.menu)

                        if recipientId != "broadcast" {
                            Label("Ruta dirigida - probará multi-hop si es necesario", systemImage: "arrow.triangle.branch")
                                .font(.caption2)
                                .foregroundColor(.orange)
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
    let localDeviceName: String
    let onRequestLocation: (MCPeerID) -> Void
    let onNavigate: (MCPeerID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(peer.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("Conectado")
                        .font(.caption2)
                        .foregroundColor(.green)
                }

                Spacer(minLength: 0)

                // Botón de navegación UWB - aparece cuando hay sesión UWB activa
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
                    // Botón de ubicar (GPS)
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

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .foregroundColor(.secondary)

                    TextField("Escribe un mensaje...", text: $messageText)
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
