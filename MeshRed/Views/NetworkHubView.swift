//
//  NetworkHubView.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Unified network hub with integrated radar and connection management
//

import SwiftUI
import MultipeerConnectivity
import CoreLocation
import os

// MARK: - Network Hub View
/// Fullscreen network management with radar visualization
struct NetworkHubView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var networkManager: NetworkManager
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme
    @StateObject private var connectionManager = ConnectionManager()
    @StateObject private var radarCalculator = RadarCalculator()
    @StateObject private var uwbPriorityManager = LinkFinderPriorityManager(maxSessions: 2)
    @StateObject private var mockConnectionManager = MockConnectionManager()
    @StateObject private var sweepDetectionManager = RadarSweepDetectionManager()

    @State private var selectedTab: NetworkTab = .connected
    @State private var selectedPeer: String? = nil
    @State private var radarMode: RadarMode = .hybrid
    @State private var navigationPath = NavigationPath()
    @State private var showMessaging = false
    @State private var sweepAngle: Double = 0
    @State private var sweepTimer: Timer?
    @State private var refreshCounter = 0

    private let maxConnections = 5
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
                MessagingDashboardView(hideBottomBar: .constant(false))
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

                Text("LinkMesh")
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
                    ForEach(0..<maxConnections, id: \.self) { index in
                        Circle()
                            .fill(index < totalConnectedCount ? Mundial2026Colors.verde : Color.gray.opacity(0.3))
                            .frame(width: 10, height: 10)
                    }
                }

                // Stats text
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(totalConnectedCount)/\(maxConnections) Conexiones")
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
        let _ = LoggingService.network.info("📡 RADAR: \(peerRadarData.count) peers total | hasRealConnections: \(hasRealConnections)")

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
                    let peerAngle = radarData.angle() ?? -1
                    let _ = LoggingService.network.info("👤 Peer: \(radarData.id) | Angle: \(String(format: "%.1f", peerAngle))° | Opacity: \(String(format: "%.2f", peerOpacity)) | Pos: (\(String(format: "%.1f", position.x)), \(String(format: "%.1f", position.y)))")

                    // TEMP: Force visibility to test rendering
                    let finalOpacity = 1.0  // TODO: Change back to peerOpacity

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
                            Color.green.opacity(0.1),
                            Color.black.opacity(0.3)
                        ] : [
                            Mundial2026Colors.verde.opacity(0.08),
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
                            Color.green.opacity(0.2) :
                            Mundial2026Colors.verde.opacity(0.3),
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
                    Color.green.opacity(0.2) :
                    Mundial2026Colors.verde.opacity(0.3),
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
                .fill(Mundial2026Colors.verde)
                .frame(width: 6, height: 6)

            Text("LinkFinder \(uwbSessionCount)/2")
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

    private var radarSweep: some View {
        RadarSweepView(radius: radarRadius)
    }

    // MARK: - Tab Selector
    private var tabSelector: some View {
        HStack(spacing: 0) {
            // Connected tab
            Button(action: { withAnimation { selectedTab = .connected } }) {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Conectados")
                            .font(.subheadline)
                            .fontWeight(selectedTab == .connected ? (accessibilitySettings.preferBoldText ? .bold : .semibold) : .regular)

                        if totalConnectedCount > 0 {
                            Text("\(totalConnectedCount)")
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
                    .foregroundColor(selectedTab == .connected ? accessibleTheme.success : Color.gray)

                    // Bottom indicator
                    Rectangle()
                        .fill(selectedTab == .connected ? accessibleTheme.success : Color.clear)
                        .frame(height: 3)
                }
            }
            .frame(maxWidth: .infinity)

            // Available tab
            Button(action: { withAnimation { selectedTab = .available } }) {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Disponibles")
                            .font(.subheadline)
                            .fontWeight(selectedTab == .available ? (accessibilitySettings.preferBoldText ? .bold : .semibold) : .regular)

                        if totalAvailableCount > 0 {
                            Text("\(totalAvailableCount)")
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
                    .foregroundColor(selectedTab == .available ? accessibleTheme.primaryBlue : Color.gray)

                    // Bottom indicator
                    Rectangle()
                        .fill(selectedTab == .available ? accessibleTheme.primaryBlue : Color.clear)
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
                if selectedTab == .connected {
                    connectedPeersList
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

    private var connectedPeersList: some View {
        Group {
            if connectedPeers.isEmpty && mockConnectedPeers.isEmpty {
                emptyStateView(
                    icon: "antenna.radiowaves.left.and.right.slash",
                    title: "Sin conexiones",
                    subtitle: "Conecta con personas cercanas"
                )
            } else {
                // Real connected peers
                ForEach(connectedPeers, id: \.self) { peer in
                    CompactPeerCard(
                        peer: peer,
                        isConnected: true,
                        isSelected: selectedPeer == peer.displayName,
                        distance: getUWBDistance(for: peer),
                        onTap: {
                            withAnimation(.spring(response: 0.3)) {
                                selectedPeer = (selectedPeer == peer.displayName) ? nil : peer.displayName
                            }
                        },
                        onAction: {
                            disconnectPeer(peer)
                        },
                        onMessage: {
                            openMessagingFor(peer)
                        }
                    )
                }

                // Mock connected peers (only if no real connections)
                ForEach(mockConnectedPeers) { mockPeer in
                    MockPeerCard(
                        mockPeer: mockPeer,
                        isConnected: true,
                        isSelected: selectedPeer == mockPeer.displayName,
                        onTap: {
                            withAnimation(.spring(response: 0.3)) {
                                selectedPeer = (selectedPeer == mockPeer.displayName) ? nil : mockPeer.displayName
                            }
                        },
                        onAction: {
                            disconnectMockPeer(mockPeer)
                        },
                        onMessage: {
                            openMessaging()
                        }
                    )
                }
            }
        }
    }

    private var availablePeersList: some View {
        Group {
            if availablePeers.isEmpty && mockAvailablePeers.isEmpty {
                emptyStateView(
                    icon: "magnifyingglass",
                    title: "Buscando dispositivos...",
                    subtitle: "Esperando conexiones cercanas"
                )
            } else {
                // Full capacity warning
                if !canConnectMore && !availablePeers.isEmpty {
                    fullCapacityBanner
                }

                // Real available peers
                ForEach(availablePeers, id: \.self) { peer in
                    CompactPeerCard(
                        peer: peer,
                        isConnected: false,
                        isSelected: false,
                        distance: nil,
                        onTap: {},
                        onAction: {
                            connectToPeer(peer)
                        },
                        onMessage: nil
                    )
                    .opacity(canConnectMore ? 1.0 : 0.5)
                    .disabled(!canConnectMore)
                }

                // Mock available peers (only if no real connections)
                ForEach(mockAvailablePeers) { mockPeer in
                    MockPeerCard(
                        mockPeer: mockPeer,
                        isConnected: false,
                        isSelected: false,
                        onTap: {},
                        onAction: {
                            connectMockPeer(mockPeer)
                        },
                        onMessage: nil
                    )
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

            Text("Capacidad máxima. Desconecta para agregar más.")
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

    private var hasRealConnections: Bool {
        !networkManager.connectedPeers.isEmpty || !networkManager.availablePeers.isEmpty
    }

    private var connectedPeers: [MCPeerID] {
        networkManager.connectedPeers
    }

    private var availablePeers: [MCPeerID] {
        networkManager.availablePeers.filter { peer in
            !connectedPeers.contains(peer) &&
            !connectionManager.isPeerBlocked(peer.displayName)
        }
    }

    private var canConnectMore: Bool {
        connectedPeers.count < maxConnections
    }

    // Show mock data only when no real connections exist
    private var mockConnectedPeers: [MockPeer] {
        hasRealConnections ? [] : mockConnectionManager.connectedMockPeers
    }

    private var mockAvailablePeers: [MockPeer] {
        hasRealConnections ? [] : mockConnectionManager.availableMockPeers
    }

    // Mock radar data with positions calculated from real distances
    private var mockRadarData: [PeerRadarData] {
        let mockPeers = mockConnectionManager.connectedMockPeers

        // Radar mapping: radarRadius = 140px represents maxRadarDistance = 30m
        let maxRadarDistance: Float = 30.0  // MultipeerConnectivity max practical range

        // Pre-defined angles for distribution (in degrees, 0° = North)
        let angles: [Double] = [
            45,    // María - NE (northeast)
            225,   // Carlos - SW (southwest)
            180    // Ana - S (south)
        ]

        return mockPeers.enumerated().map { index, mockPeer in
            let distance = mockPeer.distance ?? 0

            // Calculate radar position based on ACTUAL distance
            // Scale: distance/maxRadarDistance * radarRadius = pixel distance from center
            let pixelDistance = CGFloat(distance / maxRadarDistance) * radarRadius

            // Get angle for this peer (distribute evenly if we run out of predefined angles)
            let angle = index < angles.count ? angles[index] : Double(index * 60)
            let angleRadians = angle * .pi / 180.0

            // Calculate x, y coordinates
            // Note: In SwiftUI, Y increases downward, so we negate sin for correct orientation
            let x = pixelDistance * CGFloat(sin(angleRadians))
            let y = -pixelDistance * CGFloat(cos(angleRadians))  // Negative because Y is inverted

            let radarPosition: PeerRadarData.RadarPosition

            switch mockPeer.dataSource {
            case .uwbPrecise:
                radarPosition = .exact(x: x, y: y)
            case .uwbDistance:
                radarPosition = .ring(
                    distance: distance,
                    x: x,
                    y: y
                )
            case .gps:
                radarPosition = .gps(x: x, y: y)
            case .none:
                radarPosition = .unknown
            }

            let dataSource: PeerRadarData.DataSource
            switch mockPeer.dataSource {
            case .uwbPrecise: dataSource = .uwbPrecise
            case .uwbDistance: dataSource = .uwbDistance
            case .gps: dataSource = .gps
            case .none: dataSource = .none
            }

            return PeerRadarData(
                id: mockPeer.displayName,
                peer: mockPeer.displayName,
                position: radarPosition,
                dataSource: dataSource,
                distance: mockPeer.distance
            )
        }
    }

    private var totalConnectedCount: Int {
        connectedPeers.count + mockConnectedPeers.count
    }

    private var totalAvailableCount: Int {
        availablePeers.count + mockAvailablePeers.count
    }

    private var capacityStatus: String {
        let remaining = maxConnections - totalConnectedCount
        if remaining == 0 {
            return "Capacidad máxima"
        } else if remaining == 1 {
            return "1 espacio disponible"
        } else {
            return "\(remaining) espacios disponibles"
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

    private var uwbSessionCount: Int {
        guard #available(iOS 14.0, *), let uwbManager = networkManager.uwbSessionManager else {
            return 0
        }
        return uwbManager.activeSessions.count
    }

    /// Build radar data for all connected peers
    private var peerRadarData: [PeerRadarData] {
        var data: [PeerRadarData] = []

        // If no real connections, show mock radar data
        if !hasRealConnections {
            return mockRadarData
        }

        let deviceHeading = locationService.currentHeading?.trueHeading ?? locationService.currentHeading?.magneticHeading

        // Check if LinkFinder is available
        guard #available(iOS 14.0, *),
              let uwbManager = networkManager.uwbSessionManager else {
            return connectedPeers.map { peer in
                PeerRadarData(
                    id: peer.displayName,
                    peer: peer.displayName,
                    position: .unknown,
                    dataSource: .none,
                    distance: nil
                )
            }
        }

        var peersWithUWBDirection: [(peer: MCPeerID, direction: SIMD3<Float>, distance: Float)] = []
        var peersWithUWBDistanceOnly: [(peer: MCPeerID, distance: Float)] = []
        var peersWithoutData: [MCPeerID] = []

        for peer in connectedPeers {
            let peerId = peer.displayName

            if let distance = uwbManager.getDistance(to: peer) {
                if let direction = uwbManager.getDirection(to: peer),
                   uwbPriorityManager.shouldTrackDirection(for: peerId) {
                    peersWithUWBDirection.append((peer, direction, distance))
                } else {
                    peersWithUWBDistanceOnly.append((peer, distance))
                }
            } else {
                peersWithoutData.append(peer)
            }
        }

        // Process LinkFinder precise peers
        for (peer, direction, distance) in peersWithUWBDirection {
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
        }

        // Process LinkFinder distance-only peers
        if !peersWithUWBDistanceOnly.isEmpty {
            let ringPositions = radarCalculator.calculateRingPositions(
                peersWithDistance: peersWithUWBDistanceOnly.map { (peer: $0.peer.displayName, distance: $0.distance) }
            )

            for (index, (peer, distance)) in peersWithUWBDistanceOnly.enumerated() {
                let ringData = ringPositions[index]
                data.append(PeerRadarData(
                    id: peer.displayName,
                    peer: peer.displayName,
                    position: .ring(distance: distance, x: ringData.position.x, y: ringData.position.y),
                    dataSource: .uwbDistance,
                    distance: distance
                ))
            }
        }

        // Peers without data
        for peer in peersWithoutData {
            data.append(PeerRadarData(
                id: peer.displayName,
                peer: peer.displayName,
                position: .unknown,
                dataSource: .none,
                distance: nil
            ))
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

    private func connectToPeer(_ peer: MCPeerID) {
        guard canConnectMore else { return }

        connectionManager.manuallyConnectPeer(peer)
        networkManager.connectToPeer(peer)

        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif

        // Switch to connected tab after connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation {
                selectedTab = .connected
            }
        }
    }

    private func disconnectPeer(_ peer: MCPeerID) {
        connectionManager.manuallyDisconnectPeer(peer)
        networkManager.disconnectFromPeer(peer)

        // Clear selection if this peer was selected
        if selectedPeer == peer.displayName {
            selectedPeer = nil
        }

        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        #endif
    }

    private func getUWBDistance(for peer: MCPeerID) -> String? {
        guard #available(iOS 14.0, *),
              let uwbManager = networkManager.uwbSessionManager,
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

    private func openMessagingFor(_ peer: MCPeerID) {
        // Close current view and open messaging
        dismiss()

        // Wait for dismiss animation to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // This will be handled by the parent view
            // For now, just open messaging dashboard
            showMessaging = true
        }
    }

    private func openMessaging() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showMessaging = true
        }
    }

    // MARK: - Mock Peer Management

    private func connectMockPeer(_ peer: MockPeer) {
        mockConnectionManager.connectMockPeer(peer)

        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif

        // Switch to connected tab after connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation {
                selectedTab = .connected
            }
        }
    }

    private func disconnectMockPeer(_ peer: MockPeer) {
        mockConnectionManager.disconnectMockPeer(peer)

        // Clear selection if this peer was selected
        if selectedPeer == peer.displayName {
            selectedPeer = nil
        }

        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        #endif
    }

    // MARK: - Radar Sweep Animation

    private func startRadarSweep() {
        LoggingService.network.info("🚀 STARTING RADAR SWEEP | Speed: \(sweepDetectionManager.sweepSpeed)s per rotation")

        // Invalidate any existing timer
        sweepTimer?.invalidate()

        // Calculate how much to increment angle per timer tick
        // sweepSpeed = 4 seconds per rotation
        // timerInterval = 0.05 seconds (20 FPS)
        // increment per tick = 360° / (sweepSpeed / timerInterval)
        let timerInterval: TimeInterval = 0.05
        let degreesPerTick = 360.0 / (sweepDetectionManager.sweepSpeed / timerInterval)

        LoggingService.network.info("⚙️ Timer interval: \(timerInterval)s | Degrees per tick: \(String(format: "%.2f", degreesPerTick))°")

        // Start timer to manually update sweep angle and detect peers
        sweepTimer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { [self] _ in
            // Increment sweep angle
            sweepAngle += degreesPerTick
            if sweepAngle >= 360 {
                sweepAngle = sweepAngle.truncatingRemainder(dividingBy: 360)
            }

            // Update peer detections with current angle
            updatePeerDetections()
            refreshCounter += 1
        }

        LoggingService.network.info("✅ Timer started successfully")
    }

    private func updatePeerDetections() {
        // Debug: LoggingService.network.info sweep angle occasionally
        if Int(sweepAngle) % 45 == 0 {
            LoggingService.network.info("🔄 Sweep at \(String(format: "%.1f", sweepAngle))° | Peers: \(peerRadarData.count)")
        }

        for radarData in peerRadarData {
            guard let angle = radarData.angle() else {
                LoggingService.network.info("⚠️ No angle for peer: \(radarData.id)")
                continue
            }

            sweepDetectionManager.checkDetection(
                peerId: radarData.id,
                peerAngle: angle,
                sweepAngle: sweepAngle
            )
        }
    }
}

// MARK: - Network Tab Enum
enum NetworkTab {
    case connected
    case available
}

// MARK: - Compact Peer Card
struct CompactPeerCard: View {
    let peer: MCPeerID
    let isConnected: Bool
    let isSelected: Bool
    let distance: String?
    let onTap: () -> Void
    let onAction: () -> Void
    let onMessage: (() -> Void)?

    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isConnected ? Mundial2026Colors.verde.opacity(0.2) : Mundial2026Colors.azul.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Image(systemName: "person.fill")
                        .font(.system(size: 18))
                        .foregroundColor(isConnected ? Mundial2026Colors.verde : Mundial2026Colors.azul)
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(peer.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(accessibleTheme.textPrimary)
                        .accessibleText()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(isConnected ? accessibleTheme.success : Color.orange)
                            .frame(width: 6, height: 6)

                        if let dist = distance {
                            Text(dist)
                                .font(.caption)
                                .foregroundColor(accessibleTheme.textSecondary)
                        } else {
                            Text(isConnected ? "Conectado" : "Disponible")
                                .font(.caption)
                                .foregroundColor(accessibleTheme.textSecondary)
                        }
                    }
                }

                Spacer()

                // Message button (only for connected peers)
                if isConnected, let messageAction = onMessage {
                    Button(action: messageAction) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Mundial2026Colors.azul)
                    }
                    .buttonStyle(.plain)
                }

                // Action button
                Button(action: onAction) {
                    Image(systemName: isConnected ? "xmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(isConnected ? Mundial2026Colors.rojo : Mundial2026Colors.verde)
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

// MARK: - Mock Peer Card
struct MockPeerCard: View {
    let mockPeer: MockPeer
    let isConnected: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onAction: () -> Void
    let onMessage: (() -> Void)?

    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isConnected ? Mundial2026Colors.verde.opacity(0.2) : Mundial2026Colors.azul.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Image(systemName: "person.fill")
                        .font(.system(size: 18))
                        .foregroundColor(isConnected ? Mundial2026Colors.verde : Mundial2026Colors.azul)
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(mockPeer.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(accessibleTheme.textPrimary)
                        .accessibleText()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(isConnected ? accessibleTheme.success : Color.orange)
                            .frame(width: 6, height: 6)

                        if let distance = mockPeer.distance {
                            Text(formatMockDistance(distance))
                                .font(.caption)
                                .foregroundColor(accessibleTheme.textSecondary)
                        } else {
                            Text(isConnected ? "Conectado" : "Disponible")
                                .font(.caption)
                                .foregroundColor(accessibleTheme.textSecondary)
                        }
                    }
                }

                Spacer()

                // Message button (only for connected mock peers)
                if isConnected, let messageAction = onMessage {
                    Button(action: messageAction) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Mundial2026Colors.azul)
                    }
                    .buttonStyle(.plain)
                }

                // Action button
                Button(action: onAction) {
                    Image(systemName: isConnected ? "xmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(isConnected ? Mundial2026Colors.rojo : Mundial2026Colors.verde)
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

    private func formatMockDistance(_ meters: Float) -> String {
        if meters < 1.0 {
            return String(format: "%.0fcm", meters * 100)
        } else if meters < 100 {
            return String(format: "%.1fm", meters)
        } else {
            return String(format: "%.0fm", meters)
        }
    }
}

// MARK: - Radar Sweep Animation
struct RadarSweepView: View {
    let radius: CGFloat
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // Sweep line (rotating)
            Path { path in
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: 0, y: -radius))
            }
            .stroke(
                LinearGradient(
                    colors: [
                        Color.green.opacity(0.8),
                        Color.green.opacity(0.3),
                        Color.green.opacity(0.0)
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                ),
                lineWidth: 2
            )
            .rotationEffect(.degrees(rotation))

            // Sweep gradient (pie shape)
            Circle()
                .trim(from: 0, to: 0.25) // 90 degree sweep
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color.green.opacity(0.0),
                            Color.green.opacity(0.15),
                            Color.green.opacity(0.3),
                            Color.green.opacity(0.0)
                        ]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(0)
                    ),
                    style: StrokeStyle(lineWidth: radius * 2, lineCap: .butt)
                )
                .frame(width: radius * 2, height: radius * 2)
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: radius * 2, height: radius * 2)
        .onAppear {
            withAnimation(
                Animation.linear(duration: 3.0)
                    .repeatForever(autoreverses: false)
            ) {
                rotation = 360
            }
        }
    }
}

// MARK: - Preview
#Preview {
    NetworkHubView()
        .environmentObject(NetworkManager())
}
