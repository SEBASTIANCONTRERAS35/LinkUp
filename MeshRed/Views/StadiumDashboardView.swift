//
//  StadiumDashboardView.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//

import SwiftUI
import os

struct StadiumDashboardView: View {
    // MARK: - Environment
    @EnvironmentObject var networkManager: NetworkManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // MARK: - State
    @State private var showSettings = false
    @State private var selectedTab: DashboardTab = .home
    @State private var showGeofenceList = false
    @State private var showSimulationControl = false
    @StateObject private var mockGroupsManager = MockFamilyGroupsManager.shared

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
            StadiumModeSettingsView()
                .environmentObject(networkManager)
        }
        .sheet(isPresented: $showGeofenceList) {
            if let linkfenceManager = networkManager.linkfenceManager {
                LinkFenceListView(
                    linkfenceManager: linkfenceManager,
                    locationService: networkManager.locationService
                )
            } else {
                Text("Geofencing no disponible")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showSimulationControl) {
            SimulationControlPanelView()
                .environmentObject(networkManager)
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
        let matchProgress = min(max(Double(matchMinute) / 90.0, 0), 1)

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Partido en curso".uppercased())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Capsule())

                Spacer()

                Label("\(matchMinute) Min", systemImage: "clock.fill")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Capsule())
            }

            HStack(spacing: 16) {
                matchTeamColumn(flag: "🇲🇽", name: homeTeam, role: "Local")

                matchScoreStack

                matchTeamColumn(flag: "🇨🇦", name: awayTeam, role: "Visitante")
            }

            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                            .frame(height: 6)

                        Capsule()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: geometry.size.width * matchProgress, height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text("Minuto \(matchMinute) de 90")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.8))

                    Spacer()

                    Text("\(Int(matchProgress * 100))% del partido")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            HStack(spacing: 12) {
                Label(stadiumName, systemImage: "sportscourt.fill")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())

                Label(sectionNumber, systemImage: "mappin.and.ellipse")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())

                Spacer()
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(matchCardColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Mundial2026Colors.verde.opacity(0.2), radius: 12, x: 0, y: 8)
    }

    private var matchScoreStack: some View {
        let spacing = scaled(10, min: 6, max: 20)
        let vsPaddingH = scaled(8, min: 6, max: 18)
        let vsPaddingV = scaled(4, min: 3, max: 12)
        let vsSpacing = scaled(2, min: 1, max: 6)
        let vsFontSize = scaled(11, min: 9, max: 20)
        let minuteFontSize = scaled(10, min: 8, max: 18)

        return HStack(spacing: spacing) {
            scoreBadge(value: homeScore, label: "Local")

            VStack(spacing: vsSpacing) {
                Text("VS")
                    .font(.system(size: vsFontSize, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))

                Text("\(matchMinute)' Min")
                    .font(.system(size: minuteFontSize, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
            }
            .padding(.horizontal, vsPaddingH)
            .padding(.vertical, vsPaddingV)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: scaled(10, min: 8, max: 16), style: .continuous))
            .accessibilityHidden(true)

            scoreBadge(value: awayScore, label: "Visita")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, scaled(8, min: 6, max: 18))
        .padding(.vertical, scaled(6, min: 4, max: 14))
    }

    private func scoreBadge(value: Int, label: String) -> some View {
        let badgeFontSize = scaled(32, min: 26, max: 80)
        let badgeWidth = scaled(48, min: 40, max: 96)
        let badgeHeight = scaled(40, min: 32, max: 76)
        let badgeCorner = scaled(10, min: 8, max: 18)
        let labelFontSize = scaled(11, min: 9, max: 18)
        let stackSpacing = scaled(4, min: 3, max: 10)
        let shadowRadius = scaled(2, min: 1, max: 5)

        return VStack(spacing: stackSpacing) {
            Text("\(value)")
                .font(.system(size: badgeFontSize, weight: .black, design: .rounded))
                .foregroundColor(matchCardColor)
                .frame(width: badgeWidth, height: badgeHeight)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: badgeCorner, style: .continuous))
                .shadow(color: Color.black.opacity(0.1), radius: shadowRadius, x: 0, y: 1)

            Text(label.uppercased())
                .font(.system(size: labelFontSize, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label == "Local" ? "Equipo local" : "Equipo visitante") \(value) goles")
    }

    private func matchTeamColumn(flag: String, name: String, role: String) -> some View {
        let circleSize = scaled(56, min: 44, max: 96)
        let flagFontSize = scaled(28, min: 22, max: 44)
        let nameFontSize = scaled(12, min: 10, max: 20)
        let roleFontSize = scaled(11, min: 9, max: 18)
        let columnSpacing = scaled(8, min: 6, max: 14)

        return VStack(spacing: columnSpacing) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: circleSize, height: circleSize)

                Text(flag)
                    .font(.system(size: flagFontSize))
            }

            VStack(spacing: scaled(3, min: 2, max: 6)) {
                Text(name.uppercased())
                    .font(.system(size: nameFontSize, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text(role.uppercased())
                    .font(.system(size: roleFontSize, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var matchCardColor: Color {
        Color(hex: "2853A1")
    }

    private func scaled(_ base: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        var value = base * dynamicScaleFactor
        value = max(minValue, value)
        value = min(maxValue, value)
        return value
    }

    private func scaled(_ base: CGFloat, min minValue: CGFloat) -> CGFloat {
        max(minValue, base * dynamicScaleFactor)
    }

    private func scaled(_ base: CGFloat) -> CGFloat {
        base * dynamicScaleFactor
    }

    private var dynamicScaleFactor: CGFloat {
        switch dynamicTypeSize {
        case .xSmall: return 0.85
        case .small: return 0.9
        case .medium: return 0.98
        case .xLarge: return 1.16
        case .xxLarge: return 1.26
        case .xxxLarge: return 1.36
        case .accessibility1: return 1.55
        case .accessibility2: return 1.7
        case .accessibility3: return 1.9
        case .accessibility4: return 2.1
        case .accessibility5: return 2.3
        @unknown default: return 1.0
        }
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
                iconColor: Mundial2026Colors.verde,
                backgroundColor: Color(red: 0.9, green: 0.95, blue: 1.0)
            ) {
                // Action for network
                LoggingService.network.info("Tu red tapped")
            }

          

            // Ubicaciones
            FeatureCard(
                title: "Ubicaciones",
                icon: "mappin.and.ellipse",
                iconColor: .blue,
                backgroundColor: Color(red: 0.9, green: 0.95, blue: 1.0)
            ) {
                LoggingService.network.info("Ubicaciones tapped")
            }

            // Perimetros
            FeatureCard(
                title: "Perimetros",
                icon: "network",
                iconColor: .blue,
                backgroundColor: Color(red: 0.9, green: 0.95, blue: 1.0)
            ) {
                showGeofenceList = true
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


// MARK: - Preview
#Preview {
    StadiumDashboardView()
        .environmentObject(NetworkManager())
}
