//
//  SOSView.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  SOS Emergency System for Stadium Events
//

import SwiftUI

struct SOSView: View {
    @EnvironmentObject var networkManager: NetworkManager
    @State private var selectedSOSType: SOSType?
    @State private var showSOSConfirmation = false
    @State private var isSOSActive = false
    @State private var additionalMessage = ""

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                headerView

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 32) {
                        // Emergency header info
                        emergencyHeader

                        // SOS Type Grid
                        sosTypeGrid

                        // Extra spacing for bottom nav
                        Color.clear.frame(height: 100)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                }

                Spacer()
            }
            .background(Color.appBackgroundDark.ignoresSafeArea())
            .sheet(item: $selectedSOSType) { sosType in
                SOSConfirmationView(
                    sosType: sosType,
                    networkManager: networkManager,
                    onConfirm: { message in
                        sendSOSAlert(type: sosType, message: message)
                    }
                )
            }
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sistema de Emergencias")
                    .font(.headline)
                    .fontWeight(.semibold)
                Text("Selecciona el tipo de ayuda que necesitas")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Connection status
            HStack(spacing: 6) {
                Circle()
                    .fill(networkManager.connectedPeers.isEmpty ? Color.orange : Color.appAccent)
                    .frame(width: 8, height: 8)
                Text("\(networkManager.connectedPeers.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.95))
    }

    // MARK: - Emergency Header
    private var emergencyHeader: some View {
        EmptyView()
    }

    // MARK: - SOS Type Grid
    private var sosTypeGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("¿Qué tipo de ayuda necesitas?")
                .font(.headline)
                .fontWeight(.semibold)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                ForEach(SOSType.allCases) { sosType in
                    SOSTypeCard(sosType: sosType) {
                        selectedSOSType = sosType
                    }
                }
            }
        }
    }

    // MARK: - Actions
    private func sendSOSAlert(type: SOSType, message: String?) {
        // Haptic feedback based on SOS type
        let hapticPattern: HapticPatternType = {
            switch type {
            case .emergenciaMedica:
                return .sosEmergency
            case .seguridad:
                return .sosSecurity
            case .perdido:
                return .sosLostChild
            case .asistencia:
                return .sosEmergency
            }
        }()

        HapticManager.shared.playPattern(hapticPattern, priority: .emergency)

        // Create SOS alert
        let alert = SOSAlert(
            type: type,
            senderID: networkManager.localDeviceName,
            senderName: networkManager.localDeviceName,
            location: nil, // TODO: Get current location
            message: message
        )

        // TODO: Send via network
        print("🆘 SOS Alert sent: \(type.rawValue)")

        isSOSActive = true

        // Auto-dismiss after showing
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isSOSActive = false
        }
    }
}

// MARK: - SOS Type Card
struct SOSTypeCard: View {
    let sosType: SOSType
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            // Haptic feedback on tap
            HapticManager.shared.play(.heavy, priority: .ui)
            action()
        }) {
            VStack(spacing: 16) {
                // Icon container
                ZStack {
                    Circle()
                        .fill(sosType.color.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: sosType.icon)
                        .font(.system(size: 26))
                        .foregroundColor(sosType.color)
                }

                // Title
                Text(sosType.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(sosType.color.opacity(0.2), lineWidth: 2)
            )
            .shadow(color: Color.black.opacity(isPressed ? 0.05 : 0.08), radius: isPressed ? 4 : 12, x: 0, y: isPressed ? 2 : 6)
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
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
    }
}

// MARK: - SOS Confirmation View
struct SOSConfirmationView: View {
    @Environment(\.dismiss) var dismiss
    let sosType: SOSType
    @ObservedObject var networkManager: NetworkManager
    let onConfirm: (String?) -> Void

    @State private var additionalMessage = ""
    @State private var isProcessing = false
    @FocusState private var isTextEditorFocused: Bool

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    // Icon header
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(sosType.color.opacity(0.15))
                                .frame(width: 80, height: 80)

                            Image(systemName: sosType.icon)
                                .font(.system(size: 36))
                                .foregroundColor(sosType.color)
                        }

                        VStack(spacing: 6) {
                            Text(sosType.rawValue)
                                .font(.title2)
                                .fontWeight(.bold)

                            Text(sosType.description)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, 24)

                    // Info cards
                    VStack(spacing: 12) {
                        // Network status card
                        HStack(spacing: 12) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.title3)
                                .foregroundColor(sosType.color)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Dispositivos conectados")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("\(networkManager.connectedPeers.count) dispositivos recibirán la alerta")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                        )

                        // Location card
                        HStack(spacing: 12) {
                            Image(systemName: "location.fill")
                                .font(.title3)
                                .foregroundColor(sosType.color)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ubicación compartida")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("Tu posición será enviada automáticamente")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                        )
                    }

                    // Additional message
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Mensaje adicional (opcional)")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        ZStack(alignment: .topLeading) {
                            if additionalMessage.isEmpty {
                                Text("Describe tu situación...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary.opacity(0.5))
                                    .padding(.top, 8)
                                    .padding(.leading, 12)
                            }

                            TextEditor(text: $additionalMessage)
                                .font(.subheadline)
                                .frame(height: 100)
                                .padding(8)
                                .focused($isTextEditorFocused)
                                .scrollContentBackground(.hidden)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.gray.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isTextEditorFocused ? sosType.color.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
                        )
                    }

                    Spacer(minLength: 20)

                    // Confirm button
                    Button(action: confirmSOS) {
                        HStack(spacing: 10) {
                            if isProcessing {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.body)
                            }
                            Text(isProcessing ? "Enviando..." : "Enviar Alerta")
                                .fontWeight(.semibold)
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(sosType.color)
                        )
                        .shadow(color: sosType.color.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .disabled(isProcessing)
                    .buttonStyle(.plain)
                    .padding(.bottom, 32)
                }
                .padding(.horizontal, 20)
            }
            .background(Color.appBackgroundDark.ignoresSafeArea())
            .navigationTitle("Confirmar Solicitud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .foregroundColor(sosType.color)
                }
            }
        }
    }

    private func confirmSOS() {
        isProcessing = true
        isTextEditorFocused = false

        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            onConfirm(additionalMessage.isEmpty ? nil : additionalMessage)
            isProcessing = false
            dismiss()
        }
    }
}

// MARK: - Preview
#Preview {
    SOSView()
        .environmentObject(NetworkManager())
}
