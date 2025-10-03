//
//  WatchEmergencyDetector.swift
//  MeshRed Watch App
//
//  Created for CSC 2025 - UNAM
//  Emergency Detection Service for Apple Watch
//  Uses HealthKit Heart Rate + Fall Detection
//

import Foundation
import HealthKit
import WatchKit
import Combine

/// Estado de detección de emergencias
enum EmergencyDetectionState {
    case monitoring           // Monitore normal
    case suspected           // Sospecha de emergencia (1 sensor activo)
    case countdownActive     // Countdown activo (esperando cancelación)
    case confirmed           // Emergencia confirmada (enviada)
    case userCancelled       // Usuario canceló
}

/// Tipo de emergencia detectada
enum DetectedEmergencyType {
    case highHeartRate       // Taquicardia
    case lowHeartRate        // Bradicardia
    case rapidHeartRateChange // Cambio abrupto de HR
    case fall                // Caída detectada
    case inactivity          // Inactividad prolongada después de actividad
    case manual              // Manual (usuario presionó SOS)
}

/// Detector de emergencias para Apple Watch
class WatchEmergencyDetector: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published var detectionState: EmergencyDetectionState = .monitoring
    @Published var currentHeartRate: Double = 0
    @Published var isMonitoring: Bool = false
    @Published var detectedEmergencyType: DetectedEmergencyType?

    // MARK: - Private Properties

    private let healthStore = HKHealthStore()
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var workoutSession: HKWorkoutSession?

    // Historial de HR para detectar cambios abruptos
    private var heartRateHistory: [(bpm: Double, timestamp: Date)] = []
    private let heartRateHistoryLimit = 10  // Últimos 10 samples

    // Umbrales de detección (ajustables por edad/condición)
    private var highHeartRateThreshold: Double = 150  // BPM
    private var lowHeartRateThreshold: Double = 40    // BPM
    private var rapidChangeThreshold: Double = 30     // BPM en 10s

    // Estado de detección
    private var lastEmergencyCheck: Date?
    private let minimumCheckInterval: TimeInterval = 2.0  // No revisar más de cada 2s

    // Cancellables
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    override init() {
        super.init()
        print("🚨 WatchEmergencyDetector: Initialized")
    }

    // MARK: - Public Methods

    /// Iniciar monitoreo de emergencias
    func startMonitoring() {
        print("▶️ WatchEmergencyDetector: Starting monitoring...")

        requestHealthKitAuthorization { [weak self] success in
            guard success else {
                print("❌ WatchEmergencyDetector: HealthKit authorization failed")
                return
            }

            self?.startHeartRateMonitoring()
            self?.isMonitoring = true

            print("✅ WatchEmergencyDetector: Monitoring started")
        }
    }

    /// Detener monitoreo
    func stopMonitoring() {
        print("⏹️ WatchEmergencyDetector: Stopping monitoring...")

        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }

        isMonitoring = false
    }

    /// Confirmar emergencia manualmente
    func confirmEmergency(type: DetectedEmergencyType) {
        detectedEmergencyType = type
        detectionState = .confirmed
        print("🚨 WatchEmergencyDetector: Emergency confirmed - \(type)")
    }

    /// Cancelar emergencia detectada
    func cancelEmergency() {
        detectionState = .userCancelled
        detectedEmergencyType = nil
        print("✅ WatchEmergencyDetector: Emergency cancelled by user")

        // Volver a monitoring después de 3 segundos
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.detectionState = .monitoring
        }
    }

    /// Ajustar umbrales según edad del usuario
    func adjustThresholdsForAge(_ age: Int) {
        // Fórmula: HR max ≈ 220 - edad
        let estimatedMaxHR = 220 - age

        // Taquicardia: 85% del HR max
        highHeartRateThreshold = Double(estimatedMaxHR) * 0.85

        // Bradicardia: ajustar según edad (adultos mayores tienen HR más bajo)
        if age > 65 {
            lowHeartRateThreshold = 45
        } else {
            lowHeartRateThreshold = 40
        }

        print("🎯 WatchEmergencyDetector: Thresholds adjusted for age \(age)")
        print("   High HR: \(highHeartRateThreshold) BPM")
        print("   Low HR: \(lowHeartRateThreshold) BPM")
    }

    // MARK: - HealthKit Authorization

    private func requestHealthKitAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("❌ HealthKit not available on this device")
            completion(false)
            return
        }

        let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let typesToRead: Set<HKObjectType> = [heartRateType]

        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { success, error in
            if let error = error {
                print("❌ HealthKit authorization error: \(error.localizedDescription)")
                completion(false)
                return
            }

            print("✅ HealthKit authorized: \(success)")
            completion(success)
        }
    }

    // MARK: - Heart Rate Monitoring

    private func startHeartRateMonitoring() {
        let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!

        // Query para obtener actualizaciones en tiempo real
        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: nil,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] query, samples, deletedObjects, anchor, error in
            self?.processHeartRateSamples(samples)
        }

        // Handler para actualizaciones continuas
        query.updateHandler = { [weak self] query, samples, deletedObjects, anchor, error in
            self?.processHeartRateSamples(samples)
        }

        healthStore.execute(query)
        heartRateQuery = query

        print("📊 WatchEmergencyDetector: Heart rate monitoring started")
    }

    private func processHeartRateSamples(_ samples: [HKSample]?) {
        guard let heartRateSamples = samples as? [HKQuantitySample] else { return }
        guard !heartRateSamples.isEmpty else { return }

        for sample in heartRateSamples {
            let bpm = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
            let timestamp = sample.endDate

            DispatchQueue.main.async { [weak self] in
                self?.updateHeartRate(bpm: bpm, timestamp: timestamp)
            }
        }
    }

    private func updateHeartRate(bpm: Double, timestamp: Date) {
        // Actualizar UI
        currentHeartRate = bpm

        // Agregar a historial
        heartRateHistory.append((bpm: bpm, timestamp: timestamp))

        // Mantener solo los últimos N samples
        if heartRateHistory.count > heartRateHistoryLimit {
            heartRateHistory.removeFirst()
        }

        // Revisar anomalías
        checkForEmergency()
    }

    // MARK: - Emergency Detection Logic

    private func checkForEmergency() {
        // Rate limiting: no revisar más de cada X segundos
        if let lastCheck = lastEmergencyCheck,
           Date().timeIntervalSince(lastCheck) < minimumCheckInterval {
            return
        }

        lastEmergencyCheck = Date()

        // Solo revisar si estamos en modo monitoring
        guard detectionState == .monitoring else { return }

        // Revisar cada tipo de anomalía
        if let emergencyType = detectAbnormality() {
            triggerEmergencyDetection(type: emergencyType)
        }
    }

    private func detectAbnormality() -> DetectedEmergencyType? {
        let currentBPM = currentHeartRate

        // 1. Taquicardia
        if currentBPM > highHeartRateThreshold {
            print("⚠️ High heart rate detected: \(currentBPM) BPM (threshold: \(highHeartRateThreshold))")
            return .highHeartRate
        }

        // 2. Bradicardia
        if currentBPM < lowHeartRateThreshold && currentBPM > 0 {
            print("⚠️ Low heart rate detected: \(currentBPM) BPM (threshold: \(lowHeartRateThreshold))")
            return .lowHeartRate
        }

        // 3. Cambio abrupto de HR
        if let rapidChange = detectRapidHeartRateChange() {
            print("⚠️ Rapid heart rate change detected: \(rapidChange) BPM")
            return .rapidHeartRateChange
        }

        return nil
    }

    private func detectRapidHeartRateChange() -> Double? {
        guard heartRateHistory.count >= 2 else { return nil }

        // Comparar HR actual con HR de hace 10 segundos
        let now = Date()
        let tenSecondsAgo = now.addingTimeInterval(-10)

        // Buscar el sample más cercano a hace 10 segundos
        guard let oldSample = heartRateHistory.first(where: { $0.timestamp >= tenSecondsAgo }) else {
            return nil
        }

        let currentBPM = heartRateHistory.last?.bpm ?? 0
        let oldBPM = oldSample.bpm

        let change = abs(currentBPM - oldBPM)

        if change > rapidChangeThreshold {
            return change
        }

        return nil
    }

    private func triggerEmergencyDetection(type: DetectedEmergencyType) {
        print("🚨🚨 EMERGENCY DETECTED: \(type)")

        detectedEmergencyType = type
        detectionState = .suspected

        // Haptic de advertencia
        WKInterfaceDevice.current().play(.notification)

        // Esperar 2 segundos antes de activar countdown
        // (para filtrar falsos positivos de spikes momentáneos)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }

            // Si sigue en estado suspected, activar countdown
            if self.detectionState == .suspected {
                self.activateCountdown()
            }
        }
    }

    private func activateCountdown() {
        detectionState = .countdownActive
        print("⏱️ WatchEmergencyDetector: Countdown activated")

        // Haptic más intenso
        WKInterfaceDevice.current().play(.start)
    }

    // MARK: - Fall Detection

    /// Nota: La detección de caídas nativa de watchOS es privada
    /// Solo disponible via API oficial para apps de salud certificadas
    /// Para CSC 2025, nos enfocamos en Heart Rate que es más accesible
    ///
    /// En producción real, se integraría:
    /// - CMMotionActivityManager para detectar cambios de actividad
    /// - Acelerómetro para impactos fuertes
    /// - Pero requiere certificación de Apple para caídas reales

    // MARK: - Helpers

    func getEmergencyDescription() -> String {
        guard let type = detectedEmergencyType else {
            return "Emergencia no especificada"
        }

        switch type {
        case .highHeartRate:
            return "Ritmo cardíaco elevado (\(Int(currentHeartRate)) BPM)"
        case .lowHeartRate:
            return "Ritmo cardíaco bajo (\(Int(currentHeartRate)) BPM)"
        case .rapidHeartRateChange:
            return "Cambio abrupto de ritmo cardíaco"
        case .fall:
            return "Posible caída detectada"
        case .inactivity:
            return "Inactividad prolongada"
        case .manual:
            return "Emergencia activada manualmente"
        }
    }
}
