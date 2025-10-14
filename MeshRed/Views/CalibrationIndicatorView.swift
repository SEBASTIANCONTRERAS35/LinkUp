//
//  CalibrationIndicatorView.swift
//  MeshRed
//
//  Visual indicator for LinkFinder direction calibration status
//  Shows real-time instructions for ARKit convergence
//

import SwiftUI

/// Overlay view showing calibration instructions and progress
struct CalibrationIndicatorView: View {
    @ObservedObject var uwbManager: LinkFinderSessionManager
    let targetName: String

    @State private var animationProgress: CGFloat = 0
    @State private var isAnimating = false

    var body: some View {
        if uwbManager.isConverging && !uwbManager.convergenceReasons.isEmpty {
            VStack(spacing: 20) {
                // Calibration animation
                ZStack {
                    // Background circle
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 4)
                        .frame(width: 100, height: 100)

                    // Animated progress circle
                    Circle()
                        .trim(from: 0, to: animationProgress)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.cyan, Color.blue]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .animation(
                            Animation.linear(duration: 1.5)
                                .repeatForever(autoreverses: false),
                            value: isAnimating
                        )

                    // Phone icon
                    Image(systemName: "iphone.gen2")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(isAnimating ? 360 : 0))
                        .animation(
                            Animation.linear(duration: 3)
                                .repeatForever(autoreverses: false),
                            value: isAnimating
                        )
                }

                // Title
                Text("Calibrando LinkFinder")
                    .font(.headline)
                    .foregroundColor(.white)

                // Instructions
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(uwbManager.convergenceReasons, id: \.self) { reason in
                        HStack(spacing: 10) {
                            Image(systemName: instructionIcon(for: reason))
                                .font(.system(size: 20))
                                .foregroundColor(.cyan)
                                .frame(width: 30)

                            Text(reason)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.leading)

                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
                        )
                )

                // Figure 8 motion indicator
                if uwbManager.convergenceReasons.contains(where: { $0.contains("figura de 8") }) {
                    Figure8MotionIndicator()
                        .frame(height: 80)
                        .padding(.horizontal)
                }

                // Status text
                Text("Navegando hacia \(targetName)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.85))
                    .shadow(color: .cyan.opacity(0.3), radius: 10)
            )
            .padding()
            .transition(.opacity.combined(with: .scale))
            .onAppear {
                withAnimation {
                    isAnimating = true
                    animationProgress = 1
                }
            }
        }
    }

    /// Get appropriate icon for instruction
    private func instructionIcon(for reason: String) -> String {
        if reason.contains("figura de 8") || reason.contains("Mueve") {
            return "arrow.triangle.2.circlepath"
        } else if reason.contains("horizontalmente") {
            return "arrow.left.and.right"
        } else if reason.contains("verticalmente") {
            return "arrow.up.and.down"
        } else if reason.contains("iluminación") {
            return "light.max"
        } else {
            return "hand.draw"
        }
    }
}

/// Figure 8 motion path animation
struct Figure8MotionIndicator: View {
    @State private var progress: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Figure 8 path
                Figure8Path()
                    .stroke(Color.white.opacity(0.2), lineWidth: 2)

                // Animated dot
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 12, height: 12)
                    .shadow(color: .cyan, radius: 5)
                    .position(
                        x: figure8Position(progress: progress, size: geometry.size).x,
                        y: figure8Position(progress: progress, size: geometry.size).y
                    )
                    .animation(
                        Animation.linear(duration: 3)
                            .repeatForever(autoreverses: false),
                        value: progress
                    )
            }
        }
        .onAppear {
            progress = 1
        }
    }

    /// Calculate position along figure 8 path
    private func figure8Position(progress: CGFloat, size: CGSize) -> CGPoint {
        let t = progress * 2 * .pi
        let scale = min(size.width, size.height) * 0.35

        // Parametric equations for figure 8
        let x = sin(t) * scale + size.width / 2
        let y = sin(2 * t) * scale * 0.5 + size.height / 2

        return CGPoint(x: x, y: y)
    }
}

/// Figure 8 path shape
struct Figure8Path: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let scale = min(rect.width, rect.height) * 0.35

        // Draw figure 8 using parametric equations
        for i in 0...360 {
            let t = Double(i) * .pi / 180.0
            let x = sin(t) * scale + center.x
            let y = sin(2 * t) * scale * 0.5 + center.y

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        path.closeSubpath()
        return path
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.black
            .ignoresSafeArea()

        CalibrationIndicatorView(
            uwbManager: {
                let manager = LinkFinderSessionManager()
                manager.isConverging = true
                manager.convergenceReasons = [
                    "Mueve tu iPhone en figura de 8",
                    "Mueve horizontalmente (izquierda-derecha)",
                    "Busca un área con mejor iluminación"
                ]
                return manager
            }(),
            targetName: "José Guadalupe"
        )
    }
}