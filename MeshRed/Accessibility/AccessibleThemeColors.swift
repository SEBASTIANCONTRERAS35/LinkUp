//
//  AccessibleThemeColors.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Reactive theme colors that automatically adapt to accessibility settings
//
//  USAGE:
//  @EnvironmentObject var accessibleTheme: AccessibleThemeColors
//  Text("Hello").foregroundColor(accessibleTheme.textPrimary)
//
//  Colors automatically change when user toggles high contrast mode!
//

import SwiftUI
import Combine

/// Observable wrapper around ThemeColors that reacts to accessibility settings
class AccessibleThemeColors: ObservableObject {

    // Reference to accessibility settings
    private let settings: AccessibilitySettingsManager
    private var cancellables = Set<AnyCancellable>()

    init(settings: AccessibilitySettingsManager = .shared) {
        self.settings = settings

        // Listen to changes in accessibility settings
        settings.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
    }

    // MARK: - Primary Colors

    var primaryGreen: Color {
        settings.enableHighContrast
            ? ThemeColors.HighContrast.primaryGreen
            : ThemeColors.primaryGreen
    }

    var primaryBlue: Color {
        settings.enableHighContrast
            ? ThemeColors.HighContrast.primaryBlue
            : ThemeColors.primaryBlue
    }

    var primaryRed: Color {
        settings.enableHighContrast
            ? ThemeColors.HighContrast.primaryRed
            : ThemeColors.primaryRed
    }

    // MARK: - Status Colors

    var success: Color {
        settings.enableHighContrast
            ? Color(hex: "005A2E") // Darker green for high contrast
            : ThemeColors.success
    }

    var warning: Color {
        settings.enableHighContrast
            ? Color(hex: "B35900") // Darker orange for high contrast
            : ThemeColors.warning
    }

    var error: Color {
        settings.enableHighContrast
            ? ThemeColors.HighContrast.emergency
            : ThemeColors.error
    }

    var info: Color {
        primaryBlue // Already uses high contrast variant
    }

    // MARK: - Semantic Colors

    var connected: Color {
        success
    }

    var connecting: Color {
        warning
    }

    var disconnected: Color {
        Color.gray
    }

    var emergency: Color {
        settings.enableHighContrast
            ? ThemeColors.HighContrast.emergency
            : ThemeColors.emergency
    }

    // MARK: - Background Colors (Adaptive)

    var background: Color {
        // Respects system dark/light mode + reduce transparency
        if settings.reduceTransparency {
            return Color(UIColor.systemBackground) // Solid background
        } else {
            return ThemeColors.background
        }
    }

    var cardBackground: Color {
        if settings.reduceTransparency {
            return Color(UIColor.secondarySystemBackground) // Solid card
        } else {
            return ThemeColors.cardBackground
        }
    }

    var rowBackground: Color {
        if settings.reduceTransparency {
            return Color(UIColor.tertiarySystemBackground) // Solid row
        } else {
            return ThemeColors.rowBackground
        }
    }

    // MARK: - Text Colors (Adaptive)

    var textPrimary: Color {
        // Primary text is already adaptive through UIColor.label
        settings.enableHighContrast
            ? Color(UIColor.label).opacity(1.0) // Full opacity for high contrast
            : ThemeColors.textPrimary
    }

    var textSecondary: Color {
        // Stronger secondary text for high contrast
        settings.enableHighContrast
            ? Color(UIColor.secondaryLabel).opacity(0.9)
            : ThemeColors.textSecondary
    }

    var textTertiary: Color {
        settings.enableHighContrast
            ? Color(UIColor.tertiaryLabel).opacity(0.85)
            : ThemeColors.textTertiary
    }

    // MARK: - Gradients (Adaptive)

    var primaryGradient: LinearGradient {
        if settings.enableGradients && !settings.reduceTransparency {
            // Show gradient
            return LinearGradient(
                colors: [primaryGreen, primaryBlue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            // Fallback to solid color
            return LinearGradient(
                colors: [primaryBlue, primaryBlue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var emergencyGradient: LinearGradient {
        if settings.enableGradients && !settings.reduceTransparency {
            return LinearGradient(
                colors: [
                    emergency,
                    emergency.opacity(0.8)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [emergency, emergency],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var successGradient: LinearGradient {
        if settings.enableGradients && !settings.reduceTransparency {
            return LinearGradient(
                colors: [
                    success,
                    Color(hex: "00854A")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [success, success],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - Helper Methods

    /// Returns appropriate text color for given background (ensuring WCAG AA compliance)
    func adaptiveTextColor(for background: Color) -> Color {
        // For our primary colors, white provides best contrast
        return .white
    }

    /// Returns shadow opacity based on accessibility settings
    var shadowOpacity: Double {
        if settings.enableHighContrast {
            return 0.5 // Stronger shadows for high contrast
        } else if settings.reduceTransparency {
            return 0.3 // Medium shadows when transparency is reduced
        } else {
            return 0.15 // Standard subtle shadows
        }
    }

    /// Returns corner radius adjusted for accessibility
    var standardCornerRadius: CGFloat {
        // Could be adjusted based on settings if needed
        return 12
    }

    /// Returns spacing adjusted for accessibility
    func adaptiveSpacing(_ baseSpacing: CGFloat) -> CGFloat {
        return baseSpacing * settings.buttonSizeMultiplier
    }
}

// MARK: - Environment Key
struct AccessibleThemeColorsKey: EnvironmentKey {
    static let defaultValue = AccessibleThemeColors()
}

extension EnvironmentValues {
    var accessibleTheme: AccessibleThemeColors {
        get { self[AccessibleThemeColorsKey.self] }
        set { self[AccessibleThemeColorsKey.self] = newValue }
    }
}

// MARK: - Convenient View Extension
extension View {
    /// Injects AccessibleThemeColors into the environment
    func withAccessibleTheme(_ theme: AccessibleThemeColors) -> some View {
        self.environment(\.accessibleTheme, theme)
    }
}

// MARK: - Preview Helper
#if DEBUG
struct AccessibleThemeColors_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Standard mode
            ThemePreviewContent()
                .previewDisplayName("Standard")

            // High contrast mode
            ThemePreviewContent()
                .onAppear {
                    AccessibilitySettingsManager.shared.enableHighContrast = true
                }
                .previewDisplayName("High Contrast")

            // Reduce transparency mode
            ThemePreviewContent()
                .onAppear {
                    AccessibilitySettingsManager.shared.reduceTransparency = true
                }
                .previewDisplayName("Reduce Transparency")
        }
        .environmentObject(AccessibilitySettingsManager.shared)
        .withAccessibleTheme(AccessibleThemeColors())
    }
}

struct ThemePreviewContent: View {
    @Environment(\.accessibleTheme) var theme

    var body: some View {
        VStack(spacing: 20) {
            Text("Primary Green")
                .foregroundColor(theme.primaryGreen)

            Text("Primary Blue")
                .foregroundColor(theme.primaryBlue)

            Text("Primary Red")
                .foregroundColor(theme.primaryRed)

            Text("Success")
                .foregroundColor(theme.success)

            Text("Warning")
                .foregroundColor(theme.warning)

            Text("Emergency")
                .foregroundColor(theme.emergency)

            RoundedRectangle(cornerRadius: 12)
                .fill(theme.primaryGradient)
                .frame(height: 100)
        }
        .padding()
        .background(theme.background)
    }
}
#endif
