//
//  UWBInfoSheet.swift
//  MeshRed
//
//  Device UWB compatibility information sheet
//

import SwiftUI
import MultipeerConnectivity

struct UWBInfoSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var networkManager: NetworkManager
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Local Device Info
                    localDeviceSection

                    Divider()

                    // UWB Explanation
                    uwbExplanationSection

                    Divider()

                    // Device Compatibility
                    compatibilitySection

                    Divider()

                    // Connected Peers
                    connectedPeersSection
                }
                .padding()
            }
            .background(accessibleTheme.background)
            .navigationTitle("Información LinkFinder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Local Device Section
    private var localDeviceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Tu Dispositivo", systemImage: "iphone")
                .font(.headline)
                .foregroundColor(accessibleTheme.textPrimary)

            if #available(iOS 14.0, *),
               let uwbManager = networkManager.uwbSessionManager,
               let localCaps = uwbManager.localDeviceCapabilities {

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Modelo:")
                            .font(.subheadline)
                            .foregroundColor(accessibleTheme.textSecondary)
                        Text(localCaps.deviceModel)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(accessibleTheme.textPrimary)
                    }

                    HStack {
                        Text("Chip UWB:")
                            .font(.subheadline)
                            .foregroundColor(accessibleTheme.textSecondary)
                        if localCaps.hasU2Chip {
                            Label("U2 (3ra gen)", systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundColor(Mundial2026Colors.verde)
                        } else if localCaps.hasU1Chip {
                            Label("U1 (1ra gen)", systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundColor(Mundial2026Colors.azul)
                        } else {
                            Label("No disponible", systemImage: "xmark.circle.fill")
                                .font(.subheadline)
                                .foregroundColor(Color.red)
                        }
                    }

                    HStack {
                        Text("Capacidades:")
                            .font(.subheadline)
                            .foregroundColor(accessibleTheme.textSecondary)
                        Text(localCaps.summary)
                            .font(.subheadline)
                            .foregroundColor(accessibleTheme.textPrimary)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(localCaps.hasUWB ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                )
            }
        }
    }

    // MARK: - UWB Explanation Section
    private var uwbExplanationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("¿Qué es UWB?", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)
                .foregroundColor(accessibleTheme.textPrimary)

            VStack(alignment: .leading, spacing: 12) {
                Text("Ultra Wideband (UWB) es una tecnología de radiofrecuencia que permite:")
                    .font(.subheadline)
                    .foregroundColor(accessibleTheme.textSecondary)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Distancia precisa (±10cm)", systemImage: "ruler")
                        .font(.caption)
                        .foregroundColor(accessibleTheme.textPrimary)

                    Label("Dirección exacta con flecha", systemImage: "location.north.fill")
                        .font(.caption)
                        .foregroundColor(accessibleTheme.textPrimary)

                    Label("Funciona en multitudes", systemImage: "person.3.fill")
                        .font(.caption)
                        .foregroundColor(accessibleTheme.textPrimary)
                }
                .padding(.leading)
            }

            // Limitation warning
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(Color.orange)

                Text("La dirección requiere que AMBOS dispositivos tengan chip UWB")
                    .font(.caption)
                    .foregroundColor(Color.orange)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.1))
            )
        }
    }

    // MARK: - Compatibility Section
    private var compatibilitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Dispositivos Compatibles", systemImage: "checkmark.shield")
                .font(.headline)
                .foregroundColor(accessibleTheme.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Con chip U1 (dirección nativa):")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(accessibleTheme.textPrimary)
                Text("iPhone 11, 11 Pro, 11 Pro Max, 12, 13")
                    .font(.caption)
                    .foregroundColor(accessibleTheme.textSecondary)
                Text("→ Dirección funciona de forma nativa sin cámara")
                    .font(.caption2)
                    .foregroundColor(Mundial2026Colors.verde)
                    .padding(.leading, 8)

                Text("Con chip U1 (requiere ARKit):")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(accessibleTheme.textPrimary)
                    .padding(.top, 8)
                Text("iPhone 14, 14 Plus")
                    .font(.caption)
                    .foregroundColor(accessibleTheme.textSecondary)
                Text("→ Dirección requiere cámara activa (ARKit)")
                    .font(.caption2)
                    .foregroundColor(Color.orange)
                    .padding(.leading, 8)

                Text("Con chip U2 (requiere ARKit):")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(accessibleTheme.textPrimary)
                    .padding(.top, 8)
                Text("iPhone 15, 16, 17 y posteriores")
                    .font(.caption)
                    .foregroundColor(accessibleTheme.textSecondary)
                Text("→ Mayor alcance (60m), requiere cámara activa")
                    .font(.caption2)
                    .foregroundColor(Color.orange)
                    .padding(.leading, 8)

                Text("Sin UWB:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(Color.red)
                    .padding(.top, 8)
                Text("iPhone SE, iPhone X y anteriores")
                    .font(.caption)
                    .foregroundColor(accessibleTheme.textSecondary)
                Text("→ Sin medición de distancia/dirección UWB")
                    .font(.caption2)
                    .foregroundColor(Color.red)
                    .padding(.leading, 8)
            }
        }
    }

    // MARK: - Connected Peers Section
    private var connectedPeersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Peers Conectados", systemImage: "person.2.circle")
                .font(.headline)
                .foregroundColor(accessibleTheme.textPrimary)

            if #available(iOS 14.0, *),
               let uwbManager = networkManager.uwbSessionManager {

                if uwbManager.peerCapabilities.isEmpty {
                    Text("No hay peers con información de capacidades")
                        .font(.caption)
                        .foregroundColor(accessibleTheme.textSecondary)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.1))
                        )
                } else {
                    ForEach(Array(uwbManager.peerCapabilities.keys), id: \.self) { peerId in
                        if let peerCaps = uwbManager.peerCapabilities[peerId],
                           let localCaps = uwbManager.localDeviceCapabilities {

                            let compatibility = localCaps.isCompatibleWith(peerCaps)

                            HStack(spacing: 12) {
                                // Icon
                                Image(systemName: peerCaps.hasUWB ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                                    .font(.title2)
                                    .foregroundColor(peerCaps.hasUWB ? Mundial2026Colors.azul : Color.orange)

                                // Info
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(peerId)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(accessibleTheme.textPrimary)

                                    Text("\(peerCaps.deviceModel) • \(peerCaps.summary)")
                                        .font(.caption)
                                        .foregroundColor(accessibleTheme.textSecondary)

                                    HStack(spacing: 8) {
                                        Label("Distancia", systemImage: compatibility.distance ? "checkmark" : "xmark")
                                            .font(.caption2)
                                            .foregroundColor(compatibility.distance ? Mundial2026Colors.verde : Color.red)

                                        Label("Dirección", systemImage: compatibility.direction ? "checkmark" : "xmark")
                                            .font(.caption2)
                                            .foregroundColor(compatibility.direction ? Mundial2026Colors.verde : Color.red)
                                    }
                                }

                                Spacer()
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.1))
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    UWBInfoSheet()
        .environmentObject(NetworkManager())
        .environmentObject(AccessibilitySettingsManager())
}