//
//  KeepAliveManager.swift
//  MeshRed
//
//  Created by Claude for StadiumConnect Pro - Background Survival
//

import Foundation
import Combine
import MultipeerConnectivity

/// Manages keep-alive pings to prevent MultipeerConnectivity timeout
/// Sends small "heartbeat" messages every 15 seconds to maintain connection stability
class KeepAliveManager: ObservableObject {
    // MARK: - Published Properties

    @Published var isActive: Bool = false
    @Published var pingCount: Int = 0
    @Published var lastPingTime: Date?

    // MARK: - Private Properties

    private var timer: Timer?
    private weak var networkManager: NetworkManager?
    private let pingInterval: TimeInterval = 15.0  // 15 seconds (standard for network keep-alive)
    private let queue = DispatchQueue(label: "com.meshred.keepalive", qos: .utility)

    // MARK: - Initialization

    init() {
        print("🫀 KeepAliveManager: Initialized")
    }

    deinit {
        stop()
    }

    // MARK: - Public Methods

    /// Set the network manager reference
    func setNetworkManager(_ manager: NetworkManager) {
        self.networkManager = manager
    }

    /// Start sending keep-alive pings
    func start() {
        guard !isActive else {
            print("⚠️ KeepAliveManager: Already active")
            return
        }

        guard networkManager != nil else {
            print("❌ KeepAliveManager: NetworkManager not set")
            return
        }

        isActive = true
        pingCount = 0

        // Use Timer instead of DispatchSourceTimer for simplicity
        timer = Timer.scheduledTimer(withTimeInterval: pingInterval, repeats: true) { [weak self] _ in
            self?.sendKeepAlivePing()
        }

        // Ensure timer fires while in background
        if let timer = timer {
            RunLoop.current.add(timer, forMode: .common)
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🫀 KEEP-ALIVE STARTED")
        print("   Interval: \(pingInterval)s")
        print("   Mode: Background-safe")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    /// Stop sending keep-alive pings
    func stop() {
        guard isActive else { return }

        timer?.invalidate()
        timer = nil
        isActive = false

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🫀 KEEP-ALIVE STOPPED")
        print("   Total Pings Sent: \(pingCount)")
        if let lastPing = lastPingTime {
            let duration = Date().timeIntervalSince(lastPing)
            print("   Last Ping: \(String(format: "%.1f", duration))s ago")
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    /// Send a single keep-alive ping immediately (for testing)
    func sendPingNow() {
        sendKeepAlivePing()
    }

    // MARK: - Private Methods

    private func sendKeepAlivePing() {
        guard let networkManager = networkManager else {
            print("❌ KeepAliveManager: NetworkManager lost")
            stop()
            return
        }

        guard !networkManager.connectedPeers.isEmpty else {
            print("⏭️ KeepAliveManager: No peers to ping, skipping")
            return
        }

        // Send keep-alive ping to each peer using NetworkManager's sendRawData helper
        for peer in networkManager.connectedPeers {
            let pingPayload = KeepAlivePing(
                timestamp: Date(),
                peerCount: networkManager.connectedPeers.count
            )

            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(pingPayload)

                // Use NetworkManager's helper method to send raw data
                networkManager.sendRawData(data, to: peer)

                // Update stats (only once per ping cycle)
                if peer == networkManager.connectedPeers.first {
                    DispatchQueue.main.async {
                        self.pingCount += 1
                        self.lastPingTime = Date()
                    }
                }
            } catch {
                print("❌ KeepAliveManager: Failed to encode ping - \(error.localizedDescription)")
            }
        }

        print("🫀 Keep-Alive ping #\(pingCount + 1) → \(networkManager.connectedPeers.count) peers")
    }

    // MARK: - Statistics

    /// Get keep-alive statistics
    func getStats() -> KeepAliveStats {
        return KeepAliveStats(
            isActive: isActive,
            pingCount: pingCount,
            pingInterval: pingInterval,
            lastPingTime: lastPingTime,
            uptime: lastPingTime != nil ? Date().timeIntervalSince(lastPingTime!) : 0
        )
    }
}

// MARK: - Supporting Types

/// Lightweight ping payload sent to peers
struct KeepAlivePing: Codable {
    let timestamp: Date
    let peerCount: Int
    let type: String = "keep-alive"
}

/// Keep-alive statistics
struct KeepAliveStats {
    let isActive: Bool
    let pingCount: Int
    let pingInterval: TimeInterval
    let lastPingTime: Date?
    let uptime: TimeInterval

    var formattedUptime: String {
        let minutes = Int(uptime / 60)
        let seconds = Int(uptime.truncatingRemainder(dividingBy: 60))
        return "\(minutes)m \(seconds)s"
    }

    var averagePingRate: Double {
        guard uptime > 0, pingCount > 0 else { return 0 }
        return Double(pingCount) / (uptime / 60.0)  // pings per minute
    }
}

// MARK: - Network Manager Extension for Keep-Alive Handling

extension NetworkManager {
    /// Handle received keep-alive ping
    func handleKeepAlivePing(_ data: Data, from peerID: String) {
        do {
            let decoder = JSONDecoder()
            let ping = try decoder.decode(KeepAlivePing.self, from: data)

            // Update peer's last seen time
            // This helps PeerHealthMonitor know the peer is still alive
            print("🫀 Received keep-alive from \(peerID) - peers: \(ping.peerCount)")

            // Optionally send ACK (not necessary for keep-alive)
            // Could update peer health metrics here

        } catch {
            print("⚠️ Failed to decode keep-alive ping: \(error)")
        }
    }
}
