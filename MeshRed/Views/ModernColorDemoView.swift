//
//  ModernColorDemoView.swift
//  MeshRed - StadiumConnect Pro
//
//  Vista de demostración del nuevo sistema de colores
//

import SwiftUI

struct ModernColorDemoView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme

    var body: some View {
        ZStack {
            // Fondo oscuro moderno
            Color.appBackgroundDark
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection

                    // Botones Primarios
                    primaryButtonsSection

                    // Cards
                    cardsSection

                    // Paleta de Colores
                    colorPaletteSection

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
        .navigationTitle("Nuevo Sistema de Colores")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Cerrar") {
                    dismiss()
                }
                .foregroundColor(.appSecondary)
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "paintpalette.fill")
                .font(.system(size: 60))
                .foregroundColor(.appPrimary)
                .padding(.bottom, 8)

            Text("Nuevo Sistema de Colores")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text("Colores modernos con soporte para Assets y Dark Mode")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.appBackgroundSecondary)
        )
    }

    // MARK: - Primary Buttons Section

    private var primaryButtonsSection: some View {
        VStack(spacing: 16) {
            Text("Botones Principales")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Botón Primario
            Button(action: {}) {
                HStack {
                    Image(systemName: "star.fill")
                    Text("Botón Primario")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .padding()
                .background(Color.appPrimary)
                .foregroundColor(.white)
                .cornerRadius(12)
            }

            // Botón Secundario
            Button(action: {}) {
                HStack {
                    Image(systemName: "bolt.fill")
                    Text("Botón Secundario")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .padding()
                .background(Color.appSecondary)
                .foregroundColor(.white)
                .cornerRadius(12)
            }

            // Botón Acento
            Button(action: {}) {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Botón Acento")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .padding()
                .background(Color.appAccent)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Cards Section

    private var cardsSection: some View {
        VStack(spacing: 16) {
            Text("Tarjetas")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                colorCard(
                    title: "Primario",
                    icon: "paintbrush.fill",
                    color: .appPrimary
                )

                colorCard(
                    title: "Secundario",
                    icon: "wand.and.stars",
                    color: .appSecondary
                )

                colorCard(
                    title: "Acento",
                    icon: "flame.fill",
                    color: .appAccent
                )

                colorCard(
                    title: "Original",
                    icon: "shield.fill",
                    color: .mundial2026Verde
                )
            }
        }
    }

    // MARK: - Color Palette Section

    private var colorPaletteSection: some View {
        VStack(spacing: 16) {
            Text("Paleta de Colores")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                colorRow(name: "Primario (Violeta)", hex: "#7c3aed", color: .appPrimary)
                colorRow(name: "Secundario (Cyan)", hex: "#06B6D4", color: .appSecondary)
                colorRow(name: "Acento (Teal)", hex: "#14B8A6", color: .appAccent)
                colorRow(name: "Fondo Oscuro", hex: "#0F172A", color: .appBackgroundDark)
                colorRow(name: "Fondo Secundario", hex: "#1E293B", color: .appBackgroundSecondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.appBackgroundSecondary)
            )
        }
    }

    // MARK: - Helper Views

    private func colorCard(title: String, icon: String, color: Color) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundColor(color)

            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.appBackgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(color.opacity(0.3), lineWidth: 2)
                )
        )
    }

    private func colorRow(name: String, hex: String, color: Color) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(color)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text(hex)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        ModernColorDemoView()
            .environmentObject(AccessibilitySettingsManager.shared)
    }
}
