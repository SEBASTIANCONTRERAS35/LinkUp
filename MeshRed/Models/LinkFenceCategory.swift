//
//  LinkFenceCategory.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Categories for different types of linkfenced places
//

import SwiftUI

/// Categories for different types of linkfenced places
enum LinkFenceCategory: String, Codable, CaseIterable {
    case stadium = "Estadio"
    case concert = "Concierto"
    case restaurant = "Restaurante"
    case shopping = "Centro Comercial"
    case home = "Casa"
    case work = "Trabajo"
    case school = "Escuela"
    case custom = "Personalizado"

    // Stadium-specific zones
    case bathrooms = "Baños"
    case exits = "Salidas"
    case concessions = "Concesiones"
    case familyZone = "Zona Familiar"

    /// SF Symbol icon for each category
    var icon: String {
        switch self {
        case .stadium:
            return "sportscourt.fill"
        case .concert:
            return "music.note"
        case .restaurant:
            return "fork.knife"
        case .shopping:
            return "cart.fill"
        case .home:
            return "house.fill"
        case .work:
            return "briefcase.fill"
        case .school:
            return "book.fill"
        case .custom:
            return "mappin.circle.fill"
        case .bathrooms:
            return "figure.walk"
        case .exits:
            return "rectangle.portrait.and.arrow.right"
        case .concessions:
            return "fork.knife"
        case .familyZone:
            return "figure.2.and.child.holdinghands"
        }
    }

    /// Default color for each category (Mundial 2026 palette)
    var defaultColor: Color {
        switch self {
        case .stadium:
            return Color.appAccent
        case .concert:
            return Mundial2026Colors.rojo
        case .restaurant:
            return Color.orange
        case .shopping:
            return Color.appPrimary
        case .home:
            return Color.appPrimary
        case .work:
            return Color.gray
        case .school:
            return Color.appSecondary
        case .custom:
            return Color.appPrimary
        case .bathrooms:
            return Color.appSecondary
        case .exits:
            return Color.orange
        case .concessions:
            return Color.appAccent
        case .familyZone:
            return Color.appAccent
        }
    }

    /// Hex string representation of default color
    var defaultColorHex: String {
        switch self {
        case .stadium:
            return "006847"  // Mexico green
        case .concert:
            return "CE1126"  // Canada red
        case .restaurant:
            return "FF9500"  // Orange
        case .shopping:
            return "3C3B6E"  // USA blue
        case .home:
            return "AF52DE"  // Purple
        case .work:
            return "8E8E93"  // Gray
        case .school:
            return "007AFF"  // Blue
        case .custom:
            return "3C3B6E"  // USA blue
        case .bathrooms:
            return "007AFF"  // Blue
        case .exits:
            return "FF9500"  // Orange
        case .concessions:
            return "34C759"  // Green
        case .familyZone:
            return "006847"  // Mexico green
        }
    }
}
