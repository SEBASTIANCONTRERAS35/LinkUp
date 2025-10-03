//
//  SinglePeerRadarView.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Radar view for tracking a single peer with LinkFinder
//  Design matches NetworkHubView but optimized for single target
//

import SwiftUI
import MultipeerConnectivity
import CoreLocation

struct SinglePeerRadarView: View {
    let targetName: String
    let targetPeerID: MCPeerID
    @ObservedObject var uwbManager: LinkFinderSessionManager
    @ObservedObject var locationService: LocationService
    @ObservedObject var peerLocationTracker: PeerLocationTracker
    @ObservedObject var networkManager: NetworkManager
    let onDismiss: () -> Void
    let onSwitchToArrowNavigation: () -> Void

    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme

    @State private var radarMode: RadarMode = .hybrid
    @State private var sweepAngle: Double = 0
    @State private var sweepTimer: Timer?
    @State private var refreshCounter = 0
    @StateObject private var radarCalculator = RadarCalculator()
    @StateObject private var sweepDetectionManager = RadarSweepDetectionManager()

    private let radarRadius: CGFloat = 140.0

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                headerSection

                // Radar section (340px height like NetworkHubView)
                radarSection
                    .frame(height: 340)
                    .background(colorScheme == .dark ? Color.black.opacity(0.95) : Color(UIColor.systemBackground))

                // Peer info section (scrollable)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        peerInfoSection

                        // Extra spacing for bottom
                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            .background(accessibleTheme.background.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .onAppear {
            startRadarSweep()
        }
        .onDisappear {
            sweepTimer?.invalidate()
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            // Top bar
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: accessibilitySettings.preferBoldText ? .bold : .semibold))
                        .foregroundColor(accessibleTheme.primaryBlue)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibleButton(minTouchTarget: 44)
                .accessibilityLabel("Cerrar")

                Spacer()

                VStack(spacing: 2) {
                    Text("Rastreando a")
                        .font(.caption)
                        .foregroundColor(accessibleTheme.textSecondary)

                    Text(targetName)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(accessibleTheme.textPrimary)
                        .accessibleText()
                }

                Spacer()

                Button(action: toggleRadarMode) {
                    Image(systemName: radarMode.icon)
                        .font(.system(size: 18, weight: accessibilitySettings.preferBoldText ? .bold : .semibold))
                        .foregroundColor(accessibleTheme.primaryBlue)
                        .frame(width: 44, height: 44)
                }
                .accessibleButton(minTouchTarget: 44)
                .accessibilityLabel("Cambiar modo radar")
            }

            // Status indicator
            HStack(spacing: 12) {
                // Status icon
                Circle()
                    .fill(peerInfo.dataSource == .uwbPrecise || peerInfo.dataSource == .uwbDistance ?
                        Mundial2026Colors.azul : .orange)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(peerInfo.dataSource.displayName)
                        .font(.subheadline)
                        .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
                        .foregroundColor(accessibleTheme.textPrimary)

                    if let dist = peerInfo.distance {
                        Text(peerInfo.formattedDistance())
                            .font(.caption)
                            .foregroundColor(accessibleTheme.textSecondary)
                    }
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
        ZStack {
            // Radar background
            radarBackground

            // Radar sweep line
            RadarSweepLine(radius: radarRadius, sweepAngle: $sweepAngle)

            // Compass directions (if absolute mode)
            if effectiveRadarMode == .absolute {
                compassDirections
            }

            // Center marker
            centerMarker

            // Peer dot
            if let radarData = peerRadarData.first,
               let position = radarData.position.point {
                PeerRadarDot(
                    radarData: radarData,
                    isSelected: true,  // Always selected since it's the only one
                    onTap: {}  // No action needed
                )
                .offset(x: position.x, y: position.y)
                .opacity(1.0)  // Always visible
                .id("\(radarData.id)-\(refreshCounter)")
            }

            // Data source badge (bottom right)
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
    }

    private var radarBackground: some View {
        ZStack {
            // Adaptive background
            (colorScheme == .dark ? Color.black.opacity(0.95) : Color(UIColor.systemBackground))

            // Radar circles with blue gradient
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

            // Concentric rings
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

            // Crosshairs
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
                .fill(peerInfo.dataSource.color)
                .frame(width: 6, height: 6)

            Text(peerInfo.dataSource.displayName)
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

    // MARK: - Peer Info Section
    private var peerInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Detalles del Rastreo")
                .font(.headline)
                .foregroundColor(accessibleTheme.textPrimary)
                .accessibleText()

            VStack(spacing: 12) {
                // Distance
                if peerInfo.distance != nil {
                    InfoRow(
                        icon: "ruler",
                        label: "Distancia",
                        value: peerInfo.formattedDistance(),
                        color: Mundial2026Colors.azul
                    )
                    .environmentObject(accessibilitySettings)
                }

                // Data source
                InfoRow(
                    icon: peerInfo.dataSource.icon,
                    label: "Fuente de datos",
                    value: peerInfo.dataSource.displayName,
                    color: peerInfo.dataSource.color
                )
                .environmentObject(accessibilitySettings)

                // Last update
                InfoRow(
                    icon: "clock",
                    label: "Última actualización",
                    value: peerInfo.timeSinceUpdate(),
                    color: .gray
                )
                .environmentObject(accessibilitySettings)

                // Signal quality (if LinkFinder)
                if let quality = peerInfo.signalQuality {
                    SignalQualityBar(quality: quality)
                        .environmentObject(accessibilitySettings)
                }
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(16)
            .accessibleShadow(color: .black, radius: 4)

            // Action buttons
            VStack(spacing: 12) {
                // Switch to arrow navigation (if direction available)
                if peerInfo.hasDirection {
                    Button(action: onSwitchToArrowNavigation) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 20))
                            Text("Cambiar a Navegación por Flecha")
                                .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Mundial2026Colors.azul)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .accessibleButton(minTouchTarget: 44)
                }

                // Send message
                Button(action: {
                    onDismiss()
                    // Parent will handle opening messaging
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 20))
                        Text("Enviar Mensaje")
                            .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Mundial2026Colors.verde)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .accessibleButton(minTouchTarget: 44)
            }
        }
    }

    // MARK: - Computed Properties

    private var effectiveRadarMode: RadarMode {
        if radarMode == .hybrid {
            return locationService.currentHeading != nil ? .absolute : .relative
        }
        return radarMode
    }

    /// Build radar data for the target peer
    private var peerRadarData: [PeerRadarData] {
        guard let distance = uwbManager.getDistance(to: targetPeerID) else {
            return []
        }

        let deviceHeading = locationService.currentHeading?.trueHeading ?? locationService.currentHeading?.magneticHeading

        if let direction = uwbManager.getDirection(to: targetPeerID) {
            // Precise direction available
            let directionVector = DirectionVector(from: direction)
            let position = radarCalculator.calculatePrecisePosition(
                direction: directionVector,
                distance: distance,
                deviceHeading: deviceHeading,
                mode: effectiveRadarMode
            )

            return [PeerRadarData(
                id: targetPeerID.displayName,
                peer: targetPeerID.displayName,
                position: .exact(x: position.x, y: position.y),
                dataSource: .uwbPrecise,
                distance: distance
            )]
        } else {
            // Distance only
            let ringPositions = radarCalculator.calculateRingPositions(
                peersWithDistance: [(peer: targetPeerID.displayName, distance: distance)]
            )

            if let ringData = ringPositions.first {
                return [PeerRadarData(
                    id: targetPeerID.displayName,
                    peer: targetPeerID.displayName,
                    position: .ring(distance: distance, x: ringData.position.x, y: ringData.position.y),
                    dataSource: .uwbDistance,
                    distance: distance
                )]
            }
        }

        return []
    }

    /// Get tracking info for the peer
    private var peerInfo: PeerTrackingInfo {
        let distance = uwbManager.getDistance(to: targetPeerID)
        let hasDirection = uwbManager.getDirection(to: targetPeerID) != nil

        let dataSource: PeerTrackingInfo.TrackingDataSource
        if hasDirection {
            dataSource = .uwbPrecise
        } else if distance != nil {
            dataSource = .uwbDistance
        } else if peerLocationTracker.getPeerLocation(peerID: targetPeerID.displayName) != nil {
            dataSource = .gps
        } else {
            dataSource = .none
        }

        // Calculate signal quality (simplified - based on distance)
        let signalQuality: Float?
        if let dist = distance {
            // Closer = better quality (max 10m = 100%, 30m = 0%)
            signalQuality = max(0.0, min(1.0, (30.0 - dist) / 30.0))
        } else {
            signalQuality = nil
        }

        return PeerTrackingInfo(
            distance: distance,
            hasDirection: hasDirection,
            dataSource: dataSource,
            lastUpdate: Date(),  // TODO: Get actual last update from UWBSessionManager
            signalQuality: signalQuality
        )
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

    private func startRadarSweep() {
        print("🚀 STARTING SINGLE PEER RADAR SWEEP")

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

// MARK: - Preview
#Preview {
    let mockUWBManager = LinkFinderSessionManager()
    let mockLocationService = LocationService()
    let mockPeerTracker = PeerLocationTracker()
    let mockNetworkManager = NetworkManager()
    let mockPeer = MCPeerID(displayName: "Ana García")

    SinglePeerRadarView(
        targetName: "Ana García",
        targetPeerID: mockPeer,
        uwbManager: mockUWBManager,
        locationService: mockLocationService,
        peerLocationTracker: mockPeerTracker,
        networkManager: mockNetworkManager,
        onDismiss: {},
        onSwitchToArrowNavigation: {}
    )
    .environmentObject(AccessibilitySettingsManager())
}
