//
//  FirstMessageTracker.swift
//  MeshRed
//
//  Tracks first message restrictions and conversation states
//

import Foundation
import Combine

/// Manages first message restrictions and conversation states
/// - Tracks who has been sent a first message
/// - Tracks which conversations have received replies
/// - Persists state across app sessions
class FirstMessageTracker: ObservableObject {

    // MARK: - Singleton
    static let shared = FirstMessageTracker()

    // MARK: - Published Properties
    @Published private(set) var sentFirstMessages: Set<String> = []
    @Published private(set) var activeConversations: Set<String> = []

    // New properties for request management
    @Published private(set) var pendingRequests: [String: PendingRequest] = [:]  // Incoming requests
    @Published private(set) var rejectedRequests: Set<String> = []
    @Published private(set) var deferredRequests: Set<String> = []

    // MARK: - Private Properties
    private let sentMessagesKey = "MeshRed.FirstMessages.Sent"
    private let activeConversationsKey = "MeshRed.FirstMessages.Active"
    private let pendingRequestsKey = "MeshRed.FirstMessages.PendingRequests"
    private let rejectedRequestsKey = "MeshRed.FirstMessages.Rejected"
    private let deferredRequestsKey = "MeshRed.FirstMessages.Deferred"

    // MARK: - Nested Types

    struct PendingRequest: Codable {
        let fromPeerID: String
        let message: String
        let timestamp: Date

        var isExpired: Bool {
            // Requests expire after 7 days
            return Date().timeIntervalSince(timestamp) > 604800
        }
    }

    // MARK: - Initialization
    private init() {
        loadPersistedState()
    }

    // MARK: - Public Methods

    /// Check if a first message has been sent to a peer
    /// - Parameter peerID: The peer's identifier
    /// - Returns: True if a first message was already sent
    func hasSentFirstMessage(to peerID: String) -> Bool {
        return sentFirstMessages.contains(peerID)
    }

    /// Check if a conversation is active (has received a reply)
    /// - Parameter peerID: The peer's identifier
    /// - Returns: True if the conversation is active
    func isConversationActive(with peerID: String) -> Bool {
        return activeConversations.contains(peerID)
    }

    /// Check if messaging is allowed with a peer
    /// - Parameter peerID: The peer's identifier
    /// - Returns: True if new messages can be sent
    func canSendMessage(to peerID: String) -> Bool {
        // Can send if:
        // 1. Never sent a first message, OR
        // 2. Conversation is active (received a reply)
        return !hasSentFirstMessage(to: peerID) || isConversationActive(with: peerID)
    }

    /// Mark that a first message has been sent to a peer
    /// - Parameter peerID: The peer's identifier
    func markFirstMessageSent(to peerID: String) {
        print("📤 FirstMessageTracker: Marking first message sent to \(peerID)")

        sentFirstMessages.insert(peerID)
        savePersistedState()

        print("   Sent messages list: \(sentFirstMessages)")
    }

    /// Mark that a conversation has become active (received a reply)
    /// - Parameter peerID: The peer's identifier
    func markConversationActive(with peerID: String) {
        print("✅ FirstMessageTracker: Marking conversation active with \(peerID)")

        activeConversations.insert(peerID)
        savePersistedState()

        print("   Active conversations: \(activeConversations)")
    }

    /// Check and update conversation status when a message is received
    /// - Parameters:
    ///   - from: The sender's peer ID
    ///   - localDeviceName: The local device name to check if it's not our own message
    func handleIncomingMessage(from peerID: String, localDeviceName: String) {
        // Don't process our own messages
        guard peerID != localDeviceName else { return }

        // If we had sent a first message to this peer and conversation wasn't active
        if hasSentFirstMessage(to: peerID) && !isConversationActive(with: peerID) {
            print("🎉 FirstMessageTracker: Received reply from \(peerID) - activating conversation!")
            markConversationActive(with: peerID)
        }
    }

    /// Reset tracking for a specific peer (for testing or admin purposes)
    /// - Parameter peerID: The peer's identifier
    func resetTracking(for peerID: String) {
        print("🔄 FirstMessageTracker: Resetting tracking for \(peerID)")

        sentFirstMessages.remove(peerID)
        activeConversations.remove(peerID)
        savePersistedState()
    }

    /// Clear all tracking data
    func clearAllTracking() {
        print("🗑 FirstMessageTracker: Clearing all tracking data")

        sentFirstMessages.removeAll()
        activeConversations.removeAll()
        savePersistedState()
    }

    /// Get status description for a peer
    /// - Parameter peerID: The peer's identifier
    /// - Returns: Human-readable status
    func getStatus(for peerID: String) -> String {
        if isConversationActive(with: peerID) {
            return "Conversación activa"
        } else if hasSentFirstMessage(to: peerID) {
            return "Esperando respuesta"
        } else {
            return "Sin contacto"
        }
    }

    // MARK: - Request Management Methods

    /// Check if there's a pending request from a peer
    func hasPendingRequest(from peerID: String) -> Bool {
        if let request = pendingRequests[peerID] {
            // Clean up expired requests
            if request.isExpired {
                pendingRequests.removeValue(forKey: peerID)
                savePersistedState()
                return false
            }
            return true
        }
        return false
    }

    /// Get the pending request message from a peer
    func getPendingRequest(from peerID: String) -> PendingRequest? {
        return pendingRequests[peerID]
    }

    /// Get total count of pending requests (excluding expired)
    func getPendingRequestsCount() -> Int {
        // Clean up expired requests first
        let validRequests = pendingRequests.filter { !$0.value.isExpired }
        if validRequests.count != pendingRequests.count {
            pendingRequests = validRequests
            savePersistedState()
        }
        return validRequests.count
    }

    /// Check if a peer was rejected
    func isRejected(_ peerID: String) -> Bool {
        return rejectedRequests.contains(peerID)
    }

    /// Check if a request is deferred
    func isDeferred(_ peerID: String) -> Bool {
        return deferredRequests.contains(peerID)
    }

    /// Add an incoming message request (called when receiving first message from someone)
    func addIncomingRequest(from peerID: String, message: String, localDeviceName: String) {
        guard peerID != localDeviceName else { return }

        // Don't add if already rejected
        guard !isRejected(peerID) else {
            print("❌ FirstMessageTracker: Ignoring request from rejected peer \(peerID)")
            return
        }

        // Don't add if conversation is already active
        guard !isConversationActive(with: peerID) else {
            print("ℹ️ FirstMessageTracker: Conversation already active with \(peerID)")
            return
        }

        // Limit to 10 pending requests (anti-spam)
        if pendingRequests.count >= 10 {
            print("⚠️ FirstMessageTracker: Maximum pending requests reached")
            return
        }

        let request = PendingRequest(
            fromPeerID: peerID,
            message: message,
            timestamp: Date()
        )

        pendingRequests[peerID] = request
        print("📨 FirstMessageTracker: Added pending request from \(peerID)")
        savePersistedState()
    }

    /// Accept a message request
    func acceptRequest(from peerID: String) {
        guard let request = pendingRequests[peerID] else {
            print("⚠️ FirstMessageTracker: No pending request from \(peerID)")
            return
        }

        print("✅ FirstMessageTracker: Accepting request from \(peerID)")

        // Remove from pending
        pendingRequests.removeValue(forKey: peerID)

        // Remove from deferred if it was there
        deferredRequests.remove(peerID)

        // Mark conversation as active
        activeConversations.insert(peerID)

        savePersistedState()
    }

    /// Reject a message request
    func rejectRequest(from peerID: String) {
        print("❌ FirstMessageTracker: Rejecting request from \(peerID)")

        // Remove from pending
        pendingRequests.removeValue(forKey: peerID)

        // Remove from deferred if it was there
        deferredRequests.remove(peerID)

        // Add to rejected list
        rejectedRequests.insert(peerID)

        savePersistedState()
    }

    /// Defer a message request (decide later)
    func deferRequest(from peerID: String) {
        guard pendingRequests[peerID] != nil else {
            print("⚠️ FirstMessageTracker: No pending request from \(peerID)")
            return
        }

        print("🟡 FirstMessageTracker: Deferring request from \(peerID)")

        // Add to deferred list (keeps in pending too)
        deferredRequests.insert(peerID)

        savePersistedState()
    }

    // MARK: - Private Methods

    private func loadPersistedState() {
        // Load sent messages
        if let sentData = UserDefaults.standard.array(forKey: sentMessagesKey) as? [String] {
            sentFirstMessages = Set(sentData)
            print("📱 FirstMessageTracker: Loaded \(sentFirstMessages.count) sent messages")
        }

        // Load active conversations
        if let activeData = UserDefaults.standard.array(forKey: activeConversationsKey) as? [String] {
            activeConversations = Set(activeData)
            print("📱 FirstMessageTracker: Loaded \(activeConversations.count) active conversations")
        }

        // Load pending requests
        if let pendingData = UserDefaults.standard.data(forKey: pendingRequestsKey),
           let decoded = try? JSONDecoder().decode([String: PendingRequest].self, from: pendingData) {
            // Filter out expired requests
            pendingRequests = decoded.filter { !$0.value.isExpired }
            print("📱 FirstMessageTracker: Loaded \(pendingRequests.count) pending requests")
        }

        // Load rejected requests
        if let rejectedData = UserDefaults.standard.array(forKey: rejectedRequestsKey) as? [String] {
            rejectedRequests = Set(rejectedData)
            print("📱 FirstMessageTracker: Loaded \(rejectedRequests.count) rejected requests")
        }

        // Load deferred requests
        if let deferredData = UserDefaults.standard.array(forKey: deferredRequestsKey) as? [String] {
            deferredRequests = Set(deferredData)
            print("📱 FirstMessageTracker: Loaded \(deferredRequests.count) deferred requests")
        }
    }

    private func savePersistedState() {
        // Save sent messages
        UserDefaults.standard.set(Array(sentFirstMessages), forKey: sentMessagesKey)

        // Save active conversations
        UserDefaults.standard.set(Array(activeConversations), forKey: activeConversationsKey)

        // Save pending requests
        if let pendingData = try? JSONEncoder().encode(pendingRequests) {
            UserDefaults.standard.set(pendingData, forKey: pendingRequestsKey)
        }

        // Save rejected requests
        UserDefaults.standard.set(Array(rejectedRequests), forKey: rejectedRequestsKey)

        // Save deferred requests
        UserDefaults.standard.set(Array(deferredRequests), forKey: deferredRequestsKey)

        print("💾 FirstMessageTracker: State saved to UserDefaults")
    }
}

// MARK: - Debug Extension
#if DEBUG
extension FirstMessageTracker {
    /// Print current state for debugging
    func printDebugState() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📊 FirstMessageTracker Debug State")
        print("   Sent first messages: \(sentFirstMessages)")
        print("   Active conversations: \(activeConversations)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}
#endif