//
//  ConnectionLimitIndicator.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Circular progress indicator for connection limit
//

import SwiftUI

struct ConnectionLimitIndicator: View {
    let current: Int
    let maximum: Int

    private var progress: Double {
        guard maximum > 0 else { return 0 }
        return Double(current) / Double(maximum)
    }

    private var statusColor: Color {
        if current >= maximum {
            return Mundial2026Colors.rojo // Full - Red
        } else if current >= maximum - 1 {
            return Color.orange // Almost full - Orange
        } else {
            return Color.appAccent // Available - Teal
        }
    }

    private var statusText: String {
        if current >= maximum {
            return "Lleno"
        } else if current >= maximum - 1 {
            return "Casi lleno"
        } else {
            return "Disponible"
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Circular progress
            ZStack {
                // Background circle
                Circle()
                    .stroke(statusColor.opacity(0.2), lineWidth: 12)
                    .frame(width: 120, height: 120)

                // Progress circle
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        statusColor,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6, dampingFraction: 0.7), value: progress)

                // Center text
                VStack(spacing: 4) {
                    Text("\(current)")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(statusColor)

                    Text("/ \(maximum)")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }

            // Status text
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(statusText)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(statusColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(statusColor.opacity(0.1))
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connections: \(current) of \(maximum)")
        .accessibilityValue(statusText)
    }
}

// MARK: - Compact Version (for smaller spaces)
struct CompactConnectionLimitIndicator: View {
    let current: Int
    let maximum: Int

    private var progress: Double {
        guard maximum > 0 else { return 0 }
        return Double(current) / Double(maximum)
    }

    private var statusColor: Color {
        if current >= maximum {
            return Mundial2026Colors.rojo
        } else if current >= maximum - 1 {
            return Color.orange
        } else {
            return Color.appAccent
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Mini circular progress
            ZStack {
                Circle()
                    .stroke(statusColor.opacity(0.2), lineWidth: 4)
                    .frame(width: 32, height: 32)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(statusColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 32, height: 32)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6, dampingFraction: 0.7), value: progress)
            }

            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text("Conexiones")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text("\(current)/\(maximum)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(statusColor)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(current) of \(maximum) connections")
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 40) {
        ConnectionLimitIndicator(current: 3, maximum: 5)

        ConnectionLimitIndicator(current: 4, maximum: 5)

        ConnectionLimitIndicator(current: 5, maximum: 5)

        Divider()

        CompactConnectionLimitIndicator(current: 3, maximum: 5)
    }
    .padding()
    .background(Color.appBackgroundDark)
}
