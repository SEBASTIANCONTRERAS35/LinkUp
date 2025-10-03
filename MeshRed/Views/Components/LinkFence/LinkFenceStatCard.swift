//
//  LinkFenceStatCard.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Card component for displaying linkfence statistics
//

import SwiftUI

struct LinkFenceStatCard: View {
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme

    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            // Icon
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)
            }

            // Value
            Text(value)
                .font(.title2.bold())
                .foregroundColor(accessibleTheme.textPrimary)
                .accessibleText()

            // Label
            Text(label)
                .font(.caption)
                .foregroundColor(accessibleTheme.textSecondary)
                .accessibleText()
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .accessibleBackground(accessibleTheme.cardBackground, opacity: 1.0)
        .cornerRadius(16)
        .accessibleShadow()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Preview
#Preview {
    HStack(spacing: 12) {
        LinkFenceStatCard(
            icon: "arrow.right.circle.fill",
            value: "12",
            label: "Visitas",
            color: Mundial2026Colors.verde
        )

        LinkFenceStatCard(
            icon: "clock.fill",
            value: "8h 32min",
            label: "Tiempo Total",
            color: Mundial2026Colors.azul
        )
    }
    .padding()
    .background(Mundial2026Colors.background)
}
