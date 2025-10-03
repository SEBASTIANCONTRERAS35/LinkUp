//
//  UserDisplayNameSettingsView.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  User display name configuration UI
//

import SwiftUI

struct UserDisplayNameSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var displayNameManager = UserDisplayNameManager.shared
    @EnvironmentObject var networkManager: NetworkManager

    @State private var publicName: String = ""
    @State private var familyName: String = ""
    @State private var useDeviceName: Bool = true
    @State private var showingSaveConfirmation: Bool = false

    var body: some View {
        NavigationView {
            Form {
                // Preview Section
                previewSection

                // Public Name Section
                publicNameSection

                // Family Name Section
                familyNameSection

                // Info Section
                infoSection
            }
            .navigationTitle("Nombre de Usuario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Guardar") {
                        saveSettings()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                loadCurrentSettings()
            }
            .alert("Configuración Guardada", isPresented: $showingSaveConfirmation) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Tus nombres se han actualizado correctamente")
            }
        }
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vista Previa")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(getEffectivePublicName())
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(.orange)
                        Text("Usuarios desconocidos verán:")
                            .font(.caption)
                        Spacer()
                    }
                    Text(getEffectivePublicName())
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.leading, 24)

                    HStack {
                        Image(systemName: "person.3.fill")
                            .foregroundColor(.green)
                        Text("Tu familia verá:")
                            .font(.caption)
                        Spacer()
                    }
                    Text(getEffectiveFamilyName())
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.leading, 24)
                }
                .padding(.vertical, 4)
            }
            .padding(.vertical, 8)
        } header: {
            Label("Cómo te verán los demás", systemImage: "eye")
        }
    }

    // MARK: - Public Name Section

    private var publicNameSection: some View {
        Section {
            Toggle(isOn: $useDeviceName) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Usar nombre del dispositivo")
                        .font(.body)
                    Text(networkManager.localDeviceName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if !useDeviceName {
                TextField("Nombre público", text: $publicName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Campo de nombre público")
                    .accessibilityHint("Ingresa el nombre que verán los usuarios desconocidos")
            }
        } header: {
            Label("Nombre Público", systemImage: "antenna.radiowaves.left.and.right")
        } footer: {
            Text("Este nombre lo verán todos los usuarios de la LinkMesh, incluidos desconocidos.")
                .font(.caption)
        }
    }

    // MARK: - Family Name Section

    private var familyNameSection: some View {
        Section {
            TextField("Nombre para familia", text: $familyName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .accessibilityLabel("Campo de nombre familiar")
                .accessibilityHint("Ingresa el nombre que verán tus familiares")

            if !familyName.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Configurado: \"\(familyName)\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        } header: {
            Label("Nombre para Conocidos", systemImage: "person.3.fill")
        } footer: {
            Text("Un nombre más personal para tus grupos familiares. Si está vacío, se usará tu nombre público.")
                .font(.caption)
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                InfoRow(
                    icon: "shield.fill",
                    iconColor: .blue,
                    title: "Privacidad",
                    description: "Usa nombres diferentes para proteger tu identidad en redes públicas"
                )

                Divider()

                InfoRow(
                    icon: "person.2.fill",
                    iconColor: .green,
                    title: "Contexto Inteligente",
                    description: "La app detecta automáticamente si estás en tu grupo familiar o con desconocidos"
                )

                Divider()

                InfoRow(
                    icon: "arrow.clockwise",
                    iconColor: .orange,
                    title: "Cambios en Tiempo Real",
                    description: "Los cambios se aplicarán inmediatamente en toda la app"
                )
            }
            .padding(.vertical, 4)
        } header: {
            Label("Información", systemImage: "info.circle")
        }
    }

    // MARK: - Helper Views

    struct InfoRow: View {
        let icon: String
        let iconColor: Color
        let title: String
        let description: String

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(iconColor)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func loadCurrentSettings() {
        publicName = displayNameManager.settings.publicName
        familyName = displayNameManager.settings.familyName
        useDeviceName = displayNameManager.settings.useDeviceNameAsPublic
    }

    private func saveSettings() {
        displayNameManager.updatePublicName(publicName)
        displayNameManager.updateFamilyName(familyName)
        displayNameManager.updateUseDeviceNameAsPublic(useDeviceName)

        showingSaveConfirmation = true
    }

    private func getEffectivePublicName() -> String {
        if useDeviceName || publicName.trimmingCharacters(in: .whitespaces).isEmpty {
            return networkManager.localDeviceName
        }
        return publicName
    }

    private func getEffectiveFamilyName() -> String {
        let trimmedFamily = familyName.trimmingCharacters(in: .whitespaces)
        if !trimmedFamily.isEmpty {
            return trimmedFamily
        }
        return getEffectivePublicName()
    }
}

// MARK: - Preview

#Preview {
    UserDisplayNameSettingsView()
        .environmentObject(NetworkManager())
}
