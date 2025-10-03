//
//  JoinFamilyGroupView.swift
//  MeshRed
//
//  Created by Claude for StadiumConnect Pro
//

import SwiftUI

struct JoinFamilyGroupView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var networkManager: NetworkManager
    @ObservedObject var familyGroupManager: FamilyGroupManager
    let localPeerID: String

    @State private var groupCode = ""
    @State private var nickname = ""
    @State private var relationshipTag = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @StateObject private var displayNameManager = UserDisplayNameManager.shared

    // Validation states
    @State private var validationState: ValidationState = .idle
    @State private var foundGroupInfo: FamilyGroupInfoMessage?
    @State private var requestTimeoutTimer: Timer?

    enum ValidationState: Equatable {
        case idle
        case validating
        case foundInNetwork(groupName: String, memberCount: Int)
        case notFoundInNetwork
        case joined
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Código del grupo (ej: FAM-A7B2C)", text: $groupCode)
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        #endif
                        .onChange(of: groupCode) { _ in
                            // Reset validation when code changes
                            validationState = .idle
                            foundGroupInfo = nil
                        }

                    // Validation feedback
                    validationStatusView
                } header: {
                    Text("Código del grupo")
                } footer: {
                    Text("Ingresa el código compartido por tu familia. Lo verificaremos con dispositivos conectados.")
                }

                // Mostrar info del grupo si se encontró
                if case .foundInNetwork(let name, let count) = validationState {
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(name)
                                    .font(.headline)
                                Text("\(count) miembros")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title3)
                        }
                    } header: {
                        Text("Grupo encontrado")
                    }
                }

                Section {
                    TextField("Tu apodo (opcional)", text: $nickname)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif

                    TextField("Relación (ej: Mamá, Papá, Hijo)", text: $relationshipTag)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                } header: {
                    Text("Tu información")
                } footer: {
                    Text("Ayuda a tu familia a identificarte.")
                }

                Section {
                    // Botón de verificación
                    if validationState == .idle || validationState == .notFoundInNetwork {
                        Button(action: verifyCode) {
                            HStack {
                                Spacer()
                                if validationState == .validating {
                                    ProgressView()
                                        .padding(.trailing, 8)
                                }
                                Text(validationState == .validating ? "Buscando..." : "Verificar código")
                                    .font(.headline)
                                Spacer()
                            }
                        }
                        .disabled(!isValidCode || validationState == .validating || networkManager.connectedPeers.isEmpty)
                    }

                    // Botón de unirse (solo si encontrado)
                    if case .foundInNetwork = validationState {
                        Button(action: joinGroup) {
                            HStack {
                                Spacer()
                                Text("Unirme al grupo")
                                    .font(.headline)
                                Spacer()
                            }
                        }
                    }
                } footer: {
                    if networkManager.connectedPeers.isEmpty {
                        Text("⚠️ No hay dispositivos conectados. Conéctate a alguien primero.")
                            .foregroundColor(.orange)
                    } else if validationState == .idle {
                        Text("Conectado a \(networkManager.connectedPeers.count) dispositivo(s). Presiona 'Verificar código' para buscar el grupo.")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Unirse a Grupo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FamilyGroupInfoReceived"))) { notification in
                handleGroupInfoReceived(notification)
            }
            .onAppear {
                // Pre-fill nickname with family name from settings
                if nickname.isEmpty {
                    let deviceName = ProcessInfo.processInfo.hostName
                    nickname = displayNameManager.getCurrentFamilyName(deviceName: deviceName)
                }
            }
            .onDisappear {
                requestTimeoutTimer?.invalidate()
            }
        }
    }

    // MARK: - Validation Status View

    @ViewBuilder
    private var validationStatusView: some View {
        switch validationState {
        case .idle:
            EmptyView()

        case .validating:
            HStack {
                ProgressView()
                    .scaleEffect(0.9)
                Text("Buscando en dispositivos conectados...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

        case .foundInNetwork(let name, let count):
            Label {
                Text("Grupo '\(name)' encontrado con \(count) miembros")
                    .font(.caption)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .foregroundColor(.green)

        case .notFoundInNetwork:
            Label {
                Text("Código no encontrado en dispositivos conectados")
                    .font(.caption)
            } icon: {
                Image(systemName: "xmark.circle.fill")
            }
            .foregroundColor(.red)

        case .joined:
            Label {
                Text("Unido exitosamente")
                    .font(.caption)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .foregroundColor(.green)
        }
    }

    // MARK: - Validation

    private var isValidCode: Bool {
        let normalized = groupCode.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return FamilyGroupCode(rawCode: normalized) != nil
    }

    // MARK: - Actions

    private func verifyCode() {
        let normalized = groupCode.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)

        guard let code = FamilyGroupCode(rawCode: normalized) else {
            errorMessage = "Código inválido. Verifica el formato: FAM-XXXXX"
            showError = true
            return
        }

        guard !networkManager.connectedPeers.isEmpty else {
            errorMessage = "No hay dispositivos conectados. Conéctate primero a alguien."
            showError = true
            return
        }

        // Set validating state
        validationState = .validating
        foundGroupInfo = nil

        // Create member info
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRelation = relationshipTag.trimmingCharacters(in: .whitespacesAndNewlines)
        let memberInfo = FamilySyncMessage.FamilyMemberInfo(
            nickname: trimmedNickname.isEmpty ? nil : trimmedNickname,
            relationshipTag: trimmedRelation.isEmpty ? nil : trimmedRelation
        )

        // Send request to network
        networkManager.requestFamilyGroupInfo(
            code: code,
            requesterId: localPeerID,
            memberInfo: memberInfo
        )

        // Set timeout (5 seconds)
        requestTimeoutTimer?.invalidate()
        requestTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            if case .validating = validationState {
                validationState = .notFoundInNetwork
                print("⏱️ Family group verification timeout - code not found")
            }
        }
    }

    private func handleGroupInfoReceived(_ notification: Notification) {
        guard let groupInfo = notification.userInfo?["groupInfo"] as? FamilyGroupInfoMessage else {
            return
        }

        // Check if this response is for our code
        let normalized = groupCode.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let currentCode = FamilyGroupCode(rawCode: normalized),
              groupInfo.groupCode == currentCode else {
            return
        }

        // Cancel timeout
        requestTimeoutTimer?.invalidate()

        // Update state
        foundGroupInfo = groupInfo
        validationState = .foundInNetwork(
            groupName: groupInfo.groupName,
            memberCount: groupInfo.memberCount
        )

        print("✅ Group info received and displayed in UI")
    }

    private func joinGroup() {
        guard let groupInfo = foundGroupInfo else {
            errorMessage = "No se encontró información del grupo"
            showError = true
            return
        }

        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRelation = relationshipTag.trimmingCharacters(in: .whitespacesAndNewlines)

        familyGroupManager.joinGroupWithFullInfo(
            code: groupInfo.groupCode,
            groupName: groupInfo.groupName,
            creatorPeerID: groupInfo.creatorPeerID,
            members: groupInfo.members,
            currentPeerID: localPeerID,
            currentNickname: trimmedNickname.isEmpty ? nil : trimmedNickname,
            currentRelationshipTag: trimmedRelation.isEmpty ? nil : trimmedRelation
        )

        validationState = .joined

        // Dismiss after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            dismiss()
        }
    }
}
