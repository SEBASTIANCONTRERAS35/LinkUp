//
//  PeerConnectionCard.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Card component for displaying peer connection status
//

import SwiftUI
import MultipeerConnectivity

struct PeerConnectionCard: View {
    let peer: MCPeerID
    let isConnected: Bool
    let distance: String?
    let signalQuality: SignalQuality
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    @State private var isPressed = false

    enum SignalQuality {
        case excellent
        case good
        case poor
        case unknown

        var icon: String {
            switch self {
            case .excellent: return "antenna.radiowaves.left.and.right"
            case .good: return "wifi"
            case .poor: return "wifi.slash"
            case .unknown: return "questionmark.circle"
            }
        }

        var color: Color {
            switch self {
            case .excellent: return Color.appAccent
            case .good: return Color.appSecondary
            case .poor: return Mundial2026Colors.rojo
            case .unknown: return .gray
            }
        }

        var text: String {
            switch self {
            case .excellent: return "Excelente"
            case .good: return "Buena"
            case .poor: return "Pobre"
            case .unknown: return "Desconocida"
            }
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            // Status indicator dot
            Circle()
                .fill(isConnected ? Color.appAccent : Color.appSecondary.opacity(0.5))
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(isConnected ? Color.appAccent : Color.appSecondary, lineWidth: 2)
                        .scaleEffect(isConnected ? 1.5 : 1.0)
                        .opacity(isConnected ? 0.3 : 0)
                )
                .accessibilityHidden(true)

            // Peer info
            VStack(alignment: .leading, spacing: 6) {
                // Name
                Text(peer.displayName)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                // Status and distance
                HStack(spacing: 8) {
                    // Connection status badge
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isConnected ? Color.appAccent : Color.gray)
                            .frame(width: 6, height: 6)
                        Text(isConnected ? "Conectado" : "Disponible")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isConnected ? Color.appAccent.opacity(0.1) : Color.gray.opacity(0.1))
                    )

                    // Distance (if available)
                    if let distance = distance {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.caption2)
                            Text(distance)
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }

                    // Signal quality (if connected)
                    if isConnected {
                        HStack(spacing: 4) {
                            Image(systemName: signalQuality.icon)
                                .font(.caption2)
                            Text(signalQuality.text)
                                .font(.caption2)
                        }
                        .foregroundColor(signalQuality.color)
                    }
                }
            }

            Spacer()

            // Action button
            Button(action: {
                #if os(iOS)
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                #endif

                if isConnected {
                    onDisconnect()
                } else {
                    onConnect()
                }
            }) {
                Text(isConnected ? "Desconectar" : "Conectar")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isConnected ? Mundial2026Colors.rojo : Color.appSecondary)
                    )
                    .shadow(
                        color: (isConnected ? Mundial2026Colors.rojo : Color.appSecondary).opacity(0.3),
                        radius: isPressed ? 2 : 6,
                        x: 0,
                        y: isPressed ? 1 : 3
                    )
            }
            .buttonStyle(.plain)
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isPressed = true
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isPressed = false
                        }
                    }
            )
            .accessibilityLabel("\(isConnected ? "Disconnect from" : "Connect to") \(peer.displayName)")
            .accessibilityHint(isConnected ? "Double tap to disconnect" : "Double tap to connect")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isConnected ? Color.appAccent.opacity(0.3) : Color.appSecondary.opacity(0.2),
                    lineWidth: isConnected ? 2 : 1
                )
        )
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        // ACCESSIBILITY: Announce peer info as group
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 16) {
        PeerConnectionCard(
            peer: MCPeerID(displayName: "Ana García"),
            isConnected: true,
            distance: "1.2m",
            signalQuality: .excellent,
            onConnect: {},
            onDisconnect: {}
        )

        PeerConnectionCard(
            peer: MCPeerID(displayName: "Carlos Ruiz"),
            isConnected: false,
            distance: nil,
            signalQuality: .unknown,
            onConnect: {},
            onDisconnect: {}
        )
    }
    .padding()
    .background(Color.appBackgroundDark)
}
