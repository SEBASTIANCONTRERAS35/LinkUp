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

    // Animation state
    @State private var breathingScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.3
    @State private var glowRadius: CGFloat = 4
    @State private var badgePulse: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Main icon
            if context.state.emergencyActive {
                // EMERGENCY: Pulsing red effect
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.red, .orange],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .red.opacity(pulseOpacity), radius: glowRadius)
                    .scaleEffect(breathingScale)
            } else if context.state.trackingUser != nil {
                if context.state.isUWBTracking {
                    // UWB TRACKING: Cyan gradient with shimmer
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.cyan, Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color.cyan.opacity(0.5), radius: 3)
                } else {
                    // GPS TRACKING: Blue solid
                    Image(systemName: "location.fill")
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .blue.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .blue.opacity(0.4), radius: 2)
                }
            } else {
                // NORMAL: Breathing green network
                Image(systemName: "network")
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .mint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .green.opacity(0.4), radius: glowRadius)
                    .scaleEffect(breathingScale)
            }

            // MESSAGE BADGE: Show unread count if there are new messages
            if context.state.hasNewMessages {
                Text("\(context.state.unreadMessageCount)")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(minWidth: 12, minHeight: 12)
                    .padding(2)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.red, .red.opacity(0.9)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: .red.opacity(0.6), radius: 4)
                    )
                    .offset(x: 6, y: -4)
                    .scaleEffect(badgePulse)
            }
        }
        .onAppear {
            startAnimations()
        }
    }

    private func startAnimations() {
        // Breathing animation (1.0 → 1.08 → 1.0) every 2 seconds
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            breathingScale = 1.08
        }

        // Pulse opacity for emergency/glow
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            pulseOpacity = 0.8
        }

        // Glow radius pulsing
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            glowRadius = 6
        }

        // Badge pulse animation (for unread messages)
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            badgePulse = 1.15
        }
    }
}

@available(iOS 16.1, *)
struct CompactTrailingView: View {
    let context: ActivityViewContext<MeshActivityAttributes>

    @State private var shimmerOffset: CGFloat = -50
    @State private var distanceBounce: CGFloat = 1.0
    @State private var arrowRotation: Double = 0
    @State private var emergencyPulse: CGFloat = 1.0

    var body: some View {
        if context.state.emergencyActive {
            // EMERGENCY: Bold SOS with pulsing animation
            Text("SOS")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.red, .orange],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: .red.opacity(0.5), radius: 2)
                .scaleEffect(emergencyPulse)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                        emergencyPulse = 1.15
                    }
                }
        } else if let user = context.state.trackingUser {
            VStack(alignment: .trailing, spacing: 2) {
                // Distance with SF Rounded + bounce animation
                Text(context.state.distanceString)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.9)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .scaleEffect(distanceBounce)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: context.state.distanceString)

                // Direction arrow with rotation
                if context.state.direction != nil {
                    Text(context.state.directionEmoji)
                        .font(.system(size: 11))
                        .rotationEffect(.degrees(arrowRotation))
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: context.state.direction)
                }
            }
            .onChange(of: context.state.distanceString) { _ in
                // Bounce effect when distance updates
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    distanceBounce = 1.2
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.spring(response: 0.4)) {
                        distanceBounce = 1.0
                    }
                }
            }
            .onChange(of: context.state.direction) { _ in
                // Wiggle arrow when direction changes
                withAnimation(.spring(response: 0.3)) {
                    arrowRotation = 20
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(response: 0.4)) {
                        arrowRotation = 0
                    }
                }
            }
        } else if context.state.hasNewMessages {
            // MESSAGES COUNT: Show unread messages with icon
            VStack(spacing: 1) {
                Text("\(context.state.unreadMessageCount)")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.9)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                    .overlay(
                        // Shimmer overlay (triggers on message count change)
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.3), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 20)
                        .offset(x: shimmerOffset)
                    )

                Image(systemName: "envelope.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.red)
                    .shadow(color: .red.opacity(0.4), radius: 2)
            }
            .onChange(of: context.state.unreadMessageCount) { _ in
                triggerShimmer()
            }
        } else {
            // PEERS COUNT: Premium number display
            ZStack {
                // Number with shimmer effect on update
                Text("\(context.state.connectedPeers)")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                    .overlay(
                        // Shimmer overlay (triggers on peer count change)
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.3), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 20)
                        .offset(x: shimmerOffset)
                    )
            }
            .onChange(of: context.state.connectedPeers) { _ in
                triggerShimmer()
            }
        }
    }

    private func triggerShimmer() {
        shimmerOffset = -50
        withAnimation(.linear(duration: 0.6)) {
            shimmerOffset = 50
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
        Text(context.state.statusSummary)
            .font(.headline)
            .multilineTextAlignment(.center)
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
