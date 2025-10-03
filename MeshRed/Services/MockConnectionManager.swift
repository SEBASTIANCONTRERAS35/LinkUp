//
//  MockConnectionManager.swift
//  MeshRed
//
//  Manages simulated peer connections with JSON persistence
//

import Foundation
import Combine

class MockConnectionManager: ObservableObject {
    @Published var connectedMockPeers: [MockPeer] = []
    @Published var availableMockPeers: [MockPeer] = []

    private let userDefaults = UserDefaults.standard
    private let connectedKey = "mockConnectedPeers"
    private let availableKey = "mockAvailablePeers"

    init() {
        loadPersistedState()
    }

    // MARK: - Connection Management

    func connectMockPeer(_ peer: MockPeer) {
        // Remove from available
        availableMockPeers.removeAll { $0.id == peer.id }

        // Add to connected with updated properties
        var connectedPeer = peer
        // MultipeerConnectivity real-world range: 10-50m (indoor: 10-20m, outdoor: 20-50m)
        // Stadium scenario: mostly 5-30m realistic range with obstacles
        connectedPeer.distance = Float.random(in: 2.0...30.0)
        connectedPeer.signalQuality = determineSignalQuality(for: connectedPeer.distance!)
        connectedPeer.dataSource = determineDataSource(for: connectedPeer.distance!)

        connectedMockPeers.append(connectedPeer)

        saveState()
    }

    func disconnectMockPeer(_ peer: MockPeer) {
        // Remove from connected
        connectedMockPeers.removeAll { $0.id == peer.id }

        // Add back to available with reset properties
        var availablePeer = peer
        availablePeer.distance = nil
        availablePeer.signalQuality = .unknown
        availablePeer.dataSource = .none

        availableMockPeers.append(availablePeer)

        saveState()
    }

    // MARK: - Persistence

    private func saveState() {
        do {
            let connectedData = try JSONEncoder().encode(connectedMockPeers)
            let availableData = try JSONEncoder().encode(availableMockPeers)

            userDefaults.set(connectedData, forKey: connectedKey)
            userDefaults.set(availableData, forKey: availableKey)
        } catch {
            print("Error saving mock peer state: \(error)")
        }
    }

    private func loadPersistedState() {
        // Load connected peers
        if let connectedData = userDefaults.data(forKey: connectedKey),
           let connected = try? JSONDecoder().decode([MockPeer].self, from: connectedData) {
            connectedMockPeers = connected
        } else {
            // Default connected peers
            connectedMockPeers = MockDataManager.mockConnectedPeers
        }

        // Load available peers
        if let availableData = userDefaults.data(forKey: availableKey),
           let available = try? JSONDecoder().decode([MockPeer].self, from: availableData) {
            availableMockPeers = available
        } else {
            // Default available peers
            availableMockPeers = MockDataManager.mockAvailablePeers
        }
    }

    func resetToDefaults() {
        connectedMockPeers = MockDataManager.mockConnectedPeers
        availableMockPeers = MockDataManager.mockAvailablePeers
        saveState()
    }

    // MARK: - Helper Methods

    private func determineDataSource(for distance: Float) -> MockPeer.PeerDataSource {
        // LinkFinder works up to ~10m with precise direction
        // Beyond that, LinkFinder gives distance-only, or falls back to GPS/BLE triangulation
        if distance < 8.0 {
            return .uwbPrecise  // LinkFinder with direction (very close)
        } else if distance < 20.0 {
            return .uwbDistance  // LinkFinder distance-only (medium range)
        } else {
            return .gps  // GPS/BLE triangulation (far range, near MC limit)
        }
    }

    private func determineSignalQuality(for distance: Float) -> MockPeer.SignalQuality {
        // MultipeerConnectivity quality degrades with distance
        // Apple recommends <5m for reliable connections
        if distance < 5.0 {
            return .excellent  // Within Apple's recommended range
        } else if distance < 15.0 {
            return .good  // Moderate distance, still reliable
        } else if distance < 25.0 {
            return .fair  // Far, connection may be unstable
        } else {
            return .poor  // Near maximum MC range (30-50m), unreliable
        }
    }
}
