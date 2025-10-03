//
//  AccessibilitySettingsManager.swift
//  MeshRed - StadiumConnect Pro
//
//  Accessibility Settings Manager for CSC 2025
//  Manages all user preferences for accessibility features
//

import SwiftUI
import Combine

// MARK: - Button Size Options
enum ButtonSize: String, CaseIterable {
    case small = "small"
    case normal = "normal"
    case large = "large"

    var displayName: String {
        switch self {
        case .small: return "Pequeño"
        case .normal: return "Predeterminado"
        case .large: return "Agrandado"
        }
    }

    var multiplier: Double {
        switch self {
        case .small: return 0.85
        case .normal: return 1.0
        case .large: return 1.3
        }
    }
}

/// Centralized manager for all accessibility settings
/// Uses @AppStorage for automatic UserDefaults persistence
class AccessibilitySettingsManager: ObservableObject {

    // MARK: - Singleton
    static let shared = AccessibilitySettingsManager()

    // MARK: - 🎙️ VoiceOver & Audio Settings

    @AppStorage("accessibility.voiceOver.enableHints")
    var enableVoiceOverHints: Bool = true

    @AppStorage("accessibility.voiceOver.speakingRate")
    var voiceOverSpeakingRate: Double = 1.0 // 0.5 - 2.0

    @AppStorage("accessibility.voiceOver.pitch")
    var voiceOverPitch: Double = 1.0 // 0.5 - 2.0

    @AppStorage("accessibility.audio.announceNetworkChanges")
    var announceNetworkChanges: Bool = true

    @AppStorage("accessibility.audio.announceGeofenceTransitions")
    var announceGeofenceTransitions: Bool = true

    @AppStorage("accessibility.audio.emergencyAlertSound")
    var emergencyAlertSound: String = "default" // default, siren, alert, gentle

    @AppStorage("accessibility.audio.soundEffectsVolume")
    var soundEffectsVolume: Double = 0.7 // 0.0 - 1.0

    // MARK: - 📏 Dynamic Type & Visual Settings

    @AppStorage("accessibility.visual.maximumTextSize")
    var maximumTextSize: String = "xxxLarge" // xxxLarge, accessibility5

    @AppStorage("accessibility.visual.minimumTextSize")
    var minimumTextSize: String = "small"

    @AppStorage("accessibility.visual.buttonSize")
    private var buttonSizeRaw: String = ButtonSize.normal.rawValue

    /// Button size setting (small, normal, large)
    var buttonSize: ButtonSize {
        get {
            ButtonSize(rawValue: buttonSizeRaw) ?? .normal
        }
        set {
            buttonSizeRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    /// Computed multiplier based on button size (for backward compatibility)
    var buttonSizeMultiplier: Double {
        buttonSize.multiplier
    }

    @AppStorage("accessibility.visual.enableHighContrast")
    var enableHighContrast: Bool = false

    @AppStorage("accessibility.visual.preferBoldText")
    var preferBoldText: Bool = false

    @AppStorage("accessibility.visual.reduceTransparency")
    var reduceTransparency: Bool = false

    @AppStorage("accessibility.visual.showButtonLabels")
    var showButtonLabels: Bool = true

    // MARK: - 📳 Haptic Feedback Settings

    @AppStorage("accessibility.haptic.enabled")
    var hapticsEnabled: Bool = true

    @AppStorage("accessibility.haptic.intensity")
    var hapticIntensity: String = "medium" // light, medium, strong

    @AppStorage("accessibility.haptic.emergencyPattern")
    var emergencyHapticPattern: String = "warning" // warning, urgent, critical

    @AppStorage("accessibility.haptic.connectionChanges")
    var hapticOnConnectionChanges: Bool = true

    @AppStorage("accessibility.haptic.uiInteractions")
    var hapticOnUIInteractions: Bool = true

    @AppStorage("accessibility.haptic.linkfenceTransitions")
    var hapticOnGeofenceTransitions: Bool = true

    // MARK: - 🎬 Animations & Motion Settings

    @AppStorage("accessibility.motion.reduceMotionLevel")
    var reduceMotionLevel: String = "none" // none, some, all

    @AppStorage("accessibility.motion.animationSpeed")
    var animationSpeedMultiplier: Double = 1.0 // 0.5 - 2.0

    @AppStorage("accessibility.motion.disableParallax")
    var disableParallax: Bool = false

    @AppStorage("accessibility.motion.crossfadeOnly")
    var crossfadeOnlyTransitions: Bool = false

    @AppStorage("accessibility.motion.disablePulsingAnimations")
    var disablePulsingAnimations: Bool = false

    // MARK: - 🚨 Emergency Settings

    @AppStorage("accessibility.emergency.requireConfirmation")
    var requireSOSConfirmation: Bool = true

    @AppStorage("accessibility.emergency.countdownDuration")
    var sosCountdownDuration: Int = 5 // 3, 5, 10 seconds

    @AppStorage("accessibility.emergency.autoNotifyFamily")
    var autoNotifyFamilyOnSOS: Bool = true

    @AppStorage("accessibility.emergency.fallbackToCellular")
    var fallbackToCellularOnMeshFail: Bool = true

    @AppStorage("accessibility.emergency.vibrateDuringCountdown")
    var vibrateDuringSOSCountdown: Bool = true

    // MARK: - 📡 Network Announcements Settings

    @AppStorage("accessibility.network.announceConnections")
    var announceConnectionChanges: Bool = true

    @AppStorage("accessibility.network.announceSignalStrength")
    var announceSignalStrengthChanges: Bool = false

    @AppStorage("accessibility.network.peerConnectionSound")
    var peerConnectionSoundEffects: Bool = true

    @AppStorage("accessibility.network.statusDetailLevel")
    var networkStatusDetailLevel: String = "medium" // brief, medium, detailed

    @AppStorage("accessibility.network.announceFrequency")
    var networkAnnounceFrequency: String = "important" // all, important, critical

    // MARK: - 🗺️ Location & Navigation Settings

    @AppStorage("accessibility.location.announceZoneTransitions")
    var announceZoneTransitions: Bool = true

    @AppStorage("accessibility.location.distanceUnit")
    var distanceUnit: String = "meters" // meters, feet

    @AppStorage("accessibility.location.enableVoiceGuidance")
    var enableNavigationVoiceGuidance: Bool = true

    @AppStorage("accessibility.location.proximityAlerts")
    var enableProximityAlerts: Bool = true

    @AppStorage("accessibility.location.proximityThreshold")
    var proximityAlertThreshold: Double = 10.0 // meters

    // MARK: - 🎨 Theme & Appearance Settings

    @AppStorage("accessibility.theme.colorScheme")
    var preferredColorScheme: String = "system" // system, light, dark

    @AppStorage("accessibility.theme.primaryColor")
    var primaryColorTheme: String = "mexico" // mexico, usa, canada, custom

    @AppStorage("accessibility.theme.iconStyle")
    var iconStyle: String = "filled" // filled, outlined

    @AppStorage("accessibility.theme.enableGradients")
    var enableGradients: Bool = true

    // MARK: - 🔐 Privacy Settings

    @AppStorage("accessibility.privacy.shareLocationWithPeers")
    var shareLocationWithPeers: Bool = true

    @AppStorage("accessibility.privacy.anonymousMode")
    var anonymousMode: Bool = false

    @AppStorage("accessibility.privacy.dataCollection")
    var allowDataCollection: Bool = false

    // MARK: - ⚡️ Performance Settings

    @AppStorage("accessibility.performance.batterySaverMode")
    var batterySaverMode: Bool = false

    @AppStorage("accessibility.performance.reduceBackgroundActivity")
    var reduceBackgroundActivity: Bool = false

    @AppStorage("accessibility.performance.messageCacheSize")
    var messageCacheSize: Int = 100 // 50, 100, 200

    // MARK: - 📊 Accessibility Score Calculation

    var accessibilityScore: Int {
        var score = 0
        let totalFeatures = 20

        // Count enabled features
        if enableVoiceOverHints { score += 1 }
        if announceNetworkChanges { score += 1 }
        if announceGeofenceTransitions { score += 1 }
        if hapticsEnabled { score += 1 }
        if hapticOnConnectionChanges { score += 1 }
        if enableHighContrast { score += 1 }
        if preferBoldText { score += 1 }
        if reduceTransparency { score += 1 }
        if reduceMotionLevel != "none" { score += 1 }
        if requireSOSConfirmation { score += 1 }
        if autoNotifyFamilyOnSOS { score += 1 }
        if announceConnectionChanges { score += 1 }
        if announceZoneTransitions { score += 1 }
        if enableNavigationVoiceGuidance { score += 1 }
        if enableProximityAlerts { score += 1 }
        if showButtonLabels { score += 1 }
        if hapticOnGeofenceTransitions { score += 1 }
        if peerConnectionSoundEffects { score += 1 }
        if shareLocationWithPeers { score += 1 }
        if fallbackToCellularOnMeshFail { score += 1 }

        return Int((Double(score) / Double(totalFeatures)) * 100)
    }

    // MARK: - Presets

    enum AccessibilityPreset {
        case adultoMayor
        case discapacidadVisual
        case discapacidadAuditiva
        case discapacidadCognitiva
        case maximoRendimiento
        case recomendado
    }

    func applyPreset(_ preset: AccessibilityPreset) {
        switch preset {
        case .adultoMayor:
            // VoiceOver + Texto Grande + Haptics
            enableVoiceOverHints = true
            voiceOverSpeakingRate = 0.8
            maximumTextSize = "accessibility5"
            buttonSize = .large // ✅ Botones agrandados
            hapticsEnabled = true
            hapticIntensity = "strong"
            reduceMotionLevel = "some"
            requireSOSConfirmation = false // Faster access

        case .discapacidadVisual:
            // VoiceOver Max + Audio Cues
            enableVoiceOverHints = true
            voiceOverSpeakingRate = 1.2
            announceNetworkChanges = true
            announceGeofenceTransitions = true
            announceConnectionChanges = true
            announceZoneTransitions = true
            hapticsEnabled = true
            hapticIntensity = "strong"
            peerConnectionSoundEffects = true
            enableNavigationVoiceGuidance = true

        case .discapacidadAuditiva:
            // Haptics Max + Visual Alerts
            hapticsEnabled = true
            hapticIntensity = "strong"
            hapticOnConnectionChanges = true
            hapticOnUIInteractions = true
            hapticOnGeofenceTransitions = true
            enableHighContrast = true
            preferBoldText = true
            showButtonLabels = true
            announceNetworkChanges = false
            peerConnectionSoundEffects = false

        case .discapacidadCognitiva:
            // Simple UI + Reduce Motion
            reduceMotionLevel = "all"
            crossfadeOnlyTransitions = true
            disablePulsingAnimations = true
            showButtonLabels = true
            requireSOSConfirmation = false
            sosCountdownDuration = 10 // More time to understand
            buttonSize = .large // ✅ Botones agrandados
            preferBoldText = true

        case .maximoRendimiento:
            // Todo desactivado para performance
            hapticsEnabled = false
            announceNetworkChanges = false
            announceGeofenceTransitions = false
            announceConnectionChanges = false
            peerConnectionSoundEffects = false
            enableGradients = false
            messageCacheSize = 50
            batterySaverMode = true

        case .recomendado:
            // Configuración balanceada
            enableVoiceOverHints = true
            hapticsEnabled = true
            hapticIntensity = "medium"
            announceNetworkChanges = true
            requireSOSConfirmation = true
            sosCountdownDuration = 5
            buttonSize = .normal // ✅ Tamaño normal
        }

        // Notify observers
        objectWillChange.send()
    }

    // MARK: - Reset to Defaults

    func resetToDefaults() {
        applyPreset(.recomendado)
    }

    // MARK: - Export/Import

    func exportSettings() -> [String: Any] {
        return [
            "voiceOver": [
                "enableHints": enableVoiceOverHints,
                "speakingRate": voiceOverSpeakingRate,
                "pitch": voiceOverPitch
            ],
            "haptics": [
                "enabled": hapticsEnabled,
                "intensity": hapticIntensity,
                "emergencyPattern": emergencyHapticPattern
            ],
            "visual": [
                "maximumTextSize": maximumTextSize,
                "buttonSizeMultiplier": buttonSizeMultiplier,
                "enableHighContrast": enableHighContrast
            ],
            // Add more as needed
        ]
    }

    func importSettings(from data: [String: Any]) {
        // Implementation for importing settings
        // Would parse the dictionary and set values
    }
}
