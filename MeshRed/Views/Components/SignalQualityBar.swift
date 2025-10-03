//
//  SignalQualityBar.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Animated signal quality indicator bar
//

import SwiftUI

struct SignalQualityBar: View {
    let quality: Float  // 0.0 to 1.0
    let label: String

    @State private var animatedQuality: Float = 0.0
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme

    init(quality: Float, label: String = "Calidad de señal") {
        self.quality = min(max(quality, 0.0), 1.0)  // Clamp between 0 and 1
        self.label = label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 14))
                        .foregroundColor(qualityColor)

                    Text(label)
                        .font(.caption)
                        .foregroundColor(accessibleTheme.textSecondary)
                }

                Spacer()

                Text(qualityText)
                    .font(.caption)
                    .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
                    .foregroundColor(qualityColor)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)

                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: qualityGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * CGFloat(animatedQuality), height: 8)
                        .animation(.easeOut(duration: 0.8), value: animatedQuality)
                }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 8)
        .onAppear {
            // Animate to actual quality
            withAnimation(.easeOut(duration: 0.8)) {
                animatedQuality = quality
            }
        }
        .onChange(of: quality) { oldValue, newValue in
            withAnimation(.easeOut(duration: 0.5)) {
                animatedQuality = newValue
            }
        }
    }

    private var qualityColor: Color {
        if quality >= 0.8 {
            return Mundial2026Colors.verde
        } else if quality >= 0.6 {
            return Mundial2026Colors.azul
        } else if quality >= 0.4 {
            return .orange
        } else {
            return Mundial2026Colors.rojo
        }
    }

    private var qualityGradient: [Color] {
        if quality >= 0.8 {
            return [Mundial2026Colors.verde.opacity(0.7), Mundial2026Colors.verde]
        } else if quality >= 0.6 {
            return [Mundial2026Colors.azul.opacity(0.7), Mundial2026Colors.azul]
        } else if quality >= 0.4 {
            return [.orange.opacity(0.7), .orange]
        } else {
            return [Mundial2026Colors.rojo.opacity(0.7), Mundial2026Colors.rojo]
        }
    }

    private var qualityText: String {
        let percentage = Int(quality * 100)
        if quality >= 0.8 {
            return "Excelente (\(percentage)%)"
        } else if quality >= 0.6 {
            return "Buena (\(percentage)%)"
        } else if quality >= 0.4 {
            return "Regular (\(percentage)%)"
        } else if quality >= 0.2 {
            return "Débil (\(percentage)%)"
        } else {
            return "Muy débil (\(percentage)%)"
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        SignalQualityBar(quality: 0.95)
        SignalQualityBar(quality: 0.75)
        SignalQualityBar(quality: 0.50)
        SignalQualityBar(quality: 0.25)
        SignalQualityBar(quality: 0.10)
    }
    .padding()
    .environmentObject(AccessibilitySettingsManager())
}
