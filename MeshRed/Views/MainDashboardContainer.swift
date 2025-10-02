//
//  MainDashboardContainer.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Main container that handles navigation between dashboard views
//

import SwiftUI
import MultipeerConnectivity

struct MainDashboardContainer: View {
    @EnvironmentObject var networkManager: NetworkManager
    @State private var selectedTab: DashboardTab = .home

    var body: some View {
        ZStack {
            // Content based on selected tab
            Group {
                switch selectedTab {
                case .home:
                    ImprovedHomeView()
                        .environmentObject(networkManager)
                        .transition(.opacity)
                case .chat:
                    MessagingDashboardView()
                        .environmentObject(networkManager)
                        .transition(.opacity)
                case .sos:
                    SOSDashboardViewContent(selectedTab: $selectedTab)
                        .transition(.opacity)
                }
            }

            // Bottom navigation overlay (always visible)
            VStack {
                Spacer()
                SharedBottomNavigationBar(selectedTab: $selectedTab)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
    }
}

// MARK: - Stadium Dashboard Content (Home)
struct StadiumDashboardViewContent: View {
    @Binding var selectedTab: DashboardTab
    @State private var showSettings = false

    // Mock Data
    @State private var stadiumName = "Estadio Azteca"
    @State private var sectionNumber = "Sección 4B"
    @State private var homeTeam = "MÉXICO"
    @State private var awayTeam = "CANADÁ"
    @State private var homeScore = 0
    @State private var awayScore = 0
    @State private var matchMinute = 78

    var body: some View {
        VStack(spacing: 0) {
            // Header
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

            // Scrollable content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Match score card
                    matchScoreCard

                    // Feature grid (2x2)
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 16) {
                        FeatureCard(
                            title: "Tu red",
                            icon: "person.3.fill",
                            iconColor: Mundial2026Colors.verde,
                            backgroundColor: Mundial2026Colors.verde.opacity(0.15)
                        ) {
                            print("Tu red tapped")
                        }

                        FeatureCard(
                            title: "",
                            icon: "",
                            iconColor: .gray,
                            backgroundColor: Color(red: 0.95, green: 0.95, blue: 0.95),
                            isEmpty: true
                        ) {}

                        FeatureCard(
                            title: "Ubicaciones",
                            icon: "mappin.and.ellipse",
                            iconColor: Mundial2026Colors.azul,
                            backgroundColor: Mundial2026Colors.azul.opacity(0.15)
                        ) {
                            print("Ubicaciones tapped")
                        }

                        FeatureCard(
                            title: "Perimetros",
                            icon: "network",
                            iconColor: Mundial2026Colors.rojo,
                            backgroundColor: Mundial2026Colors.rojo.opacity(0.15)
                        ) {
                            print("Perimetros tapped")
                        }
                    }

                    // Extra spacing for bottom nav
                    Color.clear.frame(height: 150)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }

            Spacer()
        }
        .background(Color(red: 0.98, green: 0.98, blue: 0.99).ignoresSafeArea())
        .sheet(isPresented: $showSettings) {
            SettingsPlaceholderView()
        }
    }

    private var matchScoreCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                VStack(spacing: 12) {
                    Text("🇲🇽")
                        .font(.system(size: 48))
                    Text(homeTeam)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)

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
                        colors: [Mundial2026Colors.verde, Mundial2026Colors.azul],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Mundial2026Colors.verde.opacity(0.3), radius: 12, x: 0, y: 6)
    }
}

// MARK: - SOS Dashboard Content
struct SOSDashboardViewContent: View {
    @Binding var selectedTab: DashboardTab
    @EnvironmentObject var networkManager: NetworkManager

    var body: some View {
        SOSView()
            .environmentObject(networkManager)
    }
}

// MARK: - Shared Bottom Navigation Bar
struct SharedBottomNavigationBar: View {
    @Binding var selectedTab: DashboardTab

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 56) {
                BottomNavButton(
                    icon: selectedTab == .home ? "house.fill" : "house",
                    color: Mundial2026Colors.azul,
                    isSelected: selectedTab == .home
                ) {
                    selectedTab = .home
                }

                BottomNavButton(
                    icon: selectedTab == .chat ? "message.fill" : "message",
                    color: Mundial2026Colors.verde,
                    isSelected: selectedTab == .chat
                ) {
                    selectedTab = .chat
                }

                BottomNavButton(
                    icon: "exclamationmark.triangle.fill",
                    color: Mundial2026Colors.rojo,
                    isSelected: selectedTab == .sos,
                    isEmergency: true
                ) {
                    selectedTab = .sos
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background(
                Color.white
                    .ignoresSafeArea()
                    .shadow(color: Color.black.opacity(0.08), radius: 20, x: 0, y: -5)
            )

            // Bottom safe area cover
            Color.white
                .ignoresSafeArea(edges: .bottom)
                .frame(height: 0)
        }
    }
}

// MARK: - Preview
#Preview {
    MainDashboardContainer()
        .environmentObject(NetworkManager())
}
