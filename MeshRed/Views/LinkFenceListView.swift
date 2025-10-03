//
//  LinkFenceListView.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Main view for managing multiple linkfences with selection
//

import SwiftUI

struct LinkFenceListView: View {
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme
    @Environment(\.dismiss) var dismiss
    @ObservedObject var linkfenceManager: LinkFenceManager
    @ObservedObject var locationService: LocationService

    @State private var searchText = ""
    @State private var showCreateGeofence = false
    @State private var selectedGeofence: CustomLinkFence?
    @State private var showAlert = false
    @State private var alertMessage = ""

    var body: some View {
        NavigationView {
            ZStack {
                accessibleTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header with active count badge
                    headerView

                    // Search bar
                    searchBar

                    // Geofences list
                    if filteredGeofences.isEmpty {
                        emptyStateView
                    } else {
                        linkfencesList
                    }
                }
            }
            .navigationTitle("Mis Lugares")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") {
                        dismiss()
                    }
                    .accessibleButton()
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showCreateGeofence = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(accessibleTheme.primaryGreen)
                    }
                    .accessibleButton()
                }
            }
            .sheet(isPresented: $showCreateGeofence) {
                LinkFenceCreatorView(
                    linkfenceManager: linkfenceManager,
                    locationService: locationService
                )
            }
            .sheet(item: $selectedGeofence) { linkfence in
                LinkFenceDetailView(
                    linkfence: linkfence,
                    linkfenceManager: linkfenceManager
                )
            }
            .alert("Límite Alcanzado", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
        .onAppear {
            // Always load mock data for demo
            linkfenceManager.loadMockData()
        }
    }

    // MARK: - Header View
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(linkfenceManager.myGeofences.count) lugares")
                    .font(.subheadline)
                    .foregroundColor(accessibleTheme.textSecondary)
                    .accessibleText()
            }

            Spacer()

            ActiveLinkFencesBadge(
                activeCount: linkfenceManager.activeGeofences.count
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .accessibleBackground(accessibleTheme.cardBackground)
    }

    // MARK: - Search Bar
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Buscar lugares...", text: $searchText)
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .accessibleBackground(accessibleTheme.cardBackground, opacity: 1.0)
        .cornerRadius(12)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Geofences List
    private var linkfencesList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 12) {
                ForEach(filteredGeofences) { linkfence in
                    LinkFenceRow(
                        linkfence: linkfence,
                        stats: linkfenceManager.getStatistics(for: linkfence.id),
                        isMonitoring: linkfence.isMonitoring,
                        onToggleMonitoring: {
                            handleToggleMonitoring(for: linkfence)
                        },
                        onTap: {
                            selectedGeofence = linkfence
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)  // Extra space for bottom nav
        }
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "map.circle")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("No hay lugares guardados")
                .font(.title3)
                .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
                .foregroundColor(accessibleTheme.textPrimary)
                .accessibleText()

            Text("Crea un linkfence para empezar a monitorear tus lugares favoritos")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .accessibleText()

            // Hidden tap area to load mock data (triple tap)
            Color.clear
                .frame(height: 60)
                .contentShape(Rectangle())
                .onTapGesture(count: 3) {
                    linkfenceManager.loadMockData()
                }

            Button(action: { showCreateGeofence = true }) {
                Label("Crear Lugar", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(accessibleTheme.primaryGreen)
                    .cornerRadius(14)
            }
            .accessibleButton()
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Computed Properties
    private var filteredGeofences: [CustomLinkFence] {
        if searchText.isEmpty {
            return linkfenceManager.myGeofences
        } else {
            return linkfenceManager.myGeofences.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    // MARK: - Helper Methods
    private func handleToggleMonitoring(for linkfence: CustomLinkFence) {
        // Check if trying to activate and already at limit
        if !linkfence.isMonitoring && linkfenceManager.activeGeofences.count >= LinkFenceManager.maxMonitoredGeofences {
            alertMessage = "Has alcanzado el límite de \(LinkFenceManager.maxMonitoredGeofences) lugares activos. Desactiva otro lugar primero."
            showAlert = true
            return
        }

        // Haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Toggle monitoring
        linkfenceManager.toggleMonitoring(for: linkfence.id)
    }
}

// MARK: - Preview
#Preview {
    LinkFenceListView(
        linkfenceManager: {
            let manager = LinkFenceManager(
                locationService: LocationService(),
                familyGroupManager: FamilyGroupManager()
            )
            manager.loadMockData()
            return manager
        }(),
        locationService: LocationService()
    )
}
