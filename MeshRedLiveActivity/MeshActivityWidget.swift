//
//  MeshActivityWidget.swift
//  MeshRedLiveActivity
//
//  Created by Claude for StadiumConnect Pro - Live Activities
//

import ActivityKit
import WidgetKit
import SwiftUI

/// Main Live Activity Widget for StadiumConnect Pro mesh networking
@available(iOS 16.1, *)
struct MeshActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MeshActivityAttributes.self) { context in
            // Lock Screen / Banner UI
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            // Dynamic Island UI
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeadingView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailingView(context: context)
                }
                DynamicIslandExpandedRegion(.center) {
                    ExpandedCenterView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottomView(context: context)
                }
            } compactLeading: {
                // Compact Leading (left side of island)
                CompactLeadingView(context: context)
            } compactTrailing: {
                // Compact Trailing (right side of island)
                CompactTrailingView(context: context)
            } minimal: {
                // Minimal (when multiple activities are active)
                MinimalView(context: context)
            }
        }
    }
}

// MARK: - Lock Screen View

@available(iOS 16.1, *)
struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<MeshActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "network")
                    .foregroundColor(.blue)
                    .font(.headline)

                Text("StadiumConnect Pro")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                // Connection quality indicator
                Text(context.state.connectionQuality.emoji)
                    .font(.title3)
            }

            // Main content
            if context.state.emergencyActive {
                EmergencyLockScreenContent(state: context.state)
            } else if context.state.trackingUser != nil {
                TrackingLockScreenContent(state: context.state)
            } else if context.state.activeLinkFence != nil {
                GeofenceLockScreenContent(state: context.state)
            } else {
                DefaultLockScreenContent(state: context.state)
            }

            // Footer with timestamp
            HStack {
                Text("Actualizado \(timeAgo(from: context.state.lastUpdated))")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(context.state.connectedPeers) conectados")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .activityBackgroundTint(backgroundColor(for: context.state))
        .activitySystemActionForegroundColor(.white)
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "hace \(seconds)s" }
        if seconds < 3600 { return "hace \(seconds / 60)m" }
        return "hace \(seconds / 3600)h"
    }

    private func backgroundColor(for state: MeshActivityAttributes.ContentState) -> Color {
        if state.emergencyActive {
            return .red
        } else if state.trackingUser != nil {
            return .blue
        } else {
            return .green
        }
    }
}

// MARK: - Emergency Lock Screen Content

@available(iOS 16.1, *)
struct EmergencyLockScreenContent: View {
    let state: MeshActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundColor(.red)

            VStack(alignment: .leading, spacing: 4) {
                Text("🚨 EMERGENCIA ACTIVA")
                    .font(.headline)
                    .foregroundColor(.red)

                if let type = state.emergencyType {
                    Text(type)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }

                Text("Personal médico notificado")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Tracking Lock Screen Content

@available(iOS 16.1, *)
struct TrackingLockScreenContent: View {
    let state: MeshActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            if state.isUWBTracking {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.title)
                    .foregroundColor(.cyan)
            } else {
                Image(systemName: "location.fill")
                    .font(.title)
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Buscando a \(state.trackingUser ?? "...")")
                    .font(.headline)

                HStack(spacing: 8) {
                    if let distance = state.distance {
                        Text(state.distanceString)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }

                    if state.direction != nil {
                        Text(state.directionEmoji)
                            .font(.title2)
                    }
                }

                Text(state.isUWBTracking ? "Precisión UWB" : "GPS")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Geofence Lock Screen Content

@available(iOS 16.1, *)
struct GeofenceLockScreenContent: View {
    let state: MeshActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "map.circle.fill")
                .font(.title)
                .foregroundColor(.purple)

            VStack(alignment: .leading, spacing: 4) {
                Text(state.activeLinkFence ?? "")
                    .font(.headline)

                if let status = state.linkfenceStatus {
                    HStack(spacing: 4) {
                        Text(status.emoji)
                        Text(status.displayName)
                            .font(.subheadline)
                    }
                }

                if state.nearbyFamilyMembers > 0 {
                    Text("\(state.nearbyFamilyMembers) miembros cerca")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Default Lock Screen Content

@available(iOS 16.1, *)
struct DefaultLockScreenContent: View {
    let state: MeshActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Red Mesh Activa")
                    .font(.headline)

                Text("\(state.connectedPeers) dispositivos conectados")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if state.familyMemberCount > 0 {
                VStack(spacing: 4) {
                    Image(systemName: "person.3.fill")
                        .font(.title2)
                        .foregroundColor(.green)

                    Text("\(state.nearbyFamilyMembers)/\(state.familyMemberCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Compact Views (Dynamic Island)

@available(iOS 16.1, *)
struct CompactLeadingView: View {
    let context: ActivityViewContext<MeshActivityAttributes>

    var body: some View {
        if context.state.emergencyActive {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
        } else if context.state.trackingUser != nil {
            if context.state.isUWBTracking {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .foregroundColor(.cyan)
            } else {
                Image(systemName: "location.fill")
                    .foregroundColor(.blue)
            }
        } else {
            Image(systemName: "network")
                .foregroundColor(.green)
        }
    }
}

@available(iOS 16.1, *)
struct CompactTrailingView: View {
    let context: ActivityViewContext<MeshActivityAttributes>

    var body: some View {
        if context.state.emergencyActive {
            Text("SOS")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.red)
        } else if let user = context.state.trackingUser {
            VStack(alignment: .trailing, spacing: 0) {
                Text(context.state.distanceString)
                    .font(.caption2)
                    .fontWeight(.semibold)

                if context.state.direction != nil {
                    Text(context.state.directionEmoji)
                        .font(.caption2)
                }
            }
        } else {
            Text("\(context.state.connectedPeers)")
                .font(.caption)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Minimal View

@available(iOS 16.1, *)
struct MinimalView: View {
    let context: ActivityViewContext<MeshActivityAttributes>

    var body: some View {
        if context.state.emergencyActive {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
        } else if context.state.trackingUser != nil {
            Image(systemName: "location.fill")
                .foregroundColor(.blue)
        } else {
            Text("\(context.state.connectedPeers)")
                .font(.caption2)
                .fontWeight(.bold)
        }
    }
}

// MARK: - Expanded Views (Dynamic Island)

@available(iOS 16.1, *)
struct ExpandedLeadingView: View {
    let context: ActivityViewContext<MeshActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if context.state.emergencyActive {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundColor(.red)
            } else if context.state.trackingUser != nil {
                Image(systemName: context.state.isUWBTracking ? "arrow.triangle.turn.up.right.diamond.fill" : "location.fill")
                    .font(.title2)
                    .foregroundColor(context.state.isUWBTracking ? .cyan : .blue)
            } else {
                Image(systemName: "network")
                    .font(.title2)
                    .foregroundColor(.green)
            }

            Text(context.state.connectionQuality.emoji)
                .font(.caption)
        }
    }
}

@available(iOS 16.1, *)
struct ExpandedTrailingView: View {
    let context: ActivityViewContext<MeshActivityAttributes>

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let user = context.state.trackingUser, let distance = context.state.distance {
                Text(context.state.distanceString)
                    .font(.title2)
                    .fontWeight(.bold)

                if context.state.direction != nil {
                    Text(context.state.directionEmoji)
                        .font(.title)
                }
            } else {
                Text("\(context.state.connectedPeers)")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("peers")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

@available(iOS 16.1, *)
struct ExpandedCenterView: View {
    let context: ActivityViewContext<MeshActivityAttributes>

    var body: some View {
        Text(context.state.statusSummary)
            .font(.headline)
            .multilineTextAlignment(.center)
    }
}

@available(iOS 16.1, *)
struct ExpandedBottomView: View {
    let context: ActivityViewContext<MeshActivityAttributes>

    var body: some View {
        HStack {
            if context.state.familyMemberCount > 0 {
                Label("\(context.state.nearbyFamilyMembers)/\(context.state.familyMemberCount) familia", systemImage: "person.3.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            Spacer()

            if context.state.activeLinkFence != nil {
                Label(context.state.activeLinkFence ?? "", systemImage: "map.circle")
                    .font(.caption)
                    .foregroundColor(.purple)
            }

            Spacer()

            if context.state.isRelayingMessages {
                Label("Relay", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal)
    }
}
