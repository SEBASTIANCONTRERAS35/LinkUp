//
//  FamilyGroupView.swift
//  MeshRed
//
//  Created by Claude for StadiumConnect Pro
//

import SwiftUI
import MultipeerConnectivity
import os

struct FamilyGroupView: View {
    @EnvironmentObject var networkManager: NetworkManager
    @ObservedObject var familyGroupManager: FamilyGroupManager

    @State private var showCreateGroup = false
    @State private var showJoinGroup = false
    @State private var showShareSheet = false
    @State private var showSimulationControl = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    if familyGroupManager.hasActiveGroup {
                        activeGroupView
                    } else {
                        emptyStateView
                    }
                }
                .padding(20)
            }
            .background(appBackgroundColor.ignoresSafeArea())
            .navigationTitle("Grupo Familiar")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showCreateGroup) {
                CreateFamilyGroupView(
                    familyGroupManager: familyGroupManager,
                    localPeerID: networkManager.localDeviceName
                )
                .environmentObject(networkManager)
            }
            .sheet(isPresented: $showJoinGroup) {
                JoinFamilyGroupView(
                    familyGroupManager: familyGroupManager,
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

    // MARK: - Active Group View

    private var activeGroupView: some View {
        VStack(spacing: 20) {
            if let group = familyGroupManager.currentGroup {
                // Group Header Card
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.name)
                                .font(.title2.bold())
                                .foregroundColor(.white)

                            Text("\(group.memberCount) miembros")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                        }

                        Spacer()

                        Button(action: { showShareSheet = true }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    Divider()
                        .overlay(Color.white.opacity(0.2))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Código de grupo")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))

                        HStack {
                            Text(group.code.displayCode)
                                .font(.system(.title3, design: .monospaced).bold())
                                .foregroundColor(.white)

                            Spacer()

                            Button(action: copyCodeToClipboard) {
                                Label("Copiar", systemImage: "doc.on.doc")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.white)
                                    .foregroundColor(.blue)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.cyan.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .blue.opacity(0.3), radius: 12, x: 0, y: 6)

                // Members List
                VStack(alignment: .leading, spacing: 16) {
                    Text("Miembros de la familia")
                        .font(.headline)
                        .padding(.horizontal, 4)

                    if group.members.isEmpty {
                        EmptyMembersView()
                    } else {
                        VStack(spacing: 12) {
                            ForEach(group.membersByLastSeen) { member in
                                FamilyMemberRow(
                                    member: member,
                                    isConnected: isConnected(peerID: member.peerID)
                                )
                            }
                        }
                    }
                }

                // Leave Group Button
                Button(action: leaveGroup) {
                    Label("Salir del grupo", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.subheadline.bold())
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let group = familyGroupManager.currentGroup {
                ShareSheet(items: [shareText(for: group)])
            }
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.blue.opacity(0.6))

                VStack(spacing: 8) {
                    Text("No tienes un grupo familiar")
                        .font(.title2.bold())

                    Text("Crea o únete a un grupo para encontrar a tu familia fácilmente en el estadio")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            // Hidden tap area to access simulation (triple tap)
            Color.clear
                .frame(height: 60)
                .contentShape(Rectangle())
                .onTapGesture(count: 3) {
                    showSimulationControl = true
                }

            VStack(spacing: 12) {
                Button(action: { showCreateGroup = true }) {
                    Label("Crear nuevo grupo", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: { showJoinGroup = true }) {
                    Label("Unirme a un grupo", systemImage: "qrcode.viewfinder")
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Helper Methods

    private func isConnected(peerID: String) -> Bool {
        return networkManager.connectedPeers.contains { $0.displayName == peerID }
    }

    private func copyCodeToClipboard() {
        guard let code = familyGroupManager.groupCode else { return }

        #if os(iOS)
        UIPasteboard.general.string = code.displayCode
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code.displayCode, forType: .string)
        #endif

        LoggingService.network.info("📋 Código copiado: \(code.displayCode)")
    }

    private func shareText(for group: FamilyGroup) -> String {
        return """
        ¡Únete a mi grupo familiar en StadiumConnect!

        Grupo: \(group.name)
        Código: \(group.code.displayCode)

        Escanea este QR o ingresa el código en la app para unirte.
        """
    }

    private func leaveGroup() {
        familyGroupManager.leaveGroup()
    }

    private var appBackgroundColor: Color {
        #if os(iOS)
        Color(.systemGroupedBackground)
        #else
        Color(NSColor.windowBackgroundColor)
        #endif
    }
}

// MARK: - Family Member Row

struct FamilyMemberRow: View {
    let member: FamilyMember
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 14) {
            // Status indicator
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 48, height: 48)

                Image(systemName: member.isCurrentDevice ? "person.fill" : "person")
                    .font(.title3)
                    .foregroundColor(statusColor)
            }

            // Member info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(member.displayName)
                        .font(.subheadline.bold())

                    if member.isCurrentDevice {
                        Text("(Tú)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let relation = member.relationshipTag {
                    Text(relation)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(statusText)
                    .font(.caption2)
                    .foregroundColor(statusColor)
            }

            Spacer()

            if isConnected && !member.isCurrentDevice {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.green)
            }
        }
        .padding(14)
        .background(Color.meshCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var statusColor: Color {
        if member.isCurrentDevice {
            return .blue
        } else if isConnected {
            return .green
        } else if member.isRecentlySeen {
            return .orange
        } else {
            return .secondary
        }
    }

    private var statusText: String {
        if isConnected {
            return "Conectado ahora"
        } else if let lastSeen = member.lastSeenDate {
            return member.timeSinceLastSeen
        } else {
            return "Nunca visto"
        }
    }
}

struct EmptyMembersView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2.slash")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("No hay miembros aún")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("Comparte el código para que tu familia se una")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Share Sheet (iOS/macOS)

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#elseif os(macOS)
struct ShareSheet: NSViewRepresentable {
    let items: [Any]

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

// MARK: - Helpers

private extension Color {
    static var meshCardBackground: Color {
        #if os(iOS)
        return Color(.secondarySystemBackground)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }
}
