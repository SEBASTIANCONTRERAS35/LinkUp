//
//  AppColors.swift
//  MeshRed - StadiumConnect Pro
//
//  Sistema de colores centralizado usando Assets
//  Integración con tema Mundial 2026
//

import SwiftUI

// MARK: - App Colors Extension
extension Color {
    
    // MARK: - Primary Colors from Assets
    
    /// Violeta primario (#7c3aed)
    static let appPrimary = Color("PrimaryColor")
    
    /// Cyan secundario (#06B6D4)
    static let appSecondary = Color("SecondaryColor")
    
    /// Teal acento (#14B8A6)
    static let appAccent = Color("AccentColor")
    
    /// Fondo oscuro (#0F172A)
    static let appBackgroundDark = Color("BackgroundDark")
    
    /// Fondo secundario (#1E293B)
    static let appBackgroundSecondary = Color("BackgroundSecondary")
    
    // MARK: - Compatibility with Mundial 2026 Theme
    // Mantén los colores originales para compatibilidad retroactiva
    
    /// México Verde (original)
    static let mundial2026Verde = Mundial2026Colors.verde
    
    /// USA Azul (original)
    static let mundial2026Azul = Mundial2026Colors.azul
    
    /// Canadá Rojo (original)
    static let mundial2026Rojo = Mundial2026Colors.rojo
    
    // MARK: - Semantic Colors (combinando ambos sistemas)
    
    /// Color principal para botones y elementos destacados
    static var primaryButton: Color {
        appPrimary // Violeta moderno
    }
    
    /// Color para acciones secundarias
    static var secondaryButton: Color {
        appSecondary // Cyan
    }
    
    /// Color para estados activos y resaltados
    static var activeAccent: Color {
        appAccent // Teal
    }
    
    /// Color para fondos de pantallas oscuras
    static var darkBackground: Color {
        appBackgroundDark
    }
    
    /// Color para tarjetas sobre fondo oscuro
    static var darkCard: Color {
        appBackgroundSecondary
    }
}

// MARK: - UIColor Extension (para UIKit compatibility)
#if canImport(UIKit)
import UIKit

extension UIColor {
    
    /// Violeta primario (#7c3aed)
    static let appPrimary = UIColor(named: "PrimaryColor")!
    
    /// Cyan secundario (#06B6D4)
    static let appSecondary = UIColor(named: "SecondaryColor")!
    
    /// Teal acento (#14B8A6)
    static let appAccent = UIColor(named: "AccentColor")!
    
    /// Fondo oscuro (#0F172A)
    static let appBackgroundDark = UIColor(named: "BackgroundDark")!
    
    /// Fondo secundario (#1E293B)
    static let appBackgroundSecondary = UIColor(named: "BackgroundSecondary")!
}
#endif
