//
//  PeerLocationTracker.swift
//  MeshRed
//
//  Created by Emilio Contreras on 30/09/25.
//

import Foundation
import MultipeerConnectivity
import Combine

/// Manages GPS locations shared by peers for hybrid navigation
class PeerLocationTracker: ObservableObject {

    // MARK: - Published Properties

    /// GPS locations of peers (peerID -> UserLocation)
    @Published var peerLocations: [String: UserLocation] = [:]

    /// Timestamps of last updates (peerID -> Date)
    @Published var lastUpdateTimes: [String: Date] = [:]

    // MARK: - Private Properties

    /// Expiration time for cached locations (2 minutes)
    private let locationExpirationTime: TimeInterval = 120.0

    /// Timer for cleaning up stale locations
    private var cleanupTimer: Timer?

    // MARK: - Initialization

    init() {
        startCleanupTimer()
        print("📍 PeerLocationTracker: Initialized")
    }

    deinit {
        stopCleanupTimer()
    }

    // MARK: - Public Methods

    /// Update location for a peer
    /// - Parameters:
    ///   - peerID: Peer identifier (MCPeerID.displayName)
    ///   - location: GPS location
    func updatePeerLocation(peerID: String, location: UserLocation) {
        DispatchQueue.main.async {
            self.peerLocations[peerID] = location
            self.lastUpdateTimes[peerID] = Date()

            print("📍 PeerLocationTracker: Updated location for \(peerID)")
            print("   Location: \(location.coordinateString)")
            print("   Accuracy: \(location.accuracyString)")
            print("   Age: \(self.getLocationAge(for: peerID) ?? 0)s")
        }
    }

    /// Get location for a specific peer
    /// - Parameter peerID: Peer identifier
    /// - Returns: UserLocation if available and not stale, nil otherwise
    func getPeerLocation(peerID: String) -> UserLocation? {
        guard let location = peerLocations[peerID] else {
            return nil
        }

        // Check if location is stale
        if isLocationStale(for: peerID) {
            print("⚠️ PeerLocationTracker: Location for \(peerID) is stale, removing")
            removePeerLocation(peerID: peerID)
            return nil
        }

        return location
    }

    /// Remove location for a peer (e.g., when peer disconnects)
    /// - Parameter peerID: Peer identifier
    func removePeerLocation(peerID: String) {
        DispatchQueue.main.async {
            self.peerLocations.removeValue(forKey: peerID)
            self.lastUpdateTimes.removeValue(forKey: peerID)
            print("📍 PeerLocationTracker: Removed location for \(peerID)")
        }
    }

    /// Clear all peer locations
    func clearAllLocations() {
        DispatchQueue.main.async {
            self.peerLocations.removeAll()
            self.lastUpdateTimes.removeAll()
            print("📍 PeerLocationTracker: Cleared all peer locations")
        }
    }

    /// Check if a peer has a recent location available
    /// - Parameter peerID: Peer identifier
    /// - Returns: True if location exists and is not stale
    func hasRecentLocation(for peerID: String) -> Bool {
        guard peerLocations[peerID] != nil else {
            return false
        }

        return !isLocationStale(for: peerID)
    }

    /// Get age of location in seconds
    /// - Parameter peerID: Peer identifier
    /// - Returns: Age in seconds, or nil if no location
    func getLocationAge(for peerID: String) -> TimeInterval? {
        guard let lastUpdate = lastUpdateTimes[peerID] else {
            return nil
        }

        return Date().timeIntervalSince(lastUpdate)
    }

    /// Check if location is stale (older than expiration time)
    /// - Parameter peerID: Peer identifier
    /// - Returns: True if stale or missing
    func isLocationStale(for peerID: String) -> Bool {
        guard let age = getLocationAge(for: peerID) else {
            return true
        }

        return age > locationExpirationTime
    }

    /// Get all peers with recent locations
    /// - Returns: Array of peer IDs with recent locations
    func getPeersWithRecentLocations() -> [String] {
        return peerLocations.keys.filter { hasRecentLocation(for: $0) }
    }

    /// Get diagnostic status for all tracked peers
    /// - Returns: Human-readable status string
    func getDetailedStatus() -> String {
        var status = "Peer Location Tracker Status:\n"
        status += "  Total tracked peers: \(peerLocations.count)\n"
        status += "  Peers with recent locations: \(getPeersWithRecentLocations().count)\n\n"

        if peerLocations.isEmpty {
            status += "  No peer locations tracked\n"
        } else {
            status += "  Tracked locations:\n"
            for (peerID, location) in peerLocations {
                let age = getLocationAge(for: peerID) ?? 0
                let stale = isLocationStale(for: peerID) ? "⚠️ STALE" : "✅ Fresh"
                status += "    • \(peerID):\n"
                status += "      Location: \(location.coordinateString)\n"
                status += "      Accuracy: \(location.accuracyString)\n"
                status += "      Age: \(String(format: "%.0f", age))s \(stale)\n"
            }
        }

        return status
    }

    // MARK: - Private Methods

    /// Start timer for periodic cleanup of stale locations
    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.cleanupStaleLocations()
        }
    }

    /// Stop cleanup timer
    private func stopCleanupTimer() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }

    /// Remove all stale locations
    private func cleanupStaleLocations() {
        let stalePeers = peerLocations.keys.filter { isLocationStale(for: $0) }

        guard !stalePeers.isEmpty else {
            return
        }

        print("🧹 PeerLocationTracker: Cleaning up \(stalePeers.count) stale location(s)")

        for peerID in stalePeers {
            removePeerLocation(peerID: peerID)
        }
    }
}
