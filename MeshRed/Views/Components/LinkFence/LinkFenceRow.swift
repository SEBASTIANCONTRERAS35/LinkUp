//
//  LinkFenceRow.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Row component for linkfence list
//

import SwiftUI

struct LinkFenceRow: View {
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme

    let linkfence: CustomLinkFence
    let stats: LinkFenceStats?
    let isMonitoring: Bool
    let onToggleMonitoring: () -> Void
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Monitoring Toggle
                Toggle("", isOn: Binding(
                    get: { isMonitoring },
                    set: { _ in onToggleMonitoring() }
                ))
                .labelsHidden()
                .tint(linkfence.color)
                .frame(width: 50)

                // Icon with category color
                ZStack {
                    Circle()
                        .fill(linkfence.color.opacity(0.15))
                        .frame(width: 50, height: 50)

                    Image(systemName: linkfence.category.icon)
                        .font(.system(size: 22))
                        .foregroundColor(linkfence.color)
                }

                // LinkFence info
                VStack(alignment: .leading, spacing: 6) {
                    // Name
                    Text(linkfence.name)
                        .font(.headline)
                        .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
                        .foregroundColor(accessibleTheme.textPrimary)
                        .accessibleText()

                    // Stats summary
                    HStack(spacing: 12) {
                        // Visit count
                        if let stats = stats, stats.totalVisits > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.caption)
                                Text("\(stats.totalVisits) visitas")
                                    .font(.caption)
                            }
                            .foregroundColor(accessibleTheme.textSecondary)
                        } else {
                            Text("Sin visitas")
                                .font(.caption)
                                .foregroundColor(accessibleTheme.textSecondary)
                        }

                        // Last visit time
                        if let lastVisit = stats?.timeSinceLastEntry {
                            Text("· \(lastVisit)")
                                .font(.caption)
                                .foregroundColor(accessibleTheme.textSecondary)
                        }
                    }
                    .accessibleText()
                }

                Spacer()

                // Status badge
                if let stats = stats {
                    StatusBadge(isInside: stats.currentlyInside)
                }

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(accessibleTheme.textSecondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .accessibleBackground(accessibleTheme.cardBackground, opacity: 1.0)
            .cornerRadius(16)
            .accessibleShadow()
        }
        .accessibleButton()
        .accessibilityLabel("\(linkfence.name), \(isMonitoring ? "Activo" : "Inactivo")")
        .accessibilityHint("Toca para ver detalles del linkfence")
    }
}

// MARK: - Status Badge Component
struct StatusBadge: View {
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme

    let isInside: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isInside ? Color.appAccent : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)

            Text(isInside ? "Dentro" : "Fuera")
                .font(.caption2.bold())
                .foregroundColor(isInside ? Color.appAccent : .secondary)
                .accessibleText()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .accessibleBackground(isInside ? Color.appAccent : Color.gray, opacity: isInside ? 0.1 : 0.08)
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isInside ? "Dentro del linkfence" : "Fuera del linkfence")
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 16) {
        LinkFenceRow(
            linkfence: MockLinkFenceData.mockLinkFences[0],
            stats: LinkFenceStats(
                linkfenceId: MockLinkFenceData.mockLinkFences[0].id,
                linkfenceName: MockLinkFenceData.mockLinkFences[0].name,
                events: MockLinkFenceData.generateMockEvents()[MockLinkFenceData.mockLinkFences[0].id] ?? []
            ),
            isMonitoring: true,
            onToggleMonitoring: {},
            onTap: {}
        )

        LinkFenceRow(
            linkfence: MockLinkFenceData.mockLinkFences[1],
            stats: nil,
            isMonitoring: false,
            onToggleMonitoring: {},
            onTap: {}
        )
    }
    .padding()
    .background(Color.appBackgroundDark)
}
