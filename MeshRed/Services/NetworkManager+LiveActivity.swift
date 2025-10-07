//
//  NetworkManager+LiveActivity.swift
//  MeshRed
//
//  Created by Claude for StadiumConnect Pro - Live Activities Integration
//

import Foundation
import ActivityKit
import Combine
import CoreLocation
import MultipeerConnectivity

// MARK: - Live Activity Storage

@available(iOS 16.1, *)
private class LiveActivityStorage {
    static var currentActivity: Activity<MeshActivityAttributes>?
    static var activityCancellables = Set<AnyCancellable>()
}

// MARK: - Live Activity Management

@available(iOS 16.1, *)
extension NetworkManager {

    // MARK: - Public Methods

    /// Start a Live Activity for the mesh network session
    /// This should be called when the app becomes active and has connections
    func startLiveActivity() {
        // Only start if we don't already have an active activity
        guard LiveActivityStorage.currentActivity == nil else {
            print("⚠️ Live Activity already running")
            return
        }

        // Only start if ActivityKit is supported
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("⚠️ Live Activities are not enabled by user")
            return
        }

        let attributes = MeshActivityAttributes(
            sessionId: UUID().uuidString,
            localDeviceName: localDeviceName,
            startedAt: Date()
        )

        let initialState = createCurrentState()

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )

            LiveActivityStorage.currentActivity = activity

            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("🎬 LIVE ACTIVITY STARTED")
            print("   Activity ID: \(activity.id)")
            print("   Session: \(attributes.sessionId)")
            print("   Device: \(attributes.localDeviceName)")
            print("   Connected Peers: \(initialState.connectedPeers)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            // Setup automatic updates based on NetworkManager changes
            setupLiveActivityUpdates()

        } catch {
            print("❌ Failed to start Live Activity: \(error)")
        }
    }

    /// Update the Live Activity with current state
    /// This is called automatically when NetworkManager properties change
    func updateLiveActivity() {
        guard let activity = LiveActivityStorage.currentActivity else {
            print("⚠️ No active Live Activity to update")
            return
        }

        let newState = createCurrentState()

        Task {
            await activity.update(
                .init(
                    state: newState,
                    staleDate: nil
                )
            )

            print("🔄 Live Activity updated - Peers: \(newState.connectedPeers), Tracking: \(newState.trackingUser ?? "none")")
        }
    }

    /// Update Live Activity WITH alert banner (for non-Dynamic Island devices)
    /// Shows a banner notification on devices without Dynamic Island
    func updateLiveActivity(withAlert title: String, body: String, sound: AlertConfiguration.AlertSound = .default) {
        guard let activity = LiveActivityStorage.currentActivity else {
            print("⚠️ No active Live Activity to update")
            return
        }

        let newState = createCurrentState()

        let alertConfig = AlertConfiguration(
            title: LocalizedStringResource(stringLiteral: title),
            body: LocalizedStringResource(stringLiteral: body),
            sound: sound
        )

        Task {
            await activity.update(
                .init(state: newState, staleDate: nil),
                alertConfiguration: alertConfig
            )

            print("🔔 Live Activity updated WITH ALERT")
            print("   Title: \(title)")
            print("   Body: \(body)")
            print("   This shows banner on non-Dynamic Island devices")
        }
    }

    /// Stop the Live Activity
    /// This should be called when disconnecting or app is backgrounding for extended period
    func stopLiveActivity(dismissalPolicy: ActivityUIDismissalPolicy = .default) {
        guard let activity = LiveActivityStorage.currentActivity else {
            print("⚠️ No active Live Activity to stop")
            return
        }

        let finalState = createCurrentState()

        Task {
            await activity.end(
                .init(state: finalState, staleDate: nil),
                dismissalPolicy: dismissalPolicy
            )

            LiveActivityStorage.currentActivity = nil
            LiveActivityStorage.activityCancellables.removeAll()

            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("🛑 LIVE ACTIVITY STOPPED")
            print("   Final Peers: \(finalState.connectedPeers)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        }
    }

    /// Check if a Live Activity is currently active
    var hasActiveLiveActivity: Bool {
        return LiveActivityStorage.currentActivity != nil
    }

    // MARK: - Private Methods

    /// Create current state from NetworkManager properties
    private func createCurrentState() -> MeshActivityAttributes.ContentState {
        // Convert ConnectionQuality to ActivityAttributes enum
        let quality: MeshActivityAttributes.ConnectionQualityState
        switch connectionQuality {
        case .excellent:
            quality = .excellent
        case .good:
            quality = .good
        case .poor:
            quality = .poor
        case .unknown:
            quality = .unknown
        }

        // Get tracking information
        var trackingUser: String?
        var distance: Double?
        var direction: MeshActivityAttributes.CardinalDirection?
        var isUWBTracking = false

        // Check if we have an active UWB tracking session
        if #available(iOS 14.0, *), let uwbManager = uwbSessionManager {
            // Find first peer with active UWB session
            for peer in connectedPeers {
                if let dist = uwbManager.getDistance(to: peer) {
                    trackingUser = peer.displayName
                    distance = Double(dist)
                    isUWBTracking = true

                    // Get direction if available
                    if let directionVector = uwbManager.getDirection(to: peer) {
                        // Calculate horizontal angle from SIMD3 vector
                        // atan2(x, z) gives angle in radians, convert to degrees
                        let radians = atan2(Double(directionVector.x), Double(directionVector.z))
                        let degrees = radians * 180.0 / .pi
                        direction = MeshActivityAttributes.CardinalDirection.from(degrees: degrees)
                    }

                    break // Only track first active session
                }
            }
        }

        // Get family information
        let familyCount = familyGroupManager.currentGroup?.memberCount ?? 0
        let nearbyFamily = connectedPeers.filter { peer in
            familyGroupManager.isFamilyMember(peerID: peer.displayName)
        }.count

        // Get geofence information
        var activeFence: String?
        var fenceStatus: MeshActivityAttributes.LinkFenceStatus?

        if let linkfence = linkfenceManager?.activeGeofence {
            activeFence = linkfence.name

            // Determine if we're inside or outside (simplified)
            if let location = locationService.currentLocation {
                let fenceLocation = UserLocation(
                    latitude: linkfence.center.latitude,
                    longitude: linkfence.center.longitude,
                    accuracy: 0,
                    timestamp: Date()
                )
                let distanceToFence = location.distance(to: fenceLocation)
                if distanceToFence <= linkfence.radius {
                    fenceStatus = .inside
                } else {
                    fenceStatus = .outside
                }
            }
        }

        // Check for emergency (would need EmergencyManager integration)
        // For now, we'll set this to false
        let emergencyActive = false
        let emergencyType: String? = nil

        // Get unread message count from MessageStore
        let unreadMessages = messageStore.unreadCount

        return MeshActivityAttributes.ContentState(
            connectedPeers: connectedPeers.count,
            connectionQuality: quality,
            isRelayingMessages: relayingMessage,
            trackingUser: trackingUser,
            distance: distance,
            direction: direction,
            isUWBTracking: isUWBTracking,
            familyMemberCount: familyCount,
            nearbyFamilyMembers: nearbyFamily,
            activeLinkFence: activeFence,
            linkfenceStatus: fenceStatus,
            emergencyActive: emergencyActive,
            emergencyType: emergencyType,
            unreadMessageCount: unreadMessages,
            lastUpdated: Date()
        )
    }

    /// Setup automatic updates when NetworkManager properties change
    private func setupLiveActivityUpdates() {
        // Cancel any existing subscriptions
        LiveActivityStorage.activityCancellables.removeAll()

        // Update when connected peers change
        $connectedPeers
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLiveActivity()
            }
            .store(in: &LiveActivityStorage.activityCancellables)

        // Update when connection quality changes
        $connectionQuality
            .debounce(for: .seconds(1.0), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLiveActivity()
            }
            .store(in: &LiveActivityStorage.activityCancellables)

        // Update when relaying status changes
        $relayingMessage
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLiveActivity()
            }
            .store(in: &LiveActivityStorage.activityCancellables)

        // Update when unread message count changes
        messageStore.$unreadCount
            .debounce(for: .seconds(0.3), scheduler: DispatchQueue.main)
            .sink { [weak self] count in
                self?.updateLiveActivity()
                print("📬 Live Activity updated with \(count) unread messages")
            }
            .store(in: &LiveActivityStorage.activityCancellables)

        // Update periodically for UWB distance changes (every 2 seconds)
        Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                // Only update if we have UWB tracking active
                if let self = self,
                   #available(iOS 14.0, *),
                   let uwbManager = self.uwbSessionManager,
                   !self.connectedPeers.isEmpty {

                    // Check if any peer has active UWB session
                    for peer in self.connectedPeers {
                        if uwbManager.getDistance(to: peer) != nil {
                            self.updateLiveActivity()
                            break
                        }
                    }
                }
            }
            .store(in: &LiveActivityStorage.activityCancellables)

        print("✅ Live Activity auto-update observers configured")
    }
}
