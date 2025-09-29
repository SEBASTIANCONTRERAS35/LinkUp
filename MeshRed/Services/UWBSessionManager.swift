//
//  UWBSessionManager.swift
//  MeshRed
//
//  Created by Emilio Contreras on 29/09/25.
//

import Foundation
import NearbyInteraction
import MultipeerConnectivity
import Combine

/// Manages UWB (Ultra Wideband) ranging sessions with peers using NearbyInteraction framework
/// Provides centimeter-level precision for distance and direction measurements
@available(iOS 14.0, *)
class UWBSessionManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var activeSessions: [String: NISession] = [:]  // PeerID -> Session
    @Published var nearbyObjects: [String: NINearbyObject] = [:]  // PeerID -> Object
    @Published var isUWBSupported: Bool = false

    // MARK: - Private Properties
    private var discoveryTokens: [String: NIDiscoveryToken] = [:]  // PeerID -> Token
    private let queue = DispatchQueue(label: "com.meshred.uwb", qos: .userInitiated)

    // MARK: - Delegates
    weak var delegate: UWBSessionManagerDelegate?

    // MARK: - Initialization
    override init() {
        super.init()
        checkUWBSupport()
    }

    // MARK: - Public Methods

    /// Check if device supports UWB (NearbyInteraction)
    private func checkUWBSupport() {
        #if targetEnvironment(simulator)
        isUWBSupported = false
        print("⚠️ UWBSessionManager: UWB not available in simulator")
        #else
        isUWBSupported = NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
        if isUWBSupported {
            print("📡 UWBSessionManager: UWB is supported on this device")
        } else {
            print("⚠️ UWBSessionManager: UWB not supported (requires iPhone 11+ with U1/U2 chip)")
        }
        #endif
    }

    /// Get local discovery token for sharing with peers
    func getLocalDiscoveryToken() -> NIDiscoveryToken? {
        guard isUWBSupported else {
            print("❌ UWBSessionManager: Cannot get token - UWB not supported")
            return nil
        }

        // Create temporary session to get token
        let session = NISession()
        return session.discoveryToken
    }

    /// Start UWB ranging session with a peer
    func startSession(with peerID: MCPeerID, discoveryToken: NIDiscoveryToken) {
        guard isUWBSupported else {
            print("❌ UWBSessionManager: Cannot start session - UWB not supported")
            return
        }

        let peerId = peerID.displayName

        queue.async { [weak self] in
            guard let self = self else { return }

            // Check if session already exists
            if self.activeSessions[peerId] != nil {
                print("⚠️ UWBSessionManager: Session already exists for \(peerId)")
                return
            }

            // Create new session
            let session = NISession()
            session.delegate = self
            session.delegateQueue = self.queue

            // Store token
            self.discoveryTokens[peerId] = discoveryToken

            // Configure session
            let config = NINearbyPeerConfiguration(peerToken: discoveryToken)

            // Run session
            session.run(config)

            DispatchQueue.main.async {
                self.activeSessions[peerId] = session
            }

            print("📡 UWBSessionManager: Started session with \(peerId)")
        }
    }

    /// Stop UWB ranging session with a peer
    func stopSession(with peerID: MCPeerID) {
        let peerId = peerID.displayName

        queue.async { [weak self] in
            guard let self = self else { return }

            if let session = self.activeSessions[peerId] {
                session.invalidate()

                DispatchQueue.main.async {
                    self.activeSessions.removeValue(forKey: peerId)
                    self.nearbyObjects.removeValue(forKey: peerId)
                    self.discoveryTokens.removeValue(forKey: peerId)
                }

                print("📡 UWBSessionManager: Stopped session with \(peerId)")
            }
        }
    }

    /// Stop all active sessions
    func stopAllSessions() {
        queue.async { [weak self] in
            guard let self = self else { return }

            for (peerId, session) in self.activeSessions {
                session.invalidate()
                print("📡 UWBSessionManager: Stopped session with \(peerId)")
            }

            DispatchQueue.main.async {
                self.activeSessions.removeAll()
                self.nearbyObjects.removeAll()
                self.discoveryTokens.removeAll()
            }
        }
    }

    /// Get current distance to a peer (if available)
    func getDistance(to peerID: MCPeerID) -> Float? {
        let peerId = peerID.displayName
        return nearbyObjects[peerId]?.distance
    }

    /// Get current direction to a peer (if available)
    func getDirection(to peerID: MCPeerID) -> SIMD3<Float>? {
        let peerId = peerID.displayName
        return nearbyObjects[peerId]?.direction
    }

    /// Check if we have an active UWB session with a peer
    func hasActiveSession(with peerID: MCPeerID) -> Bool {
        return activeSessions[peerID.displayName] != nil
    }

    /// Get relative location info for a peer (for triangulation)
    func getRelativeLocationInfo(for peerID: MCPeerID, intermediaryLocation: UserLocation) -> RelativeLocation? {
        let peerId = peerID.displayName

        guard let nearbyObject = nearbyObjects[peerId],
              let distance = nearbyObject.distance else {
            return nil
        }

        let direction = nearbyObject.direction.map { DirectionVector(from: $0) }

        // Determine accuracy based on UWB quality
        // UWB is typically accurate to ±0.1-0.5 meters
        let accuracy: Float = 0.5

        return RelativeLocation(
            intermediaryId: "", // Will be filled by caller
            intermediaryLocation: intermediaryLocation,
            targetDistance: distance,
            targetDirection: direction,
            accuracy: accuracy
        )
    }
}

// MARK: - NISessionDelegate
@available(iOS 14.0, *)
extension UWBSessionManager: NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        // Find which peer this session belongs to
        guard let peerId = activeSessions.first(where: { $0.value === session })?.key else {
            return
        }

        // Update nearby object for this peer
        if let object = nearbyObjects.first {
            DispatchQueue.main.async {
                self.nearbyObjects[peerId] = object
            }

            if let distance = object.distance {
                let directionString = object.direction != nil ? "with direction" : "no direction"
                print("📡 UWBSessionManager: Updated \(peerId) - Distance: \(String(format: "%.2f", distance))m (\(directionString))")
            }

            // Notify delegate
            delegate?.uwbSessionManager(self, didUpdateDistanceTo: peerId, distance: object.distance, direction: object.direction)
        }
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        // Find which peer this session belongs to
        guard let peerId = activeSessions.first(where: { $0.value === session })?.key else {
            return
        }

        DispatchQueue.main.async {
            self.nearbyObjects.removeValue(forKey: peerId)
        }

        print("⚠️ UWBSessionManager: Lost tracking of \(peerId) - Reason: \(reason.description)")

        // Notify delegate
        delegate?.uwbSessionManager(self, didLoseTrackingOf: peerId, reason: reason)
    }

    func sessionWasSuspended(_ session: NISession) {
        guard let peerId = activeSessions.first(where: { $0.value === session })?.key else {
            return
        }

        print("⏸️ UWBSessionManager: Session suspended for \(peerId)")
    }

    func sessionSuspensionEnded(_ session: NISession) {
        guard let peerId = activeSessions.first(where: { $0.value === session })?.key else {
            return
        }

        print("▶️ UWBSessionManager: Session resumed for \(peerId)")
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        guard let peerId = activeSessions.first(where: { $0.value === session })?.key else {
            return
        }

        print("❌ UWBSessionManager: Session invalidated for \(peerId): \(error.localizedDescription)")

        DispatchQueue.main.async {
            self.activeSessions.removeValue(forKey: peerId)
            self.nearbyObjects.removeValue(forKey: peerId)
        }

        // Notify delegate
        delegate?.uwbSessionManager(self, sessionInvalidatedFor: peerId, error: error)
    }
}

// MARK: - UWBSessionManagerDelegate
@available(iOS 14.0, *)
protocol UWBSessionManagerDelegate: AnyObject {
    func uwbSessionManager(_ manager: UWBSessionManager, didUpdateDistanceTo peerId: String, distance: Float?, direction: SIMD3<Float>?)
    func uwbSessionManager(_ manager: UWBSessionManager, didLoseTrackingOf peerId: String, reason: NINearbyObject.RemovalReason)
    func uwbSessionManager(_ manager: UWBSessionManager, sessionInvalidatedFor peerId: String, error: Error)
}

// MARK: - NINearbyObject.RemovalReason Extension
@available(iOS 14.0, *)
extension NINearbyObject.RemovalReason {
    var description: String {
        switch self {
        case .timeout:
            return "Timeout"
        case .peerEnded:
            return "Peer Ended"
        @unknown default:
            return "Unknown"
        }
    }
}