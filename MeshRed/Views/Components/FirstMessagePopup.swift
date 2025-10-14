//
//  FirstMessagePopup.swift
//  MeshRed
//
//  Popup view for sending the first message to a new contact
//

import SwiftUI
import os

struct FirstMessagePopup: View {
    // MARK: - Properties
    let recipientName: String
    let onSend: (String) -> Void
    let onCancel: () -> Void

    @State private var messageText: String = ""
    @State private var showingConfirmation = false
    @FocusState private var isTextFieldFocused: Bool

    private let maxCharacters = 200

    // MARK: - Computed Properties
    private var charactersRemaining: Int {
        maxCharacters - messageText.count
    }

    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        messageText.count <= maxCharacters
    }

    private var characterCountColor: Color {
        if charactersRemaining < 20 {
            return .red
        } else if charactersRemaining < 50 {
            return .orange
        } else {
            return .secondary
        }
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }

            // Popup card
            VStack(spacing: 0) {
                // Header
                headerView

                // Message input
                messageInputView

                // Character counter
                characterCounterView

                // Important notice
                noticeView

                // Action buttons
                actionButtonsView
            }
            .background(Color.white)
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 24)
            .scaleEffect(showingConfirmation ? 0.95 : 1.0)
            .animation(.spring(response: 0.3), value: showingConfirmation)
        }
        .onAppear {
            // Auto-focus the text field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = true
            }
        }
    }

    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 8) {
            // Icon
            ZStack {
                Circle()
                    .fill(Mundial2026Colors.azul.opacity(0.1))
                    .frame(width: 56, height: 56)

                Image(systemName: "message.badge.filled.fill")
                    .font(.title2)
                    .foregroundColor(Mundial2026Colors.azul)
            }
            .padding(.top, 20)

            // Title
            Text("Enviar primer mensaje")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            // Recipient
            Text("Para: \(recipientName)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Message Input View
    private var messageInputView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tu mensaje")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)

            // Text editor with border
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isTextFieldFocused ? Mundial2026Colors.azul : Color.gray.opacity(0.3), lineWidth: 1)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(12)

                TextEditor(text: $messageText)
                    .focused($isTextFieldFocused)
                    .padding(8)
                    .background(Color.clear)
                    .scrollContentBackground(.hidden)
                    .frame(height: 100)
                    .onChange(of: messageText) { oldValue, newValue in
                        // Limit character count
                        if newValue.count > maxCharacters {
                            messageText = String(newValue.prefix(maxCharacters))
                        }
                    }

                // Placeholder
                if messageText.isEmpty {
                    Text("Escribe tu mensaje aquí...")
                        .foregroundColor(.gray)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Character Counter View
    private var characterCounterView: some View {
        HStack {
            Spacer()
            Text("\(messageText.count)/\(maxCharacters)")
                .font(.caption2)
                .foregroundColor(characterCountColor)
                .padding(.horizontal, 20)
                .padding(.top, 4)
        }
    }

    // MARK: - Notice View
    private var noticeView: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.caption)
                .foregroundColor(.orange)

            Text("Solo puedes enviar un mensaje inicial. La conversación se activará si recibes respuesta.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(10)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Action Buttons View
    private var actionButtonsView: some View {
        HStack(spacing: 12) {
            // Cancel button
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    onCancel()
                }
            }) {
                Text("Cancelar")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)

            // Send button
            Button(action: {
                if canSend {
                    showingConfirmation = true

                    // Haptic feedback
                    HapticManager.shared.play(.medium, priority: .ui)

                    // Send message after animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        onSend(messageText.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane.fill")
                        .font(.callout)
                    Text("Enviar")
                        .fontWeight(.semibold)
                }
                .font(.body)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canSend ? Mundial2026Colors.verde : Color.gray.opacity(0.3))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }
}

// MARK: - Alternative Confirmation Style
struct FirstMessageConfirmationPopup: View {
    let recipientName: String
    let messagePreview: String
    let onConfirm: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Success icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(Mundial2026Colors.verde)

            // Title
            Text("¿Enviar mensaje?")
                .font(.title3)
                .fontWeight(.bold)

            // Message preview
            VStack(alignment: .leading, spacing: 8) {
                Text("Tu mensaje a \(recipientName):")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(messagePreview)
                    .font(.body)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
            }
            .padding(.horizontal)

            // Warning
            Label("Recuerda: Solo puedes enviar un mensaje inicial", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.orange)

            // Buttons
            HStack(spacing: 12) {
                Button("Editar", action: onEdit)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)

                Button("Enviar", action: onConfirm)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Mundial2026Colors.verde)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding(24)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(radius: 20)
        .padding(.horizontal, 40)
    }
}

// MARK: - Success Feedback View
struct FirstMessageSentFeedback: View {
    let recipientName: String
    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "paperplane.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(Mundial2026Colors.verde)
                .scaleEffect(isVisible ? 1.0 : 0.5)

            Text("Mensaje enviado")
                .font(.headline)
                .foregroundColor(.white)

            Text("Esperando respuesta de \(recipientName)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(Color.black.opacity(0.85))
        .cornerRadius(16)
        .scaleEffect(isVisible ? 1.0 : 0.8)
        .opacity(isVisible ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                isVisible = true
            }

            // Auto-dismiss after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.3)) {
                    isVisible = false
                }
            }
        }
    }
}

// MARK: - Preview
#if DEBUG
struct FirstMessagePopup_Previews: PreviewProvider {
    static var previews: some View {
        FirstMessagePopup(
            recipientName: "María García",
            onSend: { message in
                LoggingService.network.info("Sending: \(message)")
            },
            onCancel: {
                LoggingService.network.info("Cancelled")
            }
        )
        .previewDevice("iPhone 15")

        FirstMessageConfirmationPopup(
            recipientName: "Carlos López",
            messagePreview: "Hola Carlos, ¿cómo estás? Me gustaría conectar contigo.",
            onConfirm: {},
            onEdit: {}
        )
        .previewLayout(.sizeThatFits)
        .padding()
        .background(Color.gray.opacity(0.2))

        FirstMessageSentFeedback(recipientName: "Ana Martínez")
            .previewLayout(.sizeThatFits)
            .padding()
            .background(Color.gray.opacity(0.2))
    }
}
#endif