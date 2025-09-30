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

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                // Header
                VStack(spacing: 8) {
                HStack {
                    Circle()
                        .fill(connectionStatusColor)
                        .frame(width: 12, height: 12)

                    Text(networkManager.localDeviceName)
                        .font(.headline)

                    Spacer()

                    HStack(spacing: 4) {
                        Text(networkManager.connectionQuality.rawValue)
                        Text(networkManager.connectionQuality.displayName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if networkManager.relayingMessage {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text("Reenviando...")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    Text(connectionStatusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Disponibles: \(networkManager.availablePeers.count)")
                        .font(.caption2)

                    Spacer()

                    if networkManager.pendingAcksCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.caption2)
                            Text("ACKs: \(networkManager.pendingAcksCount)")
                                .font(.caption2)
                        }
                        .foregroundColor(.orange)
                    }

                    Text("Conectados: \(networkManager.connectedPeers.count)")
                        .font(.caption2)
                }

                if networkManager.networkStats.blocked > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Text("\(networkManager.networkStats.blocked) bloqueados")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding()
            #if os(iOS)
            .background(Color(.systemBackground))
            #else
            .background(Color(NSColor.controlBackgroundColor))
            #endif
            .cornerRadius(12)

            // Available Peers
            GroupBox("Dispositivos Detectados") {
                if networkManager.availablePeers.isEmpty {
                    Text("Buscando dispositivos...")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    VStack(alignment: .leading) {
                        ForEach(networkManager.availablePeers, id: \.self) { peer in
                            HStack {
                                Image(systemName: "iphone")
                                    .foregroundColor(.blue)
                                Text(peer.displayName)
                                Spacer()
                                Text("Disponible")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            // Connected Peers
            GroupBox("Dispositivos Conectados") {
                if networkManager.connectedPeers.isEmpty {
                    VStack {
                        Text("No hay dispositivos conectados")
                            .foregroundColor(.secondary)
                            .padding()

                        Button(action: {
                            print("🔄 User requested network restart")
                            networkManager.restartServicesIfNeeded()
                        }) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Reconectar")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(networkManager.connectedPeers, id: \.self) { peer in
                            HStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Image(systemName: "iphone")
                                    .foregroundColor(.green)
                                Text(peer.displayName)
                                Spacer()

                                // Locate button
                                Button(action: {
                                    requestLocation(for: peer)
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "location.circle")
                                        Text("Ubicar")
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                                }

                                Text("Conectado")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            .padding(.vertical, 4)

                            // Show location response if available
                            if let response = networkManager.locationRequestManager.getResponse(for: peer.displayName) {
                                LocationResponseView(response: response, localDeviceName: networkManager.localDeviceName)
                                    .padding(.leading, 24)
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }

            // Messages
            GroupBox("Mensajes") {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if networkManager.messageStore.messages.isEmpty {
                            Text("No hay mensajes")
                                .foregroundColor(.secondary)
                                .padding()
                        } else {
                            ForEach(networkManager.messageStore.sortedMessages) { message in
                                MessageBubble(
                                    message: message,
                                    isFromLocal: message.sender == networkManager.localDeviceName
                                )
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(height: 200)
            }

            // Network Stats
            if showAdvancedOptions {
                GroupBox("Estadísticas de Red") {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Intentos de conexión:")
                                .font(.caption)
                            Spacer()
                            Text("\(networkManager.networkStats.attempts)")
                                .font(.caption.monospaced())
                        }
                        HStack {
                            Text("Peers bloqueados:")
                                .font(.caption)
                            Spacer()
                            Text("\(networkManager.networkStats.blocked)")
                                .font(.caption.monospaced())
                                .foregroundColor(networkManager.networkStats.blocked > 0 ? .orange : .primary)
                        }
                        HStack {
                            Text("Conexiones activas:")
                                .font(.caption)
                            Spacer()
                            Text("\(networkManager.networkStats.active)")
                                .font(.caption.monospaced())
                                .foregroundColor(.green)
                        }

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: "location.circle")
                                        .font(.caption2)
                                    Text("Ubicación:")
                                        .font(.caption)
                                    Text(locationStatusText)
                                        .font(.caption)
                                        .foregroundColor(locationStatusColor)
                                }

                                if networkManager.locationService.authorizationStatus == .notDetermined {
                                    Button(action: {
                                        networkManager.locationService.requestPermissions()
                                    }) {
                                        Text("Solicitar Permisos")
                                            .font(.caption2)
                                    }
                                    .buttonStyle(BorderedButtonStyle())
                                    .controlSize(.mini)
                                }
                            }

                            Spacer()

                            Button(action: clearConnections) {
                                Label("Limpiar Conexiones", systemImage: "arrow.clockwise")
                                    .font(.caption)
                            }
                            .buttonStyle(BorderedButtonStyle())
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Advanced Options
            VStack(spacing: 12) {
                Button(action: { showAdvancedOptions.toggle() }) {
                    HStack {
                        Image(systemName: showAdvancedOptions ? "chevron.down" : "chevron.right")
                            .font(.caption)
                        Text("Opciones Avanzadas")
                            .font(.caption)
                        Spacer()
                    }
                }
                .buttonStyle(PlainButtonStyle())

                if showAdvancedOptions {
                    VStack(spacing: 8) {
                        // Message Type Selector
                        HStack {
                            Text("Tipo:")
                                .font(.caption)
                            Picker("Tipo", selection: $selectedMessageType) {
                                ForEach(MessageType.allCases, id: \.self) { type in
                                    Text(type.displayName)
                                        .tag(type)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }

                        // Priority Indicator
                        HStack {
                            Text("Prioridad:")
                                .font(.caption)
                            Circle()
                                .fill(priorityColor(for: selectedMessageType))
                                .frame(width: 8, height: 8)
                            Text("\(selectedMessageType.defaultPriority)")
                                .font(.caption)
                                .foregroundColor(priorityColor(for: selectedMessageType))
                            Spacer()
                        }

                        // Recipient Selector (for testing multi-hop)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Destinatario:")
                                .font(.caption)
                            Picker("Destinatario", selection: $recipientId) {
                                Text("Broadcast (todos)").tag("broadcast")
                                ForEach(networkManager.connectedPeers, id: \.self) { peer in
                                    Text(peer.displayName).tag(peer.displayName)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())

                            if recipientId != "broadcast" {
                                HStack {
                                    Image(systemName: "arrow.triangle.branch")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                    Text("Mensaje dirigido - probará multi-hop si no hay conexión directa")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            }
                        }

                        // Requires ACK Toggle
                        Toggle(isOn: $requiresAck) {
                            HStack {
                                Image(systemName: "checkmark.seal")
                                    .font(.caption)
                                Text("Requiere confirmación")
                                    .font(.caption)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                    }
                    .padding()
                    #if os(iOS)
                    .background(Color(.systemGray6))
                    #else
                    .background(Color(NSColor.controlBackgroundColor))
                    #endif
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal)
            }
            .padding()
        }

            // Input field fijo en la parte inferior
            VStack(spacing: 0) {
                Divider()

                HStack {
                    TextField("Escribe un mensaje...", text: $messageText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            sendMessage()
                        }

                    Button(action: sendMessage) {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(.white)
                            .padding(8)
                            .background(messageText.isEmpty ? Color.gray : priorityColor(for: selectedMessageType))
                            .cornerRadius(8)
                    }
                    .disabled(messageText.isEmpty || networkManager.connectedPeers.isEmpty)
                }
                .padding()
                #if os(iOS)
            .background(Color(.systemBackground))
            #else
            .background(Color(NSColor.controlBackgroundColor))
            #endif
            }
        }
        #if os(iOS)
        .background(Color(.systemGroupedBackground))
        #else
        .background(Color(NSColor.windowBackgroundColor))
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
        print("📍 User requested location for \(peer.displayName)")
        networkManager.sendLocationRequest(to: peer.displayName)
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
        HStack {
            if isFromLocal {
                Spacer()
            }

            VStack(alignment: isFromLocal ? .trailing : .leading, spacing: 4) {
                if !isFromLocal {
                    Text(message.sender)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }

                Text(message.content)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    #if os(iOS)
                    .background(isFromLocal ? Color.blue : Color(.systemGray5))
                    #else
                    .background(isFromLocal ? Color.blue : Color(NSColor.controlBackgroundColor))
                    #endif
                    .foregroundColor(isFromLocal ? .white : .primary)
                    .cornerRadius(16)

                Text(message.formattedTime)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: 250, alignment: isFromLocal ? .trailing : .leading)

            if !isFromLocal {
                Spacer()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(NetworkManager())
}