//
//  LinkFenceDetailView.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Detail view for a specific linkfence with stats and event history
//

import SwiftUI
import MapKit

struct LinkFenceDetailView: View {
    let linkfence: CustomLinkFence
    @ObservedObject var linkfenceManager: LinkFenceManager

    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme
    @Environment(\.dismiss) var dismiss
    @State private var showDeleteAlert = false
    @State private var region: MKCoordinateRegion

    init(linkfence: CustomLinkFence, linkfenceManager: LinkFenceManager) {
        self.linkfence = linkfence
        self.linkfenceManager = linkfenceManager

        // Initialize map region
        _region = State(initialValue: MKCoordinateRegion(
            center: linkfence.center,
            latitudinalMeters: linkfence.radius * 3,
            longitudinalMeters: linkfence.radius * 3
        ))
    }

    private var stats: LinkFenceStats? {
        linkfenceManager.getStatistics(for: linkfence.id)
    }

    private var events: [LinkFenceEventMessage] {
        linkfenceManager.getEvents(for: linkfence.id)
    }

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Hero section
                    heroSection

                    // Statistics grid
                    if let stats = stats {
                        statisticsGrid(stats: stats)
                    }

                    // Map preview
                    mapPreview

                    // Events timeline
                    eventsSection

                    // Actions
                    actionsSection

                    // Bottom spacing
                    Color.clear.frame(height: 50)
                }
                .padding(.horizontal, 20)
            }
            .background(accessibleTheme.background.ignoresSafeArea())
            .navigationTitle(linkfence.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") {
                        dismiss()
                    }
                    .accessibleButton()
                }
            }
            .alert("Eliminar Lugar", isPresented: $showDeleteAlert) {
                Button("Cancelar", role: .cancel) {}
                Button("Eliminar", role: .destructive) {
                    linkfenceManager.removeGeofence(linkfence.id)
                    dismiss()
                }
            } message: {
                Text("¿Estás seguro de que deseas eliminar '\(linkfence.name)'? Esta acción no se puede deshacer.")
            }
        }
    }

    // MARK: - Hero Section
    private var heroSection: some View {
        VStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(linkfence.color.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: linkfence.category.icon)
                    .font(.system(size: 36))
                    .foregroundColor(linkfence.color)
            }

            // Name
            Text(linkfence.name)
                .font(.title2)
                .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
                .foregroundColor(accessibleTheme.textPrimary)
                .accessibleText()

            // Category & Status
            HStack(spacing: 12) {
                // Category badge
                HStack(spacing: 6) {
                    Image(systemName: linkfence.category.icon)
                        .font(.caption)
                    Text(linkfence.category.rawValue)
                        .font(.caption)
                        .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
                }
                .foregroundColor(linkfence.color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .accessibleBackground(linkfence.color, opacity: 0.1)
                .cornerRadius(12)

                // Status badge
                if let stats = stats {
                    StatusBadge(isInside: stats.currentlyInside)
                }
            }

            // Monitoring toggle
            Toggle(isOn: Binding(
                get: { linkfence.isMonitoring },
                set: { _ in
                    linkfenceManager.toggleMonitoring(for: linkfence.id)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            )) {
                Label("Monitorear este lugar", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.subheadline)
                    .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
            }
            .tint(linkfence.color)
            .padding()
            .accessibleBackground(accessibleTheme.cardBackground, opacity: 1.0)
            .cornerRadius(12)
        }
        .padding(.top, 20)
    }

    // MARK: - Statistics Grid
    private func statisticsGrid(stats: LinkFenceStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Estadísticas")
                .font(.headline)
                .foregroundColor(accessibleTheme.textPrimary)
                .accessibleText()

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                LinkFenceStatCard(
                    icon: "arrow.right.circle.fill",
                    value: "\(stats.totalVisits)",
                    label: "Visitas",
                    color: accessibleTheme.primaryGreen
                )

                LinkFenceStatCard(
                    icon: "clock.fill",
                    value: stats.formattedTotalTime,
                    label: "Tiempo Total",
                    color: accessibleTheme.primaryBlue
                )

                LinkFenceStatCard(
                    icon: "calendar",
                    value: stats.timeSinceLastEntry ?? "Nunca",
                    label: "Última Entrada",
                    color: accessibleTheme.primaryRed
                )

                LinkFenceStatCard(
                    icon: "hourglass",
                    value: stats.formattedAverageDuration,
                    label: "Prom. Estancia",
                    color: .orange
                )
            }
        }
    }

    // MARK: - Map Preview
    private var mapPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ubicación")
                .font(.headline)
                .foregroundColor(accessibleTheme.textPrimary)
                .accessibleText()

            ZStack {
                // Map
                Map(coordinateRegion: .constant(region), annotationItems: [linkfence]) { fence in
                    MapAnnotation(coordinate: fence.center) {
                        ZStack {
                            Circle()
                                .fill(fence.color.opacity(0.2))
                                .frame(width: 40, height: 40)

                            Circle()
                                .stroke(fence.color, lineWidth: 2)
                                .frame(width: 40, height: 40)

                            Image(systemName: fence.category.icon)
                                .font(.system(size: 16))
                                .foregroundColor(fence.color)
                        }
                    }
                }
                .frame(height: 200)
                .cornerRadius(16)
                .disabled(true)  // Prevent interaction

                // Radius overlay text
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("Radio: \(Int(linkfence.radius))m")
                            .font(.caption)
                            .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                            .padding(12)
                    }
                }
            }
        }
    }

    // MARK: - Events Section
    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Historial de Eventos")
                    .font(.headline)
                    .foregroundColor(accessibleTheme.textPrimary)
                    .accessibleText()

                Spacer()

                if !events.isEmpty {
                    Text("\(events.count) eventos")
                        .font(.caption)
                        .foregroundColor(accessibleTheme.textSecondary)
                        .accessibleText()
                }
            }

            LinkFenceEventTimeline(events: events)
        }
    }

    // MARK: - Actions Section
    private var actionsSection: some View {
        VStack(spacing: 12) {
            // Delete button
            Button(action: { showDeleteAlert = true }) {
                Label("Eliminar Lugar", systemImage: "trash.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(accessibleTheme.primaryRed)
                    .cornerRadius(14)
            }
            .accessibleButton()
        }
    }
}

// MARK: - Preview
#Preview {
    LinkFenceDetailView(
        linkfence: MockLinkFenceData.mockLinkFences[0],
        linkfenceManager: {
            let manager = LinkFenceManager(
                locationService: LocationService(),
                familyGroupManager: FamilyGroupManager()
            )
            manager.loadMockData()
            return manager
        }()
    )
}
