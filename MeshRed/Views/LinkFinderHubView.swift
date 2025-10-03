//
//  LinkFinderHubView.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Unified LinkFinder hub with radar visualization for precise peer tracking
//

import SwiftUI
import MultipeerConnectivity
import CoreLocation

// MARK: - LinkFinder Hub View
/// Fullscreen LinkFinder management with radar visualization
struct LinkFinderHubView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var networkManager: NetworkManager
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme
    @StateObject private var radarCalculator = RadarCalculator()
    @StateObject private var uwbPriorityManager = LinkFinderPriorityManager(maxSessions: 2)
    @StateObject private var sweepDetectionManager = RadarSweepDetectionManager()

    @State private var selectedTab: LinkFinderTab = .active
    @State private var selectedPeer: String? = nil
    @State private var radarMode: RadarMode = .hybrid
    @State private var showMessaging = false
    @State private var sweepAngle: Double = 0
    @State private var sweepTimer: Timer?
    @State private var refreshCounter = 0

    private let maxLinkFinderSessions = 2
    private let radarRadius: CGFloat = 140.0

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with capacity indicator
                headerSection

                // Radar section (fixed, always visible)
                radarSection
                    .frame(height: 340)
                    .background(colorScheme == .dark ? Color.black.opacity(0.95) : Color(UIColor.systemBackground))

                // Tab selector
                tabSelector

                // Peer list (scrollable)
                peerListSection
            }
            .background(accessibleTheme.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showMessaging) {
                MessagingDashboardView()
                    .environmentObject(networkManager)
            }
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            // Top bar
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: accessibilitySettings.preferBoldText ? .bold : .semibold))
                        .foregroundColor(accessibleTheme.primaryBlue)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibleButton(minTouchTarget: 44)
                .accessibilityLabel("Cerrar")

                Spacer()

                Text("Mi LinkFinder")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(accessibleTheme.textPrimary)
                    .accessibleText()

                Spacer()

                Button(action: toggleRadarMode) {
                    Image(systemName: radarMode.icon)
                        .font(.system(size: 18, weight: accessibilitySettings.preferBoldText ? .bold : .semibold))
                        .foregroundColor(accessibleTheme.primaryBlue)
                        .frame(width: 44, height: 44)
                }
                .accessibleButton(minTouchTarget: 44)
            }

            // Capacity indicator
            HStack(spacing: 16) {
                // Connection dots
                HStack(spacing: 6) {
                    ForEach(0..<maxLinkFinderSessions, id: \.self) { index in
                        Circle()
                            .fill(index < activeSessionCount ? Mundial2026Colors.azul : Color.gray.opacity(0.3))
                            .frame(width: 10, height: 10)
                    }
                }

                // Stats text
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(activeSessionCount)/\(maxLinkFinderSessions) Sesiones LinkFinder")
                        .font(.subheadline)
                        .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
                        .foregroundColor(accessibleTheme.textPrimary)
                        .accessibleText()

                    Text(capacityStatus)
                        .font(.caption)
                        .foregroundColor(accessibleTheme.textSecondary)
                }

                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .accessibleBackground(Color.white, opacity: 1.0)
        .accessibleShadow(color: .black, radius: 4)
    }

    // MARK: - Radar Section
    private var radarSection: some View {
        let _ = print("📡 LINKFINDER RADAR: \(peerRadarData.count) peers with LinkFinder data")

        return ZStack {
            // Radar background
            radarBackground

            // Radar sweep line (rotating detection line)
            RadarSweepLine(radius: radarRadius, sweepAngle: $sweepAngle)

            // Compass directions (if absolute mode)
            if effectiveRadarMode == .absolute {
                compassDirections
            }

            // Center marker
            centerMarker

            // Peer dots with sweep-based visibility
            ForEach(peerRadarData) { radarData in
                if let position = radarData.position.point {
                    let peerOpacity = sweepDetectionManager.opacity(for: radarData.id)

                    // Force visibility for now
                    let finalOpacity = 1.0

                    PeerRadarDot(
                        radarData: radarData,
                        isSelected: selectedPeer == radarData.peer,
                        onTap: {
                            withAnimation(.spring(response: 0.3)) {
                                selectedPeer = (selectedPeer == radarData.peer) ? nil : radarData.peer
                            }
                        }
                    )
                    .offset(x: position.x, y: position.y)
                    .opacity(finalOpacity)
                    .id("\(radarData.id)-\(refreshCounter)")
                }
            }

            // Data source indicator (bottom right)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    dataSourceBadge
                        .padding(12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            startRadarSweep()
        }
    }

    private var radarBackground: some View {
        ZStack {
            // Adaptive background
            (colorScheme == .dark ? Color.black.opacity(0.95) : Color(UIColor.systemBackground))

            // Radar circles with adaptive gradient
            Circle()
                .fill(
                    RadialGradient(
                        colors: colorScheme == .dark ? [
                            Color.blue.opacity(0.1),
                            Color.black.opacity(0.3)
                        ] : [
                            Mundial2026Colors.azul.opacity(0.08),
                            Color.gray.opacity(0.15)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: radarRadius
                    )
                )
                .frame(width: radarRadius * 2, height: radarRadius * 2)

            // Concentric rings with adaptive color
            ForEach(1...3, id: \.self) { ring in
                Circle()
                    .stroke(
                        colorScheme == .dark ?
                            Color.blue.opacity(0.2) :
                            Mundial2026Colors.azul.opacity(0.3),
                        lineWidth: 1
                    )
                    .frame(
                        width: radarRadius * 2 * CGFloat(ring) / 3,
                        height: radarRadius * 2 * CGFloat(ring) / 3
                    )
            }

            // Crosshairs with adaptive color
            Path { path in
                path.move(to: CGPoint(x: 0, y: -radarRadius))
                path.addLine(to: CGPoint(x: 0, y: radarRadius))
                path.move(to: CGPoint(x: -radarRadius, y: 0))
                path.addLine(to: CGPoint(x: radarRadius, y: 0))
            }
            .stroke(
                colorScheme == .dark ?
                    Color.blue.opacity(0.2) :
                    Mundial2026Colors.azul.opacity(0.3),
                lineWidth: 1
            )
        }
    }

    private var compassDirections: some View {
        ZStack {
            Text("N")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(accessibleTheme.textPrimary)
                .accessibleText()
                .offset(y: -radarRadius - 15)

            Text("S")
                .font(.caption)
                .foregroundColor(accessibleTheme.textSecondary)
                .offset(y: radarRadius + 15)

            Text("E")
                .font(.caption)
                .foregroundColor(accessibleTheme.textSecondary)
                .offset(x: radarRadius + 15)

            Text("O")
                .font(.caption)
                .foregroundColor(accessibleTheme.textSecondary)
                .offset(x: -radarRadius - 15)
        }
    }

    private var centerMarker: some View {
        ZStack {
            Circle()
                .fill(colorScheme == .dark ? Color.white : Color.black)
                .frame(width: 8, height: 8)

            Circle()
                .stroke(Mundial2026Colors.azul, lineWidth: 2)
                .frame(width: 12, height: 12)
        }
    }

    private var dataSourceBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Mundial2026Colors.azul)
                .frame(width: 6, height: 6)

            Text("LinkFinder Activo")
                .font(.caption2)
                .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
                .foregroundColor(colorScheme == .dark ? .white : accessibleTheme.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(colorScheme == .dark ?
                    Color.black.opacity(0.6) :
                    Color.white.opacity(0.9))
                .overlay(
                    Capsule()
                        .stroke(Color.gray.opacity(0.3), lineWidth: colorScheme == .dark ? 0 : 1)
                )
        )
    }

    // MARK: - Tab Selector
    private var tabSelector: some View {
        HStack(spacing: 0) {
            // Active sessions tab
            Button(action: { withAnimation { selectedTab = .active } }) {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Activos")
                            .font(.subheadline)
                            .fontWeight(selectedTab == .active ? (accessibilitySettings.preferBoldText ? .bold : .semibold) : .regular)

                        if activeSessionCount > 0 {
                            Text("\(activeSessionCount)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(accessibleTheme.primaryBlue)
                                )
                        }
                    }
                    .foregroundColor(selectedTab == .active ? accessibleTheme.primaryBlue : Color.gray)

                    // Bottom indicator
                    Rectangle()
                        .fill(selectedTab == .active ? accessibleTheme.primaryBlue : Color.clear)
                        .frame(height: 3)
                }
            }
            .frame(maxWidth: .infinity)

            // Available peers tab
            Button(action: { withAnimation { selectedTab = .available } }) {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Disponibles")
                            .font(.subheadline)
                            .fontWeight(selectedTab == .available ? (accessibilitySettings.preferBoldText ? .bold : .semibold) : .regular)

                        if availablePeersCount > 0 {
                            Text("\(availablePeersCount)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(accessibleTheme.success)
                                )
                        }
                    }
                    .foregroundColor(selectedTab == .available ? accessibleTheme.success : Color.gray)

                    // Bottom indicator
                    Rectangle()
                        .fill(selectedTab == .available ? accessibleTheme.success : Color.clear)
                        .frame(height: 3)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 12)
        .accessibleBackground(Color.white, opacity: 1.0)
        .accessibleShadow(color: .black, radius: 2)
    }

    // MARK: - Peer List Section
    private var peerListSection: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                if selectedTab == .active {
                    activeSessionsList
                } else {
                    availablePeersList
                }

                // Extra spacing for bottom
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }

    private var activeSessionsList: some View {
        Group {
            if peersWithLinkFinder.isEmpty {
                emptyStateView(
                    icon: "location.slash",
                    title: "Sin sesiones LinkFinder",
                    subtitle: "Inicia una sesión de navegación con un peer conectado"
                )
            } else {
                ForEach(peersWithLinkFinder, id: \.self) { peer in
                    LinkFinderPeerCard(
                        peer: peer,
                        isActive: true,
                        isSelected: selectedPeer == peer.displayName,
                        distance: getLinkFinderDistance(for: peer),
                        hasDirection: hasLinkFinderDirection(for: peer),
                        onTap: {
                            withAnimation(.spring(response: 0.3)) {
                                selectedPeer = (selectedPeer == peer.displayName) ? nil : peer.displayName
                            }
                        },
                        onNavigate: {
                            navigateTo(peer)
                        },
                        onMessage: {
                            openMessagingFor(peer)
                        }
                    )
                }
            }
        }
    }

    private var availablePeersList: some View {
        Group {
            if connectedPeersWithoutLinkFinder.isEmpty {
                emptyStateView(
                    icon: "checkmark.circle.fill",
                    title: "Todos los peers tienen LinkFinder activo",
                    subtitle: "O no hay peers conectados"
                )
            } else {
                // Full capacity warning
                if !canStartMoreSessions {
                    fullCapacityBanner
                }

                ForEach(connectedPeersWithoutLinkFinder, id: \.self) { peer in
                    LinkFinderPeerCard(
                        peer: peer,
                        isActive: false,
                        isSelected: false,
                        distance: nil,
                        hasDirection: false,
                        onTap: {},
                        onNavigate: {
                            navigateTo(peer)
                        },
                        onMessage: {
                            openMessagingFor(peer)
                        }
                    )
                    .opacity(canStartMoreSessions ? 1.0 : 0.5)
                    .disabled(!canStartMoreSessions)
                }
            }
        }
    }

    private func emptyStateView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(accessibleTheme.primaryBlue.opacity(0.4))

            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(accessibleTheme.textPrimary)
                    .accessibleText()

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(accessibleTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var fullCapacityBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(accessibleTheme.error)

            Text("Máximo \(maxLinkFinderSessions) sesiones simultáneas de LinkFinder.")
                .font(.caption)
                .fontWeight(accessibilitySettings.preferBoldText ? .bold : .medium)
                .foregroundColor(accessibleTheme.textPrimary)

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(accessibleTheme.error.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accessibleTheme.error.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Computed Properties

    private var connectedPeers: [MCPeerID] {
        networkManager.connectedPeers
    }

    private var uwbManager: LinkFinderSessionManager? {
        guard #available(iOS 14.0, *) else { return nil }
        return networkManager.uwbSessionManager
    }

    private var activeSessionCount: Int {
        uwbManager?.activeSessions.count ?? 0
    }

    private var peersWithLinkFinder: [MCPeerID] {
        guard let uwbManager = uwbManager else { return [] }
        return connectedPeers.filter { peer in
            uwbManager.hasActiveSession(with: peer)
        }
    }

    private var connectedPeersWithoutLinkFinder: [MCPeerID] {
        guard let uwbManager = uwbManager else { return connectedPeers }
        return connectedPeers.filter { peer in
            !uwbManager.hasActiveSession(with: peer)
        }
    }

    private var availablePeersCount: Int {
        connectedPeersWithoutLinkFinder.count
    }

    private var canStartMoreSessions: Bool {
        activeSessionCount < maxLinkFinderSessions
    }

    private var capacityStatus: String {
        let remaining = maxLinkFinderSessions - activeSessionCount
        if remaining == 0 {
            return "Capacidad máxima"
        } else if remaining == 1 {
            return "1 sesión disponible"
        } else {
            return "\(remaining) sesiones disponibles"
        }
    }

    private var effectiveRadarMode: RadarMode {
        if radarMode == .hybrid {
            return locationService.currentHeading != nil ? .absolute : .relative
        }
        return radarMode
    }

    private var locationService: LocationService {
        networkManager.locationService
    }

    /// Build radar data for peers with LinkFinder sessions
    private var peerRadarData: [PeerRadarData] {
        guard let uwbManager = uwbManager else { return [] }

        var data: [PeerRadarData] = []
        let deviceHeading = locationService.currentHeading?.trueHeading ?? locationService.currentHeading?.magneticHeading

        for peer in peersWithLinkFinder {
            guard let distance = uwbManager.getDistance(to: peer) else { continue }

            if let direction = uwbManager.getDirection(to: peer),
               uwbPriorityManager.shouldTrackDirection(for: peer.displayName) {
                // Precise direction available
                let directionVector = DirectionVector(from: direction)
                let position = radarCalculator.calculatePrecisePosition(
                    direction: directionVector,
                    distance: distance,
                    deviceHeading: deviceHeading,
                    mode: effectiveRadarMode
                )

                data.append(PeerRadarData(
                    id: peer.displayName,
                    peer: peer.displayName,
                    position: .exact(x: position.x, y: position.y),
                    dataSource: .uwbPrecise,
                    distance: distance
                ))
            } else {
                // Distance only
                let ringPositions = radarCalculator.calculateRingPositions(
                    peersWithDistance: [(peer: peer.displayName, distance: distance)]
                )

                if let ringData = ringPositions.first {
                    data.append(PeerRadarData(
                        id: peer.displayName,
                        peer: peer.displayName,
                        position: .ring(distance: distance, x: ringData.position.x, y: ringData.position.y),
                        dataSource: .uwbDistance,
                        distance: distance
                    ))
                }
            }
        }

        return data
    }

    // MARK: - Helper Methods

    private func toggleRadarMode() {
        withAnimation {
            switch radarMode {
            case .absolute: radarMode = .relative
            case .relative: radarMode = .hybrid
            case .hybrid: radarMode = .absolute
            }
        }
    }

    private func getLinkFinderDistance(for peer: MCPeerID) -> String? {
        guard let uwbManager = uwbManager,
              let distance = uwbManager.getDistance(to: peer) else {
            return nil
        }

        if distance < 1.0 {
            return String(format: "%.0fcm", distance * 100)
        } else if distance < 100 {
            return String(format: "%.1fm", distance)
        } else {
            return String(format: "%.0fm", distance)
        }
    }

    private func hasLinkFinderDirection(for peer: MCPeerID) -> Bool {
        guard let uwbManager = uwbManager else { return false }
        return uwbManager.getDirection(to: peer) != nil
    }

    private func navigateTo(_ peer: MCPeerID) {
        // This would open LinkFinderNavigationView
        dismiss()
        // Navigation would be handled by parent
    }

    private func openMessagingFor(_ peer: MCPeerID) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showMessaging = true
        }
    }

    // MARK: - Radar Sweep Animation

    private func startRadarSweep() {
        print("🚀 STARTING LINKFINDER RADAR SWEEP")

        sweepTimer?.invalidate()

        let timerInterval: TimeInterval = 0.05
        let degreesPerTick = 360.0 / (sweepDetectionManager.sweepSpeed / timerInterval)

        sweepTimer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { [self] _ in
            sweepAngle += degreesPerTick
            if sweepAngle >= 360 {
                sweepAngle = sweepAngle.truncatingRemainder(dividingBy: 360)
            }

            updatePeerDetections()
            refreshCounter += 1
        }
    }

    private func updatePeerDetections() {
        for radarData in peerRadarData {
            guard let angle = radarData.angle() else { continue }

            sweepDetectionManager.checkDetection(
                peerId: radarData.id,
                peerAngle: angle,
                sweepAngle: sweepAngle
            )
        }
    }
}

// MARK: - LinkFinder Tab Enum
enum LinkFinderTab {
    case active
    case available
}

// MARK: - LinkFinder Peer Card
struct LinkFinderPeerCard: View {
    let peer: MCPeerID
    let isActive: Bool
    let isSelected: Bool
    let distance: String?
    let hasDirection: Bool
    let onTap: () -> Void
    let onNavigate: () -> Void
    let onMessage: () -> Void

    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isActive ? Mundial2026Colors.azul.opacity(0.2) : Mundial2026Colors.verde.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Image(systemName: hasDirection ? "location.fill" : "location.circle")
                        .font(.system(size: 18))
                        .foregroundColor(isActive ? Mundial2026Colors.azul : Mundial2026Colors.verde)
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(peer.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(accessibleTheme.textPrimary)
                        .accessibleText()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(isActive ? accessibleTheme.primaryBlue : Color.orange)
                            .frame(width: 6, height: 6)

                        if let dist = distance {
                            Text("\(dist) • \(hasDirection ? "Dirección" : "Solo distancia")")
                                .font(.caption)
                                .foregroundColor(accessibleTheme.textSecondary)
                        } else {
                            Text(isActive ? "LinkFinder activo" : "Disponible")
                                .font(.caption)
                                .foregroundColor(accessibleTheme.textSecondary)
                        }
                    }
                }

                Spacer()

                // Message button
                Button(action: onMessage) {
                    Image(systemName: "message.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Mundial2026Colors.azul)
                }
                .buttonStyle(.plain)

                // Navigate button
                Button(action: onNavigate) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Mundial2026Colors.verde)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? accessibleTheme.primaryBlue : Color.clear, lineWidth: 2)
            )
            .accessibleShadow(color: .black, radius: 4)
        }
        .buttonStyle(.plain)
        .accessibleButton(minTouchTarget: 44)
    }
}

// MARK: - Preview
#Preview {
    LinkFinderHubView()
        .environmentObject(NetworkManager())
        .environmentObject(AccessibilitySettingsManager())
}
