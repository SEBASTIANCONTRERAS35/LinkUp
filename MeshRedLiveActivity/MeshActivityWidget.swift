//
//  MeshActivityWidget.swift
//  MeshRedLiveActivity
//
//  Created by Claude for StadiumConnect Pro - Live Activities
//

import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

/// Main Live Activity Widget for StadiumConnect Pro mesh networking
@available(iOS 16.1, *)
struct MeshActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MeshActivityAttributes.self) { context in
            let _ = print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            let _ = print("📱 LIVE ACTIVITY RENDERING")
            let _ = print("   Activity State: \(context.state)")
            let _ = print("   Activity ID: \(context.attributes.sessionId)")
            let _ = print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            // Lock Screen / Banner UI
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            // Dynamic Island UI
            DynamicIsland {
                let _ = print("🏝️ DYNAMIC ISLAND CONFIGURATION")
                let _ = print("   Peers: \(context.state.connectedPeers)")
                let _ = print("   Emergency: \(context.state.emergencyActive)")
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
                let _ = print("   → Setting up COMPACT LEADING")
                // Compact Leading (left side of island)
                CompactLeadingView(context: context)
            } compactTrailing: {
                let _ = print("   → Setting up COMPACT TRAILING")
                // Compact Trailing (right side of island)
                CompactTrailingView(context: context)
            } minimal: {
                let _ = print("   → Setting up MINIMAL")
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
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(backgroundColor(for: context.state), lineWidth: 2.5)
        )
        .activityBackgroundTint(.clear)
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

// MARK: - Compact Views (Dynamic Island) - PREMIUM UI

@available(iOS 16.1, *)
struct CompactLeadingView: View {
    let context: ActivityViewContext<MeshActivityAttributes>

    var body: some View {
        ZStack {
            // DEBUG: Print what we're rendering
            let _ = print("🔍 COMPACT LEADING VIEW")
            let _ = print("   Emergency: \(context.state.emergencyActive)")
            let _ = print("   Tracking User: \(context.state.trackingUser ?? "nil")")
            let _ = print("   Connected Peers: \(context.state.connectedPeers)")

            // Main icon - SIMPLIFIED with explicit sizing
            if context.state.emergencyActive {
                let _ = print("   → Rendering RED triangle")
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.red)
            } else if context.state.trackingUser != nil {
                let _ = print("   → Rendering CYAN location")
                Image(systemName: "location.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.cyan)
            } else {
                let _ = print("   → Rendering GREEN network icon")
                Image(systemName: "network")
                    .font(.system(size: 20))
                    .foregroundColor(.green)
            }
        }
    }
}

@available(iOS 16.1, *)
struct CompactTrailingView: View {
    let context: ActivityViewContext<MeshActivityAttributes>

    var body: some View {
        let _ = print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        let _ = print("🔍 COMPACT TRAILING VIEW")
        let _ = print("   Unread Messages: \(context.state.unreadMessageCount)")
        let _ = print("   Has New Messages: \(context.state.hasNewMessages)")

        ZStack {
            if context.state.hasNewMessages {
                let _ = print("   → ✅ Rendering MESSAGE BADGE: \(context.state.unreadMessageCount)")
                let _ = print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 26, height: 26)

                    Text("\(context.state.unreadMessageCount)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
            } else {
                let _ = print("   → ℹ️ Rendering PEER COUNT: \(context.state.connectedPeers)")
                let _ = print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                Text("\(context.state.connectedPeers)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - Minimal View

@available(iOS 16.1, *)
struct MinimalView: View {
    let context: ActivityViewContext<MeshActivityAttributes>

    var body: some View {
        let _ = print("🔍 MINIMAL VIEW (multiple activities)")
        let _ = print("   Emergency: \(context.state.emergencyActive)")
        let _ = print("   Has New Messages: \(context.state.hasNewMessages)")
        let _ = print("   Tracking: \(context.state.trackingUser ?? "nil")")
        let _ = print("   Peers: \(context.state.connectedPeers)")

        ZStack {
            if context.state.emergencyActive {
                let _ = print("   → Rendering RED triangle")
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 12))
            } else if context.state.hasNewMessages {
                // Priority: Show message icon when there are new messages
                let _ = print("   → Rendering MESSAGE icon with badge")
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "message.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 12))

                    // Small badge indicator
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                        .offset(x: 3, y: -3)
                }
            } else if context.state.trackingUser != nil {
                let _ = print("   → Rendering BLUE location")
                Image(systemName: "location.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 12))
            } else {
                let _ = print("   → Rendering WHITE number: \(context.state.connectedPeers)")
                Text("\(context.state.connectedPeers)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - Expanded Views (Dynamic Island) - PREMIUM UI

@available(iOS 16.1, *)
struct ExpandedLeadingView: View {
    let context: ActivityViewContext<MeshActivityAttributes>

    @State private var breathingScale: CGFloat = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Main icon with premium gradient and glow
            if context.state.emergencyActive {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.red, .orange],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .red.opacity(0.6), radius: 8)
                    .scaleEffect(breathingScale)
            } else if context.state.trackingUser != nil {
                Image(systemName: context.state.isUWBTracking ? "arrow.triangle.turn.up.right.diamond.fill" : "location.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: context.state.isUWBTracking ? [Color.cyan, Color.blue] : [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: (context.state.isUWBTracking ? Color.cyan : Color.blue).opacity(0.5), radius: 6)
            } else {
                // Normal: Progress ring showing connection capacity
                ZStack {
                    // Background ring
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 3)

                    // Progress ring (current peers / max 5)
                    Circle()
                        .trim(from: 0, to: min(CGFloat(context.state.connectedPeers) / 5.0, 1.0))
                        .stroke(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: context.state.connectedPeers)

                    // Center icon
                    Image(systemName: "network")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .scaleEffect(breathingScale)
                }
                .frame(width: 44, height: 44)
                .shadow(color: .green.opacity(0.4), radius: 6)
            }

            // Connection quality with better styling
            HStack(spacing: 3) {
                Text(context.state.connectionQuality.emoji)
                    .font(.system(size: 10))

                // Signal bars indicator
                SignalBarsView(quality: context.state.connectionQuality)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                breathingScale = 1.06
            }
        }
    }
}

@available(iOS 16.1, *)
struct ExpandedTrailingView: View {
    let context: ActivityViewContext<MeshActivityAttributes>

    @State private var directionRotation: Double = 0
    @State private var distancePulse: CGFloat = 1.0

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let user = context.state.trackingUser, let distance = context.state.distance {
                // Distance with premium typography + pulse animation
                Text(context.state.distanceString)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.9)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .scaleEffect(distancePulse)
                    .animation(.easeInOut(duration: 0.3), value: context.state.distanceString)

                // Direction arrow with rotation animation
                if context.state.direction != nil {
                    Text(context.state.directionEmoji)
                        .font(.system(size: 26))
                        .shadow(color: .black.opacity(0.2), radius: 1)
                        .rotationEffect(.degrees(directionRotation))
                        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: context.state.direction)
                        .onAppear {
                            directionRotation = 0
                        }
                        .onChange(of: context.state.direction) { _ in
                            // Smooth rotation when direction changes
                            withAnimation(.spring(response: 0.5)) {
                                directionRotation += 15 // Subtle wiggle
                            }
                            withAnimation(.spring(response: 0.3).delay(0.1)) {
                                directionRotation = 0
                            }
                        }
                }

                // UWB precision indicator (NEW - no repetition!)
                if context.state.isUWBTracking {
                    HStack(spacing: 2) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 4))
                            .foregroundColor(.cyan)
                        Text("UWB")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(.cyan)
                            .kerning(0.5)
                    }
                    .opacity(0.9)
                } else {
                    HStack(spacing: 2) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 4))
                            .foregroundColor(.blue.opacity(0.6))
                        Text("GPS")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                            .kerning(0.5)
                    }
                    .opacity(0.7)
                }
            } else {
                // Peers count with premium display
                Text("\(context.state.connectedPeers)")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)

                // Label with improved typography
                Text("PEERS")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .kerning(1.2)
                    .foregroundColor(.secondary)
                    .opacity(0.8)
            }
        }
        .onAppear {
            // Pulse when distance changes
            withAnimation(.easeInOut(duration: 0.2).repeatCount(1, autoreverses: true)) {
                distancePulse = 1.1
            }
        }
        .onChange(of: context.state.distanceString) { _ in
            withAnimation(.easeInOut(duration: 0.2).repeatCount(1, autoreverses: true)) {
                distancePulse = 1.15
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeOut(duration: 0.3)) {
                    distancePulse = 1.0
                }
            }
        }
    }
}

// MARK: - Signal Bars Component

@available(iOS 16.1, *)
struct SignalBarsView: View {
    let quality: MeshActivityAttributes.ConnectionQualityState

    private var barCount: Int {
        switch quality {
        case .excellent: return 4
        case .good: return 3
        case .poor: return 1
        case .unknown: return 0
        }
    }

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < barCount ? Color.green : Color.white.opacity(0.2))
                    .frame(width: 2, height: CGFloat(4 + index * 2))
                    .animation(.spring(response: 0.3).delay(Double(index) * 0.05), value: barCount)
            }
        }
    }
}

@available(iOS 16.1, *)
struct ExpandedCenterView: View {
    let context: ActivityViewContext<MeshActivityAttributes>

    var body: some View {
        VStack(spacing: 4) {
            // Status summary
            Text(context.state.statusSummary)
                .font(.headline)
                .multilineTextAlignment(.center)

            // NEW MESSAGES counter - ALWAYS VISIBLE if there are unread messages
            if context.state.hasNewMessages {
                HStack(spacing: 6) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)

                    Text("\(context.state.unreadMessageCount) mensajes nuevos")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.15))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
}

@available(iOS 16.1, *)
struct ExpandedBottomView: View {
    let context: ActivityViewContext<MeshActivityAttributes>

    @State private var relayRotation: Double = 0
    @State private var heartbeatScale: CGFloat = 1.0
    @State private var fenceGlow: CGFloat = 0
    @State private var messagePulse: CGFloat = 1.0

    var body: some View {
        HStack(spacing: 10) {
            // TRACKING MODE: Show username being tracked
            if let user = context.state.trackingUser {
                HStack(spacing: 4) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(
                            LinearGradient(
                                colors: context.state.isUWBTracking ? [.cyan, .blue] : [.blue, .blue.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .scaleEffect(heartbeatScale)

                    Text(user)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        heartbeatScale = 1.15
                    }
                }
            }
            // NORMAL MODE: Show family members
            else if context.state.familyMemberCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.green)
                        .scaleEffect(heartbeatScale)

                    Text("\(context.state.nearbyFamilyMembers)/\(context.state.familyMemberCount)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                        heartbeatScale = 1.1
                    }
                }
            }

            Spacer()

            // Geofence with pulsing glow
            if let fence = context.state.activeLinkFence {
                HStack(spacing: 3) {
                    Image(systemName: "map.circle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.purple)
                        .shadow(color: .purple.opacity(fenceGlow), radius: 4)

                    Text(fence)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.purple)
                        .lineLimit(1)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                        fenceGlow = 0.6
                    }
                }
            }

            Spacer()

            // Relay with continuous rotation
            if context.state.isRelayingMessages {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                        .rotationEffect(.degrees(relayRotation))

                    Text("Relay")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.orange)
                }
                .onAppear {
                    withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                        relayRotation = 360
                    }
                }
            }

            // NEW MESSAGES indicator (PRIORITY!)
            if context.state.hasNewMessages {
                HStack(spacing: 3) {
                    Image(systemName: "envelope.badge.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.red)
                        .scaleEffect(messagePulse)

                    Text("\(context.state.unreadMessageCount) nuevos")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.red)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        messagePulse = 1.15
                    }
                }
            }
            // Network latency indicator (when no messages)
            else if !context.state.isRelayingMessages && context.state.trackingUser == nil {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8))
                        .foregroundColor(latencyColor)

                    Text(latencyText)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(latencyColor)
                }
                .opacity(0.8)
            }
        }
        .padding(.horizontal, 12)

        // STOP BUTTON - Always visible at bottom
        // Uses URL scheme deep link - most reliable approach for Live Activities
        // Link opens meshred://stop which triggers immediate background processing
        Link(destination: URL(string: "meshred://stop-live-activity")!) {
            HStack(spacing: 6) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Stop")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.red)
            )
        }
        .padding(.top, 8)
    }

    // Helper computed properties for latency
    private var latencyColor: Color {
        switch context.state.connectionQuality {
        case .excellent: return .green
        case .good: return .yellow
        case .poor: return .red
        case .unknown: return .gray
        }
    }

    private var latencyText: String {
        switch context.state.connectionQuality {
        case .excellent: return "<50ms"
        case .good: return "~150ms"
        case .poor: return ">300ms"
        case .unknown: return "..."
        }
    }
}
