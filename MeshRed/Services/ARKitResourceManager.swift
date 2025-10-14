//
//  ARKitResourceManager.swift
//  MeshRed
//
//  Manages ARKit session and resources for NearbyInteraction camera assistance
//  Resolves ARWorldTrackingTechnique resource constraints
//

import Foundation
import ARKit
import Combine
import os

/// Manages ARKit resources for optimal NearbyInteraction camera assistance
/// Handles resource constraints and provides fallback strategies
@available(iOS 16.0, *)
class ARKitResourceManager: NSObject, ObservableObject {

    // MARK: - Published Properties
    @Published var isARKitReady: Bool = false
    @Published var isARKitPermanentlyDisabled: Bool = false  // Set to true after max failures
    @Published var currentTrackingState: ARCamera.TrackingState = .notAvailable
    @Published var resourceConstraints: [String] = []
    @Published var isProcessingARData: Bool = false

    // MARK: - ARKit Components
    private var arSession: ARSession?
    private var arConfiguration: ARWorldTrackingConfiguration?
    private let processingQueue = DispatchQueue(label: "com.meshred.arkit", qos: .userInitiated)

    // MARK: - Resource Management
    private var memoryWarningObserver: NSObjectProtocol?
    private var thermalStateObserver: NSObjectProtocol?
    private var lastResourceCheckTime: Date = Date()
    private let resourceCheckInterval: TimeInterval = 5.0

    // MARK: - Failure Tracking
    private var consecutiveFailures: Int = 0
    private let maxRetryAttempts: Int = 2  // Stop after 2 failed attempts

    // MARK: - Initialization
    override init() {
        super.init()
        setupNotificationObservers()
        checkARKitAvailability()
    }

    deinit {
        cleanup()
    }

    // MARK: - Setup Methods

    /// Check if ARKit is available and properly configured
    private func checkARKitAvailability() {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🔍 ARKIT AVAILABILITY CHECK")
        LoggingService.network.info("   Timestamp: \(Date())")

        guard ARWorldTrackingConfiguration.isSupported else {
            LoggingService.network.info("   ❌ ARWorldTrackingConfiguration NOT supported")
            LoggingService.network.info("   Device needs A12 Bionic or later")
            isARKitReady = false
            return
        }

        LoggingService.network.info("   ✅ ARWorldTrackingConfiguration supported")

        // Check available video formats
        let formats = ARWorldTrackingConfiguration.supportedVideoFormats
        LoggingService.network.info("   Supported video formats: \(formats.count)")

        if formats.isEmpty {
            LoggingService.network.info("   ⚠️ No video formats available - camera may be in use")
            resourceConstraints.append("Camera unavailable")
        }

        // Check for specific capabilities
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            LoggingService.network.info("   ✅ Scene reconstruction supported")
        }

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            LoggingService.network.info("   ✅ Depth sensing supported")
        }

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        isARKitReady = true
    }

    /// Setup notification observers for system resource monitoring
    private func setupNotificationObservers() {
        // Memory warning observer
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }

        // Thermal state observer
        thermalStateObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleThermalStateChange()
        }
    }

    // MARK: - Public Methods

    /// Initialize and configure ARKit session for NearbyInteraction
    /// This MUST be called before enabling camera assistance
    func prepareARKitSession() -> Bool {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("🚀 PREPARING ARKIT SESSION")
        LoggingService.network.info("   Purpose: Enable camera assistance for NearbyInteraction")

        guard isARKitReady else {
            LoggingService.network.info("   ❌ ARKit not ready - cannot prepare session")
            return false
        }

        // FIXED: Clean up any existing session COMPLETELY
        if arSession != nil {
            LoggingService.network.info("   🧹 Cleaning up existing ARSession (complete)")

            // Step 1: Pause session
            arSession?.pause()

            // Step 2: Remove delegate to prevent callbacks during cleanup
            arSession?.delegate = nil

            // Step 3: Nil out references
            arSession = nil
            arConfiguration = nil

            LoggingService.network.info("   ✅ Previous ARSession fully deallocated")
        }

        // Create new AR session with optimized settings
        arSession = ARSession()
        arSession?.delegate = self

        // Configure for minimal resource usage (NearbyInteraction only needs basic tracking)
        arConfiguration = ARWorldTrackingConfiguration()

        guard let config = arConfiguration else {
            LoggingService.network.info("   ❌ Failed to create ARWorldTrackingConfiguration")
            return false
        }

        // CRITICAL: Optimize configuration for resource constraints
        configureForMinimalResources(config)

        LoggingService.network.info("   ✅ ARSession created and configured")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        return true
    }

    /// Start ARKit session with resource-aware configuration
    func startARKitSession() {
        // Don't attempt to start if permanently disabled
        if isARKitPermanentlyDisabled {
            LoggingService.network.info("⏹️ ARKit is permanently disabled - skipping start")
            return
        }

        guard let session = arSession,
              let config = arConfiguration else {
            LoggingService.network.info("❌ ARKitResourceManager: No session to start")
            return
        }

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("▶️ STARTING ARKIT SESSION")
        LoggingService.network.info("   Configuration: Minimal resources mode")

        // Check system resources before starting
        if !checkSystemResources() {
            LoggingService.network.info("   ⚠️ System resources constrained - using fallback config")
            configureForExtremeLowResources(config)
        }

        // Run the session
        session.run(config, options: [.resetTracking, .removeExistingAnchors])

        LoggingService.network.info("   ✅ ARSession.run() called")
        LoggingService.network.info("   Waiting for world tracking to initialize...")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        isProcessingARData = true
    }

    /// Pause ARKit session to free resources
    func pauseARKitSession() {
        LoggingService.network.info("⏸️ Pausing ARKit session to free resources")
        arSession?.pause()
        isProcessingARData = false
    }

    /// Stop and cleanup ARKit session
    func stopARKitSession() {
        LoggingService.network.info("⏹️ Stopping ARKit session (complete cleanup)")

        // FIXED: Complete cleanup to prevent resource leaks
        if let session = arSession {
            // Step 1: Pause session
            session.pause()

            // Step 2: Remove delegate to prevent callbacks
            session.delegate = nil

            LoggingService.network.info("   ✅ ARSession delegate removed")
        }

        // Step 3: Nil out all references
        arSession = nil
        arConfiguration = nil
        isProcessingARData = false

        // Note: Don't set isARKitReady = false here, as device capability doesn't change
        // Only set if there's a fatal error

        LoggingService.network.info("   ✅ ARKit resources fully released")
    }

    // MARK: - Configuration Methods

    /// Configure ARKit for minimal resource usage
    /// This is critical for avoiding resource constraints
    private func configureForMinimalResources(_ config: ARWorldTrackingConfiguration) {
        LoggingService.network.info("🔧 Configuring ARKit for MINIMAL resources:")

        // 1. Disable all unnecessary features
        config.environmentTexturing = .none  // Don't capture environment
        LoggingService.network.info("   • Environment texturing: DISABLED")

        config.wantsHDREnvironmentTextures = false  // No HDR
        LoggingService.network.info("   • HDR textures: DISABLED")

        if #available(iOS 14.0, *) {
            config.sceneReconstruction = []  // No 3D reconstruction
            LoggingService.network.info("   • Scene reconstruction: DISABLED")
        }

        config.providesAudioData = false  // No audio
        LoggingService.network.info("   • Audio data: DISABLED")

        // 2. Use lowest resolution video format to reduce memory/processing
        let formats = ARWorldTrackingConfiguration.supportedVideoFormats
        if let lowestResFormat = formats.min(by: {
            $0.imageResolution.width * $0.imageResolution.height <
            $1.imageResolution.width * $1.imageResolution.height
        }) {
            config.videoFormat = lowestResFormat
            LoggingService.network.info("   • Video format: \(Int(lowestResFormat.imageResolution.width))x\(Int(lowestResFormat.imageResolution.height))")
            LoggingService.network.info("   • Frame rate: \(lowestResFormat.framesPerSecond) fps")
        }

        // 3. Limit plane detection to horizontal only (less processing)
        config.planeDetection = [.horizontal]
        LoggingService.network.info("   • Plane detection: HORIZONTAL only")

        // 4. Set world alignment to gravity (simplest mode)
        config.worldAlignment = .gravity
        LoggingService.network.info("   • World alignment: GRAVITY")

        // 5. Disable automatic image/object detection
        config.detectionImages = nil
        config.detectionObjects = []
        LoggingService.network.info("   • Image/Object detection: DISABLED")

        // 6. Enable auto focus for better tracking in varied conditions
        config.isAutoFocusEnabled = true
        LoggingService.network.info("   • Auto focus: ENABLED")

        // 7. Light estimation minimal
        config.isLightEstimationEnabled = false
        LoggingService.network.info("   • Light estimation: DISABLED")
    }

    /// Configure for extreme low resources (thermal throttling or memory pressure)
    private func configureForExtremeLowResources(_ config: ARWorldTrackingConfiguration) {
        LoggingService.network.info("🔴 EXTREME LOW RESOURCE MODE:")

        configureForMinimalResources(config)

        // Additional restrictions
        config.planeDetection = []  // No plane detection at all
        LoggingService.network.info("   • Plane detection: COMPLETELY DISABLED")

        // Use gravity and heading for more stable tracking
        config.worldAlignment = .gravityAndHeading
        LoggingService.network.info("   • World alignment: GRAVITY + HEADING")

        // Reduce maximum number of tracked images
        config.maximumNumberOfTrackedImages = 0
        LoggingService.network.info("   • Tracked images: 0")
    }

    // MARK: - Resource Monitoring

    /// Check current system resources
    private func checkSystemResources() -> Bool {
        LoggingService.network.info("🔍 Checking system resources...")

        var resourcesOK = true
        resourceConstraints.removeAll()

        // Check thermal state
        let thermalState = ProcessInfo.processInfo.thermalState
        switch thermalState {
        case .nominal:
            LoggingService.network.info("   • Thermal state: ✅ Nominal")
        case .fair:
            LoggingService.network.info("   • Thermal state: ⚠️ Fair")
        case .serious:
            LoggingService.network.info("   • Thermal state: 🔥 Serious")
            resourceConstraints.append("Device overheating")
            resourcesOK = false
        case .critical:
            LoggingService.network.info("   • Thermal state: 🔥🔥 CRITICAL")
            resourceConstraints.append("Critical thermal state")
            resourcesOK = false
        @unknown default:
            LoggingService.network.info("   • Thermal state: Unknown")
        }

        // Check available memory
        let memoryInfo = ProcessInfo.processInfo
        let physicalMemory = memoryInfo.physicalMemory
        let memoryUsage = getMemoryUsage()
        let memoryPercentage = Double(memoryUsage) / Double(physicalMemory) * 100

        LoggingService.network.info("   • Memory usage: \(String(format: "%.1f", memoryPercentage))%")

        if memoryPercentage > 80 {
            resourceConstraints.append("High memory usage")
            resourcesOK = false
        }

        // Check if camera is available
        let cameraAvailable = !AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        ).devices.isEmpty

        if !cameraAvailable {
            LoggingService.network.info("   • Camera: ❌ Not available")
            resourceConstraints.append("Camera unavailable")
            resourcesOK = false
        } else {
            LoggingService.network.info("   • Camera: ✅ Available")
        }

        return resourcesOK
    }

    /// Get current memory usage in bytes
    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        return result == KERN_SUCCESS ? info.resident_size : 0
    }

    // MARK: - Event Handlers

    private func handleMemoryWarning() {
        LoggingService.network.info("⚠️ MEMORY WARNING RECEIVED")
        resourceConstraints.append("Memory warning")

        // Reduce ARKit resources
        if let config = arConfiguration {
            LoggingService.network.info("   Switching to extreme low resource mode")
            configureForExtremeLowResources(config)
            arSession?.run(config, options: [])
        }
    }

    private func handleThermalStateChange() {
        let state = ProcessInfo.processInfo.thermalState
        LoggingService.network.info("🌡️ Thermal state changed: \(String(describing: state), privacy: .public)")

        if state == .serious || state == .critical {
            // Pause ARKit to cool down
            LoggingService.network.info("   Pausing ARKit due to thermal state")
            pauseARKitSession()

            // Resume after cooldown
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                if ProcessInfo.processInfo.thermalState == .nominal ||
                   ProcessInfo.processInfo.thermalState == .fair {
                    LoggingService.network.info("   Thermal state improved - resuming ARKit")
                    self?.startARKitSession()
                }
            }
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        stopARKitSession()

        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        if let observer = thermalStateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

// MARK: - ARSessionDelegate
@available(iOS 16.0, *)
extension ARKitResourceManager: ARSessionDelegate {

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Update tracking state
        if currentTrackingState != frame.camera.trackingState {
            currentTrackingState = frame.camera.trackingState

            DispatchQueue.main.async {
                self.handleTrackingStateChange(frame.camera.trackingState)
            }
        }

        // Periodic resource check (every 5 seconds)
        if Date().timeIntervalSince(lastResourceCheckTime) > resourceCheckInterval {
            lastResourceCheckTime = Date()
            _ = checkSystemResources()
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        LoggingService.network.info("❌ ARSession failed: \(error.localizedDescription)")

        consecutiveFailures += 1

        DispatchQueue.main.async {
            self.resourceConstraints.append("ARKit error: \(error.localizedDescription)")
            self.isProcessingARData = false
        }

        // Only retry if we haven't exceeded max attempts
        if consecutiveFailures <= maxRetryAttempts {
            LoggingService.network.info("   Will attempt ARKit recovery (attempt \(self.consecutiveFailures)/\(self.maxRetryAttempts))...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.startARKitSession()
            }
        } else {
            LoggingService.network.info("   ⚠️ ARKit failed \(self.consecutiveFailures) times - PERMANENTLY DISABLING camera assist")
            LoggingService.network.info("   Note: UWB will continue to work without camera assistance")
            DispatchQueue.main.async {
                self.isARKitReady = false
                self.isARKitPermanentlyDisabled = true
            }
            // Cleanup ARKit resources completely
            stopARKitSession()
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        LoggingService.network.info("⏸️ ARSession interrupted")

        DispatchQueue.main.async {
            self.isProcessingARData = false
            self.resourceConstraints.append("Session interrupted")
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        LoggingService.network.info("▶️ ARSession interruption ended")

        DispatchQueue.main.async {
            self.resourceConstraints.removeAll(where: { $0.contains("interrupted") })
            self.isProcessingARData = true
        }

        // Reset session with current configuration
        if let config = arConfiguration {
            session.run(config, options: [.resetTracking])
        }
    }

    private func handleTrackingStateChange(_ state: ARCamera.TrackingState) {
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("📷 AR TRACKING STATE CHANGE")

        switch state {
        case .notAvailable:
            LoggingService.network.info("   Status: ❌ NOT AVAILABLE")
            resourceConstraints.append("AR tracking not available")

        case .limited(let reason):
            LoggingService.network.info("   Status: ⚠️ LIMITED")

            switch reason {
            case .excessiveMotion:
                LoggingService.network.info("   Reason: Excessive motion")
                resourceConstraints.append("Move slower for better tracking")

            case .insufficientFeatures:
                LoggingService.network.info("   Reason: Insufficient visual features")
                LoggingService.network.info("   Solution: Point at area with more visual detail")
                resourceConstraints.append("Point at detailed surfaces")

            case .initializing:
                LoggingService.network.info("   Reason: Initializing...")
                resourceConstraints.append("Initializing AR")

            case .relocalizing:
                LoggingService.network.info("   Reason: Relocalizing...")
                resourceConstraints.append("Relocalizing")

            @unknown default:
                LoggingService.network.info("   Reason: Unknown")
                resourceConstraints.append("Tracking limited")
            }

        case .normal:
            LoggingService.network.info("   Status: ✅ NORMAL")
            resourceConstraints.removeAll()
            consecutiveFailures = 0  // Reset failure counter on successful tracking
        }

        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}