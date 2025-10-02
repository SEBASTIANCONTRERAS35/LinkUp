//
//  Mundial2026Theme.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Official color palette for FIFA World Cup 2026 (Mexico 🇲🇽 USA 🇺🇸 Canada 🇨🇦)
//

import SwiftUI

// MARK: - Mundial 2026 Color Palette
struct Mundial2026Colors {
    // Primary Colors - Official FIFA World Cup 2026
    static let verde = Color(hex: "006847")      // 🇲🇽 Mexico Green
    static let azul = Color(hex: "3C3B6E")       // 🇺🇸 USA Blue
    static let rojo = Color(hex: "CE1126")       // 🇨🇦 Canada Red

    // Secondary/Support Colors
    static let verdeClaro = Color(hex: "00A86B") // Lighter green for accents
    static let azulClaro = Color(hex: "5B5D9E")  // Lighter blue for accents
    static let rojoClaro = Color(hex: "E85D75")  // Lighter red for accents

    // Neutral Colors
    static let background = Color(hex: "F8F8F9")  // Light gray background
    static let cardBackground = Color.white
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary

    // Status Colors
    static let success = verde
    static let warning = Color.orange
    static let error = rojo
    static let info = azul
}

// MARK: - Color Extension for Hex Support
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Theme Gradients
struct Mundial2026Gradients {
    // Primary gradient (Mexico green to USA blue)
    static let primary = LinearGradient(
        colors: [Mundial2026Colors.verde, Mundial2026Colors.azul],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Secondary gradient (USA blue to Canada red)
    static let secondary = LinearGradient(
        colors: [Mundial2026Colors.azul, Mundial2026Colors.rojo],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Accent gradient (Mexico green to Canada red)
    static let accent = LinearGradient(
        colors: [Mundial2026Colors.verde, Mundial2026Colors.rojo],
        startPoint: .leading,
        endPoint: .trailing
    )

    // Match card gradient
    static let matchCard = LinearGradient(
        colors: [
            Mundial2026Colors.azul,
            Mundial2026Colors.azul.opacity(0.9)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Theme Styles
struct Mundial2026Styles {
    // Button styles with official colors
    struct PrimaryButton: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Mundial2026Colors.verde)
                .cornerRadius(12)
                .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
        }
    }

    struct SecondaryButton: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Mundial2026Colors.azul)
                .cornerRadius(12)
                .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
        }
    }

    struct DangerButton: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Mundial2026Colors.rojo)
                .cornerRadius(12)
                .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
        }
    }
}
