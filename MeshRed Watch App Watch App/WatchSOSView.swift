//
//  WatchSOSView.swift
//  MeshRed Watch App
//
//  Created for CSC 2025 - UNAM
//  Emergency SOS Button for Apple Watch
//

import SwiftUI
import WatchKit

struct WatchSOSView: View {
    @StateObject private var emergencyDetector = WatchEmergencyDetector()
    @State private var isPressed = false
    @State private var showCountdown = false
    @State private var showEmergencyDetected = false

    var body: some View {
        ZStack {
            // Botón SOS gigante que ocupa toda la pantalla
            Button(action: triggerManualSOS) {
                ZStack {
                    // Fondo pulsante
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.red.opacity(isPressed ? 0.9 : 1.0),
                                    Color.red.opacity(isPressed ? 0.7 : 0.85)
                                ],
                                center: .center,
                                startRadius: 20,
                                endRadius: 100
                            )
                        )
                        .scaleEffect(isPressed ? 0.95 : 1.0)
                        .animation(.easeInOut(duration: 0.1), value: isPressed)

                    // Contenido
                    VStack(spacing: 8) {
                        Image(systemName: "sos.circle.fill")
                            .font(.system(size: 50, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)

                        Text("SOS")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)

                        Text("Mantén presionado")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        isPressed = true
                    }
                    .onEnded { _ in
                        isPressed = false
                    }
            )
            .edgesIgnoringSafeArea(.all)

            // Indicador de monitoreo activo (esquina superior)
            if emergencyDetector.isMonitoring {
                VStack {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.pink)

                            Text("\(Int(emergencyDetector.currentHeartRate))")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.6))
                        )

                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                    Spacer()
                }
            }
        }
        .sheet(isPresented: $showCountdown) {
            WatchEmergencyCountdownView(
                emergencyType: .manual,
                onConfirm: sendSOS,
                onCancel: {
                    showCountdown = false
                }
            )
        }
        .sheet(isPresented: $showEmergencyDetected) {
            if let type = emergencyDetector.detectedEmergencyType {
                WatchEmergencyCountdownView(
                    emergencyType: type,
                    description: emergencyDetector.getEmergencyDescription(),
                    onConfirm: sendAutoDetectedSOS,
                    onCancel: {
                        emergencyDetector.cancelEmergency()
                        showEmergencyDetected = false
                    }
                )
            }
        }
        .onAppear {
            // Iniciar monitoreo automático
            emergencyDetector.startMonitoring()
        }
        .onChange(of: emergencyDetector.detectionState) { oldValue, newValue in
            // Mostrar countdown cuando se detecta emergencia automática
            if newValue == .countdownActive {
                showEmergencyDetected = true
            }
        }
    }

    private func triggerManualSOS() {
        // Haptic fuerte
        WKInterfaceDevice.current().play(.notification)

        showCountdown = true
    }

    private func sendSOS() {
        print("🚨 Sending MANUAL SOS from Watch...")

        // TODO: Enviar SOS via WatchConnectivity al iPhone
        // let alert = SOSAlert(...)
        // WatchConnectivityManager.shared.sendSOS(alert)

        // Haptic de confirmación
        WKInterfaceDevice.current().play(.success)

        showCountdown = false
    }

    private func sendAutoDetectedSOS() {
        print("🚨 Sending AUTO-DETECTED SOS from Watch...")

        // TODO: Enviar SOS con información del sensor
        // let alert = SOSAlert(...)
        // WatchConnectivityManager.shared.sendSOS(alert)

        // Haptic de confirmación
        WKInterfaceDevice.current().play(.success)

        emergencyDetector.confirmEmergency(type: emergencyDetector.detectedEmergencyType!)
        showEmergencyDetected = false
    }
}

// MARK: - Countdown View

struct WatchEmergencyCountdownView: View {
    let emergencyType: DetectedEmergencyType
    var description: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var countdown = 15
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 16) {
            // Tipo de emergencia
            VStack(spacing: 4) {
                Image(systemName: iconForType)
                    .font(.system(size: 32))
                    .foregroundColor(.red)

                Text(titleForType)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)

                if let desc = description {
                    Text(desc)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            // Countdown circular
            ZStack {
                Circle()
                    .stroke(Color.red.opacity(0.3), lineWidth: 6)
                    .frame(width: 70, height: 70)

                Circle()
                    .trim(from: 0, to: CGFloat(countdown) / 15.0)
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(-90))

                Text("\(countdown)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.red)
            }

            // Botón CANCELAR grande
            Button(action: {
                timer?.invalidate()
                WKInterfaceDevice.current().play(.stop)
                onCancel()
            }) {
                Text("CANCELAR")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .onAppear {
            startCountdown()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func startCountdown() {
        // Haptic inicial fuerte
        WKInterfaceDevice.current().play(.start)

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if countdown > 0 {
                countdown -= 1

                // Haptic cada segundo
                if countdown <= 5 {
                    WKInterfaceDevice.current().play(.click)
                }
            } else {
                // Countdown terminado → enviar SOS
                timer?.invalidate()
                WKInterfaceDevice.current().play(.success)
                onConfirm()
            }
        }
    }

    private var iconForType: String {
        switch emergencyType {
        case .manual:
            return "hand.raised.fill"
        case .highHeartRate, .lowHeartRate, .rapidHeartRateChange:
            return "heart.fill"
        case .fall:
            return "figure.fall"
        case .inactivity:
            return "bed.double.fill"
        }
    }

    private var titleForType: String {
        switch emergencyType {
        case .manual:
            return "Enviar SOS"
        case .highHeartRate:
            return "Ritmo Cardíaco Elevado"
        case .lowHeartRate:
            return "Ritmo Cardíaco Bajo"
        case .rapidHeartRateChange:
            return "Cambio Abrupto de HR"
        case .fall:
            return "Posible Caída"
        case .inactivity:
            return "Inactividad Detectada"
        }
    }
}

#Preview {
    WatchSOSView()
}
