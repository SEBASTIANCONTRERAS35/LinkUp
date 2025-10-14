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
    @State private var showSimulationControl = false
    @StateObject private var mockGroupsManager = MockFamilyGroupsManager.shared

    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                Spacer()

                // Icon
                Image(systemName: "person.3.fill")
                    .font(.system(size: 100))
                    .foregroundColor(Color.appPrimary.opacity(0.3)) // ✅ Violeta moderno

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

                // Hidden tap area to access simulation (triple tap)
                Color.clear
                    .frame(height: 60)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 3) {
                        showSimulationControl = true
                    }

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
                                .fill(Color.appPrimary) // ✅ Violeta moderno
                        )
                        .shadow(color: Color.appPrimary.opacity(0.3), radius: 8, x: 0, y: 4)
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
                        .foregroundColor(Color.appPrimary) // ✅ Violeta moderno
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.appPrimary.opacity(0.1)) // ✅ Violeta moderno
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.appPrimary, lineWidth: 2) // ✅ Violeta moderno
                        )
                    }
                    .buttonStyle(.plain)

                    // Hidden simulation button (for testing - triple tap to reveal)
                    // This is invisible to users but accessible for demos
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
            .background(Color.appBackgroundDark.ignoresSafeArea()) // ✅ Fondo oscuro moderno
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") {
                        dismiss()
                    }
                    .foregroundColor(Color.appPrimary) // ✅ Violeta moderno
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
            .sheet(isPresented: $showSimulationControl) {
                SimulationControlPanelView()
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
