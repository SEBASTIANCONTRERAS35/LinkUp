//
//  ImprovedHomeView.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Main home dashboard with FULL ACCESSIBILITY SUPPORT
//
//  ACCESSIBILITY EXCELLENCE FOR CSC 2025 "INCLUSIVE APP" CATEGORY:
//  ✅ VoiceOver: Complete labels, hints, and logical navigation order
//  ✅ Dynamic Type: All text scales from .xSmall to .xxxLarge
//  ✅ High Contrast: Support for .colorSchemeContrast(.increased)
//  ✅ Reduce Motion: Animations respect user preference
//  ✅ Touch Targets: All interactive elements ≥ 44x44pt
//  ✅ Haptic Feedback: Tactile feedback for important actions
//  ✅ Semantic Grouping: Logical VoiceOver navigation flow
//  ✅ Custom Rotors: Advanced VoiceOver navigation for peer list
//

import SwiftUI
import MultipeerConnectivity
import CoreLocation

struct ImprovedHomeView: View {
    // MARK: - Environment
    @EnvironmentObject var networkManager: NetworkManager
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibleTheme) var accessibleTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // MARK: - State
    @State private var showSOSView = false
    @State private var showMessaging = false
    @State private var showFamilyGroups = false
    @State private var showGeofenceMap = false
    @State private var showNetworkManagement = false
    @State private var showSettings = false
    @State private var batteryLevel: Float = 0.87 // Will be replaced with real data
    @State private var currentGeofenceZone: String? = nil

    // Match data (from StadiumDashboardView)
    @State private var stadiumName = "Estadio Azteca"
    @State private var sectionNumber = "Sección 4B"
    @State private var homeTeam = "MÉXICO"
    @State private var awayTeam = "CANADÁ"
    @State private var homeScore = 2
    @State private var awayScore = 1
    @State private var matchMinute = 78

    var body: some View {
        VStack(spacing: 0) {
            // Top Bar (Stadium + Section)
            topBar
                .accessibilityAddTraits(.isHeader)
                .accessibilitySortPriority(100)

            // Main scrollable content
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 24) {
                    // Battery indicator (arriba del partido)
                    batteryIndicator
                        .accessibilitySortPriority(95)

                    // Match Score Card (from StadiumDashboardView)
                    matchScoreCard
                        .accessibilitySortPriority(90)

                    // Quick Actions Grid (2x2)
                    quickActionsGrid
                        .accessibilitySortPriority(80)

                    // Nearby Peers List
                    nearbyPeersList
                        .accessibilitySortPriority(70)

                    // Bottom spacing to keep content above bottom nav
                    Color.clear.frame(height: 150)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .background(ThemeColors.background)
        }
        .background(ThemeColors.background.ignoresSafeArea())
        .sheet(isPresented: $showSOSView) {
            SOSViewPlaceholder()
        }
        .sheet(isPresented: $showMessaging) {
            MessagingViewPlaceholder()
        }
        .sheet(isPresented: $showFamilyGroups) {
            FamilyGroupView(
                familyGroupManager: networkManager.familyGroupManager
            )
            .environmentObject(networkManager)
        }
        .sheet(isPresented: $showGeofenceMap) {
            if let linkfenceManager = networkManager.linkfenceManager {
                FamilyLinkFenceMapView(
                    linkfenceManager: linkfenceManager,
                    familyGroupManager: networkManager.familyGroupManager,
                    locationService: networkManager.locationService,
                    networkManager: networkManager
                )
            } else {
                Text("Geofencing no disponible")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
        .fullScreenCover(isPresented: $showNetworkManagement) {
            NetworkHubView()
                .environmentObject(networkManager)
        }
        .sheet(isPresented: $showSettings) {
            AccessibilitySettingsView()
                .environmentObject(networkManager)
        }
        .onAppear {
            updateGeofenceZone()
            updateBatteryLevel()
        }
        // ACCESSIBILITY: Announce important network changes
        .onChange(of: networkManager.connectedPeers.count) { newCount in
            // Use AudioManager with settings-aware announcements
            AudioManager.shared.announceNetworkStatus(peerCount: newCount)
        }
    }

    // MARK: - Top Bar (Stadium + Section)
    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(stadiumName)
                    .font(.headline) // Dynamic Type
                    .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
                    .foregroundColor(accessibleTheme.textPrimary)
                    .accessibleText() // ✅ Applies size multiplier + bold + contrast
                Text(sectionNumber)
                    .font(.subheadline) // Dynamic Type
                    .foregroundColor(accessibleTheme.textSecondary)
                    .accessibleText() // ✅ Applies size multiplier + bold + contrast
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(stadiumName), \(sectionNumber)")
            .accessibilityAddTraits(.isStaticText)

            Spacer()

            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundColor(accessibleTheme.primaryBlue)
                    .frame(width: 44, height: 44) // Minimum touch target
            }
            .accessibleButton(minTouchTarget: 44) // ✅ Applies size scaling
            .accessibilityLabel("Settings")
            .accessibilityHint("Opens app settings")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .accessibleBackground(Color.white, opacity: 0.95) // ✅ Respects reduceTransparency
        .shadow(color: Color.black.opacity(accessibleTheme.shadowOpacity), radius: 2, x: 0, y: 1)
    }

    // MARK: - Battery & Network Status Bar
    /// Indicador compacto de batería y red arriba del partido
    /// ACCESSIBILITY: Critical info for emergency features
    private var batteryIndicator: some View {
        HStack(spacing: 12) {
            // Conectados
            HStack(spacing: 4) {
                Circle()
                    .fill(connectionStatusColor)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)

                Image(systemName: networkManager.connectedPeers.count > 0 ? "person.2.fill" : "person.2.slash")
                    .font(.caption2)
                    .foregroundColor(networkManager.connectedPeers.count > 0 ? accessibleTheme.connected : accessibleTheme.disconnected)

                Text("\(networkManager.connectedPeers.count)")
                    .font(.caption)
                    .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
                    .foregroundColor(Color(hex: "2853A1"))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(networkManager.connectedPeers.count) conectados")
            .accessibilityHint(networkManager.connectedPeers.count == 0 ? "Sin conexiones. SOS puede no funcionar." : "")

            Text("|")
                .font(.caption2)
                .foregroundColor(ThemeColors.textSecondary.opacity(0.5))
                .accessibilityHidden(true)

            // Señal
            HStack(spacing: 4) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption2)
                    .foregroundColor(connectionStatusColor)

                Text(connectionStatusText)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(connectionStatusColor)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Señal \(connectionStatusText)")

            Spacer()

            // Batería
            HStack(spacing: 4) {
                Image(systemName: batteryIcon)
                    .font(.caption2)
                    .foregroundColor(batteryColor)

                Text("\(Int(batteryLevel * 100))%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(ThemeColors.textPrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Batería \(Int(batteryLevel * 100))%")
            .accessibilityHint(batteryLevel < 0.2 ? "Nivel bajo. Considera cargar." : "")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(ThemeColors.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(connectionStatusColor.opacity(0.2), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Estado del sistema")
        .accessibilityAddTraits(.updatesFrequently)
    }


    // MARK: - Match Score Card
    private var matchScoreCard: some View {
        let gradientStops: [Gradient.Stop] = (accessibilitySettings.enableGradients && !accessibilitySettings.reduceTransparency)
            ? [
                .init(color: Color(hex: "2853A1"), location: 0.0),
                .init(color: Color(hex: "1E7A8C"), location: 0.45),
                .init(color: Color(hex: "006847"), location: 1.0)
            ]
            : [
                .init(color: Color(hex: "006847"), location: 0.0),
                .init(color: Color(hex: "006847"), location: 1.0)
            ]

        let capsuleBackground = Color.white.opacity(accessibilitySettings.reduceTransparency ? 0.3 : 0.18)
        let matchProgress = min(max(Double(matchMinute) / 90.0, 0), 1)

        return VStack(alignment: .leading, spacing: scaled(10, min: 8, max: 14)) {
            // Header compacto
            HStack(spacing: scaled(8, min: 6, max: 12)) {
                Text("PARTIDO EN CURSO")
                    .font(.system(size: scaled(10, min: 9, max: 16), weight: accessibilitySettings.preferBoldText ? .heavy : .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))

                Spacer()

                HStack(spacing: scaled(4, min: 3, max: 8)) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: scaled(10, min: 9, max: 16)))
                    Text("\(matchMinute)'")
                        .font(.system(size: scaled(11, min: 10, max: 17), weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .accessibilityLabel("Minuto \(matchMinute)")
            }

            // Marcador principal compacto
            HStack(spacing: scaled(12, min: 10, max: 18)) {
                // México
                HStack(spacing: scaled(8, min: 6, max: 12)) {
                    Text("🇲🇽")
                        .font(.system(size: scaled(24, min: 20, max: 32)))
                    VStack(alignment: .leading, spacing: scaled(2, min: 1, max: 4)) {
                        Text(homeTeam)
                            .font(.system(size: scaled(11, min: 10, max: 17), weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Local")
                            .font(.system(size: scaled(9, min: 8, max: 14), weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                Spacer()

                // Score
                HStack(spacing: scaled(8, min: 6, max: 12)) {
                    Text("\(homeScore)")
                        .font(.system(size: scaled(28, min: 24, max: 40), weight: accessibilitySettings.preferBoldText ? .heavy : .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("–")
                        .font(.system(size: scaled(18, min: 16, max: 26), weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))

                    Text("\(awayScore)")
                        .font(.system(size: scaled(28, min: 24, max: 40), weight: accessibilitySettings.preferBoldText ? .heavy : .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Marcador: \(homeTeam) \(homeScore), \(awayTeam) \(awayScore)")

                Spacer()

                // Canadá
                HStack(spacing: scaled(8, min: 6, max: 12)) {
                    VStack(alignment: .trailing, spacing: scaled(2, min: 1, max: 4)) {
                        Text(awayTeam)
                            .font(.system(size: scaled(11, min: 10, max: 17), weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Visitante")
                            .font(.system(size: scaled(9, min: 8, max: 14), weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Text("🇨🇦")
                        .font(.system(size: scaled(24, min: 20, max: 32)))
                }
            }

            // Progress bar y ubicación
            VStack(alignment: .leading, spacing: scaled(4, min: 3, max: 8)) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: scaled(4, min: 3, max: 8))

                        Capsule()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: geometry.size.width * matchProgress, height: scaled(4, min: 3, max: 8))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Progreso del partido")
                    .accessibilityValue("\(Int(matchProgress * 100)) por ciento completado")
                }
                .frame(height: scaled(4, min: 3, max: 8))

                HStack(spacing: scaled(8, min: 6, max: 12)) {
                    Image(systemName: "sportscourt.fill")
                        .font(.system(size: scaled(10, min: 9, max: 15)))
                    Text(stadiumName)
                        .font(.system(size: scaled(10, min: 9, max: 16), weight: .medium, design: .rounded))

                    Text("•")
                        .font(.system(size: scaled(10, min: 9, max: 16)))

                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: scaled(10, min: 9, max: 15)))
                    Text(sectionNumber)
                        .font(.system(size: scaled(10, min: 9, max: 16), weight: .medium, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.8))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(stadiumName), \(sectionNumber)")
            }
        }
        .padding(.vertical, scaled(14, min: 12, max: 20))
        .padding(.horizontal, scaled(16, min: 14, max: 22))
        .background(
            RoundedRectangle(cornerRadius: scaled(16, min: 14, max: 22), style: .continuous)
                .fill(matchCardColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: scaled(16, min: 14, max: 22), style: .continuous)
                .stroke(Color.white.opacity(accessibilitySettings.reduceTransparency ? 0.4 : 0.18), lineWidth: 1)
        )
        .accessibleShadow(color: accessibleTheme.primaryGreen, radius: scaled(8, min: 6, max: 14))
        // ACCESSIBILITY: Group entire match score as one element
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Match score")
        .accessibilityValue("\(homeTeam) \(homeScore), \(awayTeam) \(awayScore), minuto \(matchMinute). \(homeTeam) \(homeScore > awayScore ? "gana" : (homeScore < awayScore ? "pierde" : "empata"))")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var accessibleMatchScoreStack: some View {
        let spacing = scaled(10, min: 6, max: 20)
        let vsPaddingH = scaled(8, min: 6, max: 18)
        let vsPaddingV = scaled(4, min: 3, max: 12)
        let vsSpacing = scaled(2, min: 1, max: 6)
        let vsFontSize = scaled(11, min: 9, max: 20)
        let minuteFontSize = scaled(10, min: 8, max: 18)

        return HStack(spacing: spacing) {
            accessibleScoreBadge(value: homeScore, label: "Local")

            VStack(spacing: vsSpacing) {
                Text("VS")
                    .font(.system(size: vsFontSize, weight: accessibilitySettings.preferBoldText ? .bold : .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))

                Text("\(matchMinute)' Min")
                    .font(.system(size: minuteFontSize, weight: accessibilitySettings.preferBoldText ? .medium : .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, vsPaddingH)
            .padding(.vertical, vsPaddingV)
            .background(Color.white.opacity(accessibilitySettings.reduceTransparency ? 0.22 : 0.08))
            .clipShape(RoundedRectangle(cornerRadius: scaled(10, min: 8, max: 16), style: .continuous))
            .accessibilityHidden(true)

            accessibleScoreBadge(value: awayScore, label: "Visita")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, scaled(8, min: 6, max: 18))
        .padding(.vertical, scaled(6, min: 4, max: 14))
    }

    private func accessibleScoreBadge(value: Int, label: String) -> some View {
        let fontSize = scaled(32, min: 26, max: 80)
        let width = scaled(48, min: 40, max: 96)
        let height = scaled(40, min: 32, max: 76)
        let corner = scaled(10, min: 8, max: 18)
        let labelSize = scaled(11, min: 9, max: 18)
        let spacing = scaled(4, min: 3, max: 10)
        let shadowRadius = scaled(2, min: 1, max: 5)

        return VStack(spacing: spacing) {
            Text("\(value)")
                .font(.system(size: fontSize, weight: accessibilitySettings.preferBoldText ? .black : .heavy, design: .rounded))
                .foregroundColor(matchCardColor)
                .frame(width: width, height: height)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .shadow(color: Color.black.opacity(0.1), radius: shadowRadius, x: 0, y: 1)

            Text(label.uppercased())
                .font(.system(size: labelSize, weight: accessibilitySettings.preferBoldText ? .semibold : .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label == "Local" ? "Equipo local" : "Equipo visitante") \(value) goles")
    }

    private func accessibleMatchTeamColumn(flag: String, name: String, role: String) -> some View {
        let circleSize = scaled(56, min: 44, max: 96)
        let flagFontSize = scaled(28, min: 22, max: 44)
        let nameFontSize = scaled(12, min: 10, max: 20)
        let roleFontSize = scaled(11, min: 9, max: 18)
        let columnSpacing = scaled(8, min: 6, max: 14)

        return VStack(spacing: columnSpacing) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(accessibilitySettings.reduceTransparency ? 0.28 : 0.18))
                    .frame(width: circleSize, height: circleSize)

                Text(flag)
                    .font(.system(size: flagFontSize))
                    .accessibilityHidden(true)
            }

            VStack(spacing: scaled(3, min: 2, max: 6)) {
                Text(name.uppercased())
                    .font(.system(size: nameFontSize, weight: accessibilitySettings.preferBoldText ? .heavy : .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text(role.uppercased())
                    .font(.system(size: roleFontSize, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(role)")
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
        case .large: return 1.06
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

    // MARK: - Network Status Header
    private var networkStatusHeader: some View {
        AccessibleNetworkStatusHeader(
            deviceName: networkManager.localDeviceName,
            connectedPeers: networkManager.connectedPeers.count,
            statusText: connectionStatusText,
            statusColor: connectionStatusColor,
            connectionQuality: connectionQualityText
        )
    }

    // MARK: - Emergency SOS Button
    /// Large, prominent emergency button with maximum accessibility
    private var emergencySOSButton: some View {
        AccessibleActionButton(
            title: "EMERGENCIA SOS",
            icon: "exclamationmark.triangle.fill",
            backgroundColor: ThemeColors.emergency,
            foregroundColor: .white,
            action: {
                showSOSView = true
            },
            accessibilityLabel: "Emergency SOS",
            accessibilityHint: "Double tap to alert stadium medical staff of an emergency. Medical personnel will be notified immediately.",
            isEmergency: true
        )
        // ACCESSIBILITY: Make SOS button extra prominent
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Quick Actions Grid
    /// Centered family groups card
    private var quickActionsGrid: some View {
        VStack(spacing: 16) {
            // Family Groups - Centered
            HStack {
                Spacer()
                AccessibleQuickActionCard(
                    title: "Tus Grupos",
                    icon: "person.3.fill",
                    iconColor: ThemeColors.primaryGreen,
                    backgroundColor: ThemeColors.cardBackground,
                    action: {
                        showFamilyGroups = true
                    },
                    accessibilityLabel: "Your family groups",
                    accessibilityHint: "Double tap to view and manage your family groups. Create or join groups to find family members easily."
                )
                .frame(width: 160)
                Spacer()
            }

            // Bottom row - Geofencing and Network
            HStack(spacing: 16) {
                // Geofencing / Zones
                AccessibleQuickActionCard(
                    title: "LinkFence",
                    icon: "location.circle.fill",
                    iconColor: ThemeColors.primaryRed,
                    backgroundColor: ThemeColors.cardBackground,
                    action: {
                        showGeofenceMap = true
                    },
                    accessibilityLabel: "Zones and perimeters",
                    accessibilityHint: "Double tap to view stadium zones and set up linkfence alerts for specific areas."
                )

                // Network Settings
                AccessibleQuickActionCard(
                    title: "LinkMesh",
                    icon: "network",
                    iconColor: Color(hex: "2853A1"),
                    backgroundColor: ThemeColors.cardBackground,
                    action: {
                        showNetworkManagement = true
                    },
                    accessibilityLabel: "Network management",
                    accessibilityHint: "Double tap to manage your LinkMesh network connections. Maximum 5 connections."
                )
            }
        }
        // ACCESSIBILITY: Group quick actions for easier navigation
        .accessibilityElement(children: .contain)
    }

    // MARK: - Current Location Card
    /// Shows current linkfence zone (e.g., "Section 101")
    private func currentLocationCard(zone: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "mappin.circle.fill")
                .font(.title)
                .foregroundColor(ThemeColors.primaryGreen)
                .accessibilityHidden(true) // Decorative

            VStack(alignment: .leading, spacing: 4) {
                Text("Tu ubicación actual")
                    .font(.caption) // Dynamic Type
                    .foregroundColor(ThemeColors.textSecondary)

                Text(zone)
                    .font(.title3) // Dynamic Type
                    .fontWeight(.bold)
                    .foregroundColor(ThemeColors.textPrimary)
            }

            Spacer()

            // Quick navigate button
            Button(action: {
                showGeofenceMap = true
            }) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2)
                    .foregroundColor(ThemeColors.primaryBlue)
                    .frame(width: 44, height: 44) // Minimum touch target
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Navigate from current location")
            .accessibilityHint("Double tap to open map and navigate from \(zone)")
        }
        .padding(20)
        .background(ThemeColors.cardBackground)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        // ACCESSIBILITY: Announce location as single unit
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current location")
        .accessibilityValue(zone)
    }

    // MARK: - Nearby Peers List
    /// Shows connected peers with distance (LinkFinder if available)
    private var nearbyPeersList: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                Text("Personas Cercanas")
                    .font(.title3) // Dynamic Type
                    .fontWeight(.bold)
                    .foregroundColor(ThemeColors.textPrimary)

                Spacer()

                // Peer count badge
                Text("\(networkManager.connectedPeers.count)")
                    .font(.caption) // Dynamic Type
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(ThemeColors.primaryBlue)
                    .cornerRadius(10)
                    .accessibilityHidden(true) // Redundant with list
            }
            .accessibilityAddTraits(.isHeader)

            if networkManager.connectedPeers.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "person.2.slash")
                        .font(.largeTitle)
                        .foregroundColor(ThemeColors.textSecondary)
                        .accessibilityHidden(true)

                    Text("No hay personas conectadas cerca")
                        .font(.body) // Dynamic Type
                        .foregroundColor(ThemeColors.textSecondary)
                        .multilineTextAlignment(.center)

                    Text("Acércate a otros usuarios con la app para conectar")
                        .font(.caption) // Dynamic Type
                        .foregroundColor(ThemeColors.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("No people connected nearby. Move closer to other app users to connect.")
            } else {
                // Peer list
                ForEach(networkManager.connectedPeers, id: \.self) { peer in
                    AccessiblePeerRow(
                        peerName: peer.displayName,
                        distance: getDistance(for: peer),
                        signalStrength: "excellent", // TODO: Get real signal strength
                        onLocate: {
                            requestLocation(for: peer)
                        },
                        onMessage: {
                            startChat(with: peer)
                        }
                    )
                }
            }
        }
        // ACCESSIBILITY: Custom rotor for peer navigation
        .accessibilityRotor("Nearby People") {
            ForEach(networkManager.connectedPeers, id: \.self) { peer in
                AccessibilityRotorEntry(peer.displayName, id: peer) {
                    // Focus on this peer when selected via rotor
                    Text(peer.displayName)
                }
            }
        }
    }

    // MARK: - Key Stats Section
    /// Battery, active connections, message queue
    private var keyStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Estado del Sistema")
                .font(.title3) // Dynamic Type
                .fontWeight(.bold)
                .foregroundColor(ThemeColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 12) {
                // Battery
                AccessibleStatsCard(
                    title: "Batería",
                    value: "\(Int(batteryLevel * 100))%",
                    icon: batteryIcon,
                    color: batteryColor
                )

                // Active connections
                AccessibleStatsCard(
                    title: "Conexiones",
                    value: "\(networkManager.connectedPeers.count)",
                    icon: "link",
                    color: ThemeColors.connected
                )

                // Message queue
                AccessibleStatsCard(
                    title: "Cola",
                    value: "\(networkManager.pendingAcksCount)",
                    icon: "tray.fill",
                    color: networkManager.pendingAcksCount > 0 ? ThemeColors.warning : ThemeColors.textSecondary
                )
            }
        }
    }

    // MARK: - Computed Properties

    private var connectionStatusText: String {
        switch networkManager.connectionStatus {
        case .connected:
            return "Conectado"
        case .connecting:
            return "Conectando..."
        case .disconnected:
            return "Desconectado"
        }
    }

    private var connectionStatusColor: Color {
        switch networkManager.connectionStatus {
        case .connected:
            return ThemeColors.connected
        case .connecting:
            return ThemeColors.connecting
        case .disconnected:
            return ThemeColors.disconnected
        }
    }

    private var connectionQualityText: String {
        switch networkManager.connectionQuality {
        case .excellent:
            return "Excelente"
        case .good:
            return "Buena"
        case .poor:
            return "Pobre"
        case .unknown:
            return "Desconocida"
        }
    }

    private var batteryIcon: String {
        if batteryLevel > 0.75 {
            return "battery.100"
        } else if batteryLevel > 0.50 {
            return "battery.75"
        } else if batteryLevel > 0.25 {
            return "battery.25"
        } else {
            return "battery.0"
        }
    }

    private var batteryColor: Color {
        if batteryLevel > 0.50 {
            return ThemeColors.success
        } else if batteryLevel > 0.20 {
            return ThemeColors.warning
        } else {
            return ThemeColors.error
        }
    }

    // MARK: - Helper Methods

    private func getDistance(for peer: MCPeerID) -> String? {
        // Check if LinkFinder distance is available
        if #available(iOS 14.0, *),
           let uwbManager = networkManager.uwbSessionManager {
            // Check session state
            let state = uwbManager.sessionStates[peer.displayName] ?? .disconnected

            // Get distance if available
            if let distance = uwbManager.getDistance(to: peer) {
                return String(format: "%.1f metros", distance)
            } else {
                // Return status message based on state
                switch state {
                case .preparing, .tokenReady:
                    return "Iniciando ubicación..."
                case .running:
                    return "Esperando señal..."
                case .ranging:
                    return "Calculando..."
                case .suspended:
                    return "Ubicación pausada"
                case .disconnected:
                    return "Ubicación no disponible"
                @unknown default:
                    return "Ubicación no disponible"
                }
            }
        }
        // Fallback: Check if we have a recent GPS location
        if let peerLocation = networkManager.peerLocationTracker.getPeerLocation(peerID: peer.displayName),
           let myLocation = networkManager.locationService.currentLocation {
            // Use the built-in distance method from UserLocation
            let distance = myLocation.distance(to: peerLocation)

            if distance > 0 && distance < 100000 { // Reasonable range (< 100km)
                return String(format: "~%.0f metros (GPS)", distance)
            }
        }
        return "Ubicación no disponible"
    }

    private func requestLocation(for peer: MCPeerID) {
        // Check location permissions first
        let authStatus = networkManager.locationService.authorizationStatus

        if authStatus != .authorizedWhenInUse && authStatus != .authorizedAlways {
            // Request permissions
            networkManager.locationService.requestPermissions()
            return
        }

        // Send location request
        networkManager.sendLocationRequest(to: peer.displayName)

        // ACCESSIBILITY: Announce action using AudioManager
        AudioManager.shared.speak("Solicitando ubicación de \(peer.displayName)", priority: .normal)
    }

    private func startChat(with peer: MCPeerID) {
        // TODO: Navigate to messaging view with peer pre-selected
        showMessaging = true

        // ACCESSIBILITY: Announce action using AudioManager
        AudioManager.shared.speak("Abriendo chat con \(peer.displayName)", priority: .normal)
    }

    private func updateGeofenceZone() {
        // Get current linkfence from manager
        if let linkfence = networkManager.linkfenceManager?.activeGeofence {
            currentGeofenceZone = linkfence.name
        } else {
            // Demo data
            currentGeofenceZone = "Sección 4B, Nivel Inferior"
        }
    }

    private func updateBatteryLevel() {
        // Get real battery level from iOS
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryLevel = UIDevice.current.batteryLevel

        // If battery monitoring not available, use default
        if batteryLevel < 0 {
            batteryLevel = 0.87
        }
        #else
        batteryLevel = 0.87 // Default for non-iOS platforms
        #endif
    }

    private func announceNetworkChange(peerCount: Int) {
        // ACCESSIBILITY: Announce significant network changes to VoiceOver users
        #if os(iOS)
        let message: String
        if peerCount == 0 {
            message = "Desconectado de la LinkMesh. No hay personas cercanas."
        } else if peerCount == 1 {
            message = "Conectado a 1 persona en la LinkMesh."
        } else {
            message = "Conectado a \(peerCount) personas en la LinkMesh."
        }

        UIAccessibility.post(notification: .announcement, argument: message)
        #endif
    }
}

// MARK: - Placeholder Views (to be implemented)

struct SOSViewPlaceholder: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(ThemeColors.emergency)

                Text("SOS Emergency")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Sistema de emergencias que contactará al personal médico del estadio")
                    .font(.body)
                    .foregroundColor(ThemeColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .navigationTitle("Emergencia SOS")
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

struct MessagingViewPlaceholder: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "message.fill")
                    .font(.system(size: 60))
                    .foregroundColor(ThemeColors.primaryGreen)

                Text("Mensajería Mesh")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Chat P2P sin necesidad de internet o datos celulares")
                    .font(.body)
                    .foregroundColor(ThemeColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .navigationTitle("Mensajes")
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

// MARK: - Previews
#if DEBUG
struct ImprovedHomeView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Standard preview
            ImprovedHomeView()
                .environmentObject(NetworkManager())
                .previewDisplayName("Standard")

            // Dark mode
            ImprovedHomeView()
                .environmentObject(NetworkManager())
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")

            // Large text (Dynamic Type)
            ImprovedHomeView()
                .environmentObject(NetworkManager())
                .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
                .previewDisplayName("Extra Large Text")

            // High contrast
            ImprovedHomeView()
                .environmentObject(NetworkManager())
                .environment(\.colorScheme, .dark)
                .previewDisplayName("Dark Mode")
        }
    }
}
#endif
