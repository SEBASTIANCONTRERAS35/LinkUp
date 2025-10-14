//
//  FastTrackSessionManager.swift
//  MeshRed
//
//  Zero-delay session manager for Lightning Mode
//  All cooldowns, delays, and validations bypassed
//

import Foundation
import MultipeerConnectivity
import os

/// Replacement for SessionManager with ZERO delays for stadium scenarios
class FastTrackSessionManager {

    // MARK: - Lightning Configuration

    struct FastTrackConfig {
        static let connectionTimeout: TimeInterval = 1.0    // Was 30s
        static let blockDuration: TimeInterval = 0.0        // Was 10s - NO BLOCKING
        static let cleanupInterval: TimeInterval = 0.0      // Was 5s - NO CLEANUP DELAY
        static let disconnectionCooldown: TimeInterval = 0.0 // Was 2s - INSTANT RECONNECT
        static let connectionGracePeriod: TimeInterval = 0.0 // Was 2s - NO GRACE PERIOD
        static let maxRetryAttempts = 1000                  // Was 10 - NEVER GIVE UP
        static let retryDelay: TimeInterval = 0.01          // Was 2-32s - 10ms FLAT
    }

    // MARK: - Properties

    static let shared = FastTrackSessionManager()

    private var activeConnections = Set<String>()
    private let queue = DispatchQueue(label: "com.meshred.fasttrack", attributes: .concurrent)

    // Connection metrics
    private var connectionAttempts: [String: Date] = [:]
    private var connectionSuccesses: [String: Int] = [:]
    private var connectionFailures: [String: Int] = [:]

    // MARK: - Initialization

    private init() {
        LoggingService.network.info("⚡ FastTrackSessionManager initialized - ALL DELAYS DISABLED")
    }

    // MARK: - Fast Track Methods

    /// Always returns true - no validation in Lightning mode
    func shouldAttemptConnection(to peer: MCPeerID) -> Bool {
        // In Lightning mode, ALWAYS attempt connection
        return true
    }

    /// Record attempt with no delay enforcement
    func recordConnectionAttempt(to peer: MCPeerID) {
        queue.async(flags: .barrier) { [weak self] in
            self?.connectionAttempts[peer.displayName] = Date()
        }
    }

    /// Record success instantly
    func recordSuccessfulConnection(to peer: MCPeerID) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let peerKey = peer.displayName
            self.activeConnections.insert(peerKey)
            self.connectionSuccesses[peerKey, default: 0] += 1

            // Calculate and report connection time
            if let startTime = self.connectionAttempts[peerKey] {
                let connectionTime = Date().timeIntervalSince(startTime)
                LoggingService.network.info("⚡ FastTrack: Connected to \(peerKey) in \(String(format: "%.3f", connectionTime))s")

                if connectionTime < 0.5 {
                    LoggingService.network.info("🏆 ULTRA-FAST: Under 500ms!")
                } else if connectionTime < 1.0 {
                    LoggingService.network.info("🎯 SUB-SECOND: Under 1s!")
                }
            }
        }
    }

    /// Record disconnection with instant reconnect allowed
    func recordDisconnection(from peer: MCPeerID) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let peerKey = peer.displayName
            self.activeConnections.remove(peerKey)

            // NO COOLDOWN - can reconnect immediately
            LoggingService.network.info("⚡ FastTrack: Disconnected from \(peerKey) - INSTANT RECONNECT ALLOWED")
        }
    }

    /// Record declined connection - but don't block
    func recordConnectionDeclined(to peer: MCPeerID, reason: String) {
        queue.async(flags: .barrier) { [weak self] in
            self?.connectionFailures[peer.displayName, default: 0] += 1
            LoggingService.network.info("⚡ FastTrack: Connection declined (\(reason)) - Will retry immediately")
        }
    }

    /// Get next retry delay - always minimal
    func nextRetryDelay() -> TimeInterval {
        return FastTrackConfig.retryDelay  // Always 10ms
    }

    /// Clear cooldown - instant in FastTrack
    func clearCooldown(for peer: MCPeerID) {
        // No cooldowns to clear in FastTrack
        LoggingService.network.info("⚡ FastTrack: No cooldowns - \(peer.displayName) ready for instant connection")
    }

    /// Reset peer - instant
    func resetPeer(_ peer: MCPeerID) {
        queue.async(flags: .barrier) { [weak self] in
            let peerKey = peer.displayName
            self?.activeConnections.remove(peerKey)
            self?.connectionAttempts.removeValue(forKey: peerKey)
            LoggingService.network.info("⚡ FastTrack: Instant reset for \(peerKey)")
        }
    }

    /// Get connection stats
    func getConnectionStats() -> (attempts: Int, active: Int, successRate: Double) {
        return queue.sync {
            let totalAttempts = connectionAttempts.count
            let totalSuccesses = connectionSuccesses.values.reduce(0, +)
            let totalFailures = connectionFailures.values.reduce(0, +)
            let total = totalSuccesses + totalFailures

            let successRate = total > 0 ? Double(totalSuccesses) / Double(total) * 100 : 0

            return (
                attempts: totalAttempts,
                active: activeConnections.count,
                successRate: successRate
            )
        }
    }

    /// Clear all - instant
    func clearAll() {
        queue.async(flags: .barrier) { [weak self] in
            self?.activeConnections.removeAll()
            self?.connectionAttempts.removeAll()
            self?.connectionSuccesses.removeAll()
            self?.connectionFailures.removeAll()
            LoggingService.network.info("⚡ FastTrack: Instant clear completed")
        }
    }

    /// Check if connected
    func isConnected(to peer: MCPeerID) -> Bool {
        return queue.sync {
            activeConnections.contains(peer.displayName)
        }
    }

    // MARK: - Performance Metrics

    func getPerformanceReport() -> String {
        let stats = getConnectionStats()

        return """
        ⚡ FAST TRACK SESSION MANAGER ⚡
        Active Connections: \(stats.active)
        Total Attempts: \(stats.attempts)
        Success Rate: \(String(format: "%.1f", stats.successRate))%
        Retry Delay: \(FastTrackConfig.retryDelay * 1000)ms
        Cooldowns: DISABLED
        Validation: BYPASSED
        Target: <1s connections
        """
    }
}

// MARK: - Drop-in Replacement for SessionManager

extension FastTrackSessionManager {

    /// Make FastTrackSessionManager compatible with existing SessionManager interface
    func shouldAttemptConnection(to peer: MCPeerID, ignoreCooldown: Bool) -> Bool {
        return true  // Always true in FastTrack
    }

    func getConnectionTime(for peer: MCPeerID) -> Date? {
        return queue.sync {
            connectionAttempts[peer.displayName]
        }
    }

    /// Compatibility method - does nothing in FastTrack
    func unblockPeer(_ peer: MCPeerID) {
        // No blocking in FastTrack
    }
}