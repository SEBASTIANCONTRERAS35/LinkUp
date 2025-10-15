//
//  DistanceOnlyNavigationView.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Simple distance-only view when LinkFinder is not available
//

import SwiftUI

/// Vista simple que muestra solo la distancia estimada cuando LinkFinder no está disponible
/// No muestra radar ni dirección, solo distancia calculada por GPS/RSSI
struct DistanceOnlyNavigationView: View {
    let targetName: String
    let estimatedDistance: Float?
    let distanceSource: DistanceSource
    let onDismiss: () -> Void

    enum DistanceSource {
        case gps
        case rssi
        case none

        var displayText: String {
            switch self {
            case .gps: return "Usando GPS"
            case .rssi: return "Usando Bluetooth"
            case .none: return "Sin datos disponibles"
            }
        }

        var icon: String {
            switch self {
            case .gps: return "location.fill"
            case .rssi: return "antenna.radiowaves.left.and.right"
            case .none: return "location.slash"
            }
        }

        var color: Color {
            switch self {
            case .gps: return .orange
            case .rssi: return .yellow
            case .none: return .gray
            }
        }
    }

    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 40) {
                // Header
                VStack(spacing: 8) {
                    Text("Buscando a:")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))

                    Text(targetName)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                .padding(.top, 40)

                Spacer()

                // Distance (if available)
                if let dist = estimatedDistance {
                    VStack(spacing: 8) {
                        Text("~\(distanceString(for: dist))")
                            .font(.system(size: 64, weight: .heavy, design: .rounded))
                            .foregroundColor(.cyan)

                        Text("aproximado")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding()

                    // Visual indicator (simple pulse circle)
                    DistancePulseIndicator(distance: dist)
                        .frame(width: 150, height: 150)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.4))

                        Text("Distancia no disponible")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding()
                }

                // Source info
                HStack(spacing: 12) {
                    Image(systemName: distanceSource.icon)
                        .font(.title3)
                    Text(distanceSource.displayText)
                        .font(.subheadline)
                }
                .foregroundColor(distanceSource.color)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(distanceSource.color.opacity(0.15))
                .cornerRadius(12)

                // Warning
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Sin LinkFinder Preciso")
                    }
                    .font(.subheadline)
                    .foregroundColor(.yellow)

                    Text("Requiere iPhone 11+ para navegación precisa")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()

                Spacer()

                // Close button
                Button(action: onDismiss) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("Cerrar")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
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
            return String(format: "%.0fm", dist)
        }
    }
}

/// Simple pulsing circle indicator for distance
struct DistancePulseIndicator: View {
    let distance: Float
    @State private var isPulsing = false

    // Map distance to circle size (closer = larger circle)
    private var circleSize: CGFloat {
        let maxDistance: Float = 100.0
        let normalizedDistance = min(distance, maxDistance) / maxDistance
        // Inverse: closer distance = larger circle
        return 50 + (1.0 - CGFloat(normalizedDistance)) * 80
    }

    var body: some View {
        ZStack {
            // Outer pulse ring
            Circle()
                .stroke(Color.cyan.opacity(0.3), lineWidth: 2)
                .frame(width: circleSize * 1.5, height: circleSize * 1.5)
                .scaleEffect(isPulsing ? 1.2 : 1.0)
                .opacity(isPulsing ? 0.0 : 0.8)
                .animation(
                    Animation.easeOut(duration: 2.0)
                        .repeatForever(autoreverses: false),
                    value: isPulsing
                )

            // Main circle
            Circle()
                .fill(Color.appSecondary.opacity(0.3))
                .frame(width: circleSize, height: circleSize)
                .overlay(
                    Circle()
                        .stroke(Color.appSecondary, lineWidth: 3)
                )

            // Center dot
            Circle()
                .fill(Color.appSecondary)
                .frame(width: 12, height: 12)
        }
        .onAppear {
            isPulsing = true
        }
    }
}

// MARK: - Preview

#Preview {
    DistanceOnlyNavigationView(
        targetName: "María González",
        estimatedDistance: 25.5,
        distanceSource: .gps,
        onDismiss: {}
    )
}
