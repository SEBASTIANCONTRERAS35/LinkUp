//
//  InfoRow.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Reusable component for displaying labeled information with icon
//

import SwiftUI

struct InfoRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
            }

            // Label and value
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(accessibleTheme.textSecondary)

                Text(value)
                    .font(.system(size: 15, weight: accessibilitySettings.preferBoldText ? .bold : .semibold))
                    .foregroundColor(accessibleTheme.textPrimary)
                    .accessibleText()
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    VStack(spacing: 16) {
        InfoRow(
            icon: "ruler",
            label: "Distancia",
            value: "5.3 m",
            color: Mundial2026Colors.azul
        )

        InfoRow(
            icon: "location.fill",
            label: "Fuente de datos",
            value: "LinkFinder Preciso",
            color: Mundial2026Colors.verde
        )

        InfoRow(
            icon: "clock",
            label: "Actualización",
            value: "Hace 2 seg",
            color: .gray
        )
    }
    .padding()
    .environmentObject(AccessibilitySettingsManager())
}
