//
//  CreateFamilyGroupView.swift
//  MeshRed
//
//  Created by Claude for StadiumConnect Pro
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct CreateFamilyGroupView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var familyGroupManager: FamilyGroupManager
    let localPeerID: String

    @State private var groupName = ""
    @State private var nickname = ""
    @State private var showQRCode = false
    @State private var createdGroup: FamilyGroup?
    @StateObject private var displayNameManager = UserDisplayNameManager.shared

    var body: some View {
        NavigationView {
            if showQRCode, let group = createdGroup {
                qrCodeView(for: group)
            } else {
                createGroupForm
            }
        }
        .onAppear {
            // Pre-fill nickname with family name from settings
            if nickname.isEmpty {
                let deviceName = ProcessInfo.processInfo.hostName
                nickname = displayNameManager.getCurrentFamilyName(deviceName: deviceName)
            }
        }
    }

    // MARK: - Create Group Form

    private var createGroupForm: some View {
        Form {
            Section {
                TextField("Nombre del grupo (ej: Familia Contreras)", text: $groupName)
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif

                TextField("Tu apodo (opcional)", text: $nickname)
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif
            } header: {
                Text("Información del grupo")
            } footer: {
                Text("El nombre del grupo te ayudará a identificarlo. Tu apodo es opcional y solo se verá dentro de tu familia.")
            }

            Section {
                Button(action: createGroup) {
                    HStack {
                        Spacer()
                        Text("Crear grupo familiar")
                            .font(.headline)
                        Spacer()
                    }
                }
                .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Crear Grupo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") {
                    dismiss()
                }
            }
        }
    }

    // MARK: - QR Code View

    private func qrCodeView(for group: FamilyGroup) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.green)

                    Text("¡Grupo creado!")
                        .font(.title.bold())

                    Text(group.name)
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 32)

                // QR Code
                VStack(spacing: 16) {
                    if let qrImage = generateQRCode(from: group.code.qrCodeData) {
                        #if os(iOS)
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 250, height: 250)
                            .padding()
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: .black.opacity(0.1), radius: 10)
                        #elseif os(macOS)
                        Image(nsImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 250, height: 250)
                            .padding()
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: .black.opacity(0.1), radius: 10)
                        #endif
                    }

                    VStack(spacing: 8) {
                        Text("Código del grupo")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(group.code.displayCode)
                            .font(.system(.title2, design: .monospaced).bold())
                            .foregroundColor(.blue)
                    }
                }

                VStack(spacing: 12) {
                    Text("Comparte este código con tu familia")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button(action: shareGroup) {
                        Label("Compartir código", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 32)
                }

                Button(action: { dismiss() }) {
                    Text("Listo")
                        .font(.subheadline.bold())
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Grupo Creado")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Actions

    private func createGroup() {
        let trimmedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)

        familyGroupManager.createGroup(
            name: trimmedName,
            creatorPeerID: localPeerID,
            creatorNickname: trimmedNickname.isEmpty ? nil : trimmedNickname
        )

        createdGroup = familyGroupManager.currentGroup
        withAnimation {
            showQRCode = true
        }
    }

    private func shareGroup() {
        guard let group = createdGroup else { return }

        let shareText = """
        ¡Únete a mi grupo familiar en StadiumConnect!

        Grupo: \(group.name)
        Código: \(group.code.displayCode)

        Escanea el QR o ingresa el código en la app para unirte.
        """

        #if os(iOS)
        let activityVC = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true)
        }
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(shareText, forType: .string)
        #endif
    }

    // MARK: - QR Code Generation

    private func generateQRCode(from string: String) -> PlatformImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else { return nil }

        // Scale up for better quality
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = ciImage.transformed(by: transform)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        #if os(iOS)
        return UIImage(cgImage: cgImage)
        #elseif os(macOS)
        return NSImage(cgImage: cgImage, size: NSSize(width: scaledImage.extent.width, height: scaledImage.extent.height))
        #endif
    }
}

// MARK: - Platform Image

#if os(iOS)
typealias PlatformImage = UIImage
#elseif os(macOS)
typealias PlatformImage = NSImage
#endif
