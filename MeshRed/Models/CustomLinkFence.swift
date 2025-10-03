//
//  CustomLinkFence.swift
//  MeshRed
//
//  Created by Claude for StadiumConnect Pro - Geofencing System
//

import Foundation
import CoreLocation
import SwiftUI

/// Represents a custom user-defined linkfence region
struct CustomLinkFence: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String                          // User-friendly name: "Estadio Azteca"
    let center: CLLocationCoordinate2D        // Center point of circular region
    let radius: CLLocationDistance            // Radius in meters (100-5000)
    let createdAt: Date
    let creatorPeerID: String                 // Device that created this linkfence
    var isActive: Bool                        // Currently being monitored
    var category: LinkFenceCategory            // Category of place
    var colorHex: String                      // Hex color for visual identification
    var isMonitoring: Bool                    // Whether actively monitoring this linkfence

    init(
        id: UUID = UUID(),
        name: String,
        center: CLLocationCoordinate2D,
        radius: CLLocationDistance,
        createdAt: Date = Date(),
        creatorPeerID: String,
        isActive: Bool = true,
        category: LinkFenceCategory = .custom,
        colorHex: String? = nil,
        isMonitoring: Bool = false
    ) {
        self.id = id
        self.name = name
        self.center = center
        self.radius = radius
        self.createdAt = createdAt
        self.creatorPeerID = creatorPeerID
        self.isActive = isActive
        self.category = category
        self.colorHex = colorHex ?? category.defaultColorHex
        self.isMonitoring = isMonitoring
    }

    /// Convert to CLCircularRegion for CoreLocation monitoring
    func toCLCircularRegion() -> CLCircularRegion {
        let region = CLCircularRegion(
            center: center,
            radius: radius,
            identifier: id.uuidString
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true
        return region
    }

    /// Check if a location is inside this linkfence
    func contains(_ location: UserLocation) -> Bool {
        let linkfenceCenter = CLLocation(
            latitude: center.latitude,
            longitude: center.longitude
        )
        let distance = linkfenceCenter.distance(from: location.toCLLocation())
        return distance <= radius
    }

    /// Human-readable description
    var description: String {
        return "\(name) (radio: \(Int(radius))m)"
    }

    /// Age of the linkfence
    var age: TimeInterval {
        return Date().timeIntervalSince(createdAt)
    }

    /// SwiftUI Color from hex string (uses Color(hex:) from Mundial2026Theme.swift)
    var color: Color {
        return Color(hex: colorHex)
    }

    static func == (lhs: CustomLinkFence, rhs: CustomLinkFence) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - CLLocationCoordinate2D Codable Extension

extension CLLocationCoordinate2D: Codable {
    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }
}

extension CLLocationCoordinate2D: Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}
