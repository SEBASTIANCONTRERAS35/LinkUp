//
//  LinkFinderNavigationView.swift
//  MeshRed
//
//  Created by Emilio Contreras on 29/09/25.
//

import SwiftUI
import MultipeerConnectivity

/// Vista de navegación LinkFinder híbrida con 4 niveles de fallback
/// Nivel 1: LinkFinder Direction precisa (SIMD3)
/// Nivel 2: GPS + Compass (cuando peer comparte ubicación)
/// Nivel 3: Radar circular (solo LinkFinder distance)
/// Nivel 4: Walking Triangulation (modo interactivo)
struct LinkFinderNavigationView: View {
    let targetName: String
    let targetPeerID: MCPeerID
    @ObservedObject var uwbManager: LinkFinderSessionManager
    @ObservedObject var locationService: LocationService
    @ObservedObject var peerLocationTracker: PeerLocationTracker
    @ObservedObject var networkManager: NetworkManager
    let onDismiss: () -> Void

    // State for triangulation mode
    @State private var isTriangulationMode: Bool = false
    @State private var forceArrowNavigation: Bool = false

    // Proximity haptic engine for navigation feedback
    @State private var proximityEngine = ProximityHapticEngine()

    // Computed properties que se actualizan automáticamente desde LinkFinder
    private var distance: Float? {
        let dist = uwbManager.getDistance(to: targetPeerID)
        print("🔍 LinkFinderNavigationView: Getting distance for \(targetPeerID.displayName) = \(dist?.description ?? "nil")")
        return dist
    }

    private var direction: DirectionVector? {
        if let simd = uwbManager.getDirection(to: targetPeerID) {
            let dirVector = DirectionVector(from: simd)
            print("🔍 LinkFinderNavigationView: Getting direction for \(targetPeerID.displayName)")
            print("   SIMD: x=\(simd.x), y=\(simd.y), z=\(simd.z)")
            print("   DirectionVector created: x=\(dirVector.x), y=\(dirVector.y), z=\(dirVector.z)")
            return dirVector
        }
        print("⚠️ LinkFinderNavigationView: No direction available for \(targetPeerID.displayName)")
        return nil
    }

    private var supportsDirectionMeasurement: Bool {
        uwbManager.supportsDirectionMeasurement
    }

    private var peerLocation: UserLocation? {
        peerLocationTracker.getPeerLocation(peerID: targetPeerID.displayName)
    }

    private var userHeading: Double? {
        locationService.headingValue
    }

    private var userLocation: UserLocation? {
        locationService.currentLocation
    }

    // Estimated distance when LinkFinder unavailable
    private var estimatedDistance: Float? {
        // Priority 1: LinkFinder distance (most accurate)
        if let uwbDist = distance {
            return uwbDist
        }

        // Priority 2: GPS distance
        if let myLoc = userLocation, let peerLoc = peerLocation {
            return calculateGPSDistance(from: myLoc, to: peerLoc)
        }

        return nil
    }

    // Determine distance source for display
    private var distanceSource: DistanceOnlyNavigationView.DistanceSource {
        if distance != nil {
            return .gps // Actually LinkFinder, but won't reach level5 in this case
        }

        if userLocation != nil && peerLocation != nil {
            return .gps
        }

        return .none
    }

    // Navigation level detection
    private enum NavigationLevel {
        case level0_radar           // PRIORITY: Radar view for peer tracking
        case level1_uwbPrecise      // LinkFinder direction available (arrow)
        case level2_gpsCompass      // GPS + Compass available
        case level3_radar           // Deprecated - use level0 instead
        case level4_triangulation   // Walking triangulation mode
        case level5_estimatedDistance // LinkFinder unavailable, show estimated distance only
        case loading                // Waiting for data
    }

    private var currentNavigationLevel: NavigationLevel {
        // Level 4: User activated triangulation mode
        if isTriangulationMode {
            return .level4_triangulation
        }

        // If user manually switched to arrow navigation
        if forceArrowNavigation {
            if direction != nil {
                return .level1_uwbPrecise
            } else if let _ = peerLocation, let _ = userLocation, let _ = userHeading {
                return .level2_gpsCompass
            }
            // If forced arrow but no data, fall back to radar
            forceArrowNavigation = false
        }

        // Check if we have LinkFinder distance
        guard distance != nil else {
            // No LinkFinder available - check if we can provide estimated distance
            if estimatedDistance != nil {
                return .level5_estimatedDistance
            }
            return .loading
        }

        // Check if we have direction (precise LinkFinder)
        if direction != nil {
            // PRIORITY: Level 0 - Show radar view ONLY when direction is available
            return .level0_radar
        }

        // If only distance (no direction), show distance-only view
        return .level5_estimatedDistance
    }

    var body: some View {
        ZStack {
            // Route to appropriate view based on navigation level
            switch currentNavigationLevel {
            case .level0_radar:
                level0RadarView

            case .level1_uwbPrecise:
                level1UWBPreciseView

            case .level2_gpsCompass:
                level2GPSCompassView

            case .level3_radar:
                level3RadarView

            case .level4_triangulation:
                level4TriangulationView

            case .level5_estimatedDistance:
                level5EstimatedDistanceView

            case .loading:
                loadingView
            }
        }
        .onAppear {
            // Start heading monitoring when navigation view appears
            if locationService.isHeadingAvailable {
                locationService.startMonitoringHeading()
            }

            // Start GPS location sharing with target peer
            networkManager.startSharingLocationWithPeer(peerID: targetPeerID.displayName)

            // Start location monitoring if not already active
            if !locationService.isMonitoring {
                locationService.startMonitoring()
            }

            // Start proximity haptic feedback
            proximityEngine.start()
            print("🎯 LinkFinderNavigationView: Started proximity haptic engine")
        }
        .onDisappear {
            // Stop GPS location sharing when navigation ends
            networkManager.stopSharingLocationWithPeer(peerID: targetPeerID.displayName)

            // Stop heading monitoring
            locationService.stopMonitoringHeading()

            // Stop proximity haptic feedback
            proximityEngine.stop()
            print("🎯 LinkFinderNavigationView: Stopped proximity haptic engine")
        }
        .onChange(of: distance) { newDistance in
            // Update proximity engine when distance changes
            if let dist = newDistance {
                proximityEngine.updateProximity(distance: dist, direction: uwbManager.getDirection(to: targetPeerID))
            }
        }
        .onChange(of: direction) { newDirection in
            // Update bearing if we have direction + user heading
            if newDirection != nil, let heading = userHeading, let userLoc = userLocation, let peerLoc = peerLocation {
                let relativeBearing = NavigationCalculator.calculateRelativeBearing(
                    from: userLoc,
                    to: peerLoc,
                    userHeading: heading
                )
                proximityEngine.updateBearing(relative: relativeBearing)
            }
        }
    }

    // MARK: - Level 0: Radar View (Priority)

    private var level0RadarView: some View {
        SinglePeerRadarView(
            targetName: targetName,
            targetPeerID: targetPeerID,
            uwbManager: uwbManager,
            locationService: locationService,
            peerLocationTracker: peerLocationTracker,
            networkManager: networkManager,
            onDismiss: onDismiss,
            onSwitchToArrowNavigation: {
                // User wants to switch to arrow navigation
                withAnimation {
                    forceArrowNavigation = true
                }
            }
        )
    }

    // MARK: - Level 1: LinkFinder Precise Direction

    private var level1UWBPreciseView: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                // Header
                VStack(spacing: 8) {
                    Text("Navegando hacia")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))

                    Text(targetName)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                }

                // Distance
                if let dist = distance {
                    VStack(spacing: 4) {
                        Text(distanceString(for: dist))
                            .font(.system(size: 56, weight: .heavy, design: .rounded))
                            .foregroundColor(.cyan)

                        Text("de distancia")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding()
                }

                // Directional arrow
                if let dir = direction, let dist = distance {
                    DirectionalArrow(direction: dir, distance: dist)
                        .frame(width: 250, height: 250)

                    // Direction info
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "safari")
                                .font(.title3)
                            Text("\(Int(dir.bearing))° (\(dir.cardinalDirection))")
                                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        }
                        .foregroundColor(.green)

                        Text("Dirección precisa LinkFinder")
                            .font(.caption)
                            .foregroundColor(.green.opacity(0.8))

                        if dist < 2.0 {
                            Text("¡Muy cerca!")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.yellow)
                                .padding(.top, 8)
                        }
                    }
                }

                Spacer()

                // Close button
                Button(action: onDismiss) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("Cerrar Navegación")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.red)
                    .cornerRadius(12)
                }
                .padding(.bottom, 40)
            }
            .padding()
        }
    }

    // MARK: - Level 2: GPS + Compass

    private var level2GPSCompassView: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                // Header
                VStack(spacing: 8) {
                    Text("Navegando hacia")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))

                    Text(targetName)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                }

                // Distance
                if let dist = distance {
                    VStack(spacing: 4) {
                        Text(distanceString(for: dist))
                            .font(.system(size: 56, weight: .heavy, design: .rounded))
                            .foregroundColor(.cyan)

                        Text("distancia LinkFinder")
                            .font(.caption)
                            .foregroundColor(.cyan.opacity(0.7))
                    }
                    .padding()
                }

                // GPS Navigation View
                if let userLoc = userLocation,
                   let peerLoc = peerLocation,
                   let heading = userHeading,
                   let dist = distance {
                    GPSNavigationView(
                        targetName: targetName,
                        userLocation: userLoc,
                        targetLocation: peerLoc,
                        userHeading: heading,
                        distance: dist
                    )

                    // GPS Navigation Info
                    GPSNavigationInfo(
                        targetName: targetName,
                        relativeBearing: NavigationCalculator.calculateRelativeBearing(
                            from: userLoc,
                            to: peerLoc,
                            userHeading: heading
                        ),
                        gpsDistance: userLoc.distance(to: peerLoc),
                        uwbDistance: dist,
                        targetAccuracy: peerLoc.accuracy,
                        onDismiss: onDismiss
                    )
                }

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Level 3: Radar

    private var level3RadarView: some View {
        Group {
            if let dist = distance {
                RadarNavigationView(
                    targetName: targetName,
                    distance: dist,
                    onDismiss: onDismiss,
                    onStartTriangulation: {
                        isTriangulationMode = true
                    }
                )
            }
        }
    }

    // MARK: - Level 4: Walking Triangulation

    private var level4TriangulationView: some View {
        WalkingTriangulationView(
            targetName: targetName,
            targetPeerID: targetPeerID,
            uwbManager: uwbManager,
            locationService: locationService,
            onDismiss: {
                isTriangulationMode = false
                onDismiss()
            },
            onDirectionCalculated: { bearing in
                // Direction calculated! Could transition to showing arrow
                print("✅ Triangulation complete: \(bearing)°")
                // For now, just exit triangulation mode
                isTriangulationMode = false
            }
        )
    }

    // MARK: - Level 5: Estimated Distance Only

    private var level5EstimatedDistanceView: some View {
        DistanceOnlyNavigationView(
            targetName: targetName,
            estimatedDistance: estimatedDistance,
            distanceSource: distanceSource,
            onDismiss: onDismiss
        )
    }

    // MARK: - Loading View

    private var loadingView: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                Text("Navegando hacia")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))

                Text(targetName)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                ProgressView()
                    .scaleEffect(2.0)
                    .tint(.cyan)
                    .padding()

                Text("Estableciendo ranging LinkFinder...")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                Button(action: onDismiss) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("Cancelar")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.red)
                    .cornerRadius(12)
                }
                .padding(.bottom, 40)
            }
            .padding()
        }
    }

    private func distanceString(for dist: Float) -> String {
        if dist < 1.0 {
            return String(format: "%.0fcm", dist * 100)
        } else {
            return String(format: "%.1fm", dist)
        }
    }

    // Calculate GPS distance using Haversine formula
    private func calculateGPSDistance(from: UserLocation, to: UserLocation) -> Float {
        let earthRadiusMeters: Double = 6371000.0

        // Convert to radians
        let lat1 = from.latitude * .pi / 180.0
        let lon1 = from.longitude * .pi / 180.0
        let lat2 = to.latitude * .pi / 180.0
        let lon2 = to.longitude * .pi / 180.0

        // Haversine formula
        let dLat = lat2 - lat1
        let dLon = lon2 - lon1

        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1) * cos(lat2) *
                sin(dLon / 2) * sin(dLon / 2)

        let c = 2 * atan2(sqrt(a), sqrt(1 - a))

        let distanceMeters = earthRadiusMeters * c

        return Float(distanceMeters)
    }
}

/// Flecha direccional animada que apunta hacia el objetivo
struct DirectionalArrow: View {
    let direction: DirectionVector
    let distance: Float

    @State private var isAnimating = false

    init(direction: DirectionVector, distance: Float) {
        self.direction = direction
        self.distance = distance

        // 🔍 DEBUG: Log when arrow is initialized/updated
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🎯 DIRECTIONAL ARROW UPDATE")
        print("   Direction: x=\(direction.x), y=\(direction.y), z=\(direction.z)")
        print("   Distance: \(distance)m")
        print("   Bearing will be: \(direction.bearing)°")
        print("   Rotation effect: \(-direction.bearing)°")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    var body: some View {
        ZStack {
            // Círculo de fondo
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.appSecondary.opacity(0.3),
                            Color.appSecondary.opacity(0.1),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 20,
                        endRadius: 125
                    )
                )
                .scaleEffect(isAnimating ? 1.1 : 1.0)
                .animation(
                    Animation.easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: true),
                    value: isAnimating
                )

            // Anillo exterior
            Circle()
                .stroke(Color.appSecondary.opacity(0.3), lineWidth: 2)
                .frame(width: 220, height: 220)

            // Marcadores cardinales
            CardinalMarkers()

            // Flecha principal
            VStack(spacing: 0) {
                // Punta de la flecha
                Triangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.appSecondary, Color.appPrimary]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 40, height: 50)
                    .shadow(color: Color.appSecondary, radius: 10, x: 0, y: 0)

                // Cuerpo de la flecha
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.appPrimary, Color.appSecondary]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 20, height: 60)
                    .shadow(color: Color.appSecondary, radius: 10, x: 0, y: 0)
            }
            .rotationEffect(.degrees(-direction.bearing)) // Rotar según bearing
            .scaleEffect(isAnimating ? 1.15 : 1.0)
            .animation(
                Animation.easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )

            // Punto central
            Circle()
                .fill(Color.white)
                .frame(width: 16, height: 16)
                .overlay(
                    Circle()
                        .stroke(Color.appSecondary, lineWidth: 2)
                )
        }
        .onAppear {
            isAnimating = true
        }
    }
}

/// Marcadores de direcciones cardinales
struct CardinalMarkers: View {
    let markers = [
        (label: "N", angle: 0.0),
        (label: "E", angle: 90.0),
        (label: "S", angle: 180.0),
        (label: "W", angle: 270.0)
    ]

    var body: some View {
        ZStack {
            ForEach(markers, id: \.label) { marker in
                Text(marker.label)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .offset(y: -110) // Radio desde el centro
                    .rotationEffect(.degrees(marker.angle))
            }
        }
    }
}

/// Triángulo para la punta de la flecha
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Círculo pulsante cuando no hay dirección disponible
struct PulsingCircle: View {
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Ondas expansivas
            ForEach(0..<3) { index in
                Circle()
                    .stroke(Color.appSecondary.opacity(0.4), lineWidth: 3)
                    .scaleEffect(isPulsing ? 1.5 : 0.3)
                    .opacity(isPulsing ? 0.0 : 1.0)
                    .animation(
                        Animation.easeOut(duration: 2.0)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.6),
                        value: isPulsing
                    )
            }

            // Círculo central
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [Color.appSecondary, Color.appPrimary]),
                        center: .center,
                        startRadius: 20,
                        endRadius: 80
                    )
                )
                .frame(width: 100, height: 100)
                .overlay(
                    Image(systemName: "location.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                )
        }
        .onAppear {
            isPulsing = true
        }
    }
}

// MARK: - Preview
#Preview {
    // Mock managers for preview
    let mockUWBManager = LinkFinderSessionManager()
    let mockLocationService = LocationService()
    let mockPeerTracker = PeerLocationTracker()
    let mockNetworkManager = NetworkManager()
    let mockPeer = MCPeerID(displayName: "José Guadalupe")

    LinkFinderNavigationView(
        targetName: "José Guadalupe",
        targetPeerID: mockPeer,
        uwbManager: mockUWBManager,
        locationService: mockLocationService,
        peerLocationTracker: mockPeerTracker,
        networkManager: mockNetworkManager,
        onDismiss: {}
    )
}