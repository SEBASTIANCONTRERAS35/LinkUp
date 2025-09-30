//
//  UWBNavigationView.swift
//  MeshRed
//
//  Created by Emilio Contreras on 29/09/25.
//

import SwiftUI
import MultipeerConnectivity

/// Vista de navegación UWB con flecha direccional que guía al usuario
/// Actualiza en tiempo real conforme el usuario o peer se mueven
struct UWBNavigationView: View {
    let targetName: String
    let targetPeerID: MCPeerID
    @ObservedObject var uwbManager: UWBSessionManager
    let onDismiss: () -> Void

    // Computed properties que se actualizan automáticamente desde UWB
    private var distance: Float? {
        let dist = uwbManager.getDistance(to: targetPeerID)
        print("🔍 UWBNavigationView: Getting distance for \(targetPeerID.displayName) = \(dist?.description ?? "nil")")
        return dist
    }

    private var direction: DirectionVector? {
        if let simd = uwbManager.getDirection(to: targetPeerID) {
            let dirVector = DirectionVector(from: simd)
            print("🔍 UWBNavigationView: Getting direction for \(targetPeerID.displayName)")
            print("   SIMD: x=\(simd.x), y=\(simd.y), z=\(simd.z)")
            print("   DirectionVector created: x=\(dirVector.x), y=\(dirVector.y), z=\(dirVector.z)")
            return dirVector
        }
        print("⚠️ UWBNavigationView: No direction available for \(targetPeerID.displayName)")
        return nil
    }

    private var horizontalAngle: Float? {
        let angle = uwbManager.getHorizontalAngle(to: targetPeerID)
        if let angle = angle {
            print("🔍 UWBNavigationView: Getting horizontalAngle = \(angle)°")
        }
        return angle
    }

    private var supportsDirectionMeasurement: Bool {
        uwbManager.supportsDirectionMeasurement
    }

    private var supportsCameraAssistance: Bool {
        uwbManager.supportsCameraAssistance
    }

    var body: some View {
        ZStack {
            // Fondo semi-transparente
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

                // Distancia
                VStack(spacing: 4) {
                    if let dist = distance {
                        Text(distanceString(for: dist))
                            .font(.system(size: 56, weight: .heavy, design: .rounded))
                            .foregroundColor(.cyan)

                        Text("de distancia")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    } else {
                        // Indicador de carga mientras esperamos datos
                        ProgressView()
                            .scaleEffect(2.0)
                            .tint(.cyan)
                            .padding()

                        Text("Estableciendo ranging...")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding()

                // Flecha direccional - Adaptive UI basado en capacidades del dispositivo
                if let direction = direction, let dist = distance {
                    // Nivel 1: Dirección precisa SIMD3 disponible
                    DirectionalArrow(direction: direction, distance: dist, isPrecise: true)
                        .frame(width: 250, height: 250)
                } else if let angle = horizontalAngle, let dist = distance {
                    // Nivel 2: Camera assistance (horizontal angle) disponible
                    CameraAssistedArrow(horizontalAngle: angle, distance: dist)
                        .frame(width: 250, height: 250)
                } else {
                    // Nivel 3/4: Sin dirección - Círculo pulsante
                    PulsingCircle()
                        .frame(width: 200, height: 200)
                }

                // Información adicional
                if let direction = direction, let dist = distance {
                    // Información de dirección precisa
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "safari")
                                .font(.title3)
                            Text("\(Int(direction.bearing))° (\(direction.cardinalDirection))")
                                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        }
                        .foregroundColor(.green)

                        Text("Dirección precisa (UWB)")
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
                } else if let angle = horizontalAngle, let dist = distance {
                    // Información de camera assistance
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "camera.viewfinder")
                                .font(.title3)
                            Text("\(Int(angle))° (aprox.)")
                                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        }
                        .foregroundColor(.orange)

                        Text("Dirección con asistencia de cámara")
                            .font(.caption)
                            .foregroundColor(.orange.opacity(0.8))

                        if dist < 2.0 {
                            Text("¡Muy cerca!")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.yellow)
                                .padding(.top, 8)
                        }
                    }
                } else if !supportsDirectionMeasurement {
                    // Mensaje explicativo cuando dispositivo no soporta dirección
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                            .foregroundColor(.yellow)

                        Text("Dirección no disponible")
                            .font(.headline)
                            .foregroundColor(.white)

                        Text("Tu dispositivo solo proporciona distancia UWB")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                Spacer()

                // Botón de cerrar
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

    private func distanceString(for dist: Float) -> String {
        if dist < 1.0 {
            return String(format: "%.0fcm", dist * 100)
        } else {
            return String(format: "%.1fm", dist)
        }
    }
}

/// Flecha direccional animada que apunta hacia el objetivo
struct DirectionalArrow: View {
    let direction: DirectionVector
    let distance: Float
    let isPrecise: Bool

    @State private var isAnimating = false

    init(direction: DirectionVector, distance: Float, isPrecise: Bool = true) {
        self.direction = direction
        self.distance = distance
        self.isPrecise = isPrecise

        // 🔍 DEBUG: Log when arrow is initialized/updated
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🎯 DIRECTIONAL ARROW UPDATE")
        print("   Type: \(isPrecise ? "Precise UWB" : "Approximate")")
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
                            Color.cyan.opacity(0.3),
                            Color.cyan.opacity(0.1),
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
                .stroke(Color.cyan.opacity(0.3), lineWidth: 2)
                .frame(width: 220, height: 220)

            // Marcadores cardinales
            CardinalMarkers()

            // Flecha principal
            VStack(spacing: 0) {
                // Punta de la flecha
                Triangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.cyan, Color.blue]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 40, height: 50)
                    .shadow(color: .cyan, radius: 10, x: 0, y: 0)

                // Cuerpo de la flecha
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.cyan]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 20, height: 60)
                    .shadow(color: .cyan, radius: 10, x: 0, y: 0)
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
                        .stroke(Color.cyan, lineWidth: 2)
                )
        }
        .onAppear {
            isAnimating = true
        }
    }
}

/// Flecha direccional con asistencia de cámara (solo ángulo horizontal)
struct CameraAssistedArrow: View {
    let horizontalAngle: Float
    let distance: Float

    @State private var isAnimating = false

    init(horizontalAngle: Float, distance: Float) {
        self.horizontalAngle = horizontalAngle
        self.distance = distance

        // 🔍 DEBUG: Log when arrow is initialized/updated
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📸 CAMERA ASSISTED ARROW UPDATE")
        print("   Horizontal Angle: \(horizontalAngle)°")
        print("   Distance: \(distance)m")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    var body: some View {
        ZStack {
            // Círculo de fondo con color naranja para indicar aproximación
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.orange.opacity(0.3),
                            Color.orange.opacity(0.1),
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
                .stroke(Color.orange.opacity(0.3), lineWidth: 2)
                .frame(width: 220, height: 220)

            // Marcadores cardinales
            CardinalMarkers()

            // Flecha con icono de cámara
            VStack(spacing: 0) {
                // Punta de la flecha
                Triangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.orange, Color.yellow]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 40, height: 50)
                    .shadow(color: .orange, radius: 10, x: 0, y: 0)

                // Cuerpo de la flecha
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.yellow, Color.orange]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 20, height: 60)
                    .shadow(color: .orange, radius: 10, x: 0, y: 0)
            }
            .rotationEffect(.degrees(-Double(horizontalAngle))) // Rotar según ángulo horizontal
            .scaleEffect(isAnimating ? 1.15 : 1.0)
            .animation(
                Animation.easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )

            // Punto central con icono de cámara
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .stroke(Color.orange, lineWidth: 2)
                    )

                Image(systemName: "camera.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            }
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
                    .stroke(Color.cyan.opacity(0.4), lineWidth: 3)
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
                        gradient: Gradient(colors: [Color.cyan, Color.blue]),
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
    // Mock UWBSessionManager for preview
    let mockManager = UWBSessionManager()
    let mockPeer = MCPeerID(displayName: "José Guadalupe")

    return UWBNavigationView(
        targetName: "José Guadalupe",
        targetPeerID: mockPeer,
        uwbManager: mockManager,
        onDismiss: {}
    )
}