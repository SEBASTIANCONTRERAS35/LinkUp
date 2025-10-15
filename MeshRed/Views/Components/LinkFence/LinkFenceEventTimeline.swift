//
//  LinkFenceEventTimeline.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Timeline component for displaying linkfence entry/exit events
//

import SwiftUI

struct LinkFenceEventTimeline: View {
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme

    let events: [LinkFenceEventMessage]

    // Group events by day
    private var groupedEvents: [(String, [LinkFenceEventMessage])] {
        let grouped = Dictionary(grouping: events) { event -> String in
            let calendar = Calendar.current
            let now = Date()

            if calendar.isDateInToday(event.timestamp) {
                return "Hoy"
            } else if calendar.isDateInYesterday(event.timestamp) {
                return "Ayer"
            } else if calendar.isDate(event.timestamp, equalTo: now, toGranularity: .weekOfYear) {
                return "Esta Semana"
            } else if calendar.isDate(event.timestamp, equalTo: now, toGranularity: .month) {
                return "Este Mes"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM yyyy"
                formatter.locale = Locale(identifier: "es_MX")
                return formatter.string(from: event.timestamp)
            }
        }

        // Sort by most recent first
        let sortOrder = ["Hoy", "Ayer", "Esta Semana", "Este Mes"]
        return grouped.sorted { first, second in
            if let index1 = sortOrder.firstIndex(of: first.key),
               let index2 = sortOrder.firstIndex(of: second.key) {
                return index1 < index2
            } else if sortOrder.contains(first.key) {
                return true
            } else if sortOrder.contains(second.key) {
                return false
            } else {
                return first.key > second.key
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(groupedEvents, id: \.0) { section, sectionEvents in
                VStack(alignment: .leading, spacing: 12) {
                    // Section header
                    Text(section)
                        .font(.headline)
                        .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
                        .foregroundColor(accessibleTheme.textPrimary)
                        .accessibleText()
                        .padding(.leading, 4)

                    // Events in this section
                    ForEach(sectionEvents) { event in
                        GeofenceEventRow(event: event)
                    }
                }
            }

            if events.isEmpty {
                emptyStateView
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No hay eventos")
                .font(.headline)
                .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
                .foregroundColor(accessibleTheme.textSecondary)
                .accessibleText()

            Text("Cuando entres o salgas de este lugar, los eventos aparecerán aquí")
                .font(.caption)
                .foregroundColor(accessibleTheme.textSecondary)
                .accessibleText()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Event Row Component
struct GeofenceEventRow: View {
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme

    let event: LinkFenceEventMessage

    // Calculate duration if this is an exit event with a matching entry
    private var duration: TimeInterval? {
        // This would need access to all events to calculate duration
        // For now, return nil and calculate in the parent view if needed
        return nil
    }

    var body: some View {
        HStack(spacing: 16) {
            // Event type icon
            ZStack {
                Circle()
                    .fill(eventColor.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: eventIcon)
                    .font(.system(size: 18))
                    .foregroundColor(eventColor)
            }

            // Event info
            VStack(alignment: .leading, spacing: 4) {
                // Event type
                Text(event.eventType.displayName)
                    .font(.subheadline.bold())
                    .foregroundColor(accessibleTheme.textPrimary)
                    .accessibleText()

                // Timestamp
                Text(formatTime(event.timestamp))
                    .font(.caption)
                    .foregroundColor(accessibleTheme.textSecondary)
                    .accessibleText()
            }

            Spacer()

            // Duration (if available)
            if let duration = duration {
                Text(formatDuration(duration))
                    .font(.caption.bold())
                    .foregroundColor(accessibleTheme.primaryBlue)
                    .accessibleText()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .accessibleBackground(accessibleTheme.primaryBlue, opacity: 0.1)
                    .cornerRadius(8)
            }
        }
        .padding(12)
        .accessibleBackground(accessibleTheme.cardBackground, opacity: 1.0)
        .cornerRadius(12)
        .accessibleShadow()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.eventType.displayName) a las \(formatTime(event.timestamp))")
    }

    private var eventIcon: String {
        event.eventType == .entry ? "arrow.right.circle.fill" : "arrow.left.circle.fill"
    }

    private var eventColor: Color {
        event.eventType == .entry ? Color.appAccent : Mundial2026Colors.rojo
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        formatter.locale = Locale(identifier: "es_MX")
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)min"
        } else {
            return "\(minutes)min"
        }
    }
}

// MARK: - Preview
#Preview {
    ScrollView {
        LinkFenceEventTimeline(
            events: MockLinkFenceData.generateMockEvents()[
                UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
            ] ?? []
        )
        .padding()
    }
    .background(Color.appBackgroundDark)
}
