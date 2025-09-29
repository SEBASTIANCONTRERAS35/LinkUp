//
//  LocationRequestManager.swift
//  MeshRed
//
//  Created by Emilio Contreras on 29/09/25.
//

import Foundation
import Combine

/// Coordinates location requests and responses, manages timeouts and retries
class LocationRequestManager: ObservableObject {
    // MARK: - Published Properties
    @Published var pendingRequests: [UUID: LocationRequestState] = [:]
    @Published var receivedResponses: [String: LocationResponseMessage] = [:]  // TargetId -> Response

    // MARK: - Private Properties
    private let timeoutInterval: TimeInterval = 10.0
    private let maxRetries: Int = 3
    private var timeoutTimers: [UUID: Timer] = [:]

    // MARK: - Settings
    @Published var autoRespondToRequests: Bool = true  // Automatically respond to location requests
    @Published var shareOnlyDistance: Bool = false     // Share only distance without direction (more privacy)
    @Published var allowedRequesters: Set<String>?     // Whitelist of peers allowed to request location (nil = all)

    // MARK: - Request State
    struct LocationRequestState {
        let request: LocationRequestMessage
        let timestamp: Date
        var retryCount: Int
        var status: RequestStatus
    }

    enum RequestStatus {
        case pending
        case received
        case timeout
        case denied
        case calculating
    }

    // MARK: - Public Methods

    /// Start tracking a location request
    func trackRequest(_ request: LocationRequestMessage) {
        let state = LocationRequestState(
            request: request,
            timestamp: Date(),
            retryCount: 0,
            status: .pending
        )

        DispatchQueue.main.async {
            self.pendingRequests[request.id] = state
        }

        // Start timeout timer
        startTimeoutTimer(for: request)

        print("📍 LocationRequestManager: Tracking request \(request.id) for target \(request.targetId)")
    }

    /// Handle received location response
    func handleResponse(_ response: LocationResponseMessage) {
        print("📍 LocationRequestManager: Received response for request \(response.requestId)")

        // Cancel timeout timer
        cancelTimeoutTimer(for: response.requestId)

        // Update request state
        DispatchQueue.main.async {
            if var state = self.pendingRequests[response.requestId] {
                state.status = .received
                self.pendingRequests[response.requestId] = state
            }

            // Store response
            self.receivedResponses[response.targetId] = response
        }

        // Calculate location if triangulated
        if response.responseType == .triangulated,
           let relativeLocation = response.relativeLocation,
           let direction = relativeLocation.targetDirection {

            if let calculatedLocation = LocationCalculator.calculateTargetLocation(
                from: relativeLocation.intermediaryLocation,
                distance: relativeLocation.targetDistance,
                direction: direction
            ) {
                print("📍 Calculated target location: \(calculatedLocation.coordinateString)")
            }
        }
    }

    /// Check if we should respond to a location request
    func shouldRespondToRequest(_ request: LocationRequestMessage) -> Bool {
        // Check auto-respond setting
        guard autoRespondToRequests else {
            print("📍 LocationRequestManager: Auto-respond disabled")
            return false
        }

        // Check whitelist
        if let allowed = allowedRequesters {
            guard allowed.contains(request.requesterId) else {
                print("📍 LocationRequestManager: Requester \(request.requesterId) not in whitelist")
                return false
            }
        }

        return true
    }

    /// Mark request as timed out
    func markRequestTimeout(_ requestId: UUID) {
        DispatchQueue.main.async {
            guard var state = self.pendingRequests[requestId] else { return }

            state.retryCount += 1

            if state.retryCount >= self.maxRetries {
                state.status = .timeout
                print("❌ LocationRequestManager: Request \(requestId) timed out after \(self.maxRetries) retries")
            } else {
                state.status = .pending
                print("🔄 LocationRequestManager: Retrying request \(requestId) (attempt \(state.retryCount + 1)/\(self.maxRetries))")
            }

            self.pendingRequests[requestId] = state
        }
    }

    /// Clear old responses (older than 5 minutes)
    func clearOldResponses() {
        let fiveMinutesAgo = Date().addingTimeInterval(-300)

        DispatchQueue.main.async {
            self.receivedResponses = self.receivedResponses.filter { _, response in
                response.timestamp > fiveMinutesAgo
            }
        }
    }

    /// Get response for a specific target
    func getResponse(for targetId: String) -> LocationResponseMessage? {
        return receivedResponses[targetId]
    }

    /// Get all pending requests count
    var pendingRequestsCount: Int {
        return pendingRequests.filter { $0.value.status == .pending }.count
    }

    // MARK: - Private Methods

    private func startTimeoutTimer(for request: LocationRequestMessage) {
        let timer = Timer.scheduledTimer(withTimeInterval: timeoutInterval, repeats: false) { [weak self] _ in
            self?.markRequestTimeout(request.id)
            self?.timeoutTimers.removeValue(forKey: request.id)
        }

        timeoutTimers[request.id] = timer
    }

    private func cancelTimeoutTimer(for requestId: UUID) {
        timeoutTimers[requestId]?.invalidate()
        timeoutTimers.removeValue(forKey: requestId)
    }

    // MARK: - Cleanup

    /// Cancel all pending requests and timers
    func cancelAll() {
        for timer in timeoutTimers.values {
            timer.invalidate()
        }

        DispatchQueue.main.async {
            self.timeoutTimers.removeAll()
            self.pendingRequests.removeAll()
        }
    }
}