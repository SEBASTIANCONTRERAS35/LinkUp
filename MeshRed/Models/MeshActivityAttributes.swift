//
//  MeshActivityAttributes.swift
//  MeshRed
//
//  Created by Claude for StadiumConnect Pro - Live Activities
//

import Foundation
import ActivityKit

/// Attributes for Mesh Network Live Activity
/// Displays real-time mesh networking status in Dynamic Island and Lock Screen
@available(iOS 16.1, *)
struct MeshActivityAttributes: ActivityAttributes {
    // MARK: - Static Attributes
    // These don't change during the life of the Live Activity

    /// Unique session identifier
    public var sessionId: String

    /// Local device name
    public var localDeviceName: String

    /// Timestamp when the activity started
    public var startedAt: Date

    // MARK: - Dynamic Content State
    // These values update throughout the Live Activity's lifetime

    public struct ContentState: Codable, Hashable {
        // MARK: - Network Status

        /// Number of directly connected peers
        var connectedPeers: Int

        /// Connection quality indicator
        var connectionQuality: ConnectionQualityState

        /// Whether mesh is actively relaying messages
        var isRelayingMessages: Bool

        // MARK: - Tracking/Navigation

        /// Name of user being tracked (nil if not tracking anyone)
        var trackingUser: String?

        /// Distance to tracked user in meters (nil if not tracking)
        var distance: Double?

        /// Cardinal direction to tracked user (nil if not available)
        var direction: CardinalDirection?

        /// Whether tracking uses UWB precision
        var isUWBTracking: Bool

        // MARK: - Family Group

        /// Total members in family group
        var familyMemberCount: Int

        /// Number of family members currently in range (connected or reachable)
        var nearbyFamilyMembers: Int

        // MARK: - Geofencing

        /// Name of active geofence (nil if none)
        var activeLinkFence: String?

        /// Current geofence status
        var linkfenceStatus: LinkFenceStatus?

        // MARK: - Emergency

        /// Whether there's an active emergency alert
        var emergencyActive: Bool

        /// Type of emergency if active
        var emergencyType: String?

        // MARK: - Metadata

        /// Last update timestamp
        var lastUpdated: Date

        // MARK: - Helper Properties

        /// User-friendly distance string
        var distanceString: String {
            guard let dist = distance else { return "---" }

            if dist < 1.0 {
                return String(format: "%.0fcm", dist * 100)
            } else if dist < 100 {
                return String(format: "%.0fm", dist)
            } else if dist < 1000 {
                return String(format: "%.0fm", dist)
            } else {
                return String(format: "%.1fkm", dist / 1000)
            }
        }

        /// Direction indicator emoji
        var directionEmoji: String {
            guard let dir = direction else { return "" }
            return dir.emoji
        }

        /// Status summary for compact view
        var statusSummary: String {
            if emergencyActive {
                return "🚨 Emergencia"
            } else if let user = trackingUser {
                return "Buscando a \(user)"
            } else if let fence = activeLinkFence {
                return "📍 \(fence)"
            } else if connectedPeers > 0 {
                return "\(connectedPeers) conectados"
            } else {
                return "Buscando red..."
            }
        }
    }

    // MARK: - Supporting Types

    /// Connection quality states
    public enum ConnectionQualityState: String, Codable, Hashable {
        case excellent = "excellent"
        case good = "good"
        case poor = "poor"
        case unknown = "unknown"

        var emoji: String {
            switch self {
            case .excellent: return "🟢"
            case .good: return "🟡"
            case .poor: return "🔴"
            case .unknown: return "⚪️"
            }
        }

        var displayName: String {
            switch self {
            case .excellent: return "Excelente"
            case .good: return "Buena"
            case .poor: return "Pobre"
            case .unknown: return "Desconocida"
            }
        }
    }

    /// Cardinal directions for navigation
    public enum CardinalDirection: String, Codable, Hashable {
        case north = "N"
        case northeast = "NE"
        case east = "E"
        case southeast = "SE"
        case south = "S"
        case southwest = "SW"
        case west = "W"
        case northwest = "NW"

        var emoji: String {
            switch self {
            case .north: return "⬆️"
            case .northeast: return "↗️"
            case .east: return "➡️"
            case .southeast: return "↘️"
            case .south: return "⬇️"
            case .southwest: return "↙️"
            case .west: return "⬅️"
            case .northwest: return "↖️"
            }
        }

        /// Convert degrees to cardinal direction (0° = North)
        static func from(degrees: Double) -> CardinalDirection {
            let normalized = (degrees + 360).truncatingRemainder(dividingBy: 360)

            switch normalized {
            case 337.5..<360, 0..<22.5:
                return .north
            case 22.5..<67.5:
                return .northeast
            case 67.5..<112.5:
                return .east
            case 112.5..<157.5:
                return .southeast
            case 157.5..<202.5:
                return .south
            case 202.5..<247.5:
                return .southwest
            case 247.5..<292.5:
                return .west
            case 292.5..<337.5:
                return .northwest
            default:
                return .north
            }
        }
    }

    /// Geofence status
    public enum LinkFenceStatus: String, Codable, Hashable {
        case inside = "inside"
        case outside = "outside"
        case entering = "entering"
        case exiting = "exiting"

        var emoji: String {
            switch self {
            case .inside: return "✅"
            case .outside: return "🔴"
            case .entering: return "🔵"
            case .exiting: return "🟠"
            }
        }

        var displayName: String {
            switch self {
            case .inside: return "Dentro"
            case .outside: return "Fuera"
            case .entering: return "Entrando"
            case .exiting: return "Saliendo"
            }
        }
    }
}

// MARK: - ContentState Initializer Helpers

@available(iOS 16.1, *)
extension MeshActivityAttributes.ContentState {
    /// Create initial state with default values
    static func initial() -> Self {
        return MeshActivityAttributes.ContentState(
            connectedPeers: 0,
            connectionQuality: .unknown,
            isRelayingMessages: false,
            trackingUser: nil,
            distance: nil,
            direction: nil,
            isUWBTracking: false,
            familyMemberCount: 0,
            nearbyFamilyMembers: 0,
            activeLinkFence: nil,
            linkfenceStatus: nil,
            emergencyActive: false,
            emergencyType: nil,
            lastUpdated: Date()
        )
    }

    /// Create state for active tracking scenario
    static func tracking(
        user: String,
        distance: Double,
        direction: MeshActivityAttributes.CardinalDirection?,
        isUWB: Bool,
        connectedPeers: Int
    ) -> Self {
        return MeshActivityAttributes.ContentState(
            connectedPeers: connectedPeers,
            connectionQuality: .good,
            isRelayingMessages: false,
            trackingUser: user,
            distance: distance,
            direction: direction,
            isUWBTracking: isUWB,
            familyMemberCount: 0,
            nearbyFamilyMembers: 0,
            activeLinkFence: nil,
            linkfenceStatus: nil,
            emergencyActive: false,
            emergencyType: nil,
            lastUpdated: Date()
        )
    }

    /// Create state for emergency scenario
    static func emergency(
        type: String,
        connectedPeers: Int
    ) -> Self {
        return MeshActivityAttributes.ContentState(
            connectedPeers: connectedPeers,
            connectionQuality: .good,
            isRelayingMessages: true,
            trackingUser: nil,
            distance: nil,
            direction: nil,
            isUWBTracking: false,
            familyMemberCount: 0,
            nearbyFamilyMembers: 0,
            activeLinkFence: nil,
            linkfenceStatus: nil,
            emergencyActive: true,
            emergencyType: type,
            lastUpdated: Date()
        )
    }
}
