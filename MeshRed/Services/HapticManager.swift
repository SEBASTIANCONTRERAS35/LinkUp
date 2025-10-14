//
//  HapticManager.swift
//  MeshRed - StadiumConnect Pro
//
//  Centralized Haptic Feedback Service for CSC 2025
//  Provides accessible, configurable haptic patterns for navigation, emergencies, and UI
//

import Foundation
import CoreHaptics
#if canImport(UIKit)
import UIKit
#endif
import Combine
import os

/// Priority levels for haptic feedback (higher priority can interrupt lower)
enum HapticPriority: Int, Comparable {
    case emergency = 0      // SOS, critical alerts (interrupts everything)
    case navigation = 1     // UWB proximity, geofencing (interrupts UI)
    case notification = 2   // Network events, messages (interrupts UI)
    case ui = 3            // Button taps, selections (lowest priority)

    static func < (lhs: HapticPriority, rhs: HapticPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// Basic haptic feedback types (using UIFeedbackGenerator)
enum BasicHapticType {
    case light
    case medium
    case heavy
    case soft
    case rigid
    case success
    case warning
    case error
    case selection
}

/// Advanced haptic pattern types (using Core Haptics)
enum HapticPatternType {
    case sosEmergency
    case sosSecurity
    case sosLostChild
    case peerConnected
    case peerDisconnected
    case connectionQualityDrop
    case messageReceived
    case messageSent
}

/// Geofence transition type
enum GeofenceTransitionType {
    case entry
    case exit
    case preWarning  // Approaching zone
}

/// Centralized haptic feedback manager
class HapticManager: NSObject, ObservableObject {

    // MARK: - Singleton
    static let shared = HapticManager()

    // MARK: - Settings
    private var settings = AccessibilitySettingsManager.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Core Haptics Engine
    private var hapticEngine: CHHapticEngine?
    private var supportsHaptics: Bool = false

    // MARK: - Feedback Generators (Fallback)
    #if canImport(UIKit)
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let impactSoft = UIImpactFeedbackGenerator(style: .soft)
    private let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private let notification = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()
    #endif

    // MARK: - State
    private var currentPriority: HapticPriority = .ui
    private var isPlayingPattern = false
    private let queue = DispatchQueue(label: "com.meshred.haptics", qos: .userInitiated)

    // MARK: - Throttling
    private var lastHapticTime: [HapticPriority: Date] = [:]
    private let minimumInterval: TimeInterval = 0.1  // 100ms minimum between haptics

    // MARK: - Initialization

    private override init() {
        super.init()

        // Check device capability
        supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

        if supportsHaptics {
            setupCoreHapticsEngine()
        }

        // Prepare feedback generators
        prepareGenerators()

        // Observe settings changes (DEBOUNCED to prevent spam during rapid UserDefaults validations)
        settings.objectWillChange
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleSettingsChange()
            }
            .store(in: &cancellables)

        LoggingService.network.info("🎯 HapticManager: Initialized")
        LoggingService.network.info("   Core Haptics supported: \(self.supportsHaptics)")
        LoggingService.network.info("   Haptics enabled: \(self.settings.hapticsEnabled)")
        LoggingService.network.info("   Intensity: \(self.settings.hapticIntensity)")
    }

    // MARK: - Core Haptics Setup

    private func setupCoreHapticsEngine() {
        do {
            hapticEngine = try CHHapticEngine()

            // Handle engine reset (device locked, backgrounded, etc.)
            hapticEngine?.resetHandler = { [weak self] in
                LoggingService.network.info("⚠️ HapticManager: Engine reset, restarting...")
                self?.restartEngine()
            }

            // Handle engine stopped
            hapticEngine?.stoppedHandler = { reason in
                LoggingService.network.info("⚠️ HapticManager: Engine stopped - \(String(describing: reason))")
            }

            // Start engine
            try hapticEngine?.start()

            LoggingService.network.info("✅ HapticManager: Core Haptics engine started")

        } catch {
            LoggingService.network.info("❌ HapticManager: Failed to create haptic engine: \(error)")
            supportsHaptics = false
        }
    }

    private func restartEngine() {
        queue.async { [weak self] in
            guard let self = self else { return }

            do {
                try self.hapticEngine?.start()
                LoggingService.network.info("✅ HapticManager: Engine restarted")
            } catch {
                LoggingService.network.info("❌ HapticManager: Failed to restart engine: \(error)")
            }
        }
    }

    private func prepareGenerators() {
        #if canImport(UIKit)
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        impactSoft.prepare()
        impactRigid.prepare()
        notification.prepare()
        selection.prepare()
        #endif
    }

    private func handleSettingsChange() {
        LoggingService.network.info("🎯 HapticManager: Settings updated - Enabled: \(self.settings.hapticsEnabled), Intensity: \(self.settings.hapticIntensity)")
    }

    // MARK: - Public API - Basic Haptics

    /// Play basic haptic feedback (uses UIFeedbackGenerator)
    /// - Parameters:
    ///   - type: Type of haptic feedback
    ///   - priority: Priority level (determines if it can interrupt current haptic)
    func play(_ type: BasicHapticType, priority: HapticPriority = .ui) {
        guard shouldPlayHaptic(priority: priority) else { return }

        queue.async { [weak self] in
            guard let self = self else { return }

            // Check throttling
            if !self.canPlayHaptic(priority: priority) {
                return
            }

            // Update state
            self.currentPriority = priority
            self.lastHapticTime[priority] = Date()

            // Play on main thread
            DispatchQueue.main.async {
                self.playBasicHaptic(type)
            }
        }
    }

    private func playBasicHaptic(_ type: BasicHapticType) {
        #if canImport(UIKit)
        let intensity = intensityMultiplier()

        switch type {
        case .light:
            impactLight.impactOccurred(intensity: CGFloat(intensity * 0.5))
        case .medium:
            impactMedium.impactOccurred(intensity: CGFloat(intensity * 0.7))
        case .heavy:
            impactHeavy.impactOccurred(intensity: CGFloat(intensity))
        case .soft:
            impactSoft.impactOccurred(intensity: CGFloat(intensity * 0.6))
        case .rigid:
            impactRigid.impactOccurred(intensity: CGFloat(intensity * 0.8))
        case .success:
            notification.notificationOccurred(.success)
        case .warning:
            notification.notificationOccurred(.warning)
        case .error:
            notification.notificationOccurred(.error)
        case .selection:
            selection.selectionChanged()
        }

        LoggingService.network.info("🎯 HapticManager: Played \(String(describing: type), privacy: .public) (priority: \(String(describing: self.currentPriority), privacy: .public))")
        #endif
    }

    // MARK: - Public API - Pattern Haptics

    /// Play advanced haptic pattern (uses Core Haptics if available, fallback to basic)
    /// - Parameters:
    ///   - pattern: Pattern type to play
    ///   - priority: Priority level
    func playPattern(_ pattern: HapticPatternType, priority: HapticPriority = .notification) {
        guard shouldPlayHaptic(priority: priority) else { return }

        queue.async { [weak self] in
            guard let self = self else { return }

            // Check throttling
            if !self.canPlayHaptic(priority: priority) {
                return
            }

            // Update state
            self.currentPriority = priority
            self.lastHapticTime[priority] = Date()
            self.isPlayingPattern = true

            if self.supportsHaptics {
                self.playCoreHapticPattern(pattern)
            } else {
                self.playFallbackPattern(pattern)
            }
        }
    }

    // MARK: - Public API - Geofence Haptics

    /// Play geofence transition haptic
    /// - Parameters:
    ///   - transition: Entry, exit, or pre-warning
    ///   - category: Geofence category (determines pattern variation)
    func playGeofenceTransition(_ transition: GeofenceTransitionType, category: LinkFenceCategory) {
        guard shouldPlayHaptic(priority: .navigation) else { return }
        guard settings.hapticOnGeofenceTransitions else { return }

        queue.async { [weak self] in
            guard let self = self else { return }

            self.currentPriority = .navigation
            self.lastHapticTime[.navigation] = Date()

            DispatchQueue.main.async {
                self.playGeofenceHaptic(transition: transition, category: category)
            }
        }

        LoggingService.network.info("🎯 HapticManager: Geofence \(String(describing: transition), privacy: .public) - \(category.rawValue, privacy: .public)")
    }

    private func playGeofenceHaptic(transition: GeofenceTransitionType, category: LinkFenceCategory) {
        #if canImport(UIKit)
        let intensity = intensityMultiplier()

        switch transition {
        case .entry:
            // Entry patterns vary by category
            switch category {
            case .bathrooms:
                // 2 quick light pulses
                impactLight.impactOccurred(intensity: CGFloat(intensity * 0.5))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.impactLight.impactOccurred(intensity: CGFloat(intensity * 0.5))
                }
            case .exits:
                // 1 medium pulse
                impactMedium.impactOccurred(intensity: CGFloat(intensity * 0.7))
            case .concessions:
                // 3 rapid light pulses
                for i in 0..<3 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.08) { [weak self] in
                        self?.impactLight.impactOccurred(intensity: CGFloat(intensity * 0.4))
                    }
                }
            case .familyZone:
                // Soft wave
                impactSoft.impactOccurred(intensity: CGFloat(intensity * 0.6))
            case .custom:
                // Standard entry
                impactMedium.impactOccurred(intensity: CGFloat(intensity * 0.6))
            default:
                // Fallback for any new or unrecognized categories
                impactMedium.impactOccurred(intensity: CGFloat(intensity * 0.6))
            }

        case .exit:
            // Exit is slightly softer than entry
            impactLight.impactOccurred(intensity: CGFloat(intensity * 0.4))

        case .preWarning:
            // Subtle warning 20m before zone
            impactSoft.impactOccurred(intensity: CGFloat(intensity * 0.3))
        }
        #endif
    }

    // MARK: - Helper Methods

    private func shouldPlayHaptic(priority: HapticPriority) -> Bool {
        // Check if haptics are globally enabled
        guard settings.hapticsEnabled else {
            return false
        }

        // Check battery saver mode
        if settings.batterySaverMode && priority > .navigation {
            return false  // Only emergency and navigation in battery saver
        }

        // Check context-specific settings
        switch priority {
        case .ui:
            return settings.hapticOnUIInteractions
        case .notification:
            return settings.hapticOnConnectionChanges
        case .navigation, .emergency:
            return true  // Always allow navigation and emergency
        }
    }

    private func canPlayHaptic(priority: HapticPriority) -> Bool {
        // Emergency always plays
        if priority == .emergency {
            return true
        }

        // Check if currently playing higher priority
        if isPlayingPattern && priority > currentPriority {
            return false
        }

        // Check throttling
        if let lastTime = lastHapticTime[priority] {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < minimumInterval {
                return false
            }
        }

        return true
    }

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

    // MARK: - Core Haptics Patterns

    private func playCoreHapticPattern(_ pattern: HapticPatternType) {
        guard let engine = hapticEngine else {
            playFallbackPattern(pattern)
            return
        }

        do {
            let hapticPattern = try createCoreHapticPattern(pattern)
            let player = try engine.makePlayer(with: hapticPattern)

            try player.start(atTime: CHHapticTimeImmediate)

            // Mark as not playing after pattern duration
            DispatchQueue.main.asyncAfter(deadline: .now() + estimatedDuration(pattern)) { [weak self] in
                self?.isPlayingPattern = false
            }

            LoggingService.network.info("🎯 HapticManager: Played Core Haptic pattern \(String(describing: pattern), privacy: .public)")

        } catch {
            LoggingService.network.info("❌ HapticManager: Failed to play pattern: \(error)")
            playFallbackPattern(pattern)
        }
    }

    private func createCoreHapticPattern(_ pattern: HapticPatternType) throws -> CHHapticPattern {
        let intensity = Float(intensityMultiplier())
        var events: [CHHapticEvent] = []

        switch pattern {
        case .sosEmergency:
            // 3 heavy pulses + pause + 2 medium pulses (~1.5s total)
            // HEAVY pulses
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
            ], relativeTime: 0))

            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
            ], relativeTime: 0.3))

            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
            ], relativeTime: 0.6))

            // MEDIUM pulses after pause
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.7),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            ], relativeTime: 1.0))

            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.7),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            ], relativeTime: 1.25))

        case .sosSecurity:
            // 3x [2 sharp rapid pulses] (urgent pattern)
            for cycle in 0..<3 {
                let baseTime = Double(cycle) * 0.4
                events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                ], relativeTime: baseTime))

                events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                ], relativeTime: baseTime + 0.1))
            }

        case .sosLostChild:
            // Gentle wave pattern (not alarming)
            for i in 0..<4 {
                let relativeIntensity = intensity * Float([0.4, 0.6, 0.6, 0.4][i])
                events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: relativeIntensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                ], relativeTime: Double(i) * 0.2))
            }

        case .peerConnected:
            // Success notification + light tap
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.6),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            ], relativeTime: 0))

        case .peerDisconnected:
            // Warning + descending pulse
            events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.6),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
            ], relativeTime: 0, duration: 0.2))

        case .connectionQualityDrop:
            // Single warning tap
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.5),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
            ], relativeTime: 0))

        case .messageReceived:
            // Light notification
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.4),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
            ], relativeTime: 0))

        case .messageSent:
            // Confirmation tap
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.5),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
            ], relativeTime: 0))
        }

        return try CHHapticPattern(events: events, parameters: [])
    }

    private func estimatedDuration(_ pattern: HapticPatternType) -> TimeInterval {
        switch pattern {
        case .sosEmergency:
            return 1.5
        case .sosSecurity:
            return 1.2
        case .sosLostChild:
            return 0.8
        case .peerConnected, .peerDisconnected, .connectionQualityDrop:
            return 0.3
        case .messageReceived, .messageSent:
            return 0.2
        }
    }

    // MARK: - Fallback Patterns (UIFeedbackGenerator)

    private func playFallbackPattern(_ pattern: HapticPatternType) {
        #if canImport(UIKit)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            switch pattern {
            case .sosEmergency:
                // Simulate with heavy impacts
                self.impactHeavy.impactOccurred()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.impactHeavy.impactOccurred()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self.impactHeavy.impactOccurred()
                }

            case .sosSecurity:
                self.notification.notificationOccurred(.warning)

            case .sosLostChild:
                self.impactSoft.impactOccurred()

            case .peerConnected:
                self.notification.notificationOccurred(.success)

            case .peerDisconnected:
                self.notification.notificationOccurred(.warning)

            case .connectionQualityDrop:
                self.impactLight.impactOccurred()

            case .messageReceived, .messageSent:
                self.impactLight.impactOccurred()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + self.estimatedDuration(pattern)) { [weak self] in
                self?.isPlayingPattern = false
            }
        }

        LoggingService.network.info("🎯 HapticManager: Played fallback pattern \(String(describing: pattern), privacy: .public)")
        #endif
    }

    // MARK: - Control Methods

    /// Stop all haptic feedback immediately
    func stopAll() {
        queue.async { [weak self] in
            self?.isPlayingPattern = false
            self?.currentPriority = .ui

            // Stop Core Haptics engine
            try? self?.hapticEngine?.stop()

            // Restart for next use
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                try? self?.hapticEngine?.start()
            }
        }

        LoggingService.network.info("⏹️ HapticManager: Stopped all haptics")
    }
}

