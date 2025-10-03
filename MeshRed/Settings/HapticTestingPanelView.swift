//
//  HapticTestingPanelView.swift
//  MeshRed - StadiumConnect Pro
//
//  Interactive testing panel for all haptic patterns
//  For CSC 2025 demo and accessibility testing
//

import SwiftUI

struct HapticTestingPanelView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibleTheme) var accessibleTheme
    @EnvironmentObject var settings: AccessibilitySettingsManager

    @State private var simulatedDistance: Float = 10.0
    @State private var isTestingProximity = false
    @State private var proximityEngine = ProximityHapticEngine()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                // Basic Haptics
                basicHapticsSection

                // Emergency Patterns
                emergencyPatternsSection

                // Network Events
                networkEventsSection

                // Geofence Patterns
                geofencePatternsSection

                // Proximity Navigation Simulator
                proximitySimulatorSection

                // Settings Summary
                settingsSummarySection

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .background(accessibleTheme.background.ignoresSafeArea())
        .navigationTitle("Pruebas Hápticas")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            proximityEngine.stop()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.title)
                    .foregroundColor(accessibleTheme.primaryBlue)
                Text("Panel de Pruebas Hápticas")
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Text("Prueba todos los patrones de vibración de la app. Asegúrate de que el modo silencio esté desactivado.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Current settings
            HStack {
                Image(systemName: settings.hapticsEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(settings.hapticsEnabled ? .green : .red)
                Text(settings.hapticsEnabled ? "Haptics Activados" : "Haptics Desactivados")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("Intensidad: \(settings.hapticIntensity)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(accessibleTheme.cardBackground)
            .cornerRadius(8)
        }
    }

    // MARK: - Basic Haptics

    private var basicHapticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Haptics Básicos")
                .font(.headline)
                .fontWeight(.semibold)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                HapticTestButton(title: "Light", icon: "circle", type: .light)
                HapticTestButton(title: "Medium", icon: "circle.fill", type: .medium)
                HapticTestButton(title: "Heavy", icon: "circle.circle.fill", type: .heavy)
                HapticTestButton(title: "Soft", icon: "waveform", type: .soft)
                HapticTestButton(title: "Rigid", icon: "waveform.path", type: .rigid)
                HapticTestButton(title: "Selection", icon: "hand.tap", type: .selection)
            }
        }
    }

    // MARK: - Emergency Patterns

    private var emergencyPatternsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Patrones de Emergencia")
                .font(.headline)
                .fontWeight(.semibold)

            VStack(spacing: 12) {
                EmergencyPatternButton(
                    title: "SOS Médico",
                    subtitle: "3 pulsos intensos + 2 medios",
                    icon: "cross.fill",
                    color: .red,
                    pattern: .sosEmergency
                )

                EmergencyPatternButton(
                    title: "SOS Seguridad",
                    subtitle: "Pulsos rápidos urgentes",
                    icon: "shield.fill",
                    color: .orange,
                    pattern: .sosSecurity
                )

                EmergencyPatternButton(
                    title: "Niño Perdido",
                    subtitle: "Onda suave, no alarmar",
                    icon: "figure.and.child.holdinghands",
                    color: .yellow,
                    pattern: .sosLostChild
                )
            }
        }
    }

    // MARK: - Network Events

    private var networkEventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Eventos de Red")
                .font(.headline)
                .fontWeight(.semibold)

            VStack(spacing: 12) {
                NetworkEventButton(
                    title: "Peer Conectado",
                    icon: "person.badge.plus.fill",
                    color: .green,
                    pattern: .peerConnected
                )

                NetworkEventButton(
                    title: "Peer Desconectado",
                    icon: "person.badge.minus.fill",
                    color: .orange,
                    pattern: .peerDisconnected
                )

                NetworkEventButton(
                    title: "Mensaje Recibido",
                    icon: "envelope.fill",
                    color: .blue,
                    pattern: .messageReceived
                )

                NetworkEventButton(
                    title: "Mensaje Enviado",
                    icon: "paperplane.fill",
                    color: .cyan,
                    pattern: .messageSent
                )
            }
        }
    }

    // MARK: - Geofence Patterns

    private var geofencePatternsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Geofencing por Categoría")
                .font(.headline)
                .fontWeight(.semibold)

            VStack(spacing: 12) {
                GeofencePatternButton(
                    title: "Baños",
                    subtitle: "2 pulsos cortos",
                    icon: "figure.walk",
                    category: .bathrooms
                )

                GeofencePatternButton(
                    title: "Salidas",
                    subtitle: "1 pulso largo",
                    icon: "rectangle.portrait.and.arrow.right",
                    category: .exits
                )

                GeofencePatternButton(
                    title: "Concesiones",
                    subtitle: "3 pulsos rápidos",
                    icon: "fork.knife",
                    category: .concessions
                )

                GeofencePatternButton(
                    title: "Zona Familia",
                    subtitle: "Onda suave",
                    icon: "figure.2.and.child.holdinghands",
                    category: .familyZone
                )
            }
        }
    }

    // MARK: - Proximity Simulator

    private var proximitySimulatorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Simulador de Navegación UWB")
                .font(.headline)
                .fontWeight(.semibold)

            VStack(spacing: 16) {
                // Distancia actual
                HStack {
                    Text("Distancia: \(String(format: "%.1f", simulatedDistance))m")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Spacer()

                    Text(proximityZoneDescription(simulatedDistance))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Slider
                Slider(value: $simulatedDistance, in: 0.5...20.0, step: 0.5)
                    .accentColor(accessibleTheme.primaryBlue)
                    .onChange(of: simulatedDistance) { newValue in
                        if isTestingProximity {
                            proximityEngine.updateProximity(distance: newValue)
                        }
                    }

                // Marcas de distancia
                HStack {
                    Text("0.5m")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("10m")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("20m")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Control buttons
                HStack(spacing: 12) {
                    Button(action: {
                        if isTestingProximity {
                            proximityEngine.stop()
                            isTestingProximity = false
                        } else {
                            proximityEngine.start()
                            proximityEngine.updateProximity(distance: simulatedDistance)
                            isTestingProximity = true
                        }
                    }) {
                        HStack {
                            Image(systemName: isTestingProximity ? "stop.fill" : "play.fill")
                            Text(isTestingProximity ? "Detener" : "Iniciar")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isTestingProximity ? Color.red : accessibleTheme.primaryBlue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }

                    Button(action: {
                        simulatedDistance = 1.0
                    }) {
                        Text("< 1m")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(accessibleTheme.cardBackground)
                            .foregroundColor(accessibleTheme.textPrimary)
                            .cornerRadius(12)
                    }
                }
            }
            .padding()
            .background(accessibleTheme.cardBackground)
            .cornerRadius(12)
        }
    }

    // MARK: - Settings Summary

    private var settingsSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configuración Actual")
                .font(.headline)
                .fontWeight(.semibold)

            VStack(spacing: 8) {
                SettingRow(label: "Haptics habilitados", value: settings.hapticsEnabled ? "Sí" : "No")
                SettingRow(label: "Intensidad", value: settings.hapticIntensity.capitalized)
                SettingRow(label: "UI Interactions", value: settings.hapticOnUIInteractions ? "Sí" : "No")
                SettingRow(label: "Conexiones", value: settings.hapticOnConnectionChanges ? "Sí" : "No")
                SettingRow(label: "Geofences", value: settings.hapticOnGeofenceTransitions ? "Sí" : "No")
            }
            .padding()
            .background(accessibleTheme.cardBackground)
            .cornerRadius(12)
        }
    }

    // MARK: - Helper

    private func proximityZoneDescription(_ distance: Float) -> String {
        switch distance {
        case 0..<1:
            return "¡Llegaste! (< 1m)"
        case 1..<2:
            return "Muy cerca (1-2m)"
        case 2..<5:
            return "Cerca (2-5m)"
        case 5..<10:
            return "Media distancia (5-10m)"
        case 10..<20:
            return "Lejos (10-20m)"
        default:
            return "Muy lejos (> 20m)"
        }
    }
}

// MARK: - Component Views

struct HapticTestButton: View {
    let title: String
    let icon: String
    let type: BasicHapticType
    @Environment(\.accessibleTheme) var accessibleTheme

    var body: some View {
        Button(action: {
            HapticManager.shared.play(type, priority: .ui)
        }) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(accessibleTheme.cardBackground)
            .foregroundColor(accessibleTheme.textPrimary)
            .cornerRadius(12)
        }
    }
}

struct EmergencyPatternButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let pattern: HapticPatternType
    @Environment(\.accessibleTheme) var accessibleTheme

    var body: some View {
        Button(action: {
            HapticManager.shared.playPattern(pattern, priority: .emergency)
        }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 50, height: 50)
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(accessibleTheme.textPrimary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "play.fill")
                    .foregroundColor(color)
            }
            .padding()
            .background(accessibleTheme.cardBackground)
            .cornerRadius(12)
        }
    }
}

struct NetworkEventButton: View {
    let title: String
    let icon: String
    let color: Color
    let pattern: HapticPatternType
    @Environment(\.accessibleTheme) var accessibleTheme

    var body: some View {
        Button(action: {
            HapticManager.shared.playPattern(pattern, priority: .notification)
        }) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                    .frame(width: 30)

                Text(title)
                    .font(.subheadline)
                    .foregroundColor(accessibleTheme.textPrimary)

                Spacer()

                Image(systemName: "play.fill")
                    .foregroundColor(color)
                    .font(.caption)
            }
            .padding()
            .background(accessibleTheme.cardBackground)
            .cornerRadius(12)
        }
    }
}

struct GeofencePatternButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let category: LinkFenceCategory
    @Environment(\.accessibleTheme) var accessibleTheme

    var body: some View {
        Button(action: {
            HapticManager.shared.playGeofenceTransition(.entry, category: category)
        }) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(accessibleTheme.primaryBlue)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(accessibleTheme.textPrimary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "play.fill")
                    .foregroundColor(accessibleTheme.primaryBlue)
                    .font(.caption)
            }
            .padding()
            .background(accessibleTheme.cardBackground)
            .cornerRadius(12)
        }
    }
}

struct SettingRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
    }
}
