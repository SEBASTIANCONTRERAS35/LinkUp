//
//  FamilyGroupEmptyStateView.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Empty state for family groups with create/join options
//

import SwiftUI

struct FamilyGroupEmptyStateView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var familyGroupManager: FamilyGroupManager
    let localPeerID: String
    @EnvironmentObject var networkManager: NetworkManager

    @State private var showCreateGroup = false
    @State private var showJoinGroup = false

    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                Spacer()

                // Icon
                Image(systemName: "person.3.fill")
                    .font(.system(size: 100))
                    .foregroundColor(Mundial2026Colors.azul.opacity(0.3))

                // Title and subtitle
                VStack(spacing: 12) {
                    Text("Grupo Familiar")
                        .font(.system(size: 28, weight: .bold))

                    Text("No tienes un grupo familiar")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("Crea o únete a un grupo para encontrar a\ntu familia fácilmente en el estadio")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                // Action buttons
                VStack(spacing: 16) {
                    // Create new group button
                    Button(action: { showCreateGroup = true }) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                            Text("Crear nuevo grupo")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Mundial2026Colors.azul)
                        )
                        .shadow(color: Mundial2026Colors.azul.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)

                    // Join group button
                    Button(action: { showJoinGroup = true }) {
                        HStack(spacing: 10) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.title3)
                            Text("Unirme a un grupo")
                                .font(.headline)
                        }
                        .foregroundColor(Mundial2026Colors.azul)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Mundial2026Colors.azul.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Mundial2026Colors.azul, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
            .background(Mundial2026Colors.background.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") {
                        dismiss()
                    }
                    .foregroundColor(Mundial2026Colors.azul)
                }
            }
            .sheet(isPresented: $showCreateGroup) {
                CreateFamilyGroupView(
                    familyGroupManager: familyGroupManager,
                    localPeerID: localPeerID
                )
            }
            .sheet(isPresented: $showJoinGroup) {
                JoinFamilyGroupView(
                    familyGroupManager: familyGroupManager,
                    localPeerID: localPeerID
                )
                .environmentObject(networkManager)
            }
        }
    }
}

// MARK: - Preview
#Preview {
    FamilyGroupEmptyStateView(
        familyGroupManager: FamilyGroupManager(),
        localPeerID: "test-device"
    )
    .environmentObject(NetworkManager())
}
