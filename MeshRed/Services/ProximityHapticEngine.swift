//
//  ProximityHapticEngine.swift
//  MeshRed - StadiumConnect Pro
//
//  Specialized Haptic Engine for UWB Proximity Navigation
//  Provides continuous tactile feedback during navigation to help users find others
//

import Foundation
import CoreHaptics
#if canImport(UIKit)
import UIKit
#endif
import simd

/// Proximity zones based on distance
enum ProximityZone {
    case veryFar    // > 20m - no feedback
    case far        // 10-20m - slow pulses
    case near       // 5-10m - moderate pulses
    case close      // 2-5m - fast pulses
    case veryClose  // 1-2m - very fast pulses
    case arriving   // < 1m - continuous "you're here"

    var pulsInterval: TimeInterval {
        switch self {
        case .veryFar: return 5.0
        case .far: return 3.0
        case .near: return 2.0
        case .close: return 1.0
        case .veryClose: return 0.5
        case .arriving: return 0.2  // Almost continuous
        }
    }

    var intensity: Float {
        switch self {
        case .veryFar: return 0.2
        case .far: return 0.3
        case .near: return 0.5
        case .close: return 0.6
        case .veryClose: return 0.8
        case .arriving: return 1.0
        }
    }

    var sharpness: Float {
        switch self {
        case .veryFar, .far: return 0.3
        case .near: return 0.5
        case .close: return 0.6
        case .veryClose: return 0.7
        case .arriving: return 0.9
        }
    }
}

/// Direction relative to user heading
enum RelativeDirection {
    case ahead      // ±15°
    case slightRight // 15-45°
    case right      // 45-90°
    case sharpRight // 90-135°
    case behind     // > 135°
    case slightLeft // -15 to -45°
    case left       // -45 to -90°
    case sharpLeft  // -90 to -135°

    var description: String {
        switch self {
        case .ahead: return "Frente"
        case .slightRight: return "Leve derecha"
        case .right: return "Derecha"
        case .sharpRight: return "Giro derecha"
        case .behind: return "Atrás"
        case .slightLeft: return "Leve izquierda"
        case .left: return "Izquierda"
        case .sharpLeft: return "Giro izquierda"
        }
    }

    static func from(bearing: Double) -> RelativeDirection {
        let normalized = bearing  // Already normalized -180 to 180

        switch normalized {
        case -15...15:
            return .ahead
        case 15..<45:
            return .slightRight
        case 45..<90:
            return .right
        case 90..<135:
            return .sharpRight
        case 135...180, -180..<(-135):
            return .behind
        case -45..<(-15):
            return .slightLeft
        case -90..<(-45):
            return .left
        case -135..<(-90):
            return .sharpLeft
        default:
            return .ahead
        }
    }
}

/// Proximity haptic engine for UWB navigation
class ProximityHapticEngine {

    // MARK: - Published Properties
    var isActive: Bool = false
    var currentZone: ProximityZone = .veryFar
    var currentDirection: RelativeDirection = .ahead
    var currentDistance: Float = 100.0

    // MARK: - Dependencies
    private let hapticManager = HapticManager.shared
    private let settings = AccessibilitySettingsManager.shared

    // MARK: - Core Haptics
    private var hapticEngine: CHHapticEngine?
    private var continuousPlayer: CHHapticAdvancedPatternPlayer?
    private var supportsHaptics: Bool = false

    // MARK: - State
    private var lastPulseTime: Date = Date.distantPast
    private var lastZone: ProximityZone = .veryFar
    private var lastDirection: RelativeDirection = .ahead

    // MARK: - Timer
    private var pulseTimer: Timer?

    // MARK: - Queue
    private let queue = DispatchQueue(label: "com.meshred.proximityHaptics", qos: .userInitiated)

    // MARK: - Initialization

    init() {
        supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

        if supportsHaptics {
            setupCoreHapticsEngine()
        }

        print("🎯 ProximityHapticEngine: Initialized (Core Haptics: \(supportsHaptics))")
    }

    deinit {
        stop()
    }

    // MARK: - Setup

    private func setupCoreHapticsEngine() {
        do {
            hapticEngine = try CHHapticEngine()

            hapticEngine?.resetHandler = { [weak self] in
                print("⚠️ ProximityHapticEngine: Engine reset")
                self?.restartEngine()
            }

            hapticEngine?.stoppedHandler = { reason in
                print("⚠️ ProximityHapticEngine: Engine stopped - \(reason)")
            }

            try hapticEngine?.start()
            print("✅ ProximityHapticEngine: Core Haptics engine started")

        } catch {
            print("❌ ProximityHapticEngine: Failed to create engine: \(error)")
            supportsHaptics = false
        }
    }

    private func restartEngine() {
        queue.async { [weak self] in
            do {
                try self?.hapticEngine?.start()
                print("✅ ProximityHapticEngine: Engine restarted")
            } catch {
                print("❌ ProximityHapticEngine: Failed to restart: \(error)")
            }
        }
    }

    // MARK: - Public API

    /// Start proximity haptic feedback
    func start() {
        guard settings.hapticsEnabled else {
            print("⚠️ ProximityHapticEngine: Haptics disabled in settings")
            return
        }

        guard !isActive else {
            print("⚠️ ProximityHapticEngine: Already active")
            return
        }

        isActive = true

        // Initial pulse
        playProximityPulse()

        // Start timer for continuous feedback
        startPulseTimer()

        print("🎯 ProximityHapticEngine: Started")
    }

    /// Stop proximity haptic feedback
    func stop() {
        guard isActive else { return }

        stopPulseTimer()
        stopContinuousPlayer()

        isActive = false
        currentZone = .veryFar
        currentDirection = .ahead

        print("🎯 ProximityHapticEngine: Stopped")
    }

    /// Update proximity based on distance and direction
    /// - Parameters:
    ///   - distance: Distance to target in meters
    ///   - direction: Direction vector (optional, from UWB)
    func updateProximity(distance: Float, direction: SIMD3<Float>? = nil) {
        guard isActive else { return }

        // Update distance
        currentDistance = distance

        // Calculate zone
        let newZone = zoneFromDistance(distance)

        // Check if zone changed significantly
        if newZone != lastZone {
            print("🎯 ProximityHapticEngine: Zone changed: \(lastZone) → \(newZone) (\(String(format: "%.1f", distance))m)")

            currentZone = newZone

            lastZone = newZone

            // Adjust pulse timer for new zone
            restartPulseTimer()

            // Special feedback for zone transitions
            if newZone == .arriving {
                playArrivalPattern()
            }
        }
    }

    /// Update direction based on relative bearing
    /// - Parameter bearing: Relative bearing in degrees (-180 to 180)
    func updateBearing(relative bearing: Double) {
        guard isActive else { return }

        let newDirection = RelativeDirection.from(bearing: bearing)

        if newDirection != lastDirection {
            print("🎯 ProximityHapticEngine: Direction changed: \(lastDirection.description) → \(newDirection.description)")

            currentDirection = newDirection

            lastDirection = newDirection

            // Directional feedback (subtle)
            playDirectionalHint(newDirection)
        }
    }

    // MARK: - Zone Calculation

    private func zoneFromDistance(_ distance: Float) -> ProximityZone {
        switch distance {
        case 0..<1:
            return .arriving
        case 1..<2:
            return .veryClose
        case 2..<5:
            return .close
        case 5..<10:
            return .near
        case 10..<20:
            return .far
        default:
            return .veryFar
        }
    }

    // MARK: - Pulse Timer

    private func startPulseTimer() {
        stopPulseTimer()

        let interval = currentZone.pulsInterval

        pulseTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.playProximityPulse()
        }

        print("🎯 ProximityHapticEngine: Pulse timer started (interval: \(String(format: "%.1f", interval))s)")
    }

    private func restartPulseTimer() {
        startPulseTimer()
    }

    private func stopPulseTimer() {
        pulseTimer?.invalidate()
        pulseTimer = nil
    }

    // MARK: - Haptic Patterns

    private func playProximityPulse() {
        guard settings.hapticsEnabled else { return }

        let now = Date()
        let timeSinceLastPulse = now.timeIntervalSince(lastPulseTime)

        // Throttle very fast pulses slightly
        if timeSinceLastPulse < 0.1 {
            return
        }

        lastPulseTime = now

        if supportsHaptics {
            playCoreHapticProximityPulse()
        } else {
            playFallbackProximityPulse()
        }
    }

    private func playCoreHapticProximityPulse() {
        guard let engine = hapticEngine else { return }

        do {
            let intensity = currentZone.intensity * Float(intensityMultiplier())
            let sharpness = currentZone.sharpness

            // Create pulse event
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                ],
                relativeTime: 0
            )

            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)

        } catch {
            print("❌ ProximityHapticEngine: Failed to play pulse: \(error)")
        }
    }

    private func playFallbackProximityPulse() {
        #if canImport(UIKit)
        let intensity = currentZone.intensity * Float(intensityMultiplier())

        DispatchQueue.main.async {
            switch self.currentZone {
            case .veryFar, .far:
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred(intensity: CGFloat(intensity))

            case .near, .close:
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred(intensity: CGFloat(intensity))

            case .veryClose, .arriving:
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.impactOccurred(intensity: CGFloat(intensity))
            }
        }
        #endif
    }

    private func playArrivalPattern() {
        // Special "You've arrived!" pattern
        guard supportsHaptics, let engine = hapticEngine else {
            // Fallback: 3 quick heavy pulses
            #if canImport(UIKit)
            DispatchQueue.main.async {
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                for i in 0..<3 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.15) {
                        generator.impactOccurred(intensity: 1.0)
                    }
                }
            }
            #endif
            return
        }

        do {
            let intensity = Float(intensityMultiplier())
            var events: [CHHapticEvent] = []

            // 3 ascending pulses
            for i in 0..<3 {
                let relativeIntensity = intensity * Float([0.6, 0.8, 1.0][i])
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: relativeIntensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
                    ],
                    relativeTime: Double(i) * 0.15
                ))
            }

            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)

            print("🎯 ProximityHapticEngine: Played arrival pattern")

        } catch {
            print("❌ ProximityHapticEngine: Failed to play arrival: \(error)")
        }
    }

    private func playDirectionalHint(_ direction: RelativeDirection) {
        // Subtle directional feedback
        guard supportsHaptics, let engine = hapticEngine else {
            return  // Skip directional hints on fallback
        }

        do {
            let intensity = Float(intensityMultiplier()) * 0.4  // Subtle
            var events: [CHHapticEvent] = []

            switch direction {
            case .ahead:
                // Single centered pulse
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                    ],
                    relativeTime: 0
                ))

            case .slightRight, .right, .sharpRight:
                // Two quick pulses (simulating right-biased)
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.7),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
                    ],
                    relativeTime: 0
                ))
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
                    ],
                    relativeTime: 0.08
                ))

            case .slightLeft, .left, .sharpLeft:
                // Two quick pulses (simulating left-biased)
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
                    ],
                    relativeTime: 0
                ))
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.7),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
                    ],
                    relativeTime: 0.08
                ))

            case .behind:
                // Double tap (turn around)
                for i in 0..<2 {
                    events.append(CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.8),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
                        ],
                        relativeTime: Double(i) * 0.12
                    ))
                }
            }

            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)

        } catch {
            print("❌ ProximityHapticEngine: Failed to play directional hint: \(error)")
        }
    }

    private func stopContinuousPlayer() {
        do {
            try continuousPlayer?.stop(atTime: CHHapticTimeImmediate)
            continuousPlayer = nil
        } catch {
            print("❌ ProximityHapticEngine: Failed to stop continuous player: \(error)")
        }
    }

    // MARK: - Helpers

    private func intensityMultiplier() -> Double {
        switch settings.hapticIntensity {
        case "light":
            return 0.6
        case "strong":
            return 1.0
        default:  // "medium"
            return 0.8
        }
    }
}
