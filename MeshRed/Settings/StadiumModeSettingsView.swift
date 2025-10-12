//
//  StadiumModeSettingsView.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Stadium Mode settings for extended background operation
//

import SwiftUI
import CoreLocation

struct StadiumModeSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var networkManager: NetworkManager
    @StateObject private var stadiumMode = StadiumModeManager.shared

    @State private var showExplanation = false
    @State private var showLocationPermissionAlert = false
    @State private var testMessagesSent = 0
    @State private var showMessageSentConfirmation = false
    @AppStorage("autoActivateStadiumMode") private var autoActivateStadiumMode: Bool = true

    var body: some View {
        NavigationView {
            Form {
                // Status Section
                statusSection

                // Main Toggle Section
                mainToggleSection

                // Auto-Activation Section
                autoActivationSection

                // Features Section (when enabled)
                if stadiumMode.isActive {
                    featuresSection
                }

                // Testing Section (when Live Activity is active)
                if networkManager.hasActiveLiveActivity {
                    testingSection
                }

                // Info Section
                infoSection

                // Advanced Info
                technicalDetailsSection
            }
            .navigationTitle("Modo Estadio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
            }
            .alert("Permiso de Ubicación Requerido", isPresented: $showLocationPermissionAlert) {
                Button("Abrir Ajustes") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("El Modo Estadio requiere acceso a tu ubicación en segundo plano para extender el tiempo de conexión. Por favor, habilita 'Siempre' en Ajustes > StadiumConnect Pro > Ubicación.")
            }
            .sheet(isPresented: $showExplanation) {
                StadiumModeExplanationView()
            }
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        Section {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(stadiumMode.isActive ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: stadiumMode.isActive ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 26))
                        .foregroundColor(stadiumMode.isActive ? .green : .gray)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(stadiumMode.isActive ? "Modo Activo" : "Modo Desactivado")
                        .font(.headline)
                        .foregroundColor(stadiumMode.isActive ? .green : .secondary)

                    if stadiumMode.isActive {
                        Text("Conexiones extendidas en segundo plano")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Toca el switch para activar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Main Toggle Section

    private var mainToggleSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { stadiumMode.isActive },
                set: { newValue in
                    if newValue {
                        enableStadiumMode()
                    } else {
                        stadiumMode.disable()
                    }
                }
            )) {
                HStack(spacing: 12) {
                    Image(systemName: "sportscourt.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Activar Modo Estadio")
                            .font(.body)
                            .fontWeight(.semibold)

                        if stadiumMode.isActive {
                            Text("~\(Int(stadiumMode.estimatedBackgroundTime / 60)) minutos de conexión")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("Extiende tiempo de conexión hasta 25 min")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .tint(.blue)

            Button(action: {
                showExplanation = true
            }) {
                HStack {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.blue)
                    Text("¿Qué es el Modo Estadio?")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("Configuración Principal")
        } footer: {
            Text("El Modo Estadio mantiene las conexiones activas cuando la app está en segundo plano, ideal para eventos masivos.")
                .font(.caption)
        }
    }

    // MARK: - Auto-Activation Section

    private var autoActivationSection: some View {
        Section {
            Toggle(isOn: $autoActivateStadiumMode) {
                HStack(spacing: 12) {
                    Image(systemName: "wand.and.rays")
                        .font(.body)
                        .foregroundColor(.orange)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auto-activación")
                            .font(.body)

                        Text(autoActivateStadiumMode ?
                             "Se activa automáticamente al conectar" :
                             "Activación manual desde configuración")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .tint(.orange)
        } header: {
            Text("Comportamiento Automático")
        } footer: {
            Text(autoActivateStadiumMode ?
                 "El Modo Estadio se activará automáticamente cuando se conecte el primer dispositivo." :
                 "Deberás activar manualmente el Modo Estadio cuando lo necesites.")
                .font(.caption)
        }
    }

    // MARK: - Testing Section

    private var testingSection: some View {
        Section {
            VStack(spacing: 16) {
                // Info text
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "flask.fill")
                        .font(.title3)
                        .foregroundColor(.purple)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Probar Contador de Mensajes")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Envía un mensaje de prueba para verificar que el contador aparece en Dynamic Island")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()

                // Test button
                Button(action: {
                    sendTestMessage()
                }) {
                    HStack {
                        Image(systemName: "paperplane.fill")
                            .font(.body)

                        Text("Enviar Mensaje de Prueba")
                            .font(.body)
                            .fontWeight(.semibold)

                        Spacer()

                        if testMessagesSent > 0 {
                            Text("(\(testMessagesSent))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.purple)
                    )
                }
                .buttonStyle(PlainButtonStyle())

                // Success confirmation (animated)
                if showMessageSentConfirmation {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("¡Mensaje enviado! Revisa Dynamic Island")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("Pruebas")
        } footer: {
            Text("Los mensajes de prueba se envían a una conversación separada y aparecen como no leídos en Dynamic Island.")
                .font(.caption)
        }
    }

    // MARK: - Features Section

    private var featuresSection: some View {
        Section {
            FeatureRow(
                icon: "sparkles",
                iconColor: .orange,
                title: "Live Activity Activa",
                description: "Islas Dinámicas y pantalla bloqueada",
                isActive: networkManager.hasActiveLiveActivity
            )

            FeatureRow(
                icon: "location.fill",
                iconColor: .green,
                title: "Ubicación Continua",
                description: "Extiende tiempo de fondo ~15-30 min",
                isActive: networkManager.locationService.isMonitoring
            )

            FeatureRow(
                icon: "wifi.router",
                iconColor: .blue,
                title: "Keep-Alive Pings",
                description: "Pings cada 15s para estabilidad de red",
                isActive: stadiumMode.isActive
            )

            if networkManager.connectedPeers.count > 0 {
                FeatureRow(
                    icon: "person.3.fill",
                    iconColor: .purple,
                    title: "\(networkManager.connectedPeers.count) Conexiones Activas",
                    description: "Red LinkMesh funcionando",
                    isActive: true
                )
            }
        } header: {
            Text("Características Activas")
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                StadiumInfoRow(
                    icon: "clock.fill",
                    iconColor: .orange,
                    title: "Tiempo Extendido",
                    description: "Sin Modo Estadio: 3-10 minutos\nCon Modo Estadio: 15-30 minutos"
                )

                Divider()

                StadiumInfoRow(
                    icon: "battery.100",
                    iconColor: .green,
                    title: "Optimizado para Batería",
                    description: "Usa técnicas conservadoras aprobadas por Apple Store para maximizar eficiencia"
                )

                Divider()

                StadiumInfoRow(
                    icon: "lock.shield.fill",
                    iconColor: .blue,
                    title: "Privacidad Protegida",
                    description: "Tu ubicación solo se usa internamente, nunca se comparte sin tu autorización"
                )
            }
            .padding(.vertical, 4)
        } header: {
            Text("Beneficios")
        }
    }

    // MARK: - Technical Details Section

    private var technicalDetailsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Tecnologías Utilizadas:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                TechRow(name: "Live Activities", value: "UI en Dynamic Island")
                TechRow(name: "Location Updates", value: "Extensión de fondo")
                TechRow(name: "Keep-Alive", value: "Estabilidad de red")
                TechRow(name: "MultipeerConnectivity", value: "LinkMesh P2P")
            }
            .padding(.vertical, 4)
        } header: {
            Text("Detalles Técnicos")
        } footer: {
            Text("Estrategia 'Conservadora' aprobada para App Store. Combina múltiples técnicas iOS nativas para máximo tiempo de fondo.")
                .font(.caption)
        }
    }

    // MARK: - Helper Methods

    private func enableStadiumMode() {
        // Check location permissions first
        let authStatus = networkManager.locationService.authorizationStatus

        if authStatus == .authorizedAlways {
            stadiumMode.enable()
        } else if authStatus == .authorizedWhenInUse {
            // Need "Always" permission for background location
            showLocationPermissionAlert = true
        } else {
            // Need to request permission first
            networkManager.locationService.requestPermissions()

            // Wait and check again
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if networkManager.locationService.authorizationStatus == .authorizedAlways ||
                   networkManager.locationService.authorizationStatus == .authorizedWhenInUse {
                    stadiumMode.enable()
                } else {
                    showLocationPermissionAlert = true
                }
            }
        }
    }

    // MARK: - Helper Methods - Test Message

    private func sendTestMessage() {
        let messages = [
            "¡Hola! Este es un mensaje de prueba 📱",
            "Mensaje de prueba #\(testMessagesSent + 1)",
            "Probando el contador de Dynamic Island ✨",
            "Nuevo mensaje desde Modo Estadio 🏟️",
            "Test de Live Activity funcionando 🎉"
        ]

        let senders = [
            "Sistema de Pruebas",
            "Test User",
            "Simulación",
            "Demo",
            "Test Bot"
        ]

        let randomMessage = messages.randomElement() ?? "Mensaje de prueba"
        let randomSender = senders.randomElement() ?? "Test User"

        // Send the message
        networkManager.sendSimulatedMessage(content: randomMessage, sender: randomSender)

        // Update counter
        testMessagesSent += 1

        // Show confirmation with animation
        withAnimation(.spring()) {
            showMessageSentConfirmation = true
        }

        // Hide confirmation after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.spring()) {
                showMessageSentConfirmation = false
            }
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🧪 TEST MESSAGE SENT FROM UI")
        print("   Total test messages: \(testMessagesSent)")
        print("   Sender: \(randomSender)")
        print("   Content: \(randomMessage)")
        print("   ✅ Check Dynamic Island for message counter!")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}

// MARK: - Feature Row Component

struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    var isActive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isActive ? .green : .gray)
        }
    }
}

// MARK: - Stadium Info Row Component

struct StadiumInfoRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Tech Row Component

struct TechRow: View {
    let name: String
    let value: String

    var body: some View {
        HStack {
            Text("•")
                .foregroundColor(.blue)
            Text(name)
                .font(.caption)
                .fontWeight(.medium)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Stadium Mode Explanation View

struct StadiumModeExplanationView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "sportscourt.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)

                        Text("Modo Estadio")
                            .font(.title)
                            .fontWeight(.bold)

                        Text("Mantiene tus conexiones activas durante eventos masivos")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)

                    Divider()

                    // Problem
                    ExplanationSection(
                        icon: "exclamationmark.triangle.fill",
                        iconColor: .orange,
                        title: "El Problema",
                        description: "Normalmente, iOS suspende apps en segundo plano después de 3-10 minutos, desconectando tu LinkMesh cuando minimizas la app."
                    )

                    // Solution
                    ExplanationSection(
                        icon: "lightbulb.fill",
                        iconColor: .yellow,
                        title: "La Solución",
                        description: "El Modo Estadio combina 3 tecnologías iOS para extender el tiempo de conexión hasta 25 minutos en segundo plano."
                    )

                    // How it works
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Cómo Funciona:")
                            .font(.headline)

                        ExplanationStep(
                            number: 1,
                            title: "Live Activity",
                            description: "Muestra tu estado en Dynamic Island y pantalla bloqueada"
                        )

                        ExplanationStep(
                            number: 2,
                            title: "Ubicación Continua",
                            description: "Extiende tiempo de fondo de 10 min → 15-30 min"
                        )

                        ExplanationStep(
                            number: 3,
                            title: "Keep-Alive Pings",
                            description: "Pings cada 15s mantienen conexiones estables"
                        )
                    }

                    Divider()

                    // Use cases
                    ExplanationSection(
                        icon: "flag.checkered.2.crossed",
                        iconColor: .green,
                        title: "Casos de Uso Ideales",
                        description: "• Partidos del Mundial 2026 en estadios\n• Conciertos masivos\n• Festivales con mala señal celular\n• Eventos donde necesitas estar conectado con tu grupo"
                    )

                    // Battery impact
                    ExplanationSection(
                        icon: "battery.75",
                        iconColor: .green,
                        title: "Impacto en Batería",
                        description: "Moderado. Usa técnicas conservadoras aprobadas por Apple Store. Desactiva cuando no lo necesites."
                    )
                }
                .padding()
            }
            .navigationTitle("¿Qué es el Modo Estadio?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Explanation Components

struct ExplanationSection: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(iconColor)

                Text(title)
                    .font(.headline)
            }

            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ExplanationStep: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 28, height: 28)

                Text("\(number)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview("Settings View") {
    StadiumModeSettingsView()
        .environmentObject(NetworkManager())
}

#Preview("Explanation") {
    StadiumModeExplanationView()
}
