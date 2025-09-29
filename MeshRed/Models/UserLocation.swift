//
//  UserLocation.swift
//  MeshRed
//
//  Created by Emilio Contreras on 29/09/25.
//

import Foundation
import CoreLocation

/// Represents a GPS location with accuracy information
struct UserLocation: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double  // Horizontal accuracy in meters
    let timestamp: Date

    init(latitude: Double, longitude: Double, accuracy: Double, timestamp: Date = Date()) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.timestamp = timestamp
    }

    /// Initialize from CoreLocation CLLocation
    init(from clLocation: CLLocation) {
        self.latitude = clLocation.coordinate.latitude
        self.longitude = clLocation.coordinate.longitude
        self.accuracy = clLocation.horizontalAccuracy
        self.timestamp = clLocation.timestamp
    }

    /// Convert to CLLocation for use with MapKit/CoreLocation
    func toCLLocation() -> CLLocation {
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: -1,
            timestamp: timestamp
        )
    }

    /// Calculate distance to another location
    func distance(to other: UserLocation) -> Double {
        let from = self.toCLLocation()
        let to = other.toCLLocation()
        return from.distance(from: to)
    }

    /// Human-readable coordinate string
    var coordinateString: String {
        return String(format: "%.6f, %.6f", latitude, longitude)
    }

    /// Human-readable accuracy string
    var accuracyString: String {
        if accuracy < 10 {
            return String(format: "±%.1fm", accuracy)
        } else {
            return String(format: "±%.0fm", accuracy)
        }
    }
}