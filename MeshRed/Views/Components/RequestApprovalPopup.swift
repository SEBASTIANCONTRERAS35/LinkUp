//
//  RequestApprovalPopup.swift
//  MeshRed
//
//  Popup view for approving or rejecting incoming message requests
//

import SwiftUI

struct RequestApprovalPopup: View {
    // MARK: - Properties
    let request: FirstMessageTracker.PendingRequest
    let onAccept: () -> Void
    let onReject: () -> Void
    let onDefer: () -> Void
    let onClose: () -> Void

    @State private var showConfirmReject = false
    @State private var animateIn = false

    // MARK: - Body
    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onClose()
                }
                .opacity(animateIn ? 1 : 0)

            // Popup card
            VStack(spacing: 0) {
                // Header with icon
                headerView

                // Message content
                messageContentView

                // Time info
                timeInfoView

                // Action buttons
                actionButtonsView
            }
            .background(Color.white)
            .cornerRadius(24)
            .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 24)
            .scaleEffect(animateIn ? 1.0 : 0.9)
            .opacity(animateIn ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                animateIn = true
            }
        }
        .alert("¿Rechazar solicitud?", isPresented: $showConfirmReject) {
            Button("Cancelar", role: .cancel) {}
            Button("Rechazar", role: .destructive) {
                withAnimation(.easeOut(duration: 0.3)) {
                    animateIn = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onReject()
                }
            }
        } message: {
            Text("No podrás recibir más mensajes de \(request.fromPeerID). Esta acción no se puede deshacer.")
        }
    }

    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 12) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(Mundial2026Colors.azul.opacity(0.1))
                    .frame(width: 64, height: 64)

                Image(systemName: "envelope.badge")
                    .font(.title)
                    .foregroundColor(Mundial2026Colors.azul)
                    .symbolEffect(.bounce, value: animateIn)
            }
            .padding(.top, 24)

            // Title
            VStack(spacing: 4) {
                Text("Nueva solicitud de mensaje")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text("de \(request.fromPeerID)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(Mundial2026Colors.azul)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Message Content View
    private var messageContentView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Mensaje:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
            }

            // Message bubble
            Text(request.message)
                .font(.body)
                .foregroundColor(.primary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.08))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Time Info View
    private var timeInfoView: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text(timeAgoText)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            if daysUntilExpiration < 3 {
                Label("\(daysUntilExpiration) días para responder", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Action Buttons View
    private var actionButtonsView: some View {
        VStack(spacing: 12) {
            // Primary actions
            HStack(spacing: 12) {
                // Reject button
                Button(action: {
                    showConfirmReject = true
                    HapticManager.shared.play(.warning, priority: .ui)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.callout)
                        Text("Rechazar")
                            .fontWeight(.medium)
                    }
                    .font(.body)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)

                // Accept button
                Button(action: {
                    HapticManager.shared.play(.success, priority: .ui)
                    withAnimation(.easeOut(duration: 0.3)) {
                        animateIn = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onAccept()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.callout)
                        Text("Aceptar")
                            .fontWeight(.semibold)
                    }
                    .font(.body)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Mundial2026Colors.verde)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }

            // Secondary action
            Button(action: {
                HapticManager.shared.play(.light, priority: .ui)
                withAnimation(.easeOut(duration: 0.3)) {
                    animateIn = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onDefer()
                }
            }) {
                Text("Decidir después")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    // MARK: - Computed Properties

    private var timeAgoText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: request.timestamp, relativeTo: Date())
    }

    private var daysUntilExpiration: Int {
        let remainingTime = 604800 - Date().timeIntervalSince(request.timestamp) // 7 days in seconds
        return max(0, Int(remainingTime / 86400)) // Convert to days
    }
}

// MARK: - Request List View
/// Shows all pending requests in a list format
struct PendingRequestsListView: View {
    @StateObject private var tracker = FirstMessageTracker.shared
    let onSelectRequest: (FirstMessageTracker.PendingRequest) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if tracker.pendingRequests.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "tray")
                            .font(.system(size: 60))
                            .foregroundColor(.gray.opacity(0.5))

                        Text("No hay solicitudes pendientes")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("Las solicitudes de mensaje aparecerán aquí")
                            .font(.subheadline)
                            .foregroundColor(.secondary.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    // Request list
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(tracker.pendingRequests.values), id: \.fromPeerID) { request in
                                RequestRowView(
                                    request: request,
                                    isDeferred: tracker.isDeferred(request.fromPeerID),
                                    onTap: {
                                        onSelectRequest(request)
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Solicitudes de Mensaje")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") {
                        onDismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Request Row View
struct RequestRowView: View {
    let request: FirstMessageTracker.PendingRequest
    let isDeferred: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Status icon
                ZStack {
                    Circle()
                        .fill(isDeferred ? Color.yellow.opacity(0.2) : Mundial2026Colors.azul.opacity(0.1))
                        .frame(width: 44, height: 44)

                    Image(systemName: isDeferred ? "clock.fill" : "envelope.badge")
                        .font(.title3)
                        .foregroundColor(isDeferred ? .orange : Mundial2026Colors.azul)
                }

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(request.fromPeerID)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)

                        if isDeferred {
                            Text("Pospuesto")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }

                    Text(request.message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Text(timeAgoText)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.6))
                }

                Spacer()

                // Arrow
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(12)
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var timeAgoText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: request.timestamp, relativeTo: Date())
    }
}

// MARK: - Preview
#if DEBUG
struct RequestApprovalPopup_Previews: PreviewProvider {
    static let sampleRequest = FirstMessageTracker.PendingRequest(
        fromPeerID: "María García",
        message: "Hola! Vi que estás en la sección 4B. ¿Podríamos coordinar para el partido?",
        timestamp: Date().addingTimeInterval(-3600) // 1 hour ago
    )

    static var previews: some View {
        RequestApprovalPopup(
            request: sampleRequest,
            onAccept: { print("Accepted") },
            onReject: { print("Rejected") },
            onDefer: { print("Deferred") },
            onClose: { print("Closed") }
        )
        .previewDevice("iPhone 15")

        PendingRequestsListView(
            onSelectRequest: { _ in },
            onDismiss: {}
        )
        .previewDevice("iPhone 15")
    }
}
#endif