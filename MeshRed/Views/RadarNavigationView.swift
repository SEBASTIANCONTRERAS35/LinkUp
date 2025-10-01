//
//  RadarNavigationView.swift
//  MeshRed
//
//  Created by Emilio Contreras on 30/09/25.
//

import SwiftUI

/// Radar-style circular navigation view for UWB distance-only navigation (Nivel 3)
/// Shows a circular radar with pulsing ring at the target's distance
/// Used when we have UWB distance but no direction information
struct RadarNavigationView: View {
    let targetName: String
    let distance: Float
    let onDismiss: () -> Void
    let onStartTriangulation: () -> Void

    @State private var isPulsing = false
    @State private var radarRotation: Double = 0

    // Radar configuration
    private let maxRadarRadius: CGFloat = 150.0  // Maximum radar display radius
    private let maxDisplayDistance: Float = 50.0  // Maximum distance to display (meters)

    /// Calculate visual radius on radar for given distance
    private var targetRadius: CGFloat {
        let normalizedDistance = min(distance, maxDisplayDistance) / maxDisplayDistance
        return CGFloat(normalizedDistance) * maxRadarRadius
    }

    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                // Header
                VStack(spacing: 8) {
                    Text("Buscando a:")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))

                    Text(targetName)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("\(String(format: "%.1f", distance))m de distancia")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.cyan)
                }
                .padding(.top, 40)

                Spacer()

                // Radar display
                ZStack {
                    // Background grid circles
                    ForEach(1..<5) { ring in
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            .frame(
                                width: maxRadarRadius * 2 * CGFloat(ring) / 4,
                                height: maxRadarRadius * 2 * CGFloat(ring) / 4
                            )
                    }

                    // Rotating radar sweep
                    RadarSweep(rotation: radarRotation)
                        .frame(width: maxRadarRadius * 2, height: maxRadarRadius * 2)

                    // Target ring (pulsing at target distance)
                    Circle()
                        .stroke(Color.cyan, lineWidth: 4)
                        .frame(width: targetRadius * 2, height: targetRadius * 2)
                        .scaleEffect(isPulsing ? 1.1 : 1.0)
                        .opacity(isPulsing ? 0.6 : 1.0)
                        .animation(
                            Animation.easeInOut(duration: 1.5)
                                .repeatForever(autoreverses: true),
                            value: isPulsing
                        )

                    // Target dot
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 12, height: 12)
                        .offset(y: -targetRadius)  // Position at top of circle
                        .scaleEffect(isPulsing ? 1.3 : 1.0)
                        .animation(
                            Animation.easeInOut(duration: 1.5)
                                .repeatForever(autoreverses: true),
                            value: isPulsing
                        )

                    // Center marker (user position)
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 16, height: 16)

                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                            .frame(width: 16, height: 16)
                    }

                    // Distance labels
                    ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { fraction in
                        let distanceLabel = fraction * Double(maxDisplayDistance)
                        Text("\(Int(distanceLabel))m")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.5))
                            .offset(y: -maxRadarRadius * CGFloat(fraction) - 10)
                    }
                }
                .frame(width: maxRadarRadius * 2 + 40, height: maxRadarRadius * 2 + 40)

                Spacer()

                // Info and instructions
                VStack(spacing: 16) {
                    // Status message
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.yellow)
                        Text("Dirección no disponible - Solo distancia UWB")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal)

                    // Walking triangulation button
                    Button(action: {
                        onStartTriangulation()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "figure.walk.circle.fill")
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Modo Búsqueda Guiada")
                                    .font(.headline)
                                Text("Camina para calcular dirección precisa")
                                    .font(.caption)
                                    .opacity(0.8)
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.green, Color.green.opacity(0.8)]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(15)
                    }
                    .padding(.horizontal)

                    // Hint
                    Text("Tip: Mantén el dispositivo en horizontal y gira 360° para buscar")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                Spacer()

                // Close button
                Button(action: onDismiss) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("Cerrar")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(25)
                }
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            isPulsing = true
            startRadarRotation()
        }
    }

    /// Start continuous radar rotation animation
    private func startRadarRotation() {
        withAnimation(Animation.linear(duration: 4.0).repeatForever(autoreverses: false)) {
            radarRotation = 360
        }
    }
}

/// Rotating radar sweep effect
struct RadarSweep: View {
    let rotation: Double

    var body: some View {
        ZStack {
            // Sweep gradient
            Circle()
                .trim(from: 0, to: 0.25)  // 90-degree sweep
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color.cyan.opacity(0.0),
                            Color.cyan.opacity(0.3),
                            Color.cyan.opacity(0.6)
                        ]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(90)
                    )
                )
                .rotationEffect(.degrees(rotation))

            // Sweep line
            Rectangle()
                .fill(Color.cyan.opacity(0.8))
                .frame(width: 2, height: 150)
                .offset(y: -75)
                .rotationEffect(.degrees(rotation))
        }
    }
}

// MARK: - Preview
#Preview {
    RadarNavigationView(
        targetName: "Mamá",
        distance: 15.3,
        onDismiss: {},
        onStartTriangulation: {}
    )
}
