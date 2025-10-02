//
//  StadiumDashboardView.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//

import SwiftUI

struct StadiumDashboardView: View {
    // MARK: - State
    @State private var showSettings = false
    @State private var selectedTab: DashboardTab = .home

    // MARK: - Mock Data (will be replaced with real data)
    @State private var stadiumName = "Estadio Azteca"
    @State private var sectionNumber = "Sección 4B"
    @State private var homeTeam = "MÉXICO"
    @State private var awayTeam = "CANADÁ"
    @State private var homeScore = 0
    @State private var awayScore = 0
    @State private var matchMinute = 78

    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                // Header
                headerView

                // Scrollable content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Match score card
                        matchScoreCard

                        // Feature grid (2x2)
                        featureGrid

                        // Extra spacing for bottom nav
                        Color.clear.frame(height: 150)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }

                Spacer()
            }

            // Bottom navigation overlay
            VStack {
                Spacer()
                bottomNavigationBar
            }
        }
        .background(appBackgroundColor.ignoresSafeArea())
        .sheet(isPresented: $showSettings) {
            SettingsPlaceholderView()
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(stadiumName)
                    .font(.headline)
                    .fontWeight(.semibold)
                Text(sectionNumber)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.95))
    }

    // MARK: - Match Score Card
    private var matchScoreCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                // Home team
                VStack(spacing: 12) {
                    Text("🇲🇽")
                        .font(.system(size: 48))
                    Text(homeTeam)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)

                // Score
                HStack(spacing: 12) {
                    Text("\(homeScore)")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)

                    Text("-")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))

                    Text("\(awayScore)")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                }

                // Away team
                VStack(spacing: 12) {
                    Text("🇨🇦")
                        .font(.system(size: 48))
                    Text(awayTeam)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
            }

            // Match time
            Text("\(matchMinute) Min")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.2))
                .clipShape(Capsule())
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.blue, Color.blue.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.blue.opacity(0.3), radius: 12, x: 0, y: 6)
    }

    // MARK: - Feature Grid
    private var featureGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ], spacing: 16) {
            // Tu Red
            FeatureCard(
                title: "Tu red",
                icon: "person.3.fill",
                iconColor: .blue,
                backgroundColor: Color(red: 0.9, green: 0.95, blue: 1.0)
            ) {
                // Action for network
                print("Tu red tapped")
            }

          

            // Ubicaciones
            FeatureCard(
                title: "Ubicaciones",
                icon: "mappin.and.ellipse",
                iconColor: .blue,
                backgroundColor: Color(red: 0.9, green: 0.95, blue: 1.0)
            ) {
                print("Ubicaciones tapped")
            }

            // Perimetros
            FeatureCard(
                title: "Perimetros",
                icon: "network",
                iconColor: .blue,
                backgroundColor: Color(red: 0.9, green: 0.95, blue: 1.0)
            ) {
                print("Perimetros tapped")
            }
        }
    }

    // MARK: - Bottom Navigation
    private var bottomNavigationBar: some View {
        HStack(spacing: 56) {
            // Home button
            BottomNavButton(
                icon: selectedTab == .home ? "house.fill" : "house",
                color: .blue,
                isSelected: selectedTab == .home
            ) {
                selectedTab = .home
            }

            // Chat button
            BottomNavButton(
                icon: selectedTab == .chat ? "message.fill" : "message",
                color: .green,
                isSelected: selectedTab == .chat
            ) {
                selectedTab = .chat
            }

            // SOS button
            BottomNavButton(
                icon: "exclamationmark.triangle.fill",
                color: .red,
                isSelected: selectedTab == .sos,
                isEmergency: true
            ) {
                selectedTab = .sos
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: -5)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 0)
    }

    // MARK: - Helpers
    private var appBackgroundColor: Color {
        Color(red: 0.98, green: 0.98, blue: 0.99)
    }
}

// MARK: - Feature Card Component
struct FeatureCard: View {
    let title: String
    let icon: String
    let iconColor: Color
    let backgroundColor: Color
    var isEmpty: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                if !isEmpty {
                    // Icon
                    Image(systemName: icon)
                        .font(.system(size: 36))
                        .foregroundColor(iconColor)
                        .frame(height: 50)

                    // Title
                    Text(title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isEmpty)
    }
}

// MARK: - Bottom Nav Button Component
struct BottomNavButton: View {
    let icon: String
    let color: Color
    var isSelected: Bool = false
    var isEmergency: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Background circle - filled when selected, stroke when not
                if isSelected {
                    Circle()
                        .fill(color)
                        .frame(width: 60, height: 60)
                        .shadow(
                            color: color.opacity(0.4),
                            radius: isEmergency ? 12 : 8,
                            x: 0,
                            y: 4
                        )
                } else {
                    Circle()
                        .stroke(color, lineWidth: 2.5)
                        .frame(width: 60, height: 60)
                }

                Image(systemName: icon)
                    .font(.system(size: isEmergency ? 28 : 24, weight: .semibold))
                    .foregroundColor(isSelected ? .white : color)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Dashboard Tab Enum
enum DashboardTab {
    case home
    case chat
    case sos
}

// MARK: - Settings Placeholder
struct SettingsPlaceholderView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("Configuración")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Aquí irán las configuraciones de la app")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .navigationTitle("Ajustes")
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

// MARK: - Preview
#Preview {
    StadiumDashboardView()
}
