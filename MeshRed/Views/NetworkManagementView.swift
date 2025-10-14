//
//  NetworkManagementView.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Network connection management with 5-peer limit
//

import SwiftUI
import MultipeerConnectivity
import os

struct NetworkManagementView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var networkManager: NetworkManager
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme
    @StateObject private var connectionManager = ConnectionManager()

    @State private var showUnblockAllAlert = false

    private var maxConnections: Int {
        5 // Fixed limit for this feature
    }

    private var connectedPeers: [MCPeerID] {
        networkManager.connectedPeers
    }

    private var availablePeers: [MCPeerID] {
        // Filter out already connected peers and blocked peers
        networkManager.availablePeers.filter { peer in
            !connectedPeers.contains(peer) &&
            !connectionManager.isPeerBlocked(peer.displayName)
        }
    }

    private var blockedPeers: [String] {
        Array(connectionManager.blockedPeers)
    }

    private var canConnectMore: Bool {
        connectedPeers.count < maxConnections
    }

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Connection limit indicator
                    ConnectionLimitIndicator(
                        current: connectedPeers.count,
                        maximum: maxConnections
                    )
                    .padding(.top, 20)

                    // Radar view button
                    NavigationLink(destination: NetworkRadarView()) {
                        HStack(spacing: 16) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 50, height: 50)
                                .background(accessibleTheme.primaryGradient)
                                .cornerRadius(12)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Ver Radar de Proximidad")
                                    .font(.headline)
                                    .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
                                    .foregroundColor(accessibleTheme.textPrimary)
                                    .accessibleText()

                                Text("Visualiza dónde están tus conexiones")
                                    .font(.caption)
                                    .foregroundColor(accessibleTheme.textSecondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.subheadline)
                                .foregroundColor(accessibleTheme.textSecondary)
                        }
                        .padding(16)
                        .accessibleBackground(accessibleTheme.cardBackground)
                        .cornerRadius(16)
                        .accessibleShadow()
                    }
                    .disabled(connectedPeers.isEmpty)
                    .opacity(connectedPeers.isEmpty ? 0.5 : 1.0)

                    // Connected peers section
                    if !connectedPeers.isEmpty {
                        connectedPeersSection
                    }

                    // Available peers section
                    if !availablePeers.isEmpty {
                        availablePeersSection
                    } else if canConnectMore {
                        emptyAvailableState
                    }

                    // Full capacity message
                    if !canConnectMore && !availablePeers.isEmpty {
                        fullCapacityMessage
                    }

                    // Debug section (if blocked peers exist)
                    if !blockedPeers.isEmpty {
                        blockedPeersSection
                    }

                    // Extra spacing for bottom
                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 20)
            }
            .background(accessibleTheme.background.ignoresSafeArea())
            .navigationTitle("LinkMesh")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") {
                        dismiss()
                    }
                    .foregroundColor(accessibleTheme.primaryBlue)
                    .accessibleButton()
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if !blockedPeers.isEmpty {
                        Button(action: { showUnblockAllAlert = true }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(accessibleTheme.primaryBlue)
                        }
                        .accessibleButton()
                    }
                }
            }
            .alert("Desbloquear Todos", isPresented: $showUnblockAllAlert) {
                Button("Cancelar", role: .cancel) {}
                Button("Desbloquear", role: .destructive) {
                    connectionManager.unblockAllPeers()
                }
            } message: {
                Text("¿Deseas desbloquear todos los dispositivos (\(blockedPeers.count))? Podrán reconectarse automáticamente.")
            }
        }
    }

    // MARK: - Connected Peers Section
    private var connectedPeersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                Text("Mis Conexiones")
                    .font(.headline)
                    .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
                    .accessibleText()

                Spacer()

                Text("\(connectedPeers.count)")
                    .font(.subheadline)
                    .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(accessibleTheme.primaryGreen)
                    )
            }

            // Peer cards
            ForEach(connectedPeers, id: \.self) { peer in
                PeerConnectionCard(
                    peer: peer,
                    isConnected: true,
                    distance: getDistance(for: peer),
                    signalQuality: getSignalQuality(for: peer),
                    onConnect: {},
                    onDisconnect: {
                        disconnectPeer(peer)
                    }
                )
            }
        }
    }

    // MARK: - Available Peers Section
    private var availablePeersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                Text("Disponibles para Conectar")
                    .font(.headline)
                    .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
                    .accessibleText()

                Spacer()

                Text("\(availablePeers.count)")
                    .font(.subheadline)
                    .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(accessibleTheme.primaryBlue)
                    )
            }

            // Peer cards
            ForEach(availablePeers, id: \.self) { peer in
                PeerConnectionCard(
                    peer: peer,
                    isConnected: false,
                    distance: nil,
                    signalQuality: .unknown,
                    onConnect: {
                        connectToPeer(peer)
                    },
                    onDisconnect: {}
                )
                .opacity(canConnectMore ? 1.0 : 0.5)
                .disabled(!canConnectMore)
            }
        }
    }

    // MARK: - Empty State
    private var emptyAvailableState: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundColor(accessibleTheme.primaryBlue.opacity(0.5))

            Text("Buscando dispositivos cerca...")
                .font(.subheadline)
                .foregroundColor(accessibleTheme.textSecondary)
                .accessibleText()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .accessibleBackground(accessibleTheme.cardBackground)
        .cornerRadius(16)
    }

    // MARK: - Full Capacity Message
    private var fullCapacityMessage: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundColor(accessibleTheme.error)

            VStack(alignment: .leading, spacing: 4) {
                Text("Capacidad máxima alcanzada")
                    .font(.subheadline)
                    .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
                    .accessibleText()

                Text("Desconecta a alguien para conectar a nuevas personas")
                    .font(.caption)
                    .foregroundColor(accessibleTheme.textSecondary)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(accessibleTheme.error.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(accessibleTheme.error.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Blocked Peers Section (Debug)
    private var blockedPeersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Bloqueados Temporalmente")
                    .font(.caption)
                    .foregroundColor(accessibleTheme.textSecondary)

                Spacer()

                Text("\(blockedPeers.count)")
                    .font(.caption)
                    .foregroundColor(accessibleTheme.textSecondary)
            }

            ForEach(blockedPeers, id: \.self) { peerName in
                HStack {
                    Image(systemName: "hand.raised.fill")
                        .font(.caption)
                        .foregroundColor(accessibleTheme.textSecondary)

                    Text(peerName)
                        .font(.caption)
                        .foregroundColor(accessibleTheme.textSecondary)

                    Spacer()

                    Button(action: {
                        connectionManager.unblockPeer(peerName)
                    }) {
                        Text("Desbloquear")
                            .font(.caption2)
                            .foregroundColor(accessibleTheme.primaryBlue)
                    }
                    .accessibleButton()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(accessibleTheme.textSecondary.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding(16)
        .accessibleBackground(accessibleTheme.cardBackground)
        .cornerRadius(16)
    }

    // MARK: - Helper Methods

    private func connectToPeer(_ peer: MCPeerID) {
        guard canConnectMore else {
            LoggingService.network.info("⚠️ Cannot connect: At maximum capacity (\(maxConnections))")
            return
        }

        connectionManager.manuallyConnectPeer(peer)
        networkManager.connectToPeer(peer)

        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif

        LoggingService.network.info("✅ Connecting to: \(peer.displayName)")
    }

    private func disconnectPeer(_ peer: MCPeerID) {
        connectionManager.manuallyDisconnectPeer(peer)
        networkManager.disconnectFromPeer(peer)

        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        #endif

        LoggingService.network.info("🚫 Disconnected from: \(peer.displayName)")
    }

    private func getDistance(for peer: MCPeerID) -> String? {
        // Try to get LinkFinder distance if available
        // LinkFinder distance would be retrieved here
        // For now, return nil
        return nil
    }

    private func getSignalQuality(for peer: MCPeerID) -> PeerConnectionCard.SignalQuality {
        // Get signal quality from health monitor
        // PeerHealthMonitor tracks ping/pong but doesn't expose stats publicly
        // For now, return unknown - can be enhanced later
        return .unknown
    }
}

// MARK: - Preview
#Preview {
    NetworkManagementView()
        .environmentObject(NetworkManager())
        .environmentObject(AccessibilitySettingsManager.shared)
}
