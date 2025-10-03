//
//  RadarSweepSystem.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Military-style radar sweep animation with peer detection
//

import SwiftUI
import Combine

// MARK: - Radar Sweep Line
/// Rotating sweep line with gradient trail effect
struct RadarSweepLine: View {
    let radius: CGFloat
    @Binding var sweepAngle: Double
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Sweep gradient trail (fades behind the line)
            AngularGradient(
                gradient: Gradient(colors: [
                    sweepColor.opacity(0.0),  // Start: transparent
                    sweepColor.opacity(0.1),
                    sweepColor.opacity(0.3),
                    sweepColor.opacity(0.6),
                    sweepColor.opacity(0.9),  // End: near opaque (sweep line position)
                ]),
                center: .center,
                startAngle: .degrees(0),
                endAngle: .degrees(360)
            )
            .frame(width: radius * 2, height: radius * 2)
            .mask(
                Circle()
                    .frame(width: radius * 2, height: radius * 2)
            )

            // Main sweep line (bright leading edge)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            sweepColor.opacity(0.0),
                            sweepColor
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: radius, height: 2)
                .offset(x: radius / 2)
                .shadow(color: sweepColor.opacity(0.8), radius: 4)
        }
        .rotationEffect(.degrees(sweepAngle))
        .blendMode(.plusLighter) // Additive blending for glow effect
    }

    private var sweepColor: Color {
        colorScheme == .dark ?
            Color.green :
            Mundial2026Colors.verde
    }
}

// MARK: - Peer Detection Manager
/// Manages peer visibility based on sweep detection
class RadarSweepDetectionManager: ObservableObject {
    // Last time each peer was detected (by peer ID)
    @Published var lastDetectionTime: [String: Date] = [:]

    // Sweep parameters
    let sweepSpeed: Double = 4.0  // seconds per full rotation
    let fadeOutDuration: Double = 2.5  // seconds for peer to fade out

    /// Check if sweep line has passed over a peer
    func checkDetection(peerId: String, peerAngle: Double, sweepAngle: Double) {
        // Normalize angles to 0-360
        let normalizedPeerAngle = peerAngle.truncatingRemainder(dividingBy: 360)
        let normalizedSweepAngle = sweepAngle.truncatingRemainder(dividingBy: 360)

        // Detection window: ±15 degrees from sweep line
        let detectionWindow: Double = 15

        let angleDifference = abs(normalizedSweepAngle - normalizedPeerAngle)
        let wrappedDifference = min(angleDifference, 360 - angleDifference)

        if wrappedDifference <= detectionWindow {
            print("🎯 DETECTED: \(peerId) | PeerAngle: \(String(format: "%.1f", normalizedPeerAngle))° | SweepAngle: \(String(format: "%.1f", normalizedSweepAngle))° | Diff: \(String(format: "%.1f", wrappedDifference))°")
            lastDetectionTime[peerId] = Date()
        }
    }

    /// Calculate opacity for a peer based on time since last detection
    func opacity(for peerId: String) -> Double {
        guard let lastDetected = lastDetectionTime[peerId] else {
            // print("⚫️ \(peerId): Not detected yet (opacity: 0.0)")
            return 0.0  // Not yet detected
        }

        let timeSinceDetection = Date().timeIntervalSince(lastDetected)

        if timeSinceDetection >= fadeOutDuration {
            return 0.0  // Completely faded
        }

        // Linear fade from 1.0 to 0.0 over fadeOutDuration
        let opacity = 1.0 - (timeSinceDetection / fadeOutDuration)
        let finalOpacity = max(0.0, min(1.0, opacity))

        // print("✨ \(peerId): opacity \(String(format: "%.2f", finalOpacity)) | time since: \(String(format: "%.2f", timeSinceDetection))s")

        return finalOpacity
    }

    /// Calculate angle of a peer from its x,y position
    /// - Parameters:
    ///   - x: X coordinate relative to center
    ///   - y: Y coordinate relative to center (inverted in SwiftUI)
    /// - Returns: Angle in degrees (0° = North, clockwise)
    static func calculateAngle(x: CGFloat, y: CGFloat) -> Double {
        // atan2 returns angle from positive x-axis, counter-clockwise
        // We need angle from north (negative y-axis), clockwise
        let radians = atan2(x, -y)
        var degrees = radians * 180 / .pi

        // Normalize to 0-360
        if degrees < 0 {
            degrees += 360
        }

        return degrees
    }
}

// MARK: - Peer Radar Data with Angle
extension PeerRadarData {
    /// Calculate the angle of this peer on the radar
    func angle() -> Double? {
        guard let point = position.point else { return nil }
        return RadarSweepDetectionManager.calculateAngle(x: point.x, y: point.y)
    }
}
