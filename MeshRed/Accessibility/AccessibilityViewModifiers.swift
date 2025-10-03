//
//  AccessibilityViewModifiers.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Reactive ViewModifiers that automatically apply accessibility settings
//
//  USAGE:
//  Text("Hello").modifier(AdaptiveTextModifier())
//  OR use convenient extensions: Text("Hello").accessibleText()
//

import SwiftUI

// MARK: - Adaptive Text Modifier
/// Applies buttonSizeMultiplier, bold text, and high contrast automatically
struct AdaptiveTextModifier: ViewModifier {
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager

    func body(content: Content) -> some View {
        content
            .scaleEffect(accessibilitySettings.buttonSizeMultiplier)
            .fontWeight(accessibilitySettings.preferBoldText ? .bold : .regular)
            .brightness(accessibilitySettings.enableHighContrast ? 0.1 : 0)
    }
}

// MARK: - Adaptive Button Modifier
/// Scales interactive elements (buttons, cards) according to buttonSizeMultiplier
struct AdaptiveButtonModifier: ViewModifier {
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager

    func body(content: Content) -> some View {
        content
            .scaleEffect(accessibilitySettings.buttonSizeMultiplier)
            .animation(.easeInOut(duration: 0.2), value: accessibilitySettings.buttonSizeMultiplier)
    }
}

// MARK: - Adaptive Color Modifier
/// Applies high contrast colors when enabled
struct AdaptiveColorModifier: ViewModifier {
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    let standardColor: Color
    let highContrastColor: Color

    func body(content: Content) -> some View {
        content
            .foregroundColor(
                accessibilitySettings.enableHighContrast ? highContrastColor : standardColor
            )
    }
}

// MARK: - Adaptive Background Modifier
/// Adjusts background opacity based on reduceTransparency setting
struct AdaptiveBackgroundModifier: ViewModifier {
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    let backgroundColor: Color
    let defaultOpacity: Double

    func body(content: Content) -> some View {
        content
            .background(
                backgroundColor.opacity(
                    accessibilitySettings.reduceTransparency ? 1.0 : defaultOpacity
                )
            )
    }
}

// MARK: - Adaptive Font Size Modifier
/// Applies relative font scaling based on buttonSizeMultiplier
struct AdaptiveFontSizeModifier: ViewModifier {
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    let baseSize: CGFloat

    func body(content: Content) -> some View {
        content
            .font(.system(size: baseSize * accessibilitySettings.buttonSizeMultiplier))
            .fontWeight(accessibilitySettings.preferBoldText ? .bold : .regular)
    }
}

// MARK: - Adaptive Card Modifier
/// Complete modifier for card components (size + transparency + contrast)
struct AdaptiveCardModifier: ViewModifier {
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    let backgroundColor: Color

    func body(content: Content) -> some View {
        content
            .scaleEffect(accessibilitySettings.buttonSizeMultiplier)
            .background(
                backgroundColor.opacity(
                    accessibilitySettings.reduceTransparency ? 1.0 : 0.95
                )
            )
            .animation(.easeInOut(duration: 0.2), value: accessibilitySettings.buttonSizeMultiplier)
    }
}

// MARK: - Adaptive Interactive Element
/// Complete modifier for buttons and interactive elements
/// Combines size scaling, haptics settings awareness, and visual feedback
struct AdaptiveInteractiveModifier: ViewModifier {
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    let minTouchTarget: CGFloat

    init(minTouchTarget: CGFloat = 44) {
        self.minTouchTarget = minTouchTarget
    }

    func body(content: Content) -> some View {
        content
            .frame(
                minWidth: minTouchTarget * accessibilitySettings.buttonSizeMultiplier,
                minHeight: minTouchTarget * accessibilitySettings.buttonSizeMultiplier
            )
            .scaleEffect(accessibilitySettings.buttonSizeMultiplier)
            .animation(.easeInOut(duration: 0.2), value: accessibilitySettings.buttonSizeMultiplier)
    }
}

// MARK: - Adaptive Shadow Modifier
/// Adjusts shadow based on high contrast and reduce transparency settings
struct AdaptiveShadowModifier: ViewModifier {
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    let color: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        if accessibilitySettings.enableHighContrast || accessibilitySettings.reduceTransparency {
            // Stronger, more visible shadow for high contrast
            content
                .shadow(color: color.opacity(0.5), radius: radius * 1.5, x: 0, y: 2)
        } else {
            // Standard shadow
            content
                .shadow(color: color.opacity(0.3), radius: radius, x: 0, y: 2)
        }
    }
}

// MARK: - Complete Accessibility Modifier
/// All-in-one modifier that applies all accessibility settings
/// Use this for complex views that need full accessibility support
struct CompleteAccessibilityModifier: ViewModifier {
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager

    func body(content: Content) -> some View {
        content
            .scaleEffect(accessibilitySettings.buttonSizeMultiplier)
            .fontWeight(accessibilitySettings.preferBoldText ? .bold : .regular)
            .brightness(accessibilitySettings.enableHighContrast ? 0.1 : 0)
            .animation(.easeInOut(duration: 0.2), value: accessibilitySettings.buttonSizeMultiplier)
            .animation(.easeInOut(duration: 0.2), value: accessibilitySettings.preferBoldText)
            .animation(.easeInOut(duration: 0.2), value: accessibilitySettings.enableHighContrast)
    }
}

// MARK: - Adaptive Gradient Modifier
/// Shows/hides gradients based on enableGradients setting
struct AdaptiveGradientModifier: ViewModifier {
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    let gradient: LinearGradient
    let fallbackColor: Color

    func body(content: Content) -> some View {
        if accessibilitySettings.enableGradients && !accessibilitySettings.reduceTransparency {
            content
                .background(gradient)
        } else {
            content
                .background(fallbackColor)
        }
    }
}

// MARK: - View Extensions for Easy Access
extension View {
    /// Applies adaptive text styling (size + bold + contrast)
    func accessibleText() -> some View {
        self.modifier(AdaptiveTextModifier())
    }

    /// Applies adaptive button scaling
    func accessibleButton(minTouchTarget: CGFloat = 44) -> some View {
        self.modifier(AdaptiveInteractiveModifier(minTouchTarget: minTouchTarget))
    }

    /// Applies adaptive card styling
    func accessibleCard(backgroundColor: Color = ThemeColors.cardBackground) -> some View {
        self.modifier(AdaptiveCardModifier(backgroundColor: backgroundColor))
    }

    /// Applies adaptive color based on high contrast setting
    func accessibleColor(standard: Color, highContrast: Color) -> some View {
        self.modifier(AdaptiveColorModifier(standardColor: standard, highContrastColor: highContrast))
    }

    /// Applies adaptive background with transparency awareness
    func accessibleBackground(_ color: Color, opacity: Double = 0.95) -> some View {
        self.modifier(AdaptiveBackgroundModifier(backgroundColor: color, defaultOpacity: opacity))
    }

    /// Applies adaptive shadow
    func accessibleShadow(color: Color = .black, radius: CGFloat = 8) -> some View {
        self.modifier(AdaptiveShadowModifier(color: color, radius: radius))
    }

    /// Applies complete accessibility modifications
    func fullyAccessible() -> some View {
        self.modifier(CompleteAccessibilityModifier())
    }

    /// Applies adaptive gradient or fallback solid color
    func accessibleGradient(_ gradient: LinearGradient, fallback: Color) -> some View {
        self.modifier(AdaptiveGradientModifier(gradient: gradient, fallbackColor: fallback))
    }
}

// MARK: - Preview Helpers
#if DEBUG
struct AccessibilityViewModifiers_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            Text("Accessible Text")
                .accessibleText()

            Button("Accessible Button") {}
                .accessibleButton()

            VStack {
                Text("Card Content")
            }
            .padding()
            .accessibleCard()

            Text("High Contrast Text")
                .accessibleColor(
                    standard: ThemeColors.textSecondary,
                    highContrast: ThemeColors.textPrimary
                )
        }
        .padding()
        .environmentObject(AccessibilitySettingsManager.shared)
    }
}
#endif
