//
//  ContentView.swift
//  MeshRed
//
//  Created by Emilio Contreras on 28/09/25.
//

import SwiftUI
import MultipeerConnectivity

struct ContentView: View {
    @EnvironmentObject var networkManager: NetworkManager
    @State private var messageText = ""

    var body: some View {
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

                    Text(connectionStatusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Disponibles: \(networkManager.availablePeers.count)")
                        .font(.caption2)

                    Spacer()

                    Text("Conectados: \(networkManager.connectedPeers.count)")
                        .font(.caption2)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)

            // Available Peers
            GroupBox("Dispositivos Detectados") {
                if networkManager.availablePeers.isEmpty {
                    Text("Buscando dispositivos...")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    VStack(alignment: .leading) {
                        ForEach(networkManager.availablePeers, id: \.displayName) { peer in
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
                    Text("No hay dispositivos conectados")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    VStack(alignment: .leading) {
                        ForEach(networkManager.connectedPeers, id: \.displayName) { peer in
                            HStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Image(systemName: "iphone")
                                    .foregroundColor(.green)
                                Text(peer.displayName)
                                Spacer()
                                Text("Conectado")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            .padding(.vertical, 2)
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

            Spacer()

            // Input
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
                        .background(messageText.isEmpty ? Color.gray : Color.blue)
                        .cornerRadius(8)
                }
                .disabled(messageText.isEmpty || networkManager.connectedPeers.isEmpty)
            }
            .padding()
        }
        .padding()
        .background(Color(.systemGroupedBackground))
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

        networkManager.sendMessage(messageText)
        messageText = ""
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
                    .background(isFromLocal ? Color.blue : Color(.systemGray5))
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