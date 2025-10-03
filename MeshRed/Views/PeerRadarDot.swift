//
//  PeerRadarDot.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Visual representation of peer on radar display
//

import SwiftUI

// MARK: - Peer Radar Dot
/// Visual representation of a connected peer on the radar
struct PeerRadarDot: View {
    let radarData: PeerRadarData
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        ZStack {
            if isSelected {
                // Selected: Show full info with name and distance
                VStack(spacing: 4) {
                    // Main dot
                    Circle()
                        .fill(dotColor)
                        .frame(width: dotSize, height: dotSize)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white, lineWidth: 3)
                        )
                        .shadow(color: dotColor.opacity(0.6), radius: 8)

                    // Peer name label
                    Text(radarData.peer)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(dotColor)
                        )
                        .shadow(color: .black.opacity(0.4), radius: 3)

                    // Distance indicator
                    if let distance = radarData.distance {
                        Text(formatDistance(distance))
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.7))
                            )
                            .shadow(color: .black.opacity(0.3), radius: 2)
                    }
                }
            } else {
                // Unselected: Just dot with small distance badge
                ZStack(alignment: .topTrailing) {
                    // Main dot
                    Circle()
                        .fill(dotColor)
                        .frame(width: dotSize, height: dotSize)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white, lineWidth: 1.5)
                        )
                        .shadow(color: dotColor.opacity(0.3), radius: 4)

                    // Small distance badge on top-right
                    if let distance = radarData.distance {
                        Text(formatDistanceCompact(distance))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.8))
                            )
                            .offset(x: 6, y: -4)
                    }
                }
            }
        }
        .onTapGesture {
            #if os(iOS)
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            #endif
            onTap()
        }
        // ACCESSIBILITY: VoiceOver support
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to view peer details")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Computed Properties

    /// Dot color based on data source
    private var dotColor: Color {
        radarData.dataSource.color
    }

    /// Dot size based on positioning accuracy
    private var dotSize: CGFloat {
        if isSelected {
            // Larger when selected
            switch radarData.dataSource {
            case .uwbPrecise: return 20
            case .uwbDistance: return 18
            case .gps: return 16
            case .none: return 14
            }
        } else {
            // Normal size
            switch radarData.dataSource {
            case .uwbPrecise: return 16
            case .uwbDistance: return 14
            case .gps: return 12
            case .none: return 10
            }
        }
    }

    /// Should pulse when peer is very close (< 2m)
    private var shouldPulse: Bool {
        guard let distance = radarData.distance else { return false }
        return distance < 2.0 && !reduceMotion
    }

    /// Accessibility label for VoiceOver
    private var accessibilityLabel: String {
        var label = "\(radarData.peer), "

        if let distance = radarData.distance {
            label += "distance \(formatDistance(distance)), "
        }

        label += "positioning via \(radarData.dataSource.displayName)"

        return label
    }

    // MARK: - Helper Methods

    /// Format distance for display (full detail)
    private func formatDistance(_ meters: Float) -> String {
        if meters < 1.0 {
            return String(format: "%.0fcm", meters * 100)
        } else if meters < 100 {
            return String(format: "%.1fm", meters)
        } else {
            return String(format: "%.0fm", meters)
        }
    }

    /// Format distance in compact form for unselected dots
    private func formatDistanceCompact(_ meters: Float) -> String {
        if meters < 1.0 {
            return String(format: "%.0fcm", meters * 100)
        } else if meters < 10 {
            return String(format: "%.1fm", meters)
        } else {
            return String(format: "%.0fm", meters)
        }
    }
}

// MARK: - Proximity Pulse Animation
/// Pulsing animation for very close peers (respects reduce motion)
struct ProximityPulse: ViewModifier {
    let shouldPulse: Bool
    let color: Color

    @State private var isPulsing = false

    func body(content: Content) -> some View {
        if shouldPulse {
            content
                .overlay(
                    Circle()
                        .stroke(color, lineWidth: 2)
                        .scaleEffect(isPulsing ? 1.8 : 1.0)
                        .opacity(isPulsing ? 0.0 : 0.8)
                        .animation(
                            Animation.easeOut(duration: 1.2)
                                .repeatForever(autoreverses: false),
                            value: isPulsing
                        )
                )
                .onAppear {
                    isPulsing = true
                }
        } else {
            content
        }
    }
}

// MARK: - Preview
#if DEBUG
struct PeerRadarDot_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            // Radar background
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.black.opacity(0.6),
                            Color.black.opacity(0.9)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)

            // Example dots at different positions
            VStack(spacing: 40) {
                HStack(spacing: 60) {
                    // LinkFinder Precise
                    PeerRadarDot(
                        radarData: PeerRadarData(
                            id: "1",
                            peer: "María",
                            position: .exact(x: 0, y: 0),
                            dataSource: .uwbPrecise,
                            distance: 1.5
                        ),
                        isSelected: false,
                        onTap: {}
                    )

                    // LinkFinder Distance (selected)
                    PeerRadarDot(
                        radarData: PeerRadarData(
                            id: "2",
                            peer: "Carlos",
                            position: .ring(distance: 3.2, x: 0, y: 0),
                            dataSource: .uwbDistance,
                            distance: 3.2
                        ),
                        isSelected: true,
                        onTap: {}
                    )
                }

                HStack(spacing: 60) {
                    // GPS
                    PeerRadarDot(
                        radarData: PeerRadarData(
                            id: "3",
                            peer: "Ana",
                            position: .gps(x: 0, y: 0),
                            dataSource: .gps,
                            distance: 12.8
                        ),
                        isSelected: false,
                        onTap: {}
                    )

                    // No data
                    PeerRadarDot(
                        radarData: PeerRadarData(
                            id: "4",
                            peer: "Luis",
                            position: .unknown,
                            dataSource: .none,
                            distance: nil
                        ),
                        isSelected: false,
                        onTap: {}
                    )
                }
            }
        }
        .frame(width: 400, height: 400)
        .preferredColorScheme(.dark)
    }
}
#endif
