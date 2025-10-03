//
//  GPSNavigationView.swift
//  MeshRed
//
//  Created by Emilio Contreras on 30/09/25.
//

import SwiftUI
import CoreLocation

/// GPS + Compass navigation view (Nivel 2)
/// Shows directional arrow based on GPS bearing + user's compass heading
/// Used when we have peer's GPS location and user's heading, but no LinkFinder direction
struct GPSNavigationView: View {
    let targetName: String
    let userLocation: UserLocation
    let targetLocation: UserLocation
    let userHeading: Double
    let distance: Float

    @State private var isAnimating = false

    /// Calculate relative bearing from user to target, adjusted for heading
    private var relativeBearing: Double {
        NavigationCalculator.calculateRelativeBearing(
            from: userLocation,
            to: targetLocation,
            userHeading: userHeading
        )
    }

    /// GPS distance in meters
    private var gpsDistance: Double {
        userLocation.distance(to: targetLocation)
    }

    var body: some View {
        ZStack {
            // Círculo de fondo con gradiente azul
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.blue.opacity(0.3),
                            Color.blue.opacity(0.1),
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
                .stroke(Color.blue.opacity(0.4), lineWidth: 2)
                .frame(width: 220, height: 220)

            // Marcadores cardinales
            CardinalMarkers()

            // Flecha direccional GPS-assisted
            VStack(spacing: 0) {
                // Punta de la flecha
                Triangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.cyan]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 40, height: 50)
                    .shadow(color: .blue, radius: 10, x: 0, y: 0)

                // Cuerpo de la flecha
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.cyan, Color.blue]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 20, height: 60)
                    .shadow(color: .blue, radius: 10, x: 0, y: 0)
            }
            .rotationEffect(.degrees(-relativeBearing))  // Rotate based on relative bearing
            .scaleEffect(isAnimating ? 1.15 : 1.0)
            .animation(
                Animation.easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )

            // Punto central con icono de compass
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .stroke(Color.blue, lineWidth: 2)
                    )

                Image(systemName: "location.north.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.blue)
            }

            // Distance accuracy indicator
            if targetLocation.accuracy > 20 {
                VStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text("GPS poco preciso")
                            .font(.caption2)
                    }
                    .foregroundColor(.yellow.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(8)
                    .offset(y: 100)
                }
            }
        }
        .frame(width: 250, height: 250)
        .onAppear {
            isAnimating = true
        }
    }
}

/// Información detallada de navegación GPS
struct GPSNavigationInfo: View {
    let targetName: String
    let relativeBearing: Double
    let gpsDistance: Double
    let uwbDistance: Float?
    let targetAccuracy: Double
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Target name
            Text("Navegando a: \(targetName)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            // Bearing and direction
            HStack(spacing: 12) {
                Image(systemName: "location.north.circle.fill")
                    .font(.title2)
                Text(directionDescription)
                    .font(.headline)
            }
            .foregroundColor(.blue)

            // Distances
            VStack(spacing: 8) {
                HStack {
                    Text("Distancia GPS:")
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                    Text("\(LocationCalculator.formatDistance(gpsDistance))")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }

                if let uwb = uwbDistance {
                    HStack {
                        Text("Distancia LinkFinder:")
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text(String(format: "%.2fm", uwb))
                            .fontWeight(.semibold)
                            .foregroundColor(.cyan)
                    }
                }

                HStack {
                    Text("Precisión GPS:")
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                    Text("±\(String(format: "%.0f", targetAccuracy))m")
                        .fontWeight(.semibold)
                        .foregroundColor(targetAccuracy > 20 ? .yellow : .green)
                }
            }
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)

            // Mode indicator
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                Text("Navegación GPS + Brújula")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }

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
            .padding(.top, 8)
        }
    }

    /// Human-readable direction description
    private var directionDescription: String {
        switch abs(relativeBearing) {
        case 0..<15:
            return "Adelante"
        case 15..<45:
            return relativeBearing > 0 ? "Adelante a la derecha" : "Adelante a la izquierda"
        case 45..<90:
            return relativeBearing > 0 ? "A la derecha" : "A la izquierda"
        case 90..<135:
            return relativeBearing > 0 ? "Muy a la derecha" : "Muy a la izquierda"
        case 135..<180:
            return "Detrás de ti"
        default:
            return "Detrás de ti"
        }
    }
}

// MARK: - Preview
#Preview {
    VStack {
        GPSNavigationView(
            targetName: "Mamá",
            userLocation: UserLocation(latitude: 19.4326, longitude: -99.1332, accuracy: 10.0),
            targetLocation: UserLocation(latitude: 19.4330, longitude: -99.1340, accuracy: 15.0),
            userHeading: 45.0,
            distance: 25.5
        )
        .padding()

        GPSNavigationInfo(
            targetName: "Mamá",
            relativeBearing: 45.0,
            gpsDistance: 52.3,
            uwbDistance: 25.5,
            targetAccuracy: 15.0,
            onDismiss: {}
        )
        .padding()
        .background(Color.black.opacity(0.8))
    }
}
