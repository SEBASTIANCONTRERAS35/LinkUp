//
//  NetworkRadarView.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Multi-peer radar visualization with LinkFinder directional positioning
//

import SwiftUI
import MultipeerConnectivity
import CoreLocation

// MARK: - Network Radar View
/// Radar display showing directional positions of all connected peers
struct NetworkRadarView: View {
    @EnvironmentObject var networkManager: NetworkManager
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme

    @StateObject private var radarCalculator = RadarCalculator()
    @StateObject private var uwbPriorityManager: LinkFinderPriorityManager

    @State private var radarMode: RadarMode = .hybrid
    @State private var selectedPeer: String? = nil
    @State private var showModeSelector = false

    // Constants
    private let radarRadius: CGFloat = 150.0
    private let rings = 3

    // Access LocationService through NetworkManager
    private var locationService: LocationService {
        networkManager.locationService
    }

    init() {
        // Initialize LinkFinderPriorityManager with 2 sessions (iPhone 11 conservative estimate)
        _uwbPriorityManager = StateObject(wrappedValue: LinkFinderPriorityManager(maxSessions: 2))
    }

    var body: some View {
        ZStack {
            // Background
            accessibleTheme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                radarHeader

                // Radar Display
                ZStack {
                    // Radar background with rings
                    radarBackground

                    // Compass directions (if absolute mode)
                    if effectiveRadarMode == .absolute {
                        compassDirections
                    }

                    // Center marker (you are here)
                    centerMarker

                    // Peer dots
                    ForEach(peerRadarData) { radarData in
                        if let position = radarData.position.point {
                            PeerRadarDot(
                                radarData: radarData,
                                isSelected: selectedPeer == radarData.peer,
                                onTap: {
                                    selectedPeer = (selectedPeer == radarData.peer) ? nil : radarData.peer
                                }
                            )
                            .offset(x: position.x, y: position.y)
                        }
                    }
                }
                .frame(width: radarRadius * 2.5, height: radarRadius * 2.5)
                .padding(.vertical, 20)

                // Legend
                dataSourceLegend

                Spacer()

                // Selected peer details
                if let peer = selectedPeer,
                   let radarData = peerRadarData.first(where: { $0.peer == peer }) {
                    selectedPeerCard(radarData)
                }
            }
        }
        .navigationTitle("Radar de Red")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showModeSelector.toggle() }) {
                    Image(systemName: effectiveRadarMode.icon)
                        .foregroundColor(accessibleTheme.primaryBlue)
                }
                .accessibleButton(minTouchTarget: 44)
                .accessibilityLabel("Change radar mode")
            }
        }
        .sheet(isPresented: $showModeSelector) {
            modeSelector
        }
        .onAppear {
            updatePriorities()
        }
        .onReceive(networkManager.$connectedPeers) { _ in
            updatePriorities()
        }
    }

    // MARK: - Subviews

    private var radarHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundColor(accessibleTheme.primaryBlue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Radar de Proximidad")
                        .font(.headline)
                        .foregroundColor(accessibleTheme.textPrimary)
                        .accessibleText()

                    Text("\(networkManager.connectedPeers.count) peers conectados")
                        .font(.caption)
                        .foregroundColor(accessibleTheme.textSecondary)
                }

                Spacer()

                // Mode indicator
                VStack(alignment: .trailing, spacing: 2) {
                    Text(effectiveRadarMode.displayName)
                        .font(.caption)
                        .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
                        .foregroundColor(accessibleTheme.primaryBlue)

                    Text(radarModeDescription)
                        .font(.caption2)
                        .foregroundColor(accessibleTheme.textSecondary)
                }
            }
            .padding(16)
            .background(accessibleTheme.cardBackground)
            .cornerRadius(16)
        }
        .padding(.horizontal)
        .padding(.top)
    }

    private var radarBackground: some View {
        ZStack {
            // Dark background
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.black.opacity(0.6),
                            Color.black.opacity(0.9)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: radarRadius
                    )
                )
                .frame(width: radarRadius * 2, height: radarRadius * 2)

            // Concentric rings
            ForEach(1...rings, id: \.self) { ring in
                Circle()
                    .stroke(
                        accessibleTheme.primaryGreen.opacity(0.2),
                        lineWidth: 1
                    )
                    .frame(
                        width: radarRadius * 2 * CGFloat(ring) / CGFloat(rings),
                        height: radarRadius * 2 * CGFloat(ring) / CGFloat(rings)
                    )
            }

            // Crosshairs
            Path { path in
                path.move(to: CGPoint(x: 0, y: -radarRadius))
                path.addLine(to: CGPoint(x: 0, y: radarRadius))
                path.move(to: CGPoint(x: -radarRadius, y: 0))
                path.addLine(to: CGPoint(x: radarRadius, y: 0))
            }
            .stroke(accessibleTheme.primaryGreen.opacity(0.2), lineWidth: 1)
        }
    }

    private var compassDirections: some View {
        ZStack {
            // North
            Text("N")
                .font(.caption)
                .fontWeight(accessibilitySettings.preferBoldText ? .heavy : .bold)
                .foregroundColor(.white)
                .accessibleText()
                .offset(y: -radarRadius - 20)

            // South
            Text("S")
                .font(.caption)
                .fontWeight(accessibilitySettings.preferBoldText ? .heavy : .bold)
                .foregroundColor(.white.opacity(0.6))
                .offset(y: radarRadius + 20)

            // East
            Text("E")
                .font(.caption)
                .fontWeight(accessibilitySettings.preferBoldText ? .heavy : .bold)
                .foregroundColor(.white.opacity(0.6))
                .offset(x: radarRadius + 20)

            // West
            Text("O")
                .font(.caption)
                .fontWeight(accessibilitySettings.preferBoldText ? .heavy : .bold)
                .foregroundColor(.white.opacity(0.6))
                .offset(x: -radarRadius - 20)
        }
    }

    private var centerMarker: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)

            Circle()
                .stroke(accessibleTheme.primaryBlue, lineWidth: 3)
                .frame(width: 16, height: 16)

            Text("TÚ")
                .font(.caption2)
                .fontWeight(accessibilitySettings.preferBoldText ? .heavy : .bold)
                .foregroundColor(.white)
                .accessibleText()
                .offset(y: 20)
        }
        .accessibilityLabel("Your position at center of radar")
    }

    private var dataSourceLegend: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fuentes de Datos")
                .font(.caption)
                .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
                .foregroundColor(accessibleTheme.textSecondary)
                .accessibleText()

            HStack(spacing: 20) {
                legendItem(
                    color: accessibleTheme.primaryGreen,
                    label: "LinkFinder Preciso",
                    icon: "dot.radiowaves.left.and.right"
                )

                legendItem(
                    color: accessibleTheme.warning,
                    label: "LinkFinder Distancia",
                    icon: "circle.dotted"
                )

                legendItem(
                    color: accessibleTheme.primaryBlue,
                    label: "GPS",
                    icon: "location.fill"
                )

                legendItem(
                    color: accessibleTheme.textSecondary,
                    label: "Sin datos",
                    icon: "questionmark.circle"
                )
            }
        }
        .padding(16)
        .background(accessibleTheme.cardBackground)
        .cornerRadius(16)
        .padding(.horizontal)
    }

    private func legendItem(color: Color, label: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)

            Text(label)
                .font(.caption2)
                .foregroundColor(accessibleTheme.textSecondary)
        }
    }

    private func selectedPeerCard(_ radarData: PeerRadarData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(radarData.peer)
                        .font(.headline)
                        .foregroundColor(accessibleTheme.textPrimary)
                        .accessibleText()

                    HStack(spacing: 8) {
                        Image(systemName: radarData.dataSource == .uwbPrecise ? "dot.radiowaves.left.and.right" : "location.fill")
                            .font(.caption)
                            .foregroundColor(radarData.dataSource.color)

                        Text(radarData.dataSource.displayName)
                            .font(.caption)
                            .foregroundColor(accessibleTheme.textSecondary)
                    }
                }

                Spacer()

                Button(action: { selectedPeer = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(accessibleTheme.textSecondary)
                        .font(.title3)
                }
                .accessibleButton(minTouchTarget: 44)
                .accessibilityLabel("Close peer details")
            }

            if let distance = radarData.distance {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.and.right")
                        .font(.caption)
                        .foregroundColor(accessibleTheme.primaryBlue)

                    Text("Distancia: \(radarCalculator.distanceString(for: distance))")
                        .font(.subheadline)
                        .foregroundColor(accessibleTheme.textPrimary)
                }
            }
        }
        .padding(16)
        .background(accessibleTheme.cardBackground)
        .cornerRadius(16)
        .accessibleShadow(color: accessibleTheme.textPrimary, radius: 8)
        .padding(.horizontal)
        .padding(.bottom)
        .transition(.move(edge: .bottom))
        .animation(.spring(), value: selectedPeer)
    }

    private var modeSelector: some View {
        NavigationView {
            List {
                ForEach([RadarMode.absolute, .relative, .hybrid], id: \.self) { mode in
                    Button(action: {
                        radarMode = mode
                        showModeSelector = false
                    }) {
                        HStack {
                            Image(systemName: mode.icon)
                                .foregroundColor(accessibleTheme.primaryBlue)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(mode.displayName)
                                    .font(.body)
                                    .foregroundColor(accessibleTheme.textPrimary)
                                    .accessibleText()

                                Text(modeDescription(for: mode))
                                    .font(.caption)
                                    .foregroundColor(accessibleTheme.textSecondary)
                            }

                            Spacer()

                            if radarMode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundColor(accessibleTheme.primaryGreen)
                            }
                        }
                    }
                    .accessibleButton(minTouchTarget: 44)
                }
            }
            .navigationTitle("Modo de Radar")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Computed Properties

    /// Effective radar mode (hybrid auto-selects based on compass availability)
    private var effectiveRadarMode: RadarMode {
        if radarMode == .hybrid {
            return locationService.currentHeading != nil ? .absolute : .relative
        }
        return radarMode
    }

    private var radarModeDescription: String {
        switch effectiveRadarMode {
        case .absolute: return "Fijo al norte"
        case .relative: return "Relativo a ti"
        case .hybrid: return "Automático"
        }
    }

    private func modeDescription(for mode: RadarMode) -> String {
        switch mode {
        case .absolute: return "Orientación fija respecto al norte geográfico"
        case .relative: return "Orientación relativa a tu dispositivo"
        case .hybrid: return "Automático según disponibilidad de brújula"
        }
    }

    /// Build radar data for all connected peers
    private var peerRadarData: [PeerRadarData] {
        var data: [PeerRadarData] = []

        // Get current user location and heading
        let userLocation = locationService.currentLocation
        let deviceHeading = locationService.currentHeading?.trueHeading ?? locationService.currentHeading?.magneticHeading

        // Separate peers by data availability
        var peersWithUWBDirection: [(peer: MCPeerID, direction: SIMD3<Float>, distance: Float)] = []
        var peersWithUWBDistanceOnly: [(peer: MCPeerID, distance: Float)] = []
        var peersWithoutData: [MCPeerID] = []

        // Check if LinkFinder is available
        guard #available(iOS 14.0, *),
              let uwbManager = networkManager.uwbSessionManager else {
            // No LinkFinder support - all peers without data
            return networkManager.connectedPeers.map { peer in
                PeerRadarData(
                    id: peer.displayName,
                    peer: peer.displayName,
                    position: .unknown,
                    dataSource: .none,
                    distance: nil
                )
            }
        }

        for peer in networkManager.connectedPeers {
            let peerId = peer.displayName

            // Check LinkFinder data
            if let distance = uwbManager.getDistance(to: peer) {
                if let direction = uwbManager.getDirection(to: peer),
                   uwbPriorityManager.shouldTrackDirection(for: peerId) {
                    // LinkFinder with direction (prioritized peer)
                    peersWithUWBDirection.append((peer, direction, distance))
                } else {
                    // LinkFinder distance only
                    peersWithUWBDistanceOnly.append((peer, distance))
                }
            } else {
                // No location data
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

        // Process LinkFinder distance-only peers (ring distribution)
        if !peersWithUWBDistanceOnly.isEmpty {
            let ringPositions = radarCalculator.calculateRingPositions(
                peersWithDistance: peersWithUWBDistanceOnly.map { (peer: $0.peer.displayName, distance: $0.distance) }
            )

            for (index, (peer, _)) in peersWithUWBDistanceOnly.enumerated() {
                let ringData = ringPositions[index]
                data.append(PeerRadarData(
                    id: peer.displayName,
                    peer: peer.displayName,
                    position: .ring(distance: ringData.peer == peer.displayName ? peersWithUWBDistanceOnly[index].distance : 0, x: ringData.position.x, y: ringData.position.y),
                    dataSource: .uwbDistance,
                    distance: peersWithUWBDistanceOnly[index].distance
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

    private func updatePriorities() {
        // Build distance map from LinkFinder if available
        var peerDistances: [String: Float] = [:]

        if #available(iOS 14.0, *), let uwbManager = networkManager.uwbSessionManager {
            for peer in networkManager.connectedPeers {
                if let distance = uwbManager.getDistance(to: peer) {
                    peerDistances[peer.displayName] = distance
                }
            }
        }

        uwbPriorityManager.updatePriorities(
            for: networkManager.connectedPeers,
            peerDistances: peerDistances,
            userLocation: locationService.currentLocation
        )
    }
}

// MARK: - Preview
#if DEBUG
struct NetworkRadarView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            NetworkRadarView()
                .environmentObject(NetworkManager())
        }
    }
}
#endif
