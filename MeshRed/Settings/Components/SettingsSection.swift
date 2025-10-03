//
//  SettingsSection.swift
//  MeshRed - StadiumConnect Pro
//
//  Reusable Settings Section Component with Full Accessibility
//

import SwiftUI

/// Accessible section container for settings groups
struct SettingsSection<Content: View>: View {
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme

    let icon: String
    let title: String
    let description: String?
    let iconColor: Color
    let content: () -> Content

    init(
        icon: String,
        title: String,
        description: String? = nil,
        iconColor: Color = ThemeColors.primaryBlue,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.iconColor = iconColor
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(iconColor)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
                        .foregroundColor(accessibleTheme.textPrimary)
                        .accessibleText()

                    if let description = description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(accessibleTheme.textSecondary)
                            .accessibleText()
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)
            .accessibilityValue(description ?? "")
            .accessibilityAddTraits(.isHeader)

            // Section Content
            VStack(spacing: 8) {
                content()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .accessibleBackground(accessibleTheme.cardBackground)
            .cornerRadius(accessibleTheme.standardCornerRadius)
            .accessibleShadow(color: .black.opacity(accessibleTheme.shadowOpacity), radius: 8)
        }
        .padding(.horizontal, 20)
    }
}

/// Accessible toggle row for settings
struct AccessibleSettingToggle: View {
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme

    let title: String
    let description: String?
    let icon: String?
    @Binding var isOn: Bool
    var onToggle: ((Bool) -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundColor(accessibleTheme.primaryBlue)
                    .frame(width: 24)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(accessibilitySettings.preferBoldText ? .bold : .regular)
                    .foregroundColor(accessibleTheme.textPrimary)
                    .accessibleText()

                if let description = description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(accessibleTheme.textSecondary)
                        .accessibleText()
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .onChange(of: isOn) { newValue in
                    // Haptic feedback
                    #if os(iOS)
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    #endif

                    onToggle?(newValue)
                }
                .accessibilityLabel(title)
                .accessibilityValue(isOn ? "Activado" : "Desactivado")
                .accessibilityHint(description ?? "")
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            isOn.toggle()
        }
    }
}

/// Accessible slider row for settings
struct AccessibleSettingSlider: View {
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme

    let title: String
    let description: String?
    let icon: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var valueFormatter: ((Double) -> String)?
    var onValueChange: ((Double) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.body)
                        .foregroundColor(accessibleTheme.primaryBlue)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(title)
                            .font(.body)
                            .fontWeight(accessibilitySettings.preferBoldText ? .bold : .regular)
                            .foregroundColor(accessibleTheme.textPrimary)
                            .accessibleText()

                        Spacer()

                        Text(formattedValue)
                            .font(.subheadline)
                            .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
                            .foregroundColor(accessibleTheme.primaryBlue)
                            .accessibleText()
                    }

                    if let description = description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(accessibleTheme.textSecondary)
                            .accessibleText()
                    }
                }
            }

            Slider(value: $value, in: range, step: step)
                .accentColor(accessibleTheme.primaryBlue)
                .onChange(of: value) { newValue in
                    // Haptic feedback
                    #if os(iOS)
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    #endif

                    onValueChange?(newValue)
                }
                .accessibilityLabel(title)
                .accessibilityValue(formattedValue)
                .accessibilityHint(description ?? "")
        }
        .padding(.vertical, 8)
    }

    private var formattedValue: String {
        if let formatter = valueFormatter {
            return formatter(value)
        }
        return String(format: "%.1f", value)
    }
}

/// Accessible picker row for settings
struct AccessibleSettingPicker: View {
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme

    let title: String
    let description: String?
    let icon: String?
    @Binding var selection: String
    let options: [String]
    var displayNames: [String: String]? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.body)
                        .foregroundColor(accessibleTheme.primaryBlue)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .fontWeight(accessibilitySettings.preferBoldText ? .bold : .regular)
                        .foregroundColor(accessibleTheme.textPrimary)
                        .accessibleText()

                    if let description = description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(accessibleTheme.textSecondary)
                            .accessibleText()
                    }
                }
            }

            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(displayName(for: option))
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(title)
            .accessibilityValue(displayName(for: selection))
        }
        .padding(.vertical, 8)
    }

    private func displayName(for option: String) -> String {
        displayNames?[option] ?? option.capitalized
    }
}
