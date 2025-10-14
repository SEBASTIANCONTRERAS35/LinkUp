//
//  NetworkManager+Diagnostics.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Extension: Transport layer diagnostics and connection metrics
//

import Foundation
import MultipeerConnectivity
import os

// MARK: - Transport Diagnostics Extension

extension NetworkManager {

    // MARK: - Connection Metrics

    struct ConnectionMetrics {
        var successfulSends: Int = 0
        var failedSends: Int = 0
        var lastSocketTimeout: Date?
        var connectionEstablished: Date?
        var lastDisconnect: Date?
        var disconnectCount: Int = 0

        var connectionDuration: TimeInterval? {
            guard let established = connectionEstablished else { return nil }
            return Date().timeIntervalSince(established)
        }

        var isUnstable: Bool {
            // Connection is unstable if:
            // 1. Disconnects within 30 seconds of connection
            // 2. More than 3 disconnects
            // 3. High failure rate in sends
            if let established = connectionEstablished,
               let lastDisconnect = lastDisconnect,
               lastDisconnect.timeIntervalSince(established) < 30 {
                return true
            }
            if disconnectCount > 3 {
                return true
            }
            if failedSends > 0 && successfulSends > 0 {
                let failureRate = Double(failedSends) / Double(successfulSends + failedSends)
                return failureRate > 0.3  // More than 30% failure rate
            }
            return false
        }
    }

    enum ConnectionMetricEvent {
        case sendSuccess
        case sendFailure
        case socketTimeout
        case connected
        case disconnected
    }

    // MARK: - Safe Send Helper

    /// Safely send data to peers by validating against actual session state
    /// This prevents "Peers not connected" errors caused by race conditions
    /// between local connectedPeers array and session.connectedPeers
    func safeSend(
        _ data: Data,
        toPeers peers: [MCPeerID],
        with mode: MCSessionSendDataMode,
        context: String = ""
    ) throws {
        // Validate peers against actual session state
        let sessionPeers = session.connectedPeers
        let validPeers = peers.filter { sessionPeers.contains($0) }

        guard !validPeers.isEmpty else {
            let contextStr = context.isEmpty ? "" : " (\(context))"
            LoggingService.network.info("⚠️ safeSend\(contextStr): No valid peers in session")
            LoggingService.network.info("   Requested: \(peers.map { $0.displayName })")
            LoggingService.network.info("   Session has: \(sessionPeers.map { $0.displayName })")
            throw NSError(
                domain: "NetworkManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Peers (\(peers.map { $0.displayName })) not connected"]
            )
        }

        // Log if we filtered out some peers
        if validPeers.count < peers.count {
            let filtered = peers.filter { !validPeers.contains($0) }
            LoggingService.network.info("⚠️ safeSend: Filtered out \(filtered.count) disconnected peers: \(filtered.map { $0.displayName })")
        }

        // Send to validated peers only
        try session.send(data, toPeers: validPeers, with: mode)
    }

    // MARK: - Metrics Recording

    /// Log connection metrics for diagnostics
    func recordConnectionMetrics(peer: MCPeerID, event: ConnectionMetricEvent) {
        let peerKey = peer.displayName

        if connectionMetrics[peerKey] == nil {
            connectionMetrics[peerKey] = ConnectionMetrics()
        }

        switch event {
        case .sendSuccess:
            connectionMetrics[peerKey]?.successfulSends += 1
        case .sendFailure:
            connectionMetrics[peerKey]?.failedSends += 1
        case .socketTimeout:
            connectionMetrics[peerKey]?.lastSocketTimeout = Date()
            connectionMetrics[peerKey]?.disconnectCount += 1
            logTransportDiagnostics(for: peer)
        case .connected:
            connectionMetrics[peerKey]?.connectionEstablished = Date()
        case .disconnected:
            connectionMetrics[peerKey]?.lastDisconnect = Date()
            connectionMetrics[peerKey]?.disconnectCount += 1
        }

        // Log if connection is unstable
        if let metrics = connectionMetrics[peerKey], metrics.isUnstable {
            LoggingService.network.info("⚠️ UNSTABLE CONNECTION DETECTED: \(peer.displayName)")
            logTransportDiagnostics(for: peer)

            // Check for transport failure (very short connection)
            if let connectionEstablished = metrics.connectionEstablished,
               let lastDisconnect = metrics.lastDisconnect {
                let connectionDuration = lastDisconnect.timeIntervalSince(connectionEstablished)

                if connectionDuration < 15.0 {
                    handleTransportFailure(peer: peer, peerKey: peerKey, connectionDuration: connectionDuration)
                }
            }
        }
    }

    // MARK: - Transport Failure Handling

    private func handleTransportFailure(peer: MCPeerID, peerKey: String, connectionDuration: TimeInterval) {
        // This was a transport failure
        transportFailureCount[peerKey] = (transportFailureCount[peerKey] ?? 0) + 1

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🚨 TRANSPORT FAILURE #\(self.transportFailureCount[peerKey] ?? 1) for \(peerKey)")
        LoggingService.network.info("   Connection lasted only \(String(format: "%.1f", connectionDuration))s")

        // Enable Lightning Mode Ultra-Fast for immediate reconnections
        if !UserDefaults.standard.bool(forKey: "lightningModeUltraFast") {
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            LoggingService.network.info("⚡ ENABLING LIGHTNING MODE ULTRA-FAST")
            LoggingService.network.info("   Reason: Transport failure detected")
            LoggingService.network.info("   Action: Zero cooldowns for instant reconnection")
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            UserDefaults.standard.set(true, forKey: "lightningModeUltraFast")
        }

        // Check if we should enable Bluetooth-only mode
        if !isBluetoothOnlyMode &&
           (transportFailureCount[peerKey] ?? 0) >= maxTransportFailuresBeforeFallback {
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            LoggingService.network.info("🔄 ENABLING BLUETOOTH-ONLY MODE")
            LoggingService.network.info("   Reason: \(self.transportFailureCount[peerKey] ?? 0) consecutive transport failures")
            LoggingService.network.info("   Action: Restarting services in Bluetooth-only mode")
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            isBluetoothOnlyMode = true

            // Restart the services to force Bluetooth-only mode
            DispatchQueue.main.async { [weak self] in
                self?.restartServicesInBluetoothMode()
            }
        }
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    // MARK: - Diagnostic Logging

    /// Log detailed transport layer diagnostics when issues are detected
    func logTransportDiagnostics(for peer: MCPeerID) {
        let peerKey = peer.displayName
        guard let metrics = connectionMetrics[peerKey] else { return }

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("📊 TRANSPORT LAYER DIAGNOSTICS")
        LoggingService.network.info("   Peer: \(peer.displayName)")
        LoggingService.network.info("   Successful sends: \(metrics.successfulSends)")
        LoggingService.network.info("   Failed sends: \(metrics.failedSends)")
        LoggingService.network.info("   Disconnect count: \(metrics.disconnectCount)")
        if let duration = metrics.connectionDuration {
            LoggingService.network.info("   Connection duration: \(String(format: "%.1f", duration))s")
        }
        if let lastTimeout = metrics.lastSocketTimeout {
            LoggingService.network.info("   Last socket timeout: \(lastTimeout)")
        }
        LoggingService.network.info("   Is unstable: \(metrics.isUnstable)")
        LoggingService.network.info("   ")
        LoggingService.network.info("🔍 PROBABLE CAUSES:")
        LoggingService.network.info("   ")

        // Diagnose based on metrics
        if let established = metrics.connectionEstablished,
           let lastDisconnect = metrics.lastDisconnect,
           lastDisconnect.timeIntervalSince(established) < 15 {
            LoggingService.network.info("   ❌ VERY SHORT CONNECTION (<15s)")
            LoggingService.network.info("      → WiFi Direct transport likely failing")
            LoggingService.network.info("      → TCP socket timing out after handshake")
            LoggingService.network.info("      → Data channel establishment failing")
        }

        if metrics.lastSocketTimeout != nil {
            LoggingService.network.info("   ❌ SOCKET TIMEOUT DETECTED")
            LoggingService.network.info("      → TCP connection established but data transfer failed")
            LoggingService.network.info("      → Network path switched mid-connection")
            LoggingService.network.info("      → WiFi Direct → Bluetooth fallback not working")
        }

        if metrics.disconnectCount > 3 {
            LoggingService.network.info("   ❌ MULTIPLE DISCONNECTS (\(metrics.disconnectCount))")
            LoggingService.network.info("      → Connection establishment works")
            LoggingService.network.info("      → But transport layer is unstable")
            LoggingService.network.info("      → Likely WiFi interference or weak Bluetooth")
        }

        LoggingService.network.info("   ")
        LoggingService.network.info("💡 RECOMMENDATIONS:")
        LoggingService.network.info("   ")

        if metrics.isUnstable {
            LoggingService.network.info("   1. Try disabling WiFi (use pure Bluetooth)")
            LoggingService.network.info("   2. Reduce distance between devices")
            LoggingService.network.info("   3. Check for WiFi interference (microwaves, other networks)")
            LoggingService.network.info("   4. Enable Bluetooth-only mode in settings")
        }

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}
