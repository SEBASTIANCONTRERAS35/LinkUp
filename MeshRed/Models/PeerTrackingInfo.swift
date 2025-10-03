//
//  PeerTrackingInfo.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Data model for peer tracking information
//

import Foundation
import SwiftUI

/// Information about a tracked peer for radar display
struct PeerTrackingInfo {
    let distance: Float?
    let hasDirection: Bool
    let dataSource: TrackingDataSource
    let lastUpdate: Date
    let signalQuality: Float?  // 0.0 to 1.0

    enum TrackingDataSource {
        case uwbPrecise       // LinkFinder with direction
        case uwbDistance      // LinkFinder distance only
        case gps              // GPS location
        case none             // No data available

        var displayName: String {
            switch self {
            case .uwbPrecise:
                return "LinkFinder Preciso"
            case .uwbDistance:
                return "LinkFinder (Solo Distancia)"
            case .gps:
                return "GPS Aproximado"
            case .none:
                return "Sin Datos"
            }
        }

        var icon: String {
            switch self {
            case .uwbPrecise:
                return "location.fill"
            case .uwbDistance:
                return "location.circle"
            case .gps:
                return "location.slash"
            case .none:
                return "exclamationmark.triangle"
            }
        }

        var color: Color {
            switch self {
            case .uwbPrecise:
                return Mundial2026Colors.azul
            case .uwbDistance:
                return Mundial2026Colors.verde
            case .gps:
                return .orange
            case .none:
                return .gray
            }
        }
    }

    /// Format distance for display
    func formattedDistance() -> String {
        guard let dist = distance else {
            return "Desconocido"
        }

        if dist < 1.0 {
            return String(format: "%.0f cm", dist * 100)
        } else if dist < 100 {
            return String(format: "%.1f m", dist)
        } else {
            return String(format: "%.0f m", dist)
        }
    }

    /// Calculate time since last update
    func timeSinceUpdate() -> String {
        let seconds = Int(Date().timeIntervalSince(lastUpdate))

        if seconds < 1 {
            return "Ahora"
        } else if seconds < 60 {
            return "\(seconds) seg"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes) min"
        } else {
            let hours = seconds / 3600
            return "\(hours) hr"
        }
    }

    /// Get signal quality level description
    func signalQualityLevel() -> String {
        guard let quality = signalQuality else {
            return "Desconocido"
        }

        if quality >= 0.8 {
            return "Excelente"
        } else if quality >= 0.6 {
            return "Buena"
        } else if quality >= 0.4 {
            return "Regular"
        } else if quality >= 0.2 {
            return "Débil"
        } else {
            return "Muy débil"
        }
    }
}
