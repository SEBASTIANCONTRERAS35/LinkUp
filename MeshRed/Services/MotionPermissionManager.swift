//
//  MotionPermissionManager.swift
//  MeshRed
//
//  Manages CoreMotion permission requests for UWB camera assistance
//  Required for iPhone 14+ to use ARKit-based direction measurement
//

import Foundation
import CoreMotion
import Combine
import os

/// Manages Motion & Fitness permission required for ARKit camera assistance
class MotionPermissionManager: ObservableObject {
    // MARK: - Published Properties
    @Published var authorizationStatus: CMAuthorizationStatus = .notDetermined
    @Published var isRequestingPermission: Bool = false

    // MARK: - Private Properties
    private var activityManager: CMMotionActivityManager?
    private var permissionCallbacks: [(Bool) -> Void] = []

    // MARK: - Initialization
    init() {
        checkCurrentStatus()
    }

    // MARK: - Public Methods

    /// Check current authorization status without requesting
    func checkCurrentStatus() {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🔐 MOTION PERMISSION STATUS CHECK")
        LoggingService.network.info("   Checking CMMotionActivityManager.authorizationStatus()")

        let status = CMMotionActivityManager.authorizationStatus()
        self.authorizationStatus = status

        LoggingService.network.info("   Current Status: \(self.statusDescription(status))")
        LoggingService.network.info("   Raw Value: \(status.rawValue)")

        switch status {
        case .notDetermined:
            LoggingService.network.info("   ⏳ Permission not yet requested")
            LoggingService.network.info("   Action: Will request when needed")
        case .restricted:
            LoggingService.network.info("   ⚠️ Permission RESTRICTED (MDM or parental controls)")
            LoggingService.network.info("   Impact: Camera assistance will NOT work")
            LoggingService.network.info("   Fallback: Will use compass-based direction")
        case .denied:
            LoggingService.network.info("   ❌ Permission DENIED by user")
            LoggingService.network.info("   Impact: Camera assistance will NOT work")
            LoggingService.network.info("   Fallback: Will use compass-based direction")
            LoggingService.network.info("   Fix: User must enable in Settings → Privacy → Motion & Fitness")
        case .authorized:
            LoggingService.network.info("   ✅ Permission AUTHORIZED")
            LoggingService.network.info("   Impact: Camera assistance can work")
        @unknown default:
            LoggingService.network.info("   ❓ UNKNOWN status (\(status.rawValue))")
        }

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    /// Request Motion permission with callback
    /// This MUST be called before enabling camera assistance in NISession
    func requestPermission(completion: @escaping (Bool) -> Void) {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🔐 REQUESTING MOTION PERMISSION")
        LoggingService.network.info("   Timestamp: \(Date())")

        // Check if already authorized
        let currentStatus = CMMotionActivityManager.authorizationStatus()
        LoggingService.network.info("   Pre-request status: \(self.statusDescription(currentStatus))")

        if currentStatus == .authorized {
            LoggingService.network.info("   ✅ Already authorized - no need to request")
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            completion(true)
            return
        }

        if currentStatus == .denied || currentStatus == .restricted {
            LoggingService.network.info("   ❌ Permission denied/restricted - cannot request again")
            LoggingService.network.info("   User must change in Settings")
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            completion(false)
            return
        }

        // Add callback to queue
        permissionCallbacks.append(completion)
        isRequestingPermission = true

        LoggingService.network.info("   Step 1: Creating CMMotionActivityManager...")
        activityManager = CMMotionActivityManager()

        guard let manager = activityManager else {
            LoggingService.network.info("   ❌ ERROR: Failed to create CMMotionActivityManager")
            LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            isRequestingPermission = false
            executeCallbacks(authorized: false)
            return
        }

        LoggingService.network.info("   ✓ CMMotionActivityManager created")
        LoggingService.network.info("   Step 2: Calling startActivityUpdates() to trigger permission dialog...")

        // This triggers the permission dialog
        manager.startActivityUpdates(to: .main) { [weak self] activity in
            // Activity handler - just for triggering permission
            if let activity = activity {
                LoggingService.network.info("   📊 Motion activity received: \(activity)")
            }
        }

        LoggingService.network.info("   ✓ startActivityUpdates() called")
        LoggingService.network.info("   ⏳ Waiting 1.5 seconds for iOS to show permission dialog...")
        LoggingService.network.info("   ⚠️ User MUST tap 'Allow' for camera assistance to work")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Wait for permission dialog response
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.checkPermissionResult()
        }
    }

    /// Check permission result after request
    private func checkPermissionResult() {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🔐 CHECKING PERMISSION RESULT")
        LoggingService.network.info("   Timestamp: \(Date())")

        let finalStatus = CMMotionActivityManager.authorizationStatus()
        self.authorizationStatus = finalStatus

        LoggingService.network.info("   Final Status: \(self.statusDescription(finalStatus))")
        LoggingService.network.info("   Raw Value: \(finalStatus.rawValue)")

        // Stop activity updates
        LoggingService.network.info("   Stopping activity updates...")
        activityManager?.stopActivityUpdates()
        activityManager = nil

        isRequestingPermission = false

        let authorized = finalStatus == .authorized

        if authorized {
            LoggingService.network.info("   ✅ SUCCESS: Permission GRANTED")
            LoggingService.network.info("   Impact: Camera assistance will work")
            LoggingService.network.info("   Next: Will enable isCameraAssistanceEnabled in NISession")
        } else {
            LoggingService.network.info("   ❌ FAILURE: Permission NOT granted")
            LoggingService.network.info("   Status: \(self.statusDescription(finalStatus))")

            if finalStatus == .notDetermined {
                LoggingService.network.info("   ⚠️ WARNING: User dismissed dialog without choosing")
                LoggingService.network.info("   Impact: Permission still not determined")
                LoggingService.network.info("   Action: Will retry on next attempt")
            } else if finalStatus == .denied {
                LoggingService.network.info("   ❌ User tapped 'Don't Allow'")
                LoggingService.network.info("   Impact: Camera assistance BLOCKED")
                LoggingService.network.info("   Fallback: Will use compass-based direction")
                LoggingService.network.info("   Fix: Settings → Privacy → Motion & Fitness → MeshRed → ON")
            } else if finalStatus == .restricted {
                LoggingService.network.info("   ⚠️ Restricted by system (MDM/parental controls)")
                LoggingService.network.info("   Impact: Camera assistance BLOCKED")
                LoggingService.network.info("   Fallback: Will use compass-based direction")
            }
        }

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Execute all callbacks
        executeCallbacks(authorized: authorized)
    }

    /// Execute all pending callbacks
    private func executeCallbacks(authorized: Bool) {
        LoggingService.network.info("   Executing \(self.permissionCallbacks.count) pending callback(s)...")

        for callback in permissionCallbacks {
            callback(authorized)
        }

        permissionCallbacks.removeAll()
        LoggingService.network.info("   ✓ All callbacks executed")
    }

    // MARK: - Helper Methods

    /// Get human-readable status description
    private func statusDescription(_ status: CMAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "Not Determined"
        case .restricted:
            return "Restricted"
        case .denied:
            return "Denied"
        case .authorized:
            return "Authorized"
        @unknown default:
            return "Unknown (\(status.rawValue))"
        }
    }

    /// Check if permission is currently granted
    var isAuthorized: Bool {
        return CMMotionActivityManager.authorizationStatus() == .authorized
    }

    /// Check if permission can be requested (not denied/restricted)
    var canRequestPermission: Bool {
        let status = CMMotionActivityManager.authorizationStatus()
        return status == .notDetermined
    }
}
