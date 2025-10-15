//
//  LinkFinderSessionManager.swift
//  MeshRed
//
//  Created by Emilio Contreras on 29/09/25.
//

import Foundation
import NearbyInteraction
import MultipeerConnectivity
import Combine
import AVFoundation
import CoreMotion
import ARKit
import os

// MARK: - Supporting Types for Direction Measurement

/// Direction measurement mode - indicates how direction is being calculated
enum DirectionMode {
    case preciseUWB           // UWB + ARKit camera assistance (centimeter-level)
    case approximateCompass   // GPS + Compass fallback (meter-level)
    case unavailable          // No direction measurement possible

    var description: String {
        switch self {
        case .preciseUWB:
            return "🎯 Dirección Precisa (UWB)"
        case .approximateCompass:
            return "🧭 Dirección Aproximada (Brújula)"
        case .unavailable:
            return "❌ Sin Dirección"
        }
    }

    var icon: String {
        switch self {
        case .preciseUWB:
            return "location.fill"
        case .approximateCompass:
            return "compass.fill"
        case .unavailable:
            return "location.slash"
        }
    }
}

/// Manages LinkFinder (Ultra Wideband) ranging sessions with peers using NearbyInteraction framework
/// Provides centimeter-level precision for distance and direction measurements
@available(iOS 14.0, *)
class LinkFinderSessionManager: NSObject, ObservableObject {
    // MARK: - Session State
    enum SessionState: CustomStringConvertible {
        case preparing       // Session created, token extracted, not running yet
        case tokenReady      // Waiting for remote peer's token
        case running         // .run() called, waiting for ranging to establish
        case ranging         // didUpdate received, ranging active
        case suspended       // System suspended LinkFinder
        case disconnected    // Session invalidated

        var description: String {
            switch self {
            case .preparing: return "preparing"
            case .tokenReady: return "tokenReady"
            case .running: return "running"
            case .ranging: return "ranging"
            case .suspended: return "suspended"
            case .disconnected: return "disconnected"
            }
        }
    }

    // MARK: - Device Capabilities
    struct DeviceCapabilities: Codable {
        let deviceModel: String
        let hasUWB: Bool
        let hasU1Chip: Bool
        let hasU2Chip: Bool
        let supportsDistance: Bool
        let supportsDirection: Bool
        let supportsCameraAssist: Bool
        let supportsExtendedRange: Bool
        let osVersion: String

        // Generate a human-readable summary
        var summary: String {
            var features: [String] = []

            if hasUWB {
                if hasU2Chip {
                    features.append("U2 Chip (Ultra-precise)")
                } else if hasU1Chip {
                    features.append("U1 Chip")
                } else {
                    features.append("UWB")
                }
            }

            if supportsDistance && supportsDirection {
                features.append("Distance + Direction")
            } else if supportsDistance {
                features.append("Distance only")
            }

            if supportsCameraAssist {
                features.append("Camera Assist")
            }

            if supportsExtendedRange {
                features.append("Extended Range")
            }

            if features.isEmpty {
                return "No UWB capabilities"
            }

            return features.joined(separator: ", ")
        }

        // Check compatibility with another device
        func isCompatibleWith(_ other: DeviceCapabilities) -> (distance: Bool, direction: Bool) {
            // Distance works if at least one device has UWB
            let distanceCompatible = (self.hasUWB && self.supportsDistance) || (other.hasUWB && other.supportsDistance)

            // Direction requires BOTH devices to have UWB with direction support
            let directionCompatible = (self.hasUWB && self.supportsDirection) && (other.hasUWB && other.supportsDirection)

            return (distance: distanceCompatible, direction: directionCompatible)
        }
    }

    // MARK: - Published Properties
    @Published var activeSessions: [String: NISession] = [:]  // PeerID -> Session
    @Published var nearbyObjects: [String: NINearbyObject] = [:]  // PeerID -> Object
    @Published var isLinkFinderSupported: Bool = false
    @Published var sessionStates: [String: SessionState] = [:]  // PeerID -> State
    @Published var supportsDirectionMeasurement: Bool = false
    @Published var localDeviceCapabilities: DeviceCapabilities?
    @Published var peerCapabilities: [String: DeviceCapabilities] = [:]  // PeerID -> Capabilities
    @Published var directionMode: DirectionMode = .unavailable  // Current direction measurement mode
    @Published var fallbackDirections: [String: FallbackDirection] = [:]  // PeerID -> Fallback direction
    @Published var convergenceReasons: [String] = []  // Current convergence issues
    @Published var isConverging: Bool = false  // True when actively trying to converge
    @Published var directionHints: [String] = []  // UI hints for why direction might be nil

    // MARK: - Fallback & Permission Properties
    var fallbackService: FallbackDirectionService?
    var motionPermissionManager: MotionPermissionManager?
    private var arKitResourceManager: ARKitResourceManager?  // Manages ARKit session for camera assistance
    private var directionNilTimers: [String: Timer] = [:]  // PeerID -> Timer for nil direction detection
    private var directionPermanentlyFailed: Set<String> = []  // PeerIDs where direction failed permanently (don't retry)

    // MARK: - Private Properties
    private var discoveryTokens: [String: NIDiscoveryToken] = [:]  // PeerID -> Remote peer's token
    private var localTokens: [String: NIDiscoveryToken] = [:]  // PeerID -> Our token for this peer
    private let queue = DispatchQueue(label: "com.meshred.linkfinder", qos: .userInitiated)
    private var sessionHealthTimers: [String: Timer] = [:]  // PeerID -> Health check timer
    private var sessionRetryCount: [String: Int] = [:]  // PeerID -> Retry attempt count
    private var lastRestartTime: [String: Date] = [:]  // PeerID -> Last restart timestamp

    // FIXED: Throttling para convergence updates (previene ANR/crash)
    private var lastConvergenceUpdate: Date = .distantPast  // Última actualización de convergence
    private var lastDidUpdateLog: [String: Date] = [:]  // PeerID -> Last log time (THROTTLE logging)

    // MARK: - Throttling State (ANTI-TRABADO)
    private var previousNearbyObjects: [String: NINearbyObject] = [:]  // PeerID -> Previous object (for change detection)

    // MARK: - MultipeerConnectivity Handshake State (NEW)
    // Coordinates handshake state for MC connections to prevent dual-invitation collisions
    private var outboundInviteStartedAt: [String: Date] = [:]  // PeerID -> Timestamp when we started inviting
    private var abandonedOutbound: Set<String> = []  // Peers for which we abandoned our outbound invite (accepted inbound instead)
    private let arbitrationWindowDuration: TimeInterval = 1.2  // 1.2 seconds for collision detection

    // MARK: - App Lifecycle Observers (SUSPENSION RECOVERY)
    private var foregroundObserver: NSObjectProtocol?  // Detects app returning to foreground

    // MARK: - Delegates
    weak var delegate: LinkFinderSessionManagerDelegate?
    weak var networkManager: NetworkManager?  // Reference for GPS location sharing

    // MARK: - Initialization
    override init() {
        super.init()

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔧 LinkFinderSessionManager INITIALIZATION")

        // Check UWB support
        checkUWBSupport()

        // Initialize Motion Permission Manager
        motionPermissionManager = MotionPermissionManager()
        print("   ✓ MotionPermissionManager created")

        // Initialize Fallback Direction Service
        fallbackService = FallbackDirectionService()
        print("   ✓ FallbackDirectionService created")
        print("   Note: Fallback service will start when needed")

        // Initialize ARKit Resource Manager for devices with camera assistance
        if #available(iOS 16.0, *),
           NISession.deviceCapabilities.supportsCameraAssistance {
            arKitResourceManager = ARKitResourceManager()
            print("   ✓ ARKitResourceManager created for camera assistance")
            print("   Note: Will prepare ARKit session when starting UWB")
        }

        // ✅ SUSPENSION RECOVERY: Listen for app returning to foreground
        setupForegroundObserver()

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    deinit {
        // Clean up foreground observer
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - App Lifecycle Management (SUSPENSION RECOVERY)

    /// Setup observer for app returning to foreground
    /// CRITICAL: iOS suspends NISession when app backgrounds - we need to recover automatically
    private func setupForegroundObserver() {
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppReturningToForeground()
        }
        print("   ✅ Foreground observer registered (suspension recovery)")
    }

    /// Handle app returning to foreground after suspension
    private func handleAppReturningToForeground() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔄 APP RETURNED TO FOREGROUND")
        print("   Checking for suspended LinkFinder sessions...")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Wait 2 seconds to see if iOS automatically resumes sessions
        // If sessionSuspensionEnded() gets called, great!
        // If not, we'll force restart
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.resumeSuspendedSessionsIfNeeded()
        }
    }

    /// Force resume any sessions still in .suspended state
    /// BACKGROUND: Sometimes iOS doesn't call sessionSuspensionEnded() if app was background >3 minutes
    /// SOLUTION: Manually check and restart suspended sessions
    func resumeSuspendedSessionsIfNeeded() {
        queue.async { [weak self] in
            guard let self = self else { return }

            var suspendedCount = 0
            var resumedCount = 0

            for (peerId, state) in self.sessionStates {
                if state == .suspended {
                    suspendedCount += 1

                    guard let session = self.activeSessions[peerId],
                          let token = self.discoveryTokens[peerId] else {
                        print("⚠️ Cannot resume \(peerId) - missing session or token")
                        continue
                    }

                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    print("🔄 FORCE RESUMING SUSPENDED SESSION")
                    print("   Peer: \(peerId)")
                    print("   Reason: sessionSuspensionEnded() was not called by iOS")
                    print("   Action: Manually restarting NISession")
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                    // Create configuration
                    let config = NINearbyPeerConfiguration(peerToken: token)

                    // Enable camera assistance if supported
                    if #available(iOS 16.0, *) {
                        if NISession.deviceCapabilities.supportsCameraAssistance {
                            config.isCameraAssistanceEnabled = true
                            print("   ✅ Camera assistance enabled")
                        }
                    }

                    // Restart session
                    session.run(config)
                    resumedCount += 1

                    DispatchQueue.main.async {
                        self.sessionStates[peerId] = .running
                    }

                    print("   ✅ Session restarted - should resume ranging shortly")
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                    // Haptic feedback: session resumed
                    HapticManager.shared.play(.success, priority: .navigation)
                }
            }

            if suspendedCount > 0 {
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("📊 SUSPENSION RECOVERY SUMMARY")
                print("   Total suspended sessions: \(suspendedCount)")
                print("   Successfully resumed: \(resumedCount)")
                print("   Failed to resume: \(suspendedCount - resumedCount)")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            } else {
                print("✅ No suspended sessions found - all good!")
            }
        }
    }

    // MARK: - Public Methods

    /// Check if device supports LinkFinder (NearbyInteraction)
    private func checkUWBSupport() {
        #if targetEnvironment(simulator)
        isLinkFinderSupported = false
        supportsDirectionMeasurement = false
        localDeviceCapabilities = DeviceCapabilities(
            deviceModel: "Simulator",
            hasUWB: false,
            hasU1Chip: false,
            hasU2Chip: false,
            supportsDistance: false,
            supportsDirection: false,
            supportsCameraAssist: false,
            supportsExtendedRange: false,
            osVersion: UIDevice.current.systemVersion
        )
        print("⚠️ LinkFinderSessionManager: LinkFinder not available in simulator")
        #else
        isLinkFinderSupported = NISession.deviceCapabilities.supportsPreciseDistanceMeasurement

        // Detect device model and chip type
        let deviceModel = getDeviceModel()
        let (hasU1, hasU2) = detectUWBChipType(deviceModel: deviceModel)

        if isLinkFinderSupported {
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("📡 LinkFinder DEVICE CAPABILITIES ANALYSIS")
            print("   Device Model: \(deviceModel)")
            print("   iOS Version: \(UIDevice.current.systemVersion)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("   Distance measurement: ✅")

            // Check direction measurement capability
            let nativeDirectionSupport = NISession.deviceCapabilities.supportsDirectionMeasurement
            print("   Direction measurement API: \(nativeDirectionSupport ? "✅" : "❌")")

            // IMPORTANT: Trust Apple's API, not our assumptions
            // - iPhone 11-13: Have multiple UWB antennas, CAN have native direction
            // - iPhone 14 (base): Only 1 antenna, NO direction (confirmed by developers)
            // - iPhone 14 Pro+: Have camera assistance for direction via ARKit
            // The API knows best what each device supports

            // Check for additional capabilities (iOS 16+)
            var supportsCameraAssist = false
            var supportsExtendedRange = false

            if #available(iOS 16.0, *) {
                supportsCameraAssist = NISession.deviceCapabilities.supportsCameraAssistance
                print("   Camera assistance (ARKit): \(supportsCameraAssist ? "✅" : "❌")")
            }

            // Log actual API values for debugging
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("📱 REAL API CAPABILITIES:")
            print("   supportsDirectionMeasurement: \(nativeDirectionSupport)")
            print("   supportsCameraAssistance: \(supportsCameraAssist)")

            // TRUST THE API: If supportsDirectionMeasurement OR supportsCameraAssistance = true,
            // device CAN provide direction (either via hardware or ARKit)
            let effectiveDirectionSupport = nativeDirectionSupport || supportsCameraAssist

            if nativeDirectionSupport && !supportsCameraAssist {
                // iPhone 11-13: Native direction via multiple UWB antennas (U1 chip)
                print("   ✅ Native UWB direction (hardware triangulation)")
                print("   ℹ️ Likely iPhone 11-13 with U1 chip")
                print("   💡 Direction via time-of-flight triangulation")
                print("   ⚡ NO ARKit needed - instant, low power")
            } else if nativeDirectionSupport && supportsCameraAssist {
                // Device with BOTH native + camera assistance (unlikely combo)
                print("   ✅ Native UWB direction + camera assistance available")
                print("   ℹ️ Will prefer native hardware direction")
                print("   💡 ARKit can be used as optional enhancement")
            } else if !nativeDirectionSupport && supportsCameraAssist {
                // iPhone 14 Pro/Max: NO native direction, but camera assistance available
                print("   📱 Direction via camera assistance ONLY")
                print("   ℹ️ Likely iPhone 14 Pro/Max (1 UWB antenna)")
                print("   ⚠️ Requires: Camera + Motion permissions")
                print("   ⚠️ Requires: Device movement for ARKit calibration")
            } else {
                // iPhone 14 base or older devices without direction capability
                print("   ❌ Direction NOT AVAILABLE")
                print("   ℹ️ Device limitation (no native hardware, no camera assist)")
                print("   💡 Will use GPS+Compass fallback for direction")
            }

            print("   Final effectiveDirectionSupport: \(effectiveDirectionSupport)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            supportsDirectionMeasurement = effectiveDirectionSupport

            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("   UWB Chip Detection:")
            if hasU2 {
                print("   ✅ U2 Chip (3rd gen UWB)")
                print("      • Ultra-precise ranging")
                print("      • Extended range support")
                print("      • Lower power consumption")
                supportsExtendedRange = true
            } else if hasU1 {
                print("   ✅ U1 Chip (1st gen UWB)")
                print("      • Standard ranging")
                print("      • Limited to ~9m range")
            } else {
                print("   ⚠️ UWB chip type unknown")
            }
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            // Store capabilities
            localDeviceCapabilities = DeviceCapabilities(
                deviceModel: deviceModel,
                hasUWB: true,
                hasU1Chip: hasU1,
                hasU2Chip: hasU2,
                supportsDistance: true,
                supportsDirection: effectiveDirectionSupport,
                supportsCameraAssist: supportsCameraAssist,
                supportsExtendedRange: supportsExtendedRange,
                osVersion: UIDevice.current.systemVersion
            )

            print("   Summary: \(localDeviceCapabilities!.summary)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            // Check if Nearby Interaction permission is available (iOS 15+)
            if #available(iOS 15.0, *) {
                checkNearbyInteractionPermission()
            }
        } else {
            supportsDirectionMeasurement = false

            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("❌ LinkFinder NOT SUPPORTED")
            print("   Device Model: \(deviceModel)")
            print("   Reason: No UWB chip detected")
            print("   Required: iPhone 11+ with U1/U2 chip")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            localDeviceCapabilities = DeviceCapabilities(
                deviceModel: deviceModel,
                hasUWB: false,
                hasU1Chip: false,
                hasU2Chip: false,
                supportsDistance: false,
                supportsDirection: false,
                supportsCameraAssist: false,
                supportsExtendedRange: false,
                osVersion: UIDevice.current.systemVersion
            )
        }
        #endif
    }

    /// Get the device model name
    private func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { ptr in
                String(cString: ptr)
            }
        }

        // Map model codes to friendly names
        let modelMap: [String: String] = [
            // iPhone models with UWB
            "iPhone12,1": "iPhone 11",
            "iPhone12,3": "iPhone 11 Pro",
            "iPhone12,5": "iPhone 11 Pro Max",
            "iPhone13,1": "iPhone 12 mini",
            "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,4": "iPhone 12 Pro Max",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,5": "iPhone 13",
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone17,1": "iPhone 16",
            "iPhone17,2": "iPhone 16 Plus",
            "iPhone17,3": "iPhone 16 Pro",
            "iPhone17,4": "iPhone 16 Pro Max",
            "iPhone18,1": "iPhone 17",
            "iPhone18,2": "iPhone 17 Plus",
            "iPhone18,3": "iPhone 17 Pro",
            "iPhone18,4": "iPhone 17 Pro Max"
        ]

        return modelMap[modelCode] ?? modelCode
    }

    /// Detect UWB chip type based on device model
    private func detectUWBChipType(deviceModel: String) -> (hasU1: Bool, hasU2: Bool) {
        // U1 Chip devices (first generation UWB)
        let u1Devices = [
            "iPhone 11", "iPhone 11 Pro", "iPhone 11 Pro Max",
            "iPhone 12 mini", "iPhone 12", "iPhone 12 Pro", "iPhone 12 Pro Max",
            "iPhone 13 mini", "iPhone 13", "iPhone 13 Pro", "iPhone 13 Pro Max",
            "iPhone 14", "iPhone 14 Plus"
        ]

        // U2 Chip devices (second generation UWB - more precise, lower power)
        let u2Devices = [
            "iPhone 15", "iPhone 15 Plus", "iPhone 15 Pro", "iPhone 15 Pro Max",
            "iPhone 16", "iPhone 16 Plus", "iPhone 16 Pro", "iPhone 16 Pro Max",
            "iPhone 17", "iPhone 17 Plus", "iPhone 17 Pro", "iPhone 17 Pro Max"
        ]

        if u2Devices.contains(deviceModel) {
            return (hasU1: false, hasU2: true)
        } else if u1Devices.contains(deviceModel) {
            return (hasU1: true, hasU2: false)
        }

        return (hasU1: false, hasU2: false)
    }

    /// Get human-readable description for AVAuthorizationStatus
    private func permissionStatusDescription(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "Authorized"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not Determined"
        @unknown default:
            return "Unknown"
        }
    }

    /// Check and request Nearby Interaction permission if needed
    @available(iOS 15.0, *)
    private func checkNearbyInteractionPermission() {
        // Note: iOS doesn't provide a direct way to check Nearby Interaction permission status
        // The permission dialog will be shown automatically when starting a session
        // We can only detect permission issues when a session fails
        print("📡 LinkFinderSessionManager: Nearby Interaction permission will be requested when needed")

        // Check camera and motion permissions (required for camera assistance on iPhone 14+)
        checkCameraAndMotionPermissions()
    }

    /// Check camera and motion permissions required for camera assistance (iPhone 14+ direction)
    private func checkCameraAndMotionPermissions() {
        #if !targetEnvironment(simulator)
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔐 PERMISSION STATUS CHECK (for Camera Assistance)")

        // Check camera permission
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch cameraStatus {
        case .authorized:
            print("   📷 Camera: ✅ AUTHORIZED")
        case .denied:
            print("   📷 Camera: ❌ DENIED (direction will not work)")
        case .restricted:
            print("   📷 Camera: ⚠️ RESTRICTED (parental controls or MDM)")
        case .notDetermined:
            print("   📷 Camera: ⏳ NOT DETERMINED (will request on first use)")
        @unknown default:
            print("   📷 Camera: ❓ UNKNOWN STATUS")
        }

        // Check motion permission (iOS 15+)
        if #available(iOS 15.0, *) {
            let motionStatus = CMMotionActivityManager.authorizationStatus()
            switch motionStatus {
            case .authorized:
                print("   🏃 Motion: ✅ AUTHORIZED")
            case .denied:
                print("   🏃 Motion: ❌ DENIED (may affect direction accuracy)")
            case .restricted:
                print("   🏃 Motion: ⚠️ RESTRICTED")
            case .notDetermined:
                print("   🏃 Motion: ⏳ NOT DETERMINED (will request on first use)")
            @unknown default:
                print("   🏃 Motion: ❓ UNKNOWN STATUS")
            }
        } else {
            print("   🏃 Motion: ℹ️ Permission check requires iOS 15+")
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        #endif
    }

    /// Prepare a LinkFinder session for a specific peer (step 1 of token exchange)
    /// Creates the session, extracts token, but does NOT run it yet
    /// Returns the token to send to the remote peer
    func prepareSession(for peerID: MCPeerID) -> NIDiscoveryToken? {
        guard isLinkFinderSupported else {
            print("❌ LinkFinderSessionManager: Cannot prepare session - LinkFinder not supported")
            return nil
        }

        let peerId = peerID.displayName

        // Check if session already prepared
        if activeSessions[peerId] != nil,
           let existingToken = localTokens[peerId],
           let state = sessionStates[peerId],
           state == .preparing || state == .tokenReady {
            print("✅ LinkFinderSessionManager: Session already prepared for \(peerId)")
            return existingToken
        }

        // Clean up any stale session COMPLETELY
        if let oldSession = activeSessions[peerId] {
            print("🧹 LinkFinderSessionManager: Cleaning up old session for \(peerId)")
            oldSession.invalidate()

            // CRITICAL: Remove from dictionary to prevent dual sessions
            activeSessions.removeValue(forKey: peerId)
            localTokens.removeValue(forKey: peerId)
            sessionStates.removeValue(forKey: peerId)

            // FIXED: Use dispatch queue for synchronization instead of Thread.sleep
            // This ensures cleanup completes without blocking main thread
            print("   ⏳ Waiting for NISession invalidation to complete (async)...")
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔧 LinkFinder SESSION PREPARATION")
        print("   Peer: \(peerId)")
        print("   Creating session WITHOUT running it")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Create new session for this specific peer
        let session = NISession()
        session.delegate = self
        session.delegateQueue = queue

        // Extract token from THIS session (not running yet)
        guard let token = session.discoveryToken else {
            print("❌ LinkFinderSessionManager: Failed to get discovery token from session")
            return nil
        }

        // Store session and token
        DispatchQueue.main.async {
            self.activeSessions[peerId] = session
            self.localTokens[peerId] = token
            self.sessionStates[peerId] = .preparing
            self.sessionRetryCount[peerId] = 0
        }

        print("✅ LinkFinderSessionManager: Session prepared for \(peerId)")
        print("   Token extracted: \(String(describing: token).prefix(40))...")
        print("   State: preparing")
        print("   Ready to send token to peer")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📡 COMPARTIENDO TOKEN UWB con \(peerId)")
        print("   Este token se enviará al peer para iniciar ranging")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        return token
    }

    /// Start LinkFinder ranging session with a peer (step 2 of token exchange)
    /// Requires that prepareSession() was called first
    /// Now runs the session with the remote peer's token
    func startSession(with peerID: MCPeerID, remotePeerToken: NIDiscoveryToken) {
        guard isLinkFinderSupported else {
            print("❌ LinkFinderSessionManager: Cannot start session - LinkFinder not supported")
            return
        }

        let peerId = peerID.displayName

        queue.async { [weak self] in
            guard let self = self else { return }

            // Verify we have a prepared session
            guard let session = self.activeSessions[peerId] else {
                print("❌ LinkFinderSessionManager: No prepared session found for \(peerId)")
                print("   Call prepareSession() first before startSession()")
                return
            }

            let currentState = self.sessionStates[peerId] ?? .disconnected

            // Check if already running or ranging
            if currentState == .running || currentState == .ranging {
                print("✅ LinkFinderSessionManager: Session already running for \(peerId) (state: \(currentState))")
                return
            }

            // Verify we're in preparing or tokenReady state
            if currentState != .preparing && currentState != .tokenReady {
                print("⚠️ LinkFinderSessionManager: Invalid state \(currentState) for \(peerId), expected .preparing or .tokenReady")
            }

            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("🚀 LinkFinder SESSION START")
            print("   Peer: \(peerId)")
            print("   Remote token: \(String(describing: remotePeerToken).prefix(40))...")
            print("   Our token: \(String(describing: self.localTokens[peerId]).prefix(40))...")
            print("   Previous state: \(currentState)")
            print("   Now executing session.run()")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            // Store remote peer's token
            self.discoveryTokens[peerId] = remotePeerToken

            // Configure and run session with remote peer's token
            let config = NINearbyPeerConfiguration(peerToken: remotePeerToken)

            // Enable camera assistance if available (iOS 16+)
            if #available(iOS 16.0, *) {
                let hasNativeDirection = NISession.deviceCapabilities.supportsDirectionMeasurement
                let supportsCameraAssist = NISession.deviceCapabilities.supportsCameraAssistance

                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("🔍 UWB CAPABILITY DETECTION")
                print("   Device Model: \(getDeviceModel())")
                print("   supportsDirectionMeasurement: \(hasNativeDirection)")
                print("   supportsCameraAssistance: \(supportsCameraAssist)")

                // CHIP DETECTION for Direction Support
                let deviceModel = getDeviceModel()
                let isIPhone17OrNewer = deviceModel.contains("iPhone 17") || deviceModel.contains("iPhone 18")

                // U1 Chip Detection (iPhone 11-13)
                let isU1ChipDevice = deviceModel.contains("iPhone 11") ||
                                     deviceModel.contains("iPhone 12") ||
                                     deviceModel.contains("iPhone 13")

                // U2 Chip Detection (iPhone 15+)
                let isU2ChipDevice = deviceModel.contains("iPhone 15") ||
                                     deviceModel.contains("iPhone 16") ||
                                     isIPhone17OrNewer

                // FIXED: Always enable camera assistance if supported
                // Reason: iOS 16+ may require ARKit even for U1 devices in peer-to-peer sessions
                // Research shows this improves compatibility between U1↔U2 devices
                let needsCameraForDirection = supportsCameraAssist

                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                if needsCameraForDirection {
                    if isU1ChipDevice {
                        print("📱 ENABLING ARKIT FOR U1 CHIP (iPhone 11-13)")
                        print("   Device: \(deviceModel)")
                        print("   Reason: iOS 16+ compatibility + U1↔U2 peer support")
                        print("   Hardware: 3 UWB antennas (native AoA)")
                        print("   Enhancement: ARKit fusion improves precision")
                        print("   ⚠️ Research shows U1 benefits from ARKit in peer sessions")
                    } else if deviceModel.contains("iPhone 14") {
                        print("📱 CAMERA ASSISTANCE REQUIRED (iPhone 14)")
                        print("   Device: \(deviceModel)")
                        print("   Reason: Single UWB antenna (no native direction)")
                        print("   Method: ARKit + UWB fusion")
                    } else if isU2ChipDevice {
                        print("📱 CAMERA ASSISTANCE FOR U2 CHIP (iPhone 15+)")
                        print("   Device: \(deviceModel)")
                        print("   ⚠️ WARNING: U2 chip has known direction regression")
                        print("   See: Apple Developer Forums thread 719378")
                        print("   Activating ARKit to attempt workaround")
                    } else {
                        print("📱 CAMERA ASSISTANCE AVAILABLE")
                        print("   Device: \(deviceModel)")
                        print("   Enabling ARKit for improved direction accuracy")
                    }
                } else {
                    print("⚠️ NO CAMERA ASSISTANCE AVAILABLE")
                    print("   Device: \(deviceModel)")
                    print("   Will attempt UWB-only direction (may not work)")
                    print("   Fallback: GPS + Compass if direction = nil")
                }
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                if needsCameraForDirection {
                    #if !targetEnvironment(simulator)
                    print("   📱 Device REQUIRES camera assistance for direction")
                    print("   Native direction: \(hasNativeDirection) (NO native hardware)")
                    print("   Camera assist available: \(supportsCameraAssist) (Will use ARKit)")

                    // Step 1: Check camera permission
                    let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
                    print("   📷 Camera permission: \(self.permissionStatusDescription(cameraStatus))")

                    // Step 2: Request Motion permission (CRITICAL for ARKit)
                    print("   🏃 Requesting Motion permission for ARKit...")

                    // Initialize motion permission manager if needed
                    if self.motionPermissionManager == nil {
                        self.motionPermissionManager = MotionPermissionManager()
                        print("   📱 Initialized MotionPermissionManager")
                    }

                    self.motionPermissionManager?.requestPermission { [weak self] motionAuthorized in
                        guard let self = self else { return }

                        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        print("🔐 PERMISSION CHECK RESULTS")
                        print("   Camera: \(self.permissionStatusDescription(cameraStatus))")
                        print("   Motion: \(motionAuthorized ? "✅ Authorized" : "❌ Denied/Restricted")")

                        if cameraStatus == .authorized && motionAuthorized {
                            print("   ✅ BOTH permissions granted - camera assistance will work")
                            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                            print("📱 ENABLING CAMERA ASSISTANCE")
                            print("   IMPORTANT: NISession manages ARKit internally")
                            print("   Do NOT create separate ARSession (causes camera conflict)")
                            print("   Error -17281 fixed by letting NISession handle ARKit")
                            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                            // Enable camera assistance - NISession handles ARKit internally
                            config.isCameraAssistanceEnabled = true

                            DispatchQueue.main.async {
                                self.directionMode = .preciseUWB
                            }
                        } else {
                            print("   ⚠️ Missing permissions - activating FALLBACK mode")

                            if cameraStatus != .authorized {
                                print("      ❌ Camera permission missing")
                            }
                            if !motionAuthorized {
                                print("      ❌ Motion permission missing")
                            }

                            print("   Fallback: GPS + Compass direction")
                            config.isCameraAssistanceEnabled = false

                            // Activate fallback immediately
                            DispatchQueue.main.async {
                                self.activateFallbackMode(for: peerId, reason: "Permissions denied")
                            }
                        }

                        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                        // Run session with configured settings
                        session.run(config)

                        DispatchQueue.main.async {
                            self.sessionStates[peerId] = .running
                            print("📡 LinkFinderSessionManager: Session RUNNING for \(peerId)")
                            print("   State: \(currentState) → running")
                            print("   Total active sessions: \(self.activeSessions.count)")
                            print("   Waiting for ranging to establish...")
                        }

                        // Start timer: if direction still nil after 10s → fallback
                        self.startDirectionNilTimer(for: peerId)

                        // Start health monitoring
                        self.startHealthCheck(for: peerId, initialDelay: 15.0)
                    }

                    // Exit early - completion handler will call session.run()
                    return

                    #else
                    config.isCameraAssistanceEnabled = true
                    print("   ✅ Camera assistance ENABLED (simulator)")
                    #endif
                } else {
                    // Camera assistance not supported - will try UWB-only
                    config.isCameraAssistanceEnabled = false

                    print("   ⚠️ Camera assistance NOT supported on this device")
                    print("   Attempting UWB-only direction measurement")
                    print("   Note: May activate fallback mode if direction = nil")

                    // Start timer to detect if direction never arrives
                    self.startDirectionNilTimer(for: peerId)
                }
            }

            session.run(config)

            DispatchQueue.main.async {
                self.sessionStates[peerId] = .running
                print("📡 LinkFinderSessionManager: Session RUNNING for \(peerId)")
                print("   State: preparing → running")
                print("   Total active sessions: \(self.activeSessions.count)")
                print("   Waiting for ranging to establish...")
            }

            // Start health monitoring (give it time to establish ranging)
            self.startHealthCheck(for: peerId, initialDelay: 15.0)
        }
    }

    /// Stop LinkFinder ranging session with a peer
    func stopSession(with peerID: MCPeerID) {
        let peerId = peerID.displayName

        queue.async { [weak self] in
            guard let self = self else { return }

            if let session = self.activeSessions[peerId] {
                session.invalidate()
                self.stopHealthCheck(for: peerId)

                // FIXED: Invalidate direction nil timer to prevent crashes after session closes
                self.directionNilTimers[peerId]?.invalidate()

                DispatchQueue.main.async {
                    self.activeSessions.removeValue(forKey: peerId)
                    self.nearbyObjects.removeValue(forKey: peerId)
                    self.discoveryTokens.removeValue(forKey: peerId)
                    self.localTokens.removeValue(forKey: peerId)
                    self.sessionStates[peerId] = .disconnected
                    self.sessionRetryCount.removeValue(forKey: peerId)
                    self.lastRestartTime.removeValue(forKey: peerId)
                    self.directionNilTimers.removeValue(forKey: peerId)  // FIXED: Also remove from dictionary
                    self.previousNearbyObjects.removeValue(forKey: peerId)  // FIXED: Clean throttling state
                }

                print("📡 LinkFinderSessionManager: Stopped session with \(peerId)")

                // If this was the last session, stop ARKit to free resources
                if self.activeSessions.isEmpty {
                    self.stopARKitResourcesIfNeeded()
                }
            }
        }
    }

    /// Stop ARKit resources when no longer needed
    private func stopARKitResourcesIfNeeded() {
        if #available(iOS 16.0, *),
           let arManager = arKitResourceManager,
           activeSessions.isEmpty {
            print("🔋 Stopping ARKit to free resources (no active UWB sessions)")
            arManager.stopARKitSession()
        }
    }

    // MARK: - Health Monitoring

    private func startHealthCheck(for peerId: String, initialDelay: TimeInterval = 10.0) {
        stopHealthCheck(for: peerId)  // Clear any existing timer

        // First check after initial delay
        DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay) { [weak self] in
            self?.checkSessionHealth(for: peerId)

            // Then continue with regular checks
            let timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
                self?.checkSessionHealth(for: peerId)
            }

            self?.sessionHealthTimers[peerId] = timer
        }
    }

    private func stopHealthCheck(for peerId: String) {
        sessionHealthTimers[peerId]?.invalidate()
        sessionHealthTimers[peerId] = nil
    }

    private func checkSessionHealth(for peerId: String) {
        guard activeSessions[peerId] != nil else {
            stopHealthCheck(for: peerId)
            return
        }

        let state = sessionStates[peerId] ?? .disconnected
        let hasObject = nearbyObjects[peerId] != nil

        print("🏥 LinkFinder Health Check for \(peerId): State=\(state), HasObject=\(hasObject)")

        // Only check health if we're in .running state (not .preparing or .tokenReady)
        // If we're .running but haven't received any objects for a while, try to restart
        if state == .running && !hasObject {
            let retryCount = sessionRetryCount[peerId] ?? 0

            print("⚠️ LinkFinderSessionManager: Session connected but no ranging data for \(peerId) (retry: \(retryCount)/3)")

            // Check backoff: Don't retry too frequently
            if let lastRestart = lastRestartTime[peerId] {
                let backoffDelay = pow(2.0, Double(retryCount)) * 5.0  // 5s, 10s, 20s, 40s...
                let timeSinceLastRestart = Date().timeIntervalSince(lastRestart)

                if timeSinceLastRestart < backoffDelay {
                    print("⏳ LinkFinderSessionManager: Backoff in effect for \(peerId) - waiting \(String(format: "%.1f", backoffDelay - timeSinceLastRestart))s more")
                    return
                }
            }

            // Check if we should restart (limit retries)
            if retryCount < 3 {
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("🔄 LinkFinder SESSION RESTART REQUIRED")
                print("   Peer: \(peerId)")
                print("   Reason: No ranging data received")
                print("   Retry: \(retryCount + 1)/3")
                print("   Action: Requesting bidirectional restart")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                // Increment retry count and record timestamp
                sessionRetryCount[peerId] = retryCount + 1
                lastRestartTime[peerId] = Date()

                // Notify delegate to coordinate restart with peer
                if let delegate = delegate {
                    delegate.uwbSessionManager(self, requestsRestartFor: peerId)
                } else {
                    // Fallback: local restart only (less effective)
                    performLocalSessionRestart(for: peerId)
                }
            } else {
                print("❌ LinkFinderSessionManager: Max restart attempts (3) reached for \(peerId)")
                print("   LinkFinder ranging may not be working on this device pair")
                stopHealthCheck(for: peerId)
            }
        }

        // If we successfully have ranging, reset retry count
        if state == .ranging && hasObject {
            sessionRetryCount[peerId] = 0
            lastRestartTime.removeValue(forKey: peerId)
        }
    }

    /// Perform local session restart (called when coordinated restart is confirmed)
    func performLocalSessionRestart(for peerId: String) {
        guard let session = activeSessions[peerId] else { return }

        print("🔄 LinkFinderSessionManager: Performing local session restart for \(peerId)")

        // Invalidate current session
        session.invalidate()
        activeSessions.removeValue(forKey: peerId)
        sessionStates[peerId] = .disconnected

        // Request fresh token generation from delegate
        // This ensures we get a new token for the restarted session
        if let delegate = delegate {
            delegate.uwbSessionManager(self, needsFreshTokenFor: peerId)
        }
    }

    /// Stop all active sessions
    func stopAllSessions() {
        queue.async { [weak self] in
            guard let self = self else { return }

            for (peerId, session) in self.activeSessions {
                session.invalidate()
                self.stopHealthCheck(for: peerId)
                print("📡 LinkFinderSessionManager: Stopped session with \(peerId)")
            }

            DispatchQueue.main.async {
                self.activeSessions.removeAll()
                self.nearbyObjects.removeAll()
                self.discoveryTokens.removeAll()
                self.localTokens.removeAll()
                self.sessionStates.removeAll()
                self.sessionRetryCount.removeAll()
                self.lastRestartTime.removeAll()
            }

            // Invalidate all health check timers
            for (_, timer) in self.sessionHealthTimers {
                timer.invalidate()
            }
            self.sessionHealthTimers.removeAll()

            // FIXED: Invalidate all direction nil timers
            for (_, timer) in self.directionNilTimers {
                timer.invalidate()
            }
            self.directionNilTimers.removeAll()

            // Stop ARKit to free all resources
            self.stopARKitResourcesIfNeeded()
        }
    }

    /// Get current distance to a peer (if available)
    func getDistance(to peerID: MCPeerID) -> Float? {
        let peerId = peerID.displayName
        let dist = nearbyObjects[peerId]?.distance

        // Log occasionally for debugging
        if Int.random(in: 0..<120) == 0 {
            LoggingService.network.info("📏 LinkFinderSessionManager.getDistance(\(peerId)) → \(dist?.description ?? "nil")")
        }

        return dist
    }

    /// Get current direction to a peer (if available)
    func getDirection(to peerID: MCPeerID) -> SIMD3<Float>? {
        let peerId = peerID.displayName
        let dir = nearbyObjects[peerId]?.direction

        // Log occasionally for debugging
        if Int.random(in: 0..<120) == 0 {
            if let dir = dir {
                LoggingService.network.info("🧭 LinkFinderSessionManager.getDirection(\(peerId)) → SIMD3(x:\(dir.x), y:\(dir.y), z:\(dir.z))")
            } else {
                LoggingService.network.info("🧭 LinkFinderSessionManager.getDirection(\(peerId)) → NIL")
                LoggingService.network.info("   nearbyObject exists: \(self.nearbyObjects[peerId] != nil)")
                if self.nearbyObjects[peerId] != nil {
                    LoggingService.network.info("   ⚠️ Object exists but direction is nil - check device capabilities or ARKit convergence")
                }
            }
        }

        return dir
    }

    /// Check if we have an active LinkFinder session with a peer
    func hasActiveSession(with peerID: MCPeerID) -> Bool {
        return activeSessions[peerID.displayName] != nil
    }

    /// Get detailed LinkFinder status for debugging
    func getUWBStatus(for peerID: MCPeerID) -> String {
        let peerId = peerID.displayName
        let hasSession = activeSessions[peerId] != nil
        let state = sessionStates[peerId] ?? .disconnected
        let hasObject = nearbyObjects[peerId] != nil
        let distance = nearbyObjects[peerId]?.distance

        var status = "LinkFinder Status for \(peerId):\n"
        status += "  • Session: \(hasSession ? "✅" : "❌")\n"
        status += "  • State: \(state)\n"
        status += "  • Ranging: \(hasObject ? "✅" : "❌")\n"
        if let distance = distance {
            status += "  • Distance: \(String(format: "%.2f", distance))m\n"
        } else {
            status += "  • Distance: N/A\n"
        }

        return status
    }

    /// Force restart session with peer (for debugging)
    func forceRestartSession(with peerID: MCPeerID) {
        let peerId = peerID.displayName

        print("⚡ LinkFinderSessionManager: Force restarting session with \(peerId)")

        // Stop existing session
        if let session = activeSessions[peerId] {
            session.invalidate()
        }

        // Clear state
        activeSessions.removeValue(forKey: peerId)
        sessionStates.removeValue(forKey: peerId)
        nearbyObjects.removeValue(forKey: peerId)
        stopHealthCheck(for: peerId)

        // If we have a token, restart immediately
        if let token = discoveryTokens[peerId] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                let mcPeer = MCPeerID(displayName: peerId)
                self.startSession(with: mcPeer, remotePeerToken: token)
            }
        }
    }

    /// Get relative location info for a peer (for triangulation)
    func getRelativeLocationInfo(for peerID: MCPeerID, intermediaryLocation: UserLocation) -> RelativeLocation? {
        let peerId = peerID.displayName

        guard let nearbyObject = nearbyObjects[peerId],
              let distance = nearbyObject.distance else {
            return nil
        }

        let direction = nearbyObject.direction.map { DirectionVector(from: $0) }

        // Determine accuracy based on LinkFinder quality
        // LinkFinder is typically accurate to ±0.1-0.5 meters
        let accuracy: Float = 0.5

        return RelativeLocation(
            intermediaryId: "", // Will be filled by caller
            intermediaryLocation: intermediaryLocation,
            targetDistance: distance,
            targetDirection: direction,
            accuracy: accuracy
        )
    }

    // MARK: - Capability Management

    /// Get local device capabilities
    func getLocalCapabilities() -> DeviceCapabilities? {
        return localDeviceCapabilities
    }

    /// Store peer's capabilities
    func setPeerCapabilities(_ capabilities: DeviceCapabilities, for peerID: MCPeerID) {
        let peerId = peerID.displayName
        DispatchQueue.main.async {
            self.peerCapabilities[peerId] = capabilities
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("📱 PEER CAPABILITIES RECEIVED")
            print("   Peer: \(peerId)")
            print("   Device: \(capabilities.deviceModel)")
            print("   Capabilities: \(capabilities.summary)")

            // Check compatibility with our device
            if let localCaps = self.localDeviceCapabilities {
                let compatibility = localCaps.isCompatibleWith(capabilities)
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("🔄 COMPATIBILITY CHECK")
                print("   Local: \(localCaps.deviceModel)")
                print("   Remote: \(capabilities.deviceModel)")
                print("   Distance: \(compatibility.distance ? "✅ Compatible" : "❌ Not compatible")")
                print("   Direction: \(compatibility.direction ? "✅ Compatible" : "❌ Requires both devices to have UWB")")

                // Detect U2 chip regression (iPhone 15/16/17)
                let isU2Device = capabilities.deviceModel.contains("iPhone 15") ||
                                capabilities.deviceModel.contains("iPhone 16") ||
                                capabilities.deviceModel.contains("iPhone 17") ||
                                capabilities.deviceModel.contains("iPhone 18")

                if isU2Device {
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    print("⚠️ U2 CHIP REGRESSION DETECTED")
                    print("   Peer device: \(capabilities.deviceModel)")
                    print("   Known issue: U2 chips may return direction = nil")
                    print("   Source: Apple Developer Forums thread 719378 (2024)")
                    print("   Impact: Distance works ✅, Direction may fail ❌")
                    print("   Mitigation: Will activate GPS+Compass fallback faster")
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                    // Activate fallback mode proactively for U2 peers
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                        guard let self = self else { return }
                        // Only activate if direction is still nil after 3 seconds
                        if self.nearbyObjects[peerId]?.direction == nil {
                            print("⚠️ U2 peer (\(capabilities.deviceModel)) has no direction after 3s")
                            print("   Activating GPS+Compass fallback due to U2 regression")
                            self.activateFallbackMode(for: peerId, reason: "U2 chip direction regression")
                        }
                    }
                }

                if !compatibility.direction && localCaps.hasUWB && !capabilities.hasUWB {
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    print("⚠️ HARDWARE LIMITATION DETECTED")
                    print("   \(capabilities.deviceModel) does not have UWB chip")
                    print("   Direction measurement not available")
                    print("   Distance-only mode will be used")
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                } else if !compatibility.direction && !localCaps.hasUWB && capabilities.hasUWB {
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    print("⚠️ HARDWARE LIMITATION DETECTED")
                    print("   Your device (\(localCaps.deviceModel)) lacks UWB chip")
                    print("   Direction measurement not available")
                    print("   Distance-only mode will be used")
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                }
            }
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        }
    }

    /// Get compatibility status with a peer
    func getCompatibilityStatus(with peerID: MCPeerID) -> (distance: Bool, direction: Bool)? {
        let peerId = peerID.displayName
        guard let localCaps = localDeviceCapabilities,
              let peerCaps = peerCapabilities[peerId] else {
            return nil
        }

        return localCaps.isCompatibleWith(peerCaps)
    }

    /// Check if direction is available for a specific peer
    func isDirectionAvailable(for peerID: MCPeerID) -> Bool {
        let compatibility = getCompatibilityStatus(with: peerID)
        return compatibility?.direction ?? false
    }

    // MARK: - Fallback Direction Management

    /// Activate compass-based fallback direction mode
    private func activateFallbackMode(for peerId: String, reason: String) {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🧭 ACTIVATING FALLBACK DIRECTION MODE")
        print("   Peer: \(peerId)")
        print("   Reason: \(reason)")
        print("   Method: GPS + Compass bearing")
        print("")
        print("   📊 Device Capabilities Summary:")
        if let localCaps = localDeviceCapabilities {
            print("      Local Device: \(localCaps.deviceModel)")
            print("      Supports Direction: \(localCaps.supportsDirection)")
            print("      Has Camera Assist: \(localCaps.supportsCameraAssist)")
        }
        if let peerCaps = peerCapabilities[peerId] {
            print("      Peer Device: \(peerCaps.deviceModel)")
            print("      Supports Direction: \(peerCaps.supportsDirection)")
        }
        print("")
        print("   🔄 Switching direction mode: \(directionMode) → approximateCompass")

        directionMode = .approximateCompass

        // Start fallback service if not already running
        if fallbackService?.isCompassAvailable == true {
            fallbackService?.startTracking()
            print("   ✅ FallbackDirectionService started")
        } else {
            print("   ⚠️ Compass not available - fallback limited")
        }

        // Start GPS location sharing with peer for fallback direction calculation
        if let peerID = activeSessions.keys.first(where: { $0 == peerId }) {
            if let mcPeerID = networkManager?.connectedPeers.first(where: { $0.displayName == peerID }) {
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("📍 COMPARTIENDO MI UBICACIÓN GPS con \(peerId)")
                print("   🔄 Starting GPS location sharing with peer...")
                print("   Modo: Fallback direction (UWB + GPS + Compass)")
                print("   Frecuencia: Cada vez que cambia mi ubicación")
                networkManager?.startGPSLocationSharingForLinkFinder(with: mcPeerID)
                print("   ✅ GPS sharing iniciado - enviando ubicación activamente")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            } else {
                print("   ⚠️ Peer not found in NetworkManager - GPS sharing delayed")
            }
        }

        print("   💡 USER ACTION:")
        print("      - Ensure Location Services enabled")
        print("      - Hold device flat for compass accuracy")
        print("      - Move outdoors for better GPS signal")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    /// Start timer to detect persistent nil direction
    /// IMPORTANT: If direction is nil on first update, mark as permanently failed
    private func startDirectionNilTimer(for peerId: String) {
        // DON'T retry if already marked as permanently failed
        if directionPermanentlyFailed.contains(peerId) {
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("⏸️ SKIPPING DIRECTION RETRY")
            print("   Peer: \(peerId)")
            print("   Reason: Direction permanently failed (won't retry)")
            print("   Using GPS+Compass permanently")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            return
        }

        // Shorter timeout - mark as failed faster
        let timeout: TimeInterval = 2.0  // Only 2 seconds to fail permanently

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("⏱️ STARTING DIRECTION CHECK (PERMANENT)")
        print("   Peer: \(peerId)")
        print("   Timeout: \(timeout) seconds")
        print("   If nil after \(timeout)s → PERMANENTLY FAILED (no retries)")
        print("   Purpose: Single attempt to get direction, then give up")

        // Check current state
        if let object = nearbyObjects[peerId] {
            print("   Current distance: \(object.distance?.description ?? "nil")")
            print("   Current direction: \(object.direction != nil ? "AVAILABLE" : "NIL")")
        } else {
            print("   No nearby object yet (waiting for first update)")
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Cancel existing timer if any
        directionNilTimers[peerId]?.invalidate()

        // Create new timer with adaptive timeout
        let timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.checkDirectionNilTimeout(for: peerId)
        }

        directionNilTimers[peerId] = timer
    }

    /// Check if direction is still nil after timeout
    /// If nil, mark as permanently failed and never try again
    private func checkDirectionNilTimeout(for peerId: String) {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("⏱️ DIRECTION CHECK (2 SECONDS ELAPSED)")
        print("   Peer: \(peerId)")
        print("   This is the ONLY check - if nil, permanent failure")

        guard let object = nearbyObjects[peerId] else {
            print("   ⚠️ No nearby object found")
            print("   Reason: Session may not have established ranging yet")
            print("   Action: No fallback activation (waiting for ranging)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            return
        }

        print("   Distance available: \(object.distance?.description ?? "nil")")
        print("   Direction available: \(object.direction != nil ? "YES" : "NO")")

        if object.direction == nil {
            print("   ❌ DIRECTION NIL - MARKING AS PERMANENTLY FAILED")
            print("   This device cannot provide direction to peer: \(peerId)")
            print("   Will NOT retry - switching to GPS+Compass permanently")

            // Mark as permanently failed - NEVER try again
            directionPermanentlyFailed.insert(peerId)

            print("")
            print("   🔄 ACTIVATING PERMANENT FALLBACK MODE")
            print("   Method: GPS + Compass (no retries)")
            print("   Reason: Direction not available on first attempt")
            activateFallbackMode(for: peerId, reason: "Direction permanently unavailable")
        } else {
            print("   ✅ DIRECTION NOW AVAILABLE!")
            print("   Direction: x=\(object.direction!.x), y=\(object.direction!.y), z=\(object.direction!.z)")
            print("   Switching to precise UWB mode")
            directionMode = .preciseUWB
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Clean up timer
        directionNilTimers.removeValue(forKey: peerId)
    }

    // MARK: - MultipeerConnectivity Handshake Coordination (NEW)

    /// Mark that we've started an outbound invitation to a peer
    /// Used for arbitration window detection
    func markOutboundInviteStarted(for peerID: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.outboundInviteStartedAt[peerID] = Date()
            print("🔵 HandshakeCoordinator: Outbound invite STARTED to \(peerID) at \(Date())")
        }
    }

    /// Mark that we've abandoned our outbound invitation (accepted inbound instead)
    func markOutboundInviteAbandoned(for peerID: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.abandonedOutbound.insert(peerID)
            print("⚠️ HandshakeCoordinator: Outbound invite ABANDONED for \(peerID) (accepted inbound instead)")
        }
    }

    /// Check if an inbound invitation is within the arbitration window
    /// Returns true if we started an outbound invite recently (within 1.2s)
    func isWithinArbitrationWindow(for peerID: String) -> Bool {
        return queue.sync {
            guard let startTime = self.outboundInviteStartedAt[peerID] else {
                return false  // No outbound invite in progress
            }

            let elapsed = Date().timeIntervalSince(startTime)
            let isWithin = elapsed <= self.arbitrationWindowDuration

            if isWithin {
                print("⏱️ HandshakeCoordinator: Inbound invitation from \(peerID) is WITHIN arbitration window")
                print("   Elapsed: \(String(format: "%.3f", elapsed))s / \(self.arbitrationWindowDuration)s")
            }

            return isWithin
        }
    }

    /// Check if we abandoned an outbound invite for this peer
    func didAbandonOutbound(for peerID: String) -> Bool {
        return queue.sync {
            return self.abandonedOutbound.contains(peerID)
        }
    }

    /// Clear handshake state for a peer (call when connection established or definitively failed)
    func clearHandshakeState(for peerID: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.outboundInviteStartedAt.removeValue(forKey: peerID)
            self.abandonedOutbound.remove(peerID)
            print("🧹 HandshakeCoordinator: Cleared handshake state for \(peerID)")
        }
    }

    /// Update peer GPS location for fallback direction calculation
    /// Called when NetworkManager receives GPS location from peer
    func updatePeerGPSLocation(_ location: CLLocation, for peerID: MCPeerID) {
        let peerId = peerID.displayName

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📍 RECIBIENDO UBICACIÓN GPS de \(peerId)")
        print("   El peer está compartiendo su ubicación conmigo")
        print("   Latitude: \(location.coordinate.latitude)")
        print("   Longitude: \(location.coordinate.longitude)")
        print("   Accuracy: \(location.horizontalAccuracy)m")
        print("   Timestamp: \(location.timestamp)")

        // Update fallback service with peer location
        fallbackService?.updatePeerLocation(location, for: peerId)

        // Get calculated direction
        if let fallbackDir = fallbackService?.fallbackDirections[peerId] {
            fallbackDirections[peerId] = fallbackDir

            let arrow = fallbackService?.getDirectionArrow(for: peerId) ?? "?"

            print("   🧭 Calculated fallback direction:")
            print("      Bearing: \(fallbackDir.bearing)°")
            print("      Arrow: \(arrow)")
            print("      Distance: \(String(format: "%.1f", fallbackDir.distance))m")
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    // MARK: - Throttling Helper (ANTI-TRABADO)

    /// Detecta si hubo un cambio SIGNIFICATIVO entre el objeto anterior y el nuevo
    /// Solo actualizamos @Published si el cambio es relevante para la UI
    /// OBJETIVO: Reducir actualizaciones de 30/seg → 2-3/seg
    private func hasSignificantChange(previous: NINearbyObject?, new: NINearbyObject) -> Bool {
        guard let prev = previous else {
            return true  // Primer update siempre es significativo
        }

        // DISTANCIA: Cambio significativo si >10cm (0.1m)
        let distanceThreshold: Float = 0.1
        let prevDistance = prev.distance ?? 0.0
        let newDistance = new.distance ?? 0.0
        let distanceChanged = abs(newDistance - prevDistance) > distanceThreshold

        // DIRECCIÓN: Cambio significativo si cualquier componente cambió >0.087 radianes (~5°)
        let directionThreshold: Float = 0.087
        var directionChanged = false

        if let prevDir = prev.direction, let newDir = new.direction {
            // Ambos tienen dirección - comparar componentes
            let xChanged = abs(newDir.x - prevDir.x) > directionThreshold
            let yChanged = abs(newDir.y - prevDir.y) > directionThreshold
            let zChanged = abs(newDir.z - prevDir.z) > directionThreshold
            directionChanged = xChanged || yChanged || zChanged
        } else if prev.direction == nil && new.direction != nil {
            // Dirección apareció (nil → valor)
            directionChanged = true
        } else if prev.direction != nil && new.direction == nil {
            // Dirección desapareció (valor → nil)
            directionChanged = true
        }
        // Si ambos son nil, directionChanged = false (sin cambio)

        return distanceChanged || directionChanged
    }
}

// MARK: - NISessionDelegate
@available(iOS 14.0, *)
extension LinkFinderSessionManager: NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        // Find which peer this session belongs to
        guard let peerId = activeSessions.first(where: { $0.value === session })?.key else {
            // No logging here - this delegate fires 10-30 times/second
            return
        }

        // CRITICAL: THROTTLE LOGGING to prevent I/O saturation and ANR
        // didUpdate fires 10-30 times/second → 600+ print()/second → Main thread ANR
        let now = Date()
        let lastLog = lastDidUpdateLog[peerId] ?? .distantPast
        let shouldLog = now.timeIntervalSince(lastLog) >= 2.0  // Log every 2 seconds max

        if shouldLog {
            lastDidUpdateLog[peerId] = now
            print("🎯 LinkFinderSessionManager: didUpdate called for \(peerId) with \(nearbyObjects.count) objects")
        }

        // Track if this is first update
        let isFirstUpdate = self.nearbyObjects[peerId] == nil
        let previousState = sessionStates[peerId] ?? .disconnected

        // Update nearby object for this peer
        if let object = nearbyObjects.first {
            // THROTTLED logging - only log every 2 seconds
            if shouldLog {
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("📊 LinkFinder UPDATE DETAILS")
                print("   Peer: \(peerId)")
                print("   Distance: \(object.distance?.description ?? "nil")")
            }

            if let dir = object.direction {
                if shouldLog {
                    // Calculate bearing for debugging
                    let bearing = atan2(Double(dir.x), Double(-dir.z)) * 180.0 / .pi
                    let normalizedBearing = bearing >= 0 ? bearing : bearing + 360.0
                    print("   Direction SIMD: x=\(dir.x), y=\(dir.y), z=\(dir.z)")
                    print("   Direction Bearing: \(Int(normalizedBearing))° (calculated from SIMD)")

                    // Cardinal direction
                    let cardinalDir: String
                    switch normalizedBearing {
                    case 337.5..<360.0, 0..<22.5: cardinalDir = "Norte"
                    case 22.5..<67.5: cardinalDir = "Noreste"
                    case 67.5..<112.5: cardinalDir = "Este"
                    case 112.5..<157.5: cardinalDir = "Sureste"
                    case 157.5..<202.5: cardinalDir = "Sur"
                    case 202.5..<247.5: cardinalDir = "Suroeste"
                    case 247.5..<292.5: cardinalDir = "Oeste"
                    case 292.5..<337.5: cardinalDir = "Noroeste"
                    default: cardinalDir = "Desconocido"
                    }
                    print("   Direction Cardinal: \(cardinalDir)")
                }
            } else {
                // Direction is NIL - log only when throttle allows
                if shouldLog {
                    print("   Direction: ❌ NIL")
                    print("   ⚠️ DIRECTION IS NIL - INVESTIGATING WHY:")

                    // Check device capabilities
                    if let localCaps = localDeviceCapabilities {
                        print("      • Local device supports direction: \(localCaps.supportsDirection)")
                        print("      • Device model: \(localCaps.deviceModel)")
                        print("      • Has camera assist: \(localCaps.supportsCameraAssist)")
                    }

                    // Check peer capabilities
                    if let peerCaps = peerCapabilities[peerId] {
                        print("      • Peer device supports direction: \(peerCaps.supportsDirection)")
                        print("      • Peer model: \(peerCaps.deviceModel)")

                        // Check compatibility
                        if let compatibility = getCompatibilityStatus(with: MCPeerID(displayName: peerId)) {
                            print("      • Direction compatibility: \(compatibility.direction ? "✅ COMPATIBLE" : "❌ INCOMPATIBLE")")
                            if !compatibility.direction {
                                print("      • ⚠️ BOTH devices need UWB direction support for direction to work")
                            }
                        }
                    } else {
                        print("      • ⚠️ Peer capabilities not yet received")
                    }

                    // Check device orientation (FOV requirement)
                    let deviceOrientation = UIDevice.current.orientation
                    print("      • Device orientation: \(deviceOrientation.description)")

                    if !deviceOrientation.isPortrait && deviceOrientation != .unknown {
                        print("      • ⚠️ NON-PORTRAIT orientation detected")
                        print("      • Requirement: Both devices should be in PORTRAIT")
                    }

                    // Check ARKit convergence state
                    print("      • Direction mode: \(directionMode.description)")
                    if isConverging {
                        print("      • 🔄 ARKit is CONVERGING (not ready yet)")
                        print("      • Convergence reasons: \(convergenceReasons)")
                    } else {
                        print("      • ARKit convergence: Not converging (either converged or not using ARKit)")
                    }

                    // Field of View (FOV) reminder
                    print("      • 📱 FOV Requirement:")
                    print("      • Both devices must POINT AT EACH OTHER")
                    print("      • FOV = Ultra Wide camera cone (~120° from back)")
                    print("      • Outside FOV: Distance ✅, Direction ❌")
                }

                // Build UI hints (do this even if not logging - UI needs updates)
                let deviceOrientation = UIDevice.current.orientation
                var hints: [String] = []

                if !deviceOrientation.isPortrait && deviceOrientation != .unknown {
                    hints.append("Sostén el iPhone en modo vertical (portrait)")
                }

                if isConverging {
                    hints.append(contentsOf: convergenceReasons)
                }

                hints.append("Apunta tu iPhone hacia el otro dispositivo")

                // Check for U2 peer
                if let peerCaps = peerCapabilities[peerId] {
                    let isU2 = peerCaps.deviceModel.contains("iPhone 15") ||
                              peerCaps.deviceModel.contains("iPhone 16") ||
                              peerCaps.deviceModel.contains("iPhone 17")

                    if isU2 {
                        hints.append("⚠️ El otro dispositivo tiene un chip U2 (puede tener limitaciones)")
                    }
                }

                // Update published hints for UI (always update, regardless of logging)
                DispatchQueue.main.async {
                    self.directionHints = hints
                }
            }

            if shouldLog {
                print("   IsFirstUpdate: \(isFirstUpdate)")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            }

            // ✅ THROTTLING: Solo actualizar @Published si el cambio es significativo
            // OBJETIVO: Reducir actualizaciones de 30/seg → 2-3/seg
            let previousObject = self.previousNearbyObjects[peerId]
            let shouldUpdate = hasSignificantChange(previous: previousObject, new: object)

            if shouldUpdate {
                // Guardar objeto actual como "previous" para próxima comparación
                self.previousNearbyObjects[peerId] = object

                DispatchQueue.main.async {
                    self.nearbyObjects[peerId] = object

                    if shouldLog {
                        print("✅ PUBLISHED nearbyObjects update (SIGNIFICANT CHANGE detected)")
                        if let prev = previousObject {
                            if let prevDist = prev.distance, let newDist = object.distance {
                                let distDelta = abs(newDist - prevDist)
                                print("   Distance change: \(String(format: "%.3f", distDelta))m")
                            }
                        }
                    }

                    // Transition to .ranging state when we receive ranging data
                    if self.sessionStates[peerId] != .ranging {
                        self.sessionStates[peerId] = .ranging
                        if shouldLog {
                            print("✅ Published sessionStates update: \(previousState) → ranging")
                        }
                        // Reset retry count since ranging is working
                        self.sessionRetryCount[peerId] = 0
                        self.lastRestartTime.removeValue(forKey: peerId)
                    }
                }
            } else if shouldLog {
                print("⏭️ SKIPPED nearbyObjects update (no significant change)")
                if let prev = previousObject {
                    if let prevDist = prev.distance, let newDist = object.distance {
                        let distDelta = abs(newDist - prevDist)
                        print("   Distance delta: \(String(format: "%.3f", distDelta))m (<0.1m threshold)")
                    }
                }
            }

            // ALWAYS log first update (important milestone)
            if isFirstUpdate {
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("🎉 LinkFinder RANGING ESTABLISHED")
                print("   Peer: \(peerId)")
                print("   State transition: \(previousState) → ranging")
                print("   First ranging data received!")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                // Haptic feedback: ranging established
                HapticManager.shared.play(.success, priority: .navigation)
            }

            if let distance = object.distance {
                if shouldLog {
                    let directionString = object.direction != nil ? "with direction" : "no direction"
                    print("📡 LinkFinder: \(peerId) - \(String(format: "%.2f", distance))m (\(directionString))")
                }
            } else if shouldLog {
                print("⚠️ LinkFinderSessionManager: Object detected but no distance for \(peerId)")
            }

            // Check if direction became available (switch from fallback to precise UWB)
            if object.direction != nil && directionMode == .approximateCompass {
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("🎯 DIRECTION NOW AVAILABLE - SWITCHING TO PRECISE UWB")
                print("   Peer: \(peerId)")
                print("   Previous mode: 🧭 Fallback (Compass)")
                print("   New mode: 🎯 Precise (UWB + ARKit)")

                DispatchQueue.main.async {
                    self.directionMode = .preciseUWB
                    self.directionHints = []  // Clear hints when direction is available
                }

                // Stop GPS location sharing since we have precise direction now
                if let mcPeerID = networkManager?.connectedPeers.first(where: { $0.displayName == peerId }) {
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    print("📍 DETENIENDO COMPARTIR UBICACIÓN GPS con \(peerId)")
                    print("   Razón: UWB direction ahora disponible (más preciso)")
                    print("   ✅ Ahorrando batería - GPS ya no necesario")
                    networkManager?.stopGPSLocationSharingForLinkFinder(with: mcPeerID)
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                }

                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            }

            // Notify delegate
            delegate?.uwbSessionManager(self, didUpdateDistanceTo: peerId, distance: object.distance, direction: object.direction)
        } else {
            print("⚠️ LinkFinderSessionManager: didUpdate called but no objects in array for \(peerId)")
        }
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        // Find which peer this session belongs to
        guard let peerId = activeSessions.first(where: { $0.value === session })?.key else {
            return
        }

        DispatchQueue.main.async {
            self.nearbyObjects.removeValue(forKey: peerId)
            self.sessionStates[peerId] = .running  // Still running but not ranging
        }

        print("⚠️ LinkFinderSessionManager: Lost tracking of \(peerId) - Reason: \(reason.description)")

        // Haptic feedback: lost tracking
        HapticManager.shared.play(.warning, priority: .navigation)

        // Notify delegate
        delegate?.uwbSessionManager(self, didLoseTrackingOf: peerId, reason: reason)
    }

    func sessionWasSuspended(_ session: NISession) {
        guard let peerId = activeSessions.first(where: { $0.value === session })?.key else {
            return
        }

        DispatchQueue.main.async {
            self.sessionStates[peerId] = .suspended
        }

        print("⏸️ LinkFinderSessionManager: Session suspended for \(peerId)")
        print("   Suspension reason: System suspended LinkFinder ranging (app backgrounded, device locked, or low power)")
    }

    func sessionSuspensionEnded(_ session: NISession) {
        guard let peerId = activeSessions.first(where: { $0.value === session })?.key else {
            return
        }

        print("▶️ LinkFinderSessionManager: Session resumed for \(peerId)")
        print("   Session ready to continue ranging")

        DispatchQueue.main.async {
            self.sessionStates[peerId] = .running
        }

        // Try to restart ranging if we have the token
        if let token = discoveryTokens[peerId] {
            print("   Attempting to restart ranging...")
            let config = NINearbyPeerConfiguration(peerToken: token)

            // Enable camera assistance if supported
            if #available(iOS 16.0, *) {
                if NISession.deviceCapabilities.supportsCameraAssistance {
                    config.isCameraAssistanceEnabled = true
                    print("   ✅ Camera assistance enabled for session resume")
                }
            }

            session.run(config)
        }
    }

    // MARK: - Algorithm Convergence Monitoring (iOS 16+)

    /// Called when camera assistance algorithm convergence status updates
    /// Helps understand WHY direction is nil and what user needs to do
    @available(iOS 16.0, *)
    func session(_ session: NISession, didUpdateAlgorithmConvergence convergence: NIAlgorithmConvergence, for object: NINearbyObject?) {
        // FIXED: THROTTLE convergence updates to prevent ANR/crash
        // Este método se llama 60 veces/segundo durante ranging, causando:
        // - 300+ print() statements por segundo (I/O blocking)
        // - 60 UI updates por segundo (main thread saturation)
        // - Eventual ANR → iOS Watchdog SIGKILL
        let now = Date()
        let timeSinceLastUpdate = now.timeIntervalSince(lastConvergenceUpdate)

        // Solo procesar 1 update por segundo (98.3% reducción de carga)
        guard timeSinceLastUpdate >= 1.0 else {
            // Skip este update silenciosamente
            return
        }

        // Actualizar timestamp
        lastConvergenceUpdate = now

        // Find which peer this session belongs to
        guard let peerId = activeSessions.first(where: { $0.value === session })?.key else {
            print("⚠️ LinkFinderSessionManager: didUpdateAlgorithmConvergence called but no matching session found")
            return
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📊 ALGORITHM CONVERGENCE UPDATE (throttled to 1/sec)")
        print("   Peer: \(peerId)")
        print("   Timestamp: \(Date())")
        print("   Object distance: \(object?.distance?.description ?? "nil")")
        print("   Object direction: \(object?.direction != nil ? "available" : "NIL")")

        switch convergence.status {
        case .converged:
            print("   Status: ✅ CONVERGED")
            print("   Impact: Direction should be available now")
            print("   Camera assistance: Fully calibrated")

            // Update direction mode if we were waiting
            if directionMode == .unavailable || directionMode == .approximateCompass {
                print("   🎯 Switching from \(directionMode) → preciseUWB")
                DispatchQueue.main.async {
                    self.directionMode = .preciseUWB
                }
            }

            // Clear convergence issues and update state
            DispatchQueue.main.async {
                self.convergenceReasons = []
                self.isConverging = false
            }

        case .notConverged(let reasons):
            print("   Status: ⚠️ NOT CONVERGED")
            print("   Reasons count: \(reasons.count)")
            print("   Impact: Direction will be NIL until converged")

            // Set to unavailable mode if not already in fallback
            if directionMode == .preciseUWB || directionMode == .unavailable {
                DispatchQueue.main.async {
                    self.directionMode = .unavailable
                }
            }

            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            // Collect convergence reasons for UI display
            var reasonStrings: [String] = []

            for (index, reason) in reasons.enumerated() {
                print("   Reason #\(index + 1):")

                switch reason {
                case .insufficientMovement:
                    print("      ❌ INSUFFICIENT MOVEMENT")
                    print("      Problem: Device is too still")
                    print("      Solution: Move the iPhone around")
                    print("      Details: ARKit needs motion to calibrate world tracking")

                    // Check for ARKit resource constraints
                    if #available(iOS 16.0, *),
                       let arManager = self.arKitResourceManager,
                       !arManager.resourceConstraints.isEmpty {
                        print("      ⚠️ ARKit Resource Constraints Detected:")
                        for constraint in arManager.resourceConstraints {
                            print("         • \(constraint)")
                        }
                        reasonStrings.append("Mueve tu iPhone (recursos limitados)")
                    } else {
                        reasonStrings.append("Mueve tu iPhone en figura de 8")
                    }

                case .insufficientHorizontalSweep:
                    print("      ❌ INSUFFICIENT HORIZONTAL SWEEP")
                    print("      Problem: Not enough horizontal camera movement")
                    print("      Solution: Move iPhone left-right / side-to-side")
                    print("      Details: ARKit needs horizontal motion to understand environment")
                    reasonStrings.append("Mueve horizontalmente (izquierda-derecha)")

                case .insufficientVerticalSweep:
                    print("      ❌ INSUFFICIENT VERTICAL SWEEP")
                    print("      Problem: Not enough vertical camera movement")
                    print("      Solution: Move iPhone up-down")
                    print("      Details: ARKit needs vertical motion to build 3D map")
                    reasonStrings.append("Mueve verticalmente (arriba-abajo)")

                case .insufficientLighting:
                    print("      ❌ INSUFFICIENT LIGHTING")
                    print("      Problem: Too dark for camera assistance")
                    print("      Solution: Move to better lit area")
                    print("      Details: ARKit camera needs adequate lighting to track")
                    reasonStrings.append("Busca un área con mejor iluminación")

                default:
                    print("      ❓ UNKNOWN REASON")
                    print("      Raw value: \(reason)")
                    print("      Solution: Try moving device in all directions")
                    reasonStrings.append("Mueve el dispositivo en todas las direcciones")
                }
            }

            // Update published properties for UI
            DispatchQueue.main.async {
                self.convergenceReasons = reasonStrings
                self.isConverging = true
            }

            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("   💡 USER ACTION REQUIRED:")
            print("      1. Ensure good lighting")
            print("      2. Move iPhone horizontally (left-right)")
            print("      3. Move iPhone vertically (up-down)")
            print("      4. Keep moving until direction appears")
            print("   ⏱️ Typical calibration time: 3-5 seconds")

            // Could trigger UI hint to user
            DispatchQueue.main.async {
                // Set @Published var for UI to show hints
            }

        case .unknown:
            print("   Status: ❓ UNKNOWN")
            print("   Impact: Convergence status not available")

        @unknown default:
            print("   Status: ❓ UNKNOWN CONVERGENCE STATUS (future case)")
            print("   Impact: Direction may not be available")
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {

        guard let peerId = activeSessions.first(where: { $0.value === session })?.key else {
            return
        }

        print("❌ LinkFinderSessionManager: Session invalidated for \(peerId): \(error.localizedDescription)")

        // Check if this is an ARKit-related error that doesn't require NI session termination
        let errorDescription = error.localizedDescription.lowercased()
        if errorDescription.contains("arkit") || errorDescription.contains("camera") || errorDescription.contains("world tracking") {
            print("⚠️ ARKit error detected - NearbyInteraction will continue WITHOUT camera assistance")
            print("   Note: Distance measurements will still work, direction may be less accurate")
            // Don't invalidate the NI session, just disable ARKit
            if #available(iOS 16.0, *) {
                self.arKitResourceManager?.stopARKitSession()
            }
            return  // Exit early without invalidating NI session
        }

        // Check for specific error types
        if isPermissionError(error) {
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("🔐 NEARBY INTERACTION PERMISSION ERROR")
            print("   Peer: \(peerId)")
            print("   Action: User needs to grant permission in Settings")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        }

        stopHealthCheck(for: peerId)

        // Clean up ARKit if it was being used
        if #available(iOS 16.0, *) {
            if let arManager = self.arKitResourceManager {
                print("   🧹 Cleaning up ARKit resources after session invalidation")
                arManager.cleanup()
            }
        }

        // Complete session cleanup
        DispatchQueue.main.async {
            // Remove all session-related data
            self.activeSessions.removeValue(forKey: peerId)
            self.nearbyObjects.removeValue(forKey: peerId)
            self.sessionStates[peerId] = .disconnected
            self.localTokens.removeValue(forKey: peerId)
            self.sessionRetryCount.removeValue(forKey: peerId)
            self.directionNilTimers[peerId]?.invalidate()
            self.directionNilTimers.removeValue(forKey: peerId)
            self.convergenceReasons.removeAll()  // Clear convergence reasons

            print("   ✅ Session fully cleaned up for \(peerId)")
        }

        // Notify delegate
        delegate?.uwbSessionManager(self, sessionInvalidatedFor: peerId, error: error)
    }

    /// Check if error is related to permission denial
    private func isPermissionError(_ error: Error) -> Bool {
        let errorString = error.localizedDescription.lowercased()
        return errorString.contains("user did not allow") ||
               errorString.contains("permission") ||
               errorString.contains("privacy") ||
               errorString.contains("not authorized") ||
               errorString.contains("denied")
    }
}

// MARK: - LinkFinderSessionManagerDelegate
@available(iOS 14.0, *)
protocol LinkFinderSessionManagerDelegate: AnyObject {
    func uwbSessionManager(_ manager: LinkFinderSessionManager, didUpdateDistanceTo peerId: String, distance: Float?, direction: SIMD3<Float>?)
    func uwbSessionManager(_ manager: LinkFinderSessionManager, didLoseTrackingOf peerId: String, reason: NINearbyObject.RemovalReason)
    func uwbSessionManager(_ manager: LinkFinderSessionManager, sessionInvalidatedFor peerId: String, error: Error)
    func uwbSessionManager(_ manager: LinkFinderSessionManager, requestsRestartFor peerId: String)
    func uwbSessionManager(_ manager: LinkFinderSessionManager, needsFreshTokenFor peerId: String)
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

// MARK: - UIDeviceOrientation Extension
extension UIDeviceOrientation {
    var description: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .portrait:
            return "Portrait"
        case .portraitUpsideDown:
            return "Portrait Upside Down"
        case .landscapeLeft:
            return "Landscape Left"
        case .landscapeRight:
            return "Landscape Right"
        case .faceUp:
            return "Face Up"
        case .faceDown:
            return "Face Down"
        @unknown default:
            return "Unknown Orientation"
        }
    }
}