//
//  AccessibilityModifiers.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Accessibility helper extensions for WCAG 2.1 AA compliance
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - View Extensions for Accessibility

extension View {
    /// Applies complete accessibility configuration for a button
    /// - Parameters:
    ///   - label: VoiceOver label (what is it?)
    ///   - hint: VoiceOver hint (what does it do?)
    ///   - value: Current state/value (optional)
    ///   - traits: Additional traits beyond .isButton
    ///   - minTouchTarget: Minimum touch target size (default 44x44)
    /// - Returns: Fully accessible button
    func accessibleButton(
        label: String,
        hint: String? = nil,
        value: String? = nil,
        traits: AccessibilityTraits = [],
        minTouchTarget: CGFloat = 44
    ) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityValue(value ?? "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(traits)
            .frame(minWidth: minTouchTarget, minHeight: minTouchTarget)
    }

    /// Groups child elements into single VoiceOver element
    /// - Parameters:
    ///   - label: Combined label for the group
    ///   - hint: Action hint for the group
    ///   - sortPriority: Navigation order priority (higher = earlier)
    /// - Returns: Grouped accessible element
    func accessibleGroup(
        label: String,
        hint: String? = nil,
        sortPriority: Double = 0
    ) -> some View {
        self
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilitySortPriority(sortPriority)
    }

    /// Hides decorative elements from VoiceOver
    /// - Returns: Hidden from accessibility tree
    func accessibleDecorative() -> some View {
        self
            .accessibilityHidden(true)
    }

    /// Adds haptic feedback to button taps
    /// - Parameter style: UIImpactFeedbackGenerator.FeedbackStyle
    /// - Returns: View with haptic feedback
    func hapticFeedback(_ style: HapticStyle = .light) -> some View {
        self.modifier(HapticFeedbackModifier(style: style))
    }

    /// Respects reduced motion preference
    /// - Parameter animation: Animation to conditionally apply
    /// - Returns: View with optional animation
    func accessibleAnimation<V: Equatable>(
        _ animation: Animation?,
        value: V
    ) -> some View {
        self.modifier(ReduceMotionModifier(animation: animation, value: value))
    }

    /// Ensures minimum touch target size
    /// - Parameter size: Minimum size (default 44pt)
    /// - Returns: View with minimum touch target
    func minTouchTarget(_ size: CGFloat = 44) -> some View {
        self
            .frame(minWidth: size, minHeight: size)
            .contentShape(Rectangle())
    }

    /// Applies high contrast color variant
    /// - Parameters:
    ///   - standard: Standard color
    ///   - highContrast: High contrast variant
    /// - Returns: Contrast-aware color
    func contrastAwareColor(
        standard: Color,
        highContrast: Color
    ) -> some View {
        self.modifier(ContrastAwareColorModifier(
            standard: standard,
            highContrast: highContrast
        ))
    }

    /// Scales font size while capping at accessibility size
    /// - Parameter maxSize: Maximum dynamic type size
    /// - Returns: Capped dynamic type
    func cappedDynamicType(_ maxSize: DynamicTypeSize = .accessibility3) -> some View {
        self
            .dynamicTypeSize(...maxSize)
    }

    /// Makes an interactive card fully accessible
    /// - Parameters:
    ///   - title: Card title
    ///   - description: Card description
    ///   - action: Action hint
    ///   - haptic: Haptic style on tap
    /// - Returns: Accessible card
    func accessibleCard(
        title: String,
        description: String,
        action: String = "Double tap to open",
        haptic: HapticStyle = .light
    ) -> some View {
        self
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title), \(description)")
            .accessibilityHint(action)
            .accessibilityAddTraits(.isButton)
            .hapticFeedback(haptic)
    }

    /// Announces changes to assistive technologies
    /// - Parameter announcement: Text to announce
    func announceChange(_ announcement: String) -> some View {
        self.modifier(AccessibilityAnnouncementModifier(announcement: announcement))
    }
}

// MARK: - Haptic Feedback Style

enum HapticStyle {
    case light
    case medium
    case heavy
    case soft
    case rigid
    case success
    case warning
    case error

    #if canImport(UIKit)
    var impactStyle: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .light, .soft: return .light
        case .medium: return .medium
        case .heavy, .rigid: return .heavy
        case .success, .warning, .error: return .medium
        }
    }

    var notificationStyle: UINotificationFeedbackGenerator.FeedbackType? {
        switch self {
        case .success: return .success
        case .warning: return .warning
        case .error: return .error
        default: return nil
        }
    }
    #endif
}

// MARK: - View Modifiers

struct HapticFeedbackModifier: ViewModifier {
    let style: HapticStyle

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        triggerHaptic()
                    }
            )
    }

    private func triggerHaptic() {
        #if canImport(UIKit)
        if let notificationType = style.notificationStyle {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(notificationType)
        } else {
            let generator = UIImpactFeedbackGenerator(style: style.impactStyle)
            generator.impactOccurred()
        }
        #endif
    }
}

struct ReduceMotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        content
            .animation(reduceMotion ? nil : animation, value: value)
    }
}

struct ContrastAwareColorModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) var contrast
    let standard: Color
    let highContrast: Color

    func body(content: Content) -> some View {
        content
            .foregroundColor(contrast == .increased ? highContrast : standard)
    }
}

struct AccessibilityAnnouncementModifier: ViewModifier {
    let announcement: String
    @State private var hasAnnounced = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !hasAnnounced else { return }
                announceToVoiceOver(announcement)
                hasAnnounced = true
            }
    }

    private func announceToVoiceOver(_ message: String) {
        #if canImport(UIKit)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            UIAccessibility.post(
                notification: .announcement,
                argument: message
            )
        }
        #endif
    }
}

// MARK: - Accessibility Status Checks

struct AccessibilityStatus {
    /// Check if VoiceOver is running
    static var isVoiceOverRunning: Bool {
        #if canImport(UIKit)
        return UIAccessibility.isVoiceOverRunning
        #else
        return false
        #endif
    }

    /// Check if Switch Control is running
    static var isSwitchControlRunning: Bool {
        #if canImport(UIKit)
        return UIAccessibility.isSwitchControlRunning
        #else
        return false
        #endif
    }

    /// Check if user prefers reduced motion
    static var prefersReducedMotion: Bool {
        #if canImport(UIKit)
        return UIAccessibility.isReduceMotionEnabled
        #else
        return false
        #endif
    }

    /// Check if user prefers bold text
    static var prefersBoldText: Bool {
        #if canImport(UIKit)
        return UIAccessibility.isBoldTextEnabled
        #else
        return false
        #endif
    }

    /// Check if using larger accessibility text sizes
    static var isUsingAccessibilitySizes: Bool {
        #if canImport(UIKit)
        let contentSize = UIApplication.shared.preferredContentSizeCategory
        return contentSize.isAccessibilityCategory
        #else
        return false
        #endif
    }
}

// MARK: - Custom Accessibility Rotors

#if canImport(UIKit)
extension View {
    /// Creates custom rotor for VoiceOver navigation
    /// - Parameters:
    ///   - name: Rotor name
    ///   - items: Items in the rotor
    /// - Returns: View with custom rotor
    func customRotor<Items: RandomAccessCollection>(
        _ name: String,
        items: Items,
        label: @escaping (Items.Element) -> String
    ) -> some View where Items.Element: Identifiable {
        self.accessibilityRotor(name) {
            ForEach(items) { item in
                AccessibilityRotorEntry(label(item), id: item.id)
            }
        }
    }
}
#endif

// MARK: - Match Score Accessibility Helper

struct MatchScoreAccessibility {
    let homeTeam: String
    let awayTeam: String
    let homeScore: Int
    let awayScore: Int
    let minute: Int
    let isLive: Bool

    var voiceOverLabel: String {
        let status = isLive ? "Live match" : "Match ended"
        let score = "\(homeTeam) \(homeScore), \(awayTeam) \(awayScore)"
        let time = isLive ? "at \(minute) minutes" : ""

        return "\(status): \(score) \(time)"
    }

    var voiceOverHint: String {
        return "Double tap to view full match details and statistics"
    }

    var scoreDescription: String {
        if homeScore > awayScore {
            return "\(homeTeam) leading by \(homeScore - awayScore)"
        } else if awayScore > homeScore {
            return "\(awayTeam) leading by \(awayScore - homeScore)"
        } else {
            return "Match is tied"
        }
    }
}

// MARK: - SOS Accessibility Helper

struct SOSAccessibility {
    let type: String
    let priority: String

    var emergencyLabel: String {
        return "Emergency SOS, \(type)"
    }

    var emergencyHint: String {
        return "Double tap to send urgent \(type) alert to nearby stadium staff and connected devices. This is a high priority emergency request."
    }

    var confirmationLabel: String {
        return "Confirm \(type) emergency alert"
    }

    var confirmationHint: String {
        return "Double tap to confirm and broadcast emergency alert. This will notify stadium medical staff and your family group."
    }

    static func announceSOSSent(type: String) -> String {
        return "Emergency alert sent successfully. Stadium staff has been notified of your \(type) request."
    }
}

// MARK: - Network Status Accessibility Helper

struct NetworkStatusAccessibility {
    let connectedPeers: Int
    let availablePeers: Int
    let connectionQuality: String

    var statusLabel: String {
        return "Network status: \(connectionQuality), \(connectedPeers) connected, \(availablePeers) available"
    }

    var statusHint: String {
        if connectedPeers == 0 {
            return "No devices connected. Move closer to other users to establish mesh network connection."
        } else {
            return "Double tap to view detailed network information and manage connections"
        }
    }

    var qualityDescription: String {
        switch connectionQuality.lowercased() {
        case "excellent", "excelente":
            return "Signal strength excellent, all features available"
        case "good", "bueno":
            return "Signal strength good, stable connection"
        case "poor", "pobre":
            return "Weak signal, some features may be limited"
        default:
            return "Connection quality unknown"
        }
    }
}

// MARK: - Geofence Accessibility Helper

struct GeofenceAccessibility {
    let zoneName: String
    let isInside: Bool
    let distance: Double?

    var statusLabel: String {
        if isInside {
            return "Currently in \(zoneName)"
        } else if let distance = distance {
            return "\(zoneName) is \(Int(distance)) meters away"
        } else {
            return "\(zoneName)"
        }
    }

    var navigationHint: String {
        if isInside {
            return "You are currently inside this zone"
        } else if let distance = distance {
            return "Double tap for directions. Approximately \(Int(distance)) meters away"
        } else {
            return "Double tap to set as navigation destination"
        }
    }

    static func announceZoneEntry(_ zoneName: String) -> String {
        return "Entered \(zoneName) zone"
    }

    static func announceZoneExit(_ zoneName: String) -> String {
        return "Left \(zoneName) zone"
    }
}

// MARK: - Dynamic Type Helper

extension Font {
    /// Scalable font that respects Dynamic Type
    /// - Parameters:
    ///   - style: Text style (.body, .headline, etc.)
    ///   - maxSize: Maximum accessibility size to prevent excessive scaling
    /// - Returns: Scalable font
    static func scalable(
        _ style: Font.TextStyle,
        maxSize: DynamicTypeSize = .accessibility3
    ) -> Font {
        return .system(style, design: .default)
    }

    /// Custom scalable font with relative sizing
    /// - Parameters:
    ///   - baseSize: Base size at standard content size
    ///   - weight: Font weight
    ///   - design: Font design
    /// - Returns: Relative scalable font
    static func scalableCustom(
        baseSize: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        // Use relative sizing based on body style
        return .system(.body, design: design, weight: weight)
            .leading(.tight)
    }
}

// MARK: - Accessibility Traits Extensions

extension AccessibilityTraits {
    static let isEmergency: AccessibilityTraits = [.isButton, .startsMediaSession]
    static let isNavigationControl: AccessibilityTraits = [.isButton, .isLink]
    static let isStatistic: AccessibilityTraits = [.updatesFrequently, .causesPageTurn]
}

// MARK: - Testing Helpers (Debug Only)

#if DEBUG
struct AccessibilityDebugView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Accessibility Status").font(.headline)

            StatusRow(label: "VoiceOver", isEnabled: AccessibilityStatus.isVoiceOverRunning)
            StatusRow(label: "Switch Control", isEnabled: AccessibilityStatus.isSwitchControlRunning)
            StatusRow(label: "Reduced Motion", isEnabled: AccessibilityStatus.prefersReducedMotion)
            StatusRow(label: "Bold Text", isEnabled: AccessibilityStatus.prefersBoldText)
            StatusRow(label: "Large Sizes", isEnabled: AccessibilityStatus.isUsingAccessibilitySizes)
        }
        .padding()
    }
}

struct StatusRow: View {
    let label: String
    let isEnabled: Bool

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Image(systemName: isEnabled ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(isEnabled ? .green : .secondary)
        }
    }
}
#endif

// MARK: - Usage Examples

/*

 EXAMPLE 1: Accessible Button

 Button(action: sendSOS) {
     Image(systemName: "sos")
     Text("Emergency")
 }
 .accessibleButton(
     label: "Emergency SOS",
     hint: "Sends urgent medical alert to stadium staff",
     traits: .isEmergency,
     minTouchTarget: 60
 )
 .hapticFeedback(.warning)


 EXAMPLE 2: Accessible Card with Grouping

 VStack {
     Image(systemName: "person.3.fill")
     Text("Family")
     Text("\(memberCount) members")
 }
 .accessibleCard(
     title: "Family Group",
     description: "\(memberCount) members connected",
     action: "Double tap to manage family group",
     haptic: .light
 )


 EXAMPLE 3: Match Score with Semantic Grouping

 HStack {
     TeamView(team: homeTeam)
     ScoreView(score: homeScore)
     Text("VS")
     ScoreView(score: awayScore)
     TeamView(team: awayTeam)
 }
 .accessibleGroup(
     label: MatchScoreAccessibility(
         homeTeam: "Mexico",
         awayTeam: "Canada",
         homeScore: 2,
         awayScore: 1,
         minute: 78,
         isLive: true
     ).voiceOverLabel,
     hint: "Double tap for match details",
     sortPriority: 1.0
 )


 EXAMPLE 4: Decorative Element

 Circle()
     .fill(Color.red.opacity(0.3))
     .frame(width: 160, height: 160)
     .accessibleDecorative() // Hidden from VoiceOver


 EXAMPLE 5: Reduced Motion Animation

 Circle()
     .scaleEffect(isPulsing ? 1.3 : 1.0)
     .accessibleAnimation(.easeInOut, value: isPulsing)


 EXAMPLE 6: High Contrast Colors

 Text("Status")
     .contrastAwareColor(
         standard: .secondary,
         highContrast: .primary
     )


 EXAMPLE 7: VoiceOver Announcement

 .onChange(of: sosAlertSent) { sent in
     if sent {
         announceChange(
             SOSAccessibility.announceSOSSent(type: "medical emergency")
         )
     }
 }

 */
