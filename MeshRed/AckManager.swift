import Foundation
import os

struct PendingMessage {
    var message: NetworkMessage
    let sendTime: Date
    var retryCount: Int

    init(message: NetworkMessage) {
        self.message = message
        self.sendTime = Date()
        self.retryCount = 0
    }
}

protocol AckManagerDelegate: AnyObject {
    func ackManager(_ manager: AckManager, shouldResendMessage message: NetworkMessage)
    func ackManager(_ manager: AckManager, didReceiveAckFor messageId: UUID)
    func ackManager(_ manager: AckManager, didFailToReceiveAckFor messageId: UUID)
}

class AckManager {
    weak var delegate: AckManagerDelegate?

    private var pendingAcks: [UUID: PendingMessage] = [:]
    private let maxRetries = 3
    private let baseAckTimeout: TimeInterval = 5.0  // Base timeout for direct connections
    private let checkInterval: TimeInterval = 3.0
    private let queue = DispatchQueue(label: "com.meshred.ackmanager", attributes: .concurrent)
    private var retryTimer: Timer?

    // Calculate adaptive timeout based on message TTL (potential hop count)
    private func getAckTimeout(for message: NetworkMessage) -> TimeInterval {
        // Base timeout + 1.5 seconds per possible hop
        // TTL of 1 = direct connection = 5s timeout
        // TTL of 3 = up to 3 hops = 5s + (2 * 1.5s) = 8s timeout
        // TTL of 5 = up to 5 hops = 5s + (4 * 1.5s) = 11s timeout
        let hopPenalty = Double(max(0, message.ttl - 1)) * 1.5
        return baseAckTimeout + hopPenalty
    }

    init() {
        startRetryTimer()
    }

    deinit {
        retryTimer?.invalidate()
    }

    func trackMessage(_ message: NetworkMessage) {
        guard message.requiresAck else { return }

        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            self.pendingAcks[message.id] = PendingMessage(message: message)
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("⏳ TRACKING ACK REQUEST")
            print("   Message ID: \(message.id.uuidString.prefix(8))")
            print("   Type: \(message.messageType.displayName)")
            print("   To: \(message.recipientId)")
            print("   Pending ACKs Count: \(self.pendingAcks.count)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        }
    }

    func handleAck(_ ackMessage: AckMessage) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            if var pending = self.pendingAcks[ackMessage.originalMessageId] {
                pending.message.markAcknowledged()
                self.pendingAcks.removeValue(forKey: ackMessage.originalMessageId)

                print("✅ ACK recibido para mensaje: \(ackMessage.originalMessageId) de \(ackMessage.ackSenderId)")

                DispatchQueue.main.async {
                    self.delegate?.ackManager(self, didReceiveAckFor: ackMessage.originalMessageId)
                }
            } else {
                print("⚠️ ACK recibido para mensaje no rastreado: \(ackMessage.originalMessageId)")
            }
        }
    }

    func isWaitingForAck(_ messageId: UUID) -> Bool {
        queue.sync {
            return pendingAcks[messageId] != nil
        }
    }

    private func startRetryTimer() {
        retryTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkPendingAcks()
        }
    }

    private func checkPendingAcks() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let now = Date()
            var messagesToRetry: [NetworkMessage] = []
            var messagesToRemove: [UUID] = []

            for (messageId, pending) in self.pendingAcks {
                let timeSinceSend = now.timeIntervalSince(pending.sendTime)
                let adaptiveTimeout = self.getAckTimeout(for: pending.message)

                if timeSinceSend > adaptiveTimeout {
                    if pending.retryCount < self.maxRetries {
                        var updatedPending = pending
                        updatedPending.retryCount += 1
                        updatedPending.message.ttl = max(5, updatedPending.message.ttl)
                        self.pendingAcks[messageId] = PendingMessage(message: updatedPending.message)

                        messagesToRetry.append(updatedPending.message)

                        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        print("🔄 ACK TIMEOUT - RETRYING")
                        print("   Message ID: \(messageId.uuidString.prefix(8))")
                        print("   Retry #\(updatedPending.retryCount) of \(self.maxRetries)")
                        print("   Time since send: \(String(format: "%.1f", timeSinceSend))s")
                        print("   Timeout threshold: \(String(format: "%.1f", adaptiveTimeout))s (TTL: \(pending.message.ttl))")
                        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    } else {
                        messagesToRemove.append(messageId)
                        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        print("❌ ACK FAILED - MESSAGE EXPIRED")
                        print("   Message ID: \(messageId.uuidString.prefix(8))")
                        print("   After \(self.maxRetries) retries")
                        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    }
                }
            }

            for messageId in messagesToRemove {
                self.pendingAcks.removeValue(forKey: messageId)
                DispatchQueue.main.async {
                    self.delegate?.ackManager(self, didFailToReceiveAckFor: messageId)
                }
            }

            DispatchQueue.main.async {
                for message in messagesToRetry {
                    self.delegate?.ackManager(self, shouldResendMessage: message)
                }
            }
        }
    }

    func getPendingAcksCount() -> Int {
        queue.sync {
            return pendingAcks.count
        }
    }

    func getPendingAcksStatus() -> [(messageId: UUID, type: MessageType, retryCount: Int, timePending: TimeInterval)] {
        queue.sync {
            let now = Date()
            return pendingAcks.map { (key, value) in
                (
                    messageId: key,
                    type: value.message.messageType,
                    retryCount: value.retryCount,
                    timePending: now.timeIntervalSince(value.sendTime)
                )
            }.sorted { $0.timePending > $1.timePending }
        }
    }

    func cancelPendingAck(_ messageId: UUID) {
        queue.async(flags: .barrier) { [weak self] in
            if self?.pendingAcks.removeValue(forKey: messageId) != nil {
                print("🚫 ACK cancelado para mensaje: \(messageId)")
            }
        }
    }

    func clear() {
        queue.async(flags: .barrier) { [weak self] in
            self?.pendingAcks.removeAll()
            print("🗑️ Todos los ACKs pendientes han sido limpiados")
        }
    }
}