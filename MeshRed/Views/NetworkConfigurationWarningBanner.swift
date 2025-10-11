//
//  NetworkConfigurationWarningBanner.swift
//  MeshRed
//
//  Created by Emilio Contreras on 10/10/25.
//

import SwiftUI

struct NetworkConfigurationWarningBanner: View {
    @ObservedObject var networkManager: NetworkManager
    @State private var showingSettings = false

    var body: some View {
        if networkManager.hasNetworkConfigurationIssue {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Configuración de Red Problemática")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text(networkManager.networkConfigurationMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()

                HStack(spacing: 16) {
                    Button(action: openSettings) {
                        Label("Abrir Ajustes", systemImage: "gear")
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.orange)
                            .cornerRadius(8)
                    }

                    Button(action: { showingSettings.toggle() }) {
                        Label("Más Info", systemImage: "info.circle")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding()
            .background(Color.orange.opacity(0.15))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.orange.opacity(0.5), lineWidth: 1)
            )
            .padding(.horizontal)
            .padding(.top, 8)
            .sheet(isPresented: $showingSettings) {
                NetworkConfigurationHelpView()
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

struct NetworkConfigurationHelpView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Problem Section
                    VStack(alignment: .leading, spacing: 12) {
                        Label("¿Qué está mal?", systemImage: "questionmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.orange)

                        Text("Tu dispositivo tiene WiFi habilitado pero no está conectado a ninguna red.")
                            .font(.body)
                            .foregroundColor(.secondary)

                        Text("Esto causa que MultipeerConnectivity intente usar WiFi Direct/TCP, que fallará con timeouts (Error Code 60).")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)

                    // Solutions Section
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Soluciones", systemImage: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)

                        // Solution 1
                        HStack(alignment: .top, spacing: 12) {
                            Text("1")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(Color.green)
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Conecta a una red WiFi")
                                    .font(.headline)
                                Text("Settings → WiFi → Selecciona una red")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Solution 2
                        HStack(alignment: .top, spacing: 12) {
                            Text("2")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(Color.blue)
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Desactiva WiFi completamente")
                                    .font(.headline)
                                Text("Settings → WiFi → OFF (usará Bluetooth puro)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)

                    // Technical Details Section
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Detalles Técnicos", systemImage: "wrench.and.screwdriver.fill")
                            .font(.title2)
                            .foregroundColor(.gray)

                        Text("MultipeerConnectivity usa dos modos de transporte:")
                            .font(.body)
                            .fontWeight(.semibold)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "wifi")
                                Text("WiFi Direct/Infrastructure")
                                    .font(.caption)
                            }
                            Text("Requiere WiFi conectado a una red o WiFi Direct activo")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.leading, 24)

                            Divider()

                            HStack(spacing: 8) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                Text("Bluetooth")
                                    .font(.caption)
                            }
                            Text("Funciona sin WiFi, pero requiere que WiFi esté desactivado para ser usado")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.leading, 24)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("Ayuda de Configuración")
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
}

#Preview {
    NetworkConfigurationWarningBanner(networkManager: NetworkManager())
}
