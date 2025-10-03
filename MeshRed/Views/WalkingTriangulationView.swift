//
//  WalkingTriangulationView.swift
//  MeshRed
//
//  Created by Emilio Contreras on 30/09/25.
//

import SwiftUI
import CoreLocation
import MultipeerConnectivity

/// Interactive walking triangulation wizard (Nivel 4)
/// Guides user through taking two distance readings to calculate precise direction
/// Uses circle-circle intersection geometry with LinkFinder distance measurements
struct WalkingTriangulationView: View {
    let targetName: String
    let targetPeerID: MCPeerID
    @ObservedObject var uwbManager: LinkFinderSessionManager
    @ObservedObject var locationService: LocationService

    let onDismiss: () -> Void
    let onDirectionCalculated: (Double) -> Void  // Callback with calculated bearing

    // MARK: - State Management

    enum TriangulationStep {
        case instructions       // Show initial instructions
        case reading1           // Taking first reading
        case walking            // User walking to second position
        case reading2           // Taking second reading
        case calculating        // Calculating intersection
        case result             // Show calculated direction
        case error(String)      // Error state with message
    }

    @State private var currentStep: TriangulationStep = .instructions
    @State private var reading1: NavigationCalculator.TriangulationReading?
    @State private var reading2: NavigationCalculator.TriangulationReading?
    @State private var calculatedDirection: Double?  // Bearing in degrees
    @State private var distanceWalked: Double = 0.0

    // MARK: - Computed Properties

    private var currentDistance: Float? {
        uwbManager.getDistance(to: targetPeerID)
    }

    private var canTakeReading: Bool {
        locationService.currentLocation != nil && currentDistance != nil
    }

    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.9)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView
                    .padding(.top, 40)

                Spacer()

                // Step content
                stepContentView
                    .padding(.horizontal, 20)

                Spacer()

                // Action buttons
                actionButtonsView
                    .padding(.bottom, 40)
            }
        }
        .onAppear {
            // Start monitoring location and heading for triangulation
            locationService.startMonitoring()
            locationService.startMonitoringHeading()
        }
        .onDisappear {
            // Can optionally stop monitoring to save battery
            // locationService.stopMonitoring()
            // locationService.stopMonitoringHeading()
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        VStack(spacing: 8) {
            Text("Búsqueda Guiada")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text(targetName)
                .font(.title2)
                .foregroundColor(.cyan)

            if let dist = currentDistance {
                Text("\(String(format: "%.1f", dist))m de distancia")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Step Content View

    @ViewBuilder
    private var stepContentView: some View {
        switch currentStep {
        case .instructions:
            instructionsView

        case .reading1:
            reading1View

        case .walking:
            walkingView

        case .reading2:
            reading2View

        case .calculating:
            calculatingView

        case .result:
            resultView

        case .error(let message):
            errorView(message: message)
        }
    }

    // MARK: - Instructions View

    private var instructionsView: some View {
        VStack(spacing: 24) {
            Image(systemName: "figure.walk.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            Text("¿Cómo funciona?")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 16) {
                InstructionRow(
                    number: 1,
                    icon: "1.circle.fill",
                    text: "Toma una lectura de distancia aquí"
                )

                InstructionRow(
                    number: 2,
                    icon: "2.circle.fill",
                    text: "Camina 10 metros en cualquier dirección"
                )

                InstructionRow(
                    number: 3,
                    icon: "3.circle.fill",
                    text: "Toma segunda lectura en nueva posición"
                )

                InstructionRow(
                    number: 4,
                    icon: "4.circle.fill",
                    text: "¡Calculamos la dirección precisa!"
                )
            }
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(15)

            Text("Tip: Camina en línea recta para mejor precisión")
                .font(.caption)
                .foregroundColor(.yellow.opacity(0.8))
                .padding(.top, 8)
        }
    }

    // MARK: - Reading 1 View

    private var reading1View: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 150, height: 150)

                VStack {
                    Image(systemName: "1.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)

                    Text("Lectura 1")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }

            Text("Toma la primera lectura")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            if let dist = currentDistance {
                VStack(spacing: 8) {
                    Text("Distancia actual:")
                        .foregroundColor(.white.opacity(0.7))
                    Text("\(String(format: "%.2f", dist))m")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.cyan)
                }
            }

            if !canTakeReading {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Esperando GPS y LinkFinder...")
                }
                .foregroundColor(.yellow)
            }
        }
    }

    // MARK: - Walking View

    private var walkingView: some View {
        VStack(spacing: 24) {
            // Animated walking figure
            Image(systemName: "figure.walk")
                .font(.system(size: 80))
                .foregroundColor(.blue)
                .symbolEffect(.wiggle.byLayer)

            Text("Camina 10 metros")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            if let reading1 = reading1, let currentLoc = locationService.currentLocation {
                let walked = reading1.userLocation.distance(to: currentLoc)
                distanceWalkedIndicator(walked: walked)
            }

            VStack(spacing: 12) {
                Text("• Camina en cualquier dirección")
                Text("• Mantén el dispositivo contigo")
                Text("• Detente cuando llegues a 10m")
            }
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.8))
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
        }
        .onReceive(locationService.$currentLocation) { newLocation in
            guard let reading1 = reading1, let loc = newLocation else { return }

            let walked = reading1.userLocation.distance(to: loc)
            distanceWalked = walked

            // Auto-advance when walked enough
            if walked >= 10.0 {
                withAnimation {
                    currentStep = .reading2
                }
            }
        }
    }

    // MARK: - Reading 2 View

    private var reading2View: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 150, height: 150)

                VStack {
                    Image(systemName: "2.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)

                    Text("Lectura 2")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }

            Text("Toma la segunda lectura")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            if let dist = currentDistance {
                VStack(spacing: 8) {
                    Text("Distancia actual:")
                        .foregroundColor(.white.opacity(0.7))
                    Text("\(String(format: "%.2f", dist))m")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.cyan)
                }
            }

            if let reading1 = reading1, let currentLoc = locationService.currentLocation {
                let walked = reading1.userLocation.distance(to: currentLoc)
                Text("Caminaste: \(String(format: "%.1f", walked))m")
                    .font(.headline)
                    .foregroundColor(.green)
            }
        }
    }

    // MARK: - Calculating View

    private var calculatingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(2.0)
                .tint(.cyan)

            Text("Calculando dirección...")
                .font(.title2)
                .foregroundColor(.white)

            Text("Procesando geometría de intersección de círculos")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
    }

    // MARK: - Result View

    private var resultView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            Text("¡Dirección calculada!")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)

            if let bearing = calculatedDirection {
                VStack(spacing: 12) {
                    Text("Tu familiar está:")
                        .foregroundColor(.white.opacity(0.7))

                    HStack(spacing: 12) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                            .rotationEffect(.degrees(bearing))

                        Text("\(Int(bearing))°")
                            .font(.system(size: 48, weight: .bold, design: .rounded))

                        Text(LocationCalculator.cardinalDirection(from: bearing))
                            .font(.title2)
                    }
                    .foregroundColor(.cyan)
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(15)
            }

            Button(action: {
                if let bearing = calculatedDirection {
                    onDirectionCalculated(bearing)
                }
            }) {
                HStack {
                    Image(systemName: "arrow.forward.circle.fill")
                    Text("Comenzar navegación")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 30)
                .padding(.vertical, 12)
                .background(Color.green)
                .cornerRadius(25)
            }
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 80))
                .foregroundColor(.red)

            Text("Error")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text(message)
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)

            Button(action: {
                // Reset to instructions
                reading1 = nil
                reading2 = nil
                calculatedDirection = nil
                currentStep = .instructions
            }) {
                HStack {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                    Text("Intentar de nuevo")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 30)
                .padding(.vertical, 12)
                .background(Color.orange)
                .cornerRadius(25)
            }
        }
    }

    // MARK: - Action Buttons View

    @ViewBuilder
    private var actionButtonsView: some View {
        HStack(spacing: 16) {
            // Cancel button (always visible)
            Button(action: onDismiss) {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                    Text("Cancelar")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.red.opacity(0.8))
                .cornerRadius(25)
            }

            Spacer()

            // Step-specific action button
            stepActionButton
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var stepActionButton: some View {
        switch currentStep {
        case .instructions:
            Button(action: {
                currentStep = .reading1
            }) {
                HStack {
                    Text("Comenzar")
                    Image(systemName: "arrow.forward.circle.fill")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 30)
                .padding(.vertical, 12)
                .background(Color.green)
                .cornerRadius(25)
            }

        case .reading1:
            Button(action: takeReading1) {
                HStack {
                    Image(systemName: "camera.viewfinder")
                    Text("Tomar Lectura 1")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(canTakeReading ? Color.green : Color.gray)
                .cornerRadius(25)
            }
            .disabled(!canTakeReading)

        case .walking:
            EmptyView()  // No action button during walking

        case .reading2:
            Button(action: takeReading2) {
                HStack {
                    Image(systemName: "camera.viewfinder")
                    Text("Tomar Lectura 2")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(canTakeReading ? Color.orange : Color.gray)
                .cornerRadius(25)
            }
            .disabled(!canTakeReading)

        case .calculating, .result, .error:
            EmptyView()
        }
    }

    // MARK: - Helper Views

    private func distanceWalkedIndicator(walked: Double) -> some View {
        VStack(spacing: 12) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 20)

                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.green)
                    .frame(width: CGFloat(min(walked / 10.0, 1.0)) * 280, height: 20)
            }
            .frame(width: 280)

            Text("\(String(format: "%.1f", walked)) / 10.0m")
                .font(.headline)
                .foregroundColor(.white)

            if walked < 10.0 {
                Text("Sigue caminando \(String(format: "%.1f", 10.0 - walked))m más")
                    .font(.caption)
                    .foregroundColor(.yellow)
            } else {
                Text("✅ ¡Listo! Toma la segunda lectura")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
    }

    // MARK: - Action Methods

    private func takeReading1() {
        guard let location = locationService.currentLocation,
              let distance = currentDistance else {
            return
        }

        reading1 = NavigationCalculator.TriangulationReading(
            userLocation: location,
            distanceToTarget: distance,
            timestamp: Date()
        )

        print("✅ Triangulation Reading 1 taken: \(reading1!.coordinateString)")

        withAnimation {
            currentStep = .walking
        }
    }

    private func takeReading2() {
        guard let location = locationService.currentLocation,
              let distance = currentDistance else {
            return
        }

        reading2 = NavigationCalculator.TriangulationReading(
            userLocation: location,
            distanceToTarget: distance,
            timestamp: Date()
        )

        print("✅ Triangulation Reading 2 taken: \(reading2!.coordinateString)")

        withAnimation {
            currentStep = .calculating
        }

        // Perform calculation
        calculateDirection()
    }

    private func calculateDirection() {
        guard let r1 = reading1, let r2 = reading2 else {
            currentStep = .error("Error: Lecturas faltantes")
            return
        }

        // Validate readings
        let validation = NavigationCalculator.validateTriangulationReadings(
            reading1: r1,
            reading2: r2
        )

        guard validation.isValid else {
            currentStep = .error(validation.errorMessage ?? "Error de validación")
            return
        }

        // Calculate intersection
        guard let targetCoord = NavigationCalculator.calculateTriangulatedPosition(
            reading1: r1,
            reading2: r2
        ) else {
            currentStep = .error("No se pudo calcular la intersección. Intenta caminar en una dirección diferente.")
            return
        }

        // Calculate bearing from current location to calculated target position
        guard let currentLocation = locationService.currentLocation else {
            currentStep = .error("Ubicación GPS no disponible")
            return
        }

        let targetLocation = UserLocation(
            latitude: targetCoord.latitude,
            longitude: targetCoord.longitude,
            accuracy: NavigationCalculator.estimateTriangulationAccuracy(reading1: r1, reading2: r2)
        )

        let bearing = LocationCalculator.bearing(from: currentLocation, to: targetLocation)

        calculatedDirection = bearing

        print("✅ Triangulation complete! Bearing: \(bearing)°")

        withAnimation {
            currentStep = .result
        }
    }
}

// MARK: - Instruction Row Component

struct InstructionRow: View {
    let number: Int
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.cyan)
                .frame(width: 30)

            Text(text)
                .font(.body)
                .foregroundColor(.white)

            Spacer()
        }
    }
}

// MARK: - Preview
#Preview {
    WalkingTriangulationView(
        targetName: "Mamá",
        targetPeerID: MCPeerID(displayName: "test-peer"),
        uwbManager: LinkFinderSessionManager(),
        locationService: LocationService(),
        onDismiss: {},
        onDirectionCalculated: { bearing in
            print("Calculated bearing: \(bearing)°")
        }
    )
}
