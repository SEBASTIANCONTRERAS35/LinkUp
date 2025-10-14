//
//  NetworkConfigurationWarningBanner.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Warning banner for problematic network configurations
//

import SwiftUI

struct NetworkConfigurationWarningBanner: View {
    let status: NetworkStatus
    let onFix: () -> Void

    var body: some View {
        if status.isProblematic {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundColor(iconColor)
                    .accessibilityLabel("Advertencia de configuración de red")

                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(titleText)
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                        .accessibilityAddTraits(.isHeader)

                    Text(status.suggestion)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                // Fix button
                Button(action: onFix) {
                    Text("Arreglar")
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(actionButtonColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .accessibilityLabel("Abrir ajustes para arreglar configuración de red")
                .accessibilityHint("Abre la app de Ajustes en la sección WiFi")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(backgroundColor)
            .cornerRadius(12)
            .shadow(color: shadowColor, radius: 4, x: 0, y: 2)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Computed Properties

    private var iconName: String {
        switch status.severity {
        case .critical:
            return "wifi.exclamationmark"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .ok:
            return "checkmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch status.severity {
        case .critical:
            return .red
        case .warning:
            return .orange
        case .ok:
            return .green
        }
    }

    private var titleText: String {
        switch status.severity {
        case .critical:
            return "⚠️ Configuración de Red Problemática"
        case .warning:
            return "⚠️ Advertencia de Red"
        case .ok:
            return "✅ Configuración Correcta"
        }
    }

    private var backgroundColor: Color {
        switch status.severity {
        case .critical:
            return Color.red.opacity(0.15)
        case .warning:
            return Color.orange.opacity(0.15)
        case .ok:
            return Color.green.opacity(0.15)
        }
    }

    private var actionButtonColor: Color {
        switch status.severity {
        case .critical:
            return .red
        case .warning:
            return .orange
        case .ok:
            return .green
        }
    }

    private var shadowColor: Color {
        switch status.severity {
        case .critical:
            return Color.red.opacity(0.2)
        case .warning:
            return Color.orange.opacity(0.2)
        case .ok:
            return Color.green.opacity(0.2)
        }
    }
}

// MARK: - Preview

struct NetworkConfigurationWarningBanner_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            NetworkConfigurationWarningBanner(
                status: .wifiEnabledButNotConnected,
                onFix: {
                    print("Fix tapped")
                }
            )

            NetworkConfigurationWarningBanner(
                status: .noNetworkAtAll,
                onFix: {
                    print("Fix tapped")
                }
            )

            NetworkConfigurationWarningBanner(
                status: .wifiConnected,
                onFix: {
                    print("Fix tapped")
                }
            )
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}
