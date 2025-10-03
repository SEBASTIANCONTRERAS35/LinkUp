//
//  ActiveLinkFencesBadge.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Badge showing active linkfences count
//

import SwiftUI

struct ActiveLinkFencesBadge: View {
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme

    let activeCount: Int
    let maxCount: Int = LinkFenceManager.maxMonitoredGeofences

    private var fillPercentage: Double {
        return Double(activeCount) / Double(maxCount)
    }

    private var badgeColor: Color {
        if fillPercentage >= 0.9 {
            return Mundial2026Colors.rojo  // Red when near limit
        } else if fillPercentage >= 0.7 {
            return .orange  // Orange when approaching limit
        } else {
            return Mundial2026Colors.verde  // Green when plenty of space
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            // Icon
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.caption)
                .foregroundColor(badgeColor)

            // Count
            Text("\(activeCount)/\(maxCount)")
                .font(.caption.bold())
                .foregroundColor(badgeColor)

            Text("activos")
                .font(.caption)
                .foregroundColor(accessibleTheme.textSecondary)
                .accessibleText()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibleBackground(badgeColor, opacity: 0.1)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(badgeColor.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Geofences activos: \(activeCount) de \(maxCount)")
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 16) {
        ActiveLinkFencesBadge(activeCount: 3)
        ActiveLinkFencesBadge(activeCount: 15)
        ActiveLinkFencesBadge(activeCount: 19)
    }
    .padding()
    .background(Mundial2026Colors.background)
}
