//
//  NetworkManager+Lightning.swift
//  MeshRed
//
//  Lightning Mode integration for NetworkManager
//  Bypasses all delays and cooldowns for sub-second connections
//

import Foundation
import MultipeerConnectivity
import os

extension NetworkManager {

    // MARK: - Lightning Mode Properties

    private static let lightningModeKey = "lightningModeEnabled"
    private static let ultraFastModeKey = "ultraFastModeEnabled"

    var isLightningModeEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: NetworkManager.lightningModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: NetworkManager.lightningModeKey) }
    }

    var isUltraFastModeEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: NetworkManager.ultraFastModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: NetworkManager.ultraFastModeKey) }
    }

    // MARK: - Lightning Mode Activation

    /// Enable Lightning Mode for ultra-fast connections in stadium/concert scenarios
    /// ULTRA-FAST VERSION - Aggressive optimizations for <3 second connections
    func enableLightningMode(ultraFast: Bool = true) {
        if ultraFast {
            LoggingService.network.info("⚡⚡⚡ ENABLING LIGHTNING MODE ULTRA-FAST ⚡⚡⚡")
            LoggingService.network.info("Mode: ULTRA-AGGRESSIVE for FIFA 2026 stadiums")
            LoggingService.network.info("Target: <3 second connections with bidirectional always active")
            // ⚡ Store Ultra-Fast flag for SessionManager to bypass cooldowns
            UserDefaults.standard.set(true, forKey: "lightningModeUltraFast")
        } else {
            LoggingService.network.info("⚡⚡⚡ ENABLING LIGHTNING MODE (SIMPLIFIED) ⚡⚡⚡")
            LoggingService.network.info("Optimizations: Zero cooldowns, faster timeouts, no validation")
            LoggingService.network.info("Target: Fast connections without breaking connectivity")
            UserDefaults.standard.set(false, forKey: "lightningModeUltraFast")
        }

        isLightningModeEnabled = true
        isUltraFastModeEnabled = ultraFast

        // 1. Clear all SessionManager cooldowns and blocks
        sessionManager.clearAll()
        LoggingService.network.info("  ✓ Cleared all connection cooldowns")

        // 2. Release all mutex locks to prevent blocking
        connectionMutex.releaseAllLocks()
        LoggingService.network.info("  ✓ Released all connection locks")

        // 2.5. Reset all peer reputations to neutral (Lightning Mode fresh start)
        if isOrchestratorEnabled {
            orchestrator.reputationSystem.resetAllReputations()
            LoggingService.network.info("  ✓ Reset all peer reputations to neutral (60.0)")
        } else {
            LoggingService.network.info("  ℹ️ Orchestrator disabled - reputation reset skipped")
        }

        // 3. Create session with optional encryption (faster than required)
        // Keep .optional instead of .none to maintain compatibility
        session.disconnect()
        session = MCSession(
            peer: localPeerID,
            securityIdentity: nil,
            encryptionPreference: .optional  // Balanced: fast but compatible
        )
        session.delegate = self
        LoggingService.network.info("  ✓ Session recreated with fast encryption mode")

        // 4. Restart discovery services normally (no multiple advertisers)
        restartServicesIfNeeded()
        LoggingService.network.info("  ✓ Discovery services restarted")

        if ultraFast {
            LoggingService.network.info("⚡ ULTRA-FAST Lightning Mode ACTIVE")
            LoggingService.network.info("⚡ Bidirectional connections ALWAYS enabled")
            LoggingService.network.info("⚡ Target: <3 second connections for stadiums")
        } else {
            LoggingService.network.info("⚡ Lightning Mode ACTIVE - Connections optimized for speed")
            LoggingService.network.info("⚡ No cooldowns, no blocks, fast timeouts")
        }
    }

    func disableLightningMode() {
        LoggingService.network.info("⚡ Disabling Lightning Mode - Returning to standard security")

        isLightningModeEnabled = false
        isUltraFastModeEnabled = false

        // Restore normal session with encryption
        recreateSession()

        // Restart normal discovery
        restartServicesIfNeeded()

        LoggingService.network.info("✅ Standard mode restored")
    }

    /*
    // MARK: - REMOVED: Experimental Lightning Features
    // These caused "Address already in use" errors due to multiple advertisers/browsers
    // Simplified Lightning Mode uses only core optimizations (no cooldowns, fast timeouts)

    // Removed functions:
    // - overrideDelaysForLightning()
    // - recreateSessionForLightning()
    // - startLightningDiscovery() - Created multiple advertisers/browsers
    // - enableParallelConnections()
    // - lightningConnect() - Created dynamic advertisers per peer
    */

    /// Accept all invitations instantly in Lightning mode
    func lightningAcceptInvitation(from peer: MCPeerID, handler: @escaping (Bool, MCSession?) -> Void) {
        guard isLightningModeEnabled else {
            // Fall back to normal validation
            return
        }

        LoggingService.network.info("⚡ INSTANT ACCEPT from \(peer.displayName)")
        handler(true, session)

        // Record connection time
        if let startTime = connectionAttemptTimestamps[peer.displayName] {
            let connectionTime = Date().timeIntervalSince(startTime)
            LoggingService.network.info("⚡ Connection established in \(String(format: "%.3f", connectionTime))s")

            if connectionTime < 1.0 {
                LoggingService.network.info("🎯 SUB-SECOND CONNECTION ACHIEVED!")
            }
        }
    }

    // MARK: - Connection Attempt Tracking

    func recordLightningConnectionStart(for peer: MCPeerID) {
        connectionAttemptTimestamps[peer.displayName] = Date()
    }

    func recordLightningConnectionSuccess(for peer: MCPeerID) {
        guard let startTime = connectionAttemptTimestamps[peer.displayName] else { return }

        let connectionTime = Date().timeIntervalSince(startTime)
        connectionAttemptTimestamps.removeValue(forKey: peer.displayName)

        LoggingService.network.info("⚡⚡⚡ LIGHTNING CONNECTION SUCCESS ⚡⚡⚡")
        LoggingService.network.info("Peer: \(peer.displayName)")
        LoggingService.network.info("Time: \(String(format: "%.3f", connectionTime))s")

        if connectionTime < 1.0 {
            LoggingService.network.info("🎯 TARGET ACHIEVED: SUB-SECOND CONNECTION!")
        } else if connectionTime < 2.0 {
            LoggingService.network.info("⚡ Fast connection: Under 2 seconds")
        } else if connectionTime < 5.0 {
            LoggingService.network.info("✅ Good connection: Under 5 seconds")
        } else {
            LoggingService.network.info("⚠️ Slow connection: \(String(format: "%.1f", connectionTime))s")
        }

        // Update stats
        updateLightningStats(connectionTime: connectionTime)
    }

    // MARK: - Statistics

    private func updateLightningStats(connectionTime: TimeInterval) {
        lightningConnectionTimes.append(connectionTime)

        // Keep only last 100 connections
        if lightningConnectionTimes.count > 100 {
            lightningConnectionTimes.removeFirst()
        }

        // Calculate average
        let average = lightningConnectionTimes.reduce(0, +) / Double(lightningConnectionTimes.count)
        let subSecondCount = lightningConnectionTimes.filter { $0 < 1.0 }.count
        let successRate = Double(subSecondCount) / Double(lightningConnectionTimes.count) * 100

        LoggingService.network.info("📊 LIGHTNING STATS:")
        LoggingService.network.info("  Average: \(String(format: "%.3f", average))s")
        LoggingService.network.info("  Sub-second: \(subSecondCount)/\(self.lightningConnectionTimes.count) (\(String(format: "%.1f", successRate))%)")
        LoggingService.network.info("  Best: \(String(format: "%.3f", self.lightningConnectionTimes.min() ?? 0))s")
    }

    func getLightningModeStatus() -> String {
        guard isLightningModeEnabled else {
            return "Lightning Mode: INACTIVE"
        }

        let average = lightningConnectionTimes.isEmpty ? 0 :
            lightningConnectionTimes.reduce(0, +) / Double(lightningConnectionTimes.count)

        let subSecondCount = lightningConnectionTimes.filter { $0 < 1.0 }.count

        return """
        ⚡ LIGHTNING MODE: ACTIVE
        Connections: \(lightningConnectionTimes.count)
        Average: \(String(format: "%.3f", average))s
        Sub-second: \(subSecondCount)
        Best: \(String(format: "%.3f", lightningConnectionTimes.min() ?? 0))s
        """
    }
}

/*
// MARK: - REMOVED: Lightning delegate overrides
// These were part of experimental multi-advertiser/browser system
// Simplified Lightning Mode uses standard discovery with core optimizations only

extension NetworkManager {
    // lightningBrowser() - removed
    // lightningAdvertiser() - removed
}
*/