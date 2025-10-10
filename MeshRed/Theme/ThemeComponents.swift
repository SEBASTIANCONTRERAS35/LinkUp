//
//  ThemeComponents.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Reusable Accessible Components Library
//
//  ACCESSIBILITY PRINCIPLES IMPLEMENTED:
//  1. All interactive elements ≥ 44x44pt (Apple HIG minimum)
//  2. Full VoiceOver support with labels + hints
//  3. Dynamic Type support (scales with user preferences)
//  4. High contrast mode support
//  5. Reduce Motion support
//  6. Haptic feedback for important actions
//  7. Semantic grouping for logical navigation
//

import SwiftUI

// MARK: - Accessible Action Button
/// Large, tappable button with full accessibility support
struct AccessibleActionButton: View {
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme

    let title: String
    let icon: String
    let backgroundColor: Color
    let foregroundColor: Color
    let action: () -> Void

    // Accessibility properties
    var accessibilityLabel: String
    var accessibilityHint: String
    var isEmergency: Bool = false

    var body: some View {
        Button(action: {
            // Haptic feedback using centralized HapticManager
            if isEmergency {
                HapticManager.shared.play(.warning, priority: .emergency)
            } else {
                HapticManager.shared.play(.light, priority: .ui)
            }
            action()
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2) // Scales with Dynamic Type
                    .foregroundColor(foregroundColor)

                Text(title)
                    .font(.body) // Dynamic Type enabled
                    .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold)
                    .foregroundColor(foregroundColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: 60 * accessibilitySettings.buttonSizeMultiplier // ✅ Adapts to size multiplier
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(backgroundColor)
            .cornerRadius(16)
            .accessibleShadow(color: backgroundColor, radius: 8) // ✅ Adaptive shadow
        }
        .scaleEffect(accessibilitySettings.buttonSizeMultiplier) // ✅ Scale entire button
        .animation(.easeInOut(duration: 0.2), value: accessibilitySettings.buttonSizeMultiplier)
        .buttonStyle(.plain)
        // ACCESSIBILITY: VoiceOver label and hint
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
        // ACCESSIBILITY: Increase importance for emergency buttons
        .accessibilityAddTraits(isEmergency ? .isHeader : [])
    }
}

// MARK: - Accessible Quick Action Card
/// Card-style button for quick actions grid
struct AccessibleQuickActionCard: View {
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme

    let title: String
    let icon: String
    let iconColor: Color
    let backgroundColor: Color
    let action: () -> Void

    // Accessibility
    var accessibilityLabel: String
    var accessibilityHint: String

    var body: some View {
        Button(action: {
            // Haptic feedback using centralized HapticManager
            HapticManager.shared.play(.medium, priority: .ui)
            action()
        }) {
            VStack(spacing: 12) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 36 * accessibilitySettings.buttonSizeMultiplier)) // ✅ Adaptive icon size
                    .foregroundColor(iconColor)
                    .frame(height: 44) // Ensure visual balance

                // Title
                Text(title)
                    .font(.callout) // Dynamic Type
                    .fontWeight(accessibilitySettings.preferBoldText ? .bold : .semibold) // ✅ Adaptive bold
                    .foregroundColor(accessibleTheme.textPrimary) // ✅ Uses accessible theme
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: 120 * accessibilitySettings.buttonSizeMultiplier // ✅ Adaptive height
            )
            .padding(16)
            .accessibleBackground(backgroundColor, opacity: 1.0) // ✅ Respects reduceTransparency
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        Color.primary.opacity(accessibilitySettings.enableHighContrast ? 0.15 : 0.05),
                        lineWidth: accessibilitySettings.enableHighContrast ? 2 : 1 // ✅ Stronger border for high contrast
                    )
            )
        }
        .scaleEffect(accessibilitySettings.buttonSizeMultiplier) // ✅ Scale entire card
        .animation(.easeInOut(duration: 0.2), value: accessibilitySettings.buttonSizeMultiplier)
        .buttonStyle(.plain)
        // ACCESSIBILITY: VoiceOver support
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Accessible Status Badge
/// Shows network/connection status with icon + text
struct AccessibleStatusBadge: View {
    let statusText: String
    let statusColor: Color
    let icon: String
    var isAnimated: Bool = false

    // Accessibility
    var accessibilityLabel: String

    var body: some View {
        HStack(spacing: 8) {
            // Pulsing indicator for active states
            if isAnimated {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
                    .modifier(PulsingAnimation())
            } else {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
            }

            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(statusColor)

            Text(statusText)
                .font(.caption) // Dynamic Type
                .fontWeight(.semibold)
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.15))
        .cornerRadius(12)
        // ACCESSIBILITY: Group as single element, announce combined status
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Accessible Peer Row
/// Shows connected peer with distance and actions
struct AccessiblePeerRow: View {
    let peerName: String
    let distance: String?
    let signalStrength: String // "excellent", "good", "poor"
    let onLocate: () -> Void
    let onMessage: () -> Void
    var conversationState: ConversationState = .noContact

    enum ConversationState {
        case noContact           // No se ha enviado mensaje
        case waitingResponse     // Esperando respuesta del primer mensaje
        case active             // Conversación activa (puede chatear libremente)
        case pendingIncoming    // Tiene solicitud pendiente (para recibir)
        case rejected           // Solicitud rechazada
        case deferred          // Solicitud pospuesta
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator with conversation state
            ZStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)

                // Overlay icon for conversation state
                if conversationState == .active {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(Mundial2026Colors.verde)
                        .offset(x: 6, y: -6)
                } else if conversationState == .waitingResponse {
                    Image(systemName: "clock.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .offset(x: 6, y: -6)
                } else if conversationState == .pendingIncoming {
                    // Pulsing red badge for incoming request
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Text("!")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .offset(x: 8, y: -8)
                        .modifier(PulsingAnimation())
                } else if conversationState == .deferred {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                        .offset(x: 6, y: -6)
                } else if conversationState == .rejected {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .offset(x: 6, y: -6)
                }
            }
            .frame(width: 16, height: 16)
            // ACCESSIBILITY: Decorative, not announced separately
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(peerName)
                        .font(.body) // Dynamic Type
                        .fontWeight(.semibold)
                        .foregroundColor(ThemeColors.textPrimary)

                    // Conversation state badge
                    if conversationState != .noContact {
                        Text(stateText)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(stateTextColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(stateTextColor.opacity(0.15))
                            .cornerRadius(6)
                    }
                }

                if let distance = distance {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.caption2)
                        Text(distance)
                            .font(.caption) // Dynamic Type
                    }
                    .foregroundColor(ThemeColors.textSecondary)
                }
            }

            Spacer(minLength: 12)

            // Action buttons
            HStack(spacing: 8) {
                // Locate button
                Button(action: {
                    #if os(iOS)
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    #endif
                    onLocate()
                }) {
                    Image(systemName: "location.circle.fill")
                        .font(.title3)
                        .foregroundColor(ThemeColors.primaryBlue)
                        .frame(width: 44, height: 44) // Minimum touch target
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Locate \(peerName)")
                .accessibilityHint("Double tap to see precise location using Ultra Wideband")

                // Message button with state-based appearance
                Button(action: {
                    // Different behaviors based on state
                    switch conversationState {
                    case .noContact, .active, .pendingIncoming, .deferred:
                        // Allow interaction
                        #if os(iOS)
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        #endif
                        onMessage()
                    case .waitingResponse, .rejected:
                        // Feedback for disabled state
                        #if os(iOS)
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.error)
                        #endif
                    }
                }) {
                    ZStack {
                        Image(systemName: messageIconName)
                            .font(.title3)
                            .foregroundColor(messageButtonColor)
                            .frame(width: 44, height: 44) // Minimum touch target

                        // Badge for active conversation
                        if conversationState == .active {
                            Circle()
                                .fill(Mundial2026Colors.verde)
                                .frame(width: 8, height: 8)
                                .offset(x: 12, y: -12)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(conversationState == .waitingResponse || conversationState == .rejected)
                .opacity(conversationState == .waitingResponse || conversationState == .rejected ? 0.5 : 1.0)
                .accessibilityLabel(messageAccessibilityLabel)
                .accessibilityHint(messageAccessibilityHint)
            }
        }
        .padding(16)
        .background(backgroundColorForState)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(borderColorForState, lineWidth: conversationState == .active ? 1.5 : 0)
        )
        // ACCESSIBILITY: Announce peer info as group
        .accessibilityElement(children: .contain)
    }

    // MARK: - Computed Properties

    private var statusColor: Color {
        switch conversationState {
        case .noContact:
            return ThemeColors.connected
        case .waitingResponse:
            return .orange
        case .active:
            return Mundial2026Colors.verde
        case .pendingIncoming:
            return .red
        case .deferred:
            return .yellow
        case .rejected:
            return .gray
        }
    }

    private var stateText: String {
        switch conversationState {
        case .noContact:
            return ""
        case .waitingResponse:
            return "Esperando"
        case .active:
            return "Activo"
        case .pendingIncoming:
            return "Solicitud"
        case .deferred:
            return "Pospuesto"
        case .rejected:
            return "Rechazado"
        }
    }

    private var stateTextColor: Color {
        switch conversationState {
        case .noContact:
            return .clear
        case .waitingResponse:
            return .orange
        case .active:
            return Mundial2026Colors.verde
        case .pendingIncoming:
            return .red
        case .deferred:
            return .yellow
        case .rejected:
            return .gray
        }
    }

    private var messageIconName: String {
        switch conversationState {
        case .noContact:
            return "message"
        case .waitingResponse:
            return "clock.badge.exclamationmark"
        case .active:
            return "message.fill"
        case .pendingIncoming:
            return "envelope.badge.fill"
        case .deferred:
            return "questionmark.bubble"
        case .rejected:
            return "nosign"
        }
    }

    private var messageButtonColor: Color {
        switch conversationState {
        case .noContact:
            return ThemeColors.primaryBlue
        case .waitingResponse, .rejected:
            return .gray
        case .active:
            return Mundial2026Colors.verde
        case .pendingIncoming:
            return .red
        case .deferred:
            return .yellow
        }
    }

    private var backgroundColorForState: Color {
        switch conversationState {
        case .active:
            return Mundial2026Colors.verde.opacity(0.05)
        case .pendingIncoming:
            return Color.red.opacity(0.05)
        case .rejected:
            return Color.gray.opacity(0.05)
        default:
            return ThemeColors.rowBackground
        }
    }

    private var borderColorForState: Color {
        switch conversationState {
        case .active:
            return Mundial2026Colors.verde.opacity(0.3)
        case .pendingIncoming:
            return Color.red.opacity(0.3)
        default:
            return .clear
        }
    }

    private var messageAccessibilityLabel: String {
        switch conversationState {
        case .noContact:
            return "Send first message to \(peerName)"
        case .waitingResponse:
            return "Waiting for response from \(peerName)"
        case .active:
            return "Chat with \(peerName)"
        case .pendingIncoming:
            return "Message request from \(peerName)"
        case .deferred:
            return "Deferred request from \(peerName)"
        case .rejected:
            return "Rejected request from \(peerName)"
        }
    }

    private var messageAccessibilityHint: String {
        switch conversationState {
        case .noContact:
            return "Double tap to send your first message. You can only send one message until they respond."
        case .waitingResponse:
            return "Cannot send more messages until \(peerName) responds"
        case .active:
            return "Double tap to open chat"
        case .pendingIncoming:
            return "Double tap to view and respond to message request"
        case .deferred:
            return "Double tap to view deferred message request"
        case .rejected:
            return "Request was rejected. No further messages allowed"
        }
    }
}

// MARK: - Accessible Stats Card
/// Shows key metric with icon
struct AccessibleStatsCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)

                Text(title.uppercased())
                    .font(.caption2) // Dynamic Type
                    .fontWeight(.semibold)
                    .foregroundColor(ThemeColors.textSecondary)
            }

            Text(value)
                .font(.title2) // Dynamic Type
                .fontWeight(.bold)
                .foregroundColor(ThemeColors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(ThemeColors.cardBackground)
        .cornerRadius(12)
        // ACCESSIBILITY: Announce as single stat
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

// MARK: - Accessible Network Status Header
/// Large status card showing LinkMesh network status
struct AccessibleNetworkStatusHeader: View {
    let deviceName: String
    let connectedPeers: Int
    let statusText: String
    let statusColor: Color
    let connectionQuality: String // "Excellent", "Good", "Poor"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Device name and status
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 12, height: 12)
                            .modifier(PulsingAnimation())
                            .accessibilityHidden(true) // Decorative

                        Text(deviceName)
                            .font(.headline) // Dynamic Type
                            .foregroundColor(.white)
                    }

                    Text(statusText)
                        .font(.subheadline) // Dynamic Type
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.9))
                }

                Spacer()

                // Connection quality badge
                HStack(spacing: 8) {
                    Text(connectionQualityEmoji)
                        .font(.title3)
                        .accessibilityHidden(true) // Decorative

                    Text(connectionQuality)
                        .font(.caption) // Dynamic Type
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.2))
                .cornerRadius(12)
            }

            Divider()
                .overlay(Color.white.opacity(0.2))

            // Key metrics
            HStack(spacing: 16) {
                NetworkMetric(
                    title: "Conectados",
                    value: "\(connectedPeers)",
                    icon: "link"
                )

                NetworkMetric(
                    title: "Señal",
                    value: connectionQuality,
                    icon: "antenna.radiowaves.left.and.right"
                )

                NetworkMetric(
                    title: "Red",
                    value: "Mesh",
                    icon: "network"
                )
            }
        }
        .padding(20)
        .background(ThemeColors.primaryGradient)
        .cornerRadius(24)
        .shadow(color: statusColor.opacity(0.3), radius: 12, x: 0, y: 6)
        // ACCESSIBILITY: Header with complete status
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mesh network status")
        .accessibilityValue("\(statusText), \(connectionQuality) quality, \(connectedPeers) peers connected")
        .accessibilityAddTraits(.isHeader)
    }

    private var connectionQualityEmoji: String {
        switch connectionQuality.lowercased() {
        case "excelente": return "📶"
        case "buena": return "📡"
        default: return "📉"
        }
    }
}

// MARK: - Network Metric Sub-component
private struct NetworkMetric: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.85))

                Text(title.uppercased())
                    .font(.caption2) // Dynamic Type
                    .foregroundColor(.white.opacity(0.7))
            }

            Text(value)
                .font(.title3) // Dynamic Type
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Pulsing Animation Modifier
/// Subtle pulsing for active status indicators (respects reduce motion)
struct PulsingAnimation: ViewModifier {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        if reduceMotion {
            // No animation if reduce motion is enabled
            content
        } else {
            content
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .opacity(isPulsing ? 0.5 : 1.0)
                .animation(
                    Animation.easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: true),
                    value: isPulsing
                )
                .onAppear {
                    isPulsing = true
                }
        }
    }
}

// MARK: - Accessibility Preview Helpers
#if DEBUG
struct ThemeComponents_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 20) {
                AccessibleActionButton(
                    title: "Emergencia SOS",
                    icon: "exclamationmark.triangle.fill",
                    backgroundColor: ThemeColors.emergency,
                    foregroundColor: .white,
                    action: {},
                    accessibilityLabel: "Emergency SOS",
                    accessibilityHint: "Double tap to alert stadium medical staff",
                    isEmergency: true
                )

                AccessibleQuickActionCard(
                    title: "Encontrar Familia",
                    icon: "person.3.fill",
                    iconColor: ThemeColors.primaryBlue,
                    backgroundColor: ThemeColors.cardBackground,
                    action: {},
                    accessibilityLabel: "Find family and friends",
                    accessibilityHint: "Double tap to use Ultra Wideband location"
                )

                AccessibleStatusBadge(
                    statusText: "Conectado",
                    statusColor: ThemeColors.connected,
                    icon: "checkmark.circle.fill",
                    isAnimated: true,
                    accessibilityLabel: "Connected to LinkMesh network"
                )

                AccessibleNetworkStatusHeader(
                    deviceName: "Mi iPhone",
                    connectedPeers: 12,
                    statusText: "Conectado",
                    statusColor: ThemeColors.connected,
                    connectionQuality: "Excelente"
                )

                AccessibleStatsCard(
                    title: "Batería",
                    value: "87%",
                    icon: "battery.75",
                    color: ThemeColors.success
                )
            }
            .padding()
        }
        .background(ThemeColors.background)
    }
}
#endif
