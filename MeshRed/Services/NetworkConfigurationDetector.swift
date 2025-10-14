//
//  NetworkConfigurationDetector.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Detects problematic network configurations that break MultipeerConnectivity
//

import Foundation
import Network
import Combine
import UIKit
import os

/// Detects problematic network configurations that cause MultipeerConnectivity failures
class NetworkConfigurationDetector: ObservableObject {

    // MARK: - Published Properties

    @Published var currentStatus: NetworkStatus = .unknown
    @Published var isProblematic: Bool = false
    @Published var suggestionText: String = ""

    // MARK: - Network Monitor

    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.meshred.network-config-detector")

    // MARK: - Initialization

    init() {
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Public Methods

    /// Start monitoring network configuration
    func startMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            let status = self.analyzeNetworkPath(path)

            DispatchQueue.main.async {
                self.currentStatus = status
                self.isProblematic = status.isProblematic
                self.suggestionText = status.suggestion

                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                LoggingService.network.info("🔍 NETWORK CONFIGURATION DETECTED")
                LoggingService.network.info("   Status: \(status.rawValue)")
                LoggingService.network.info("   Problematic: \(status.isProblematic)")
                if status.isProblematic {
                    LoggingService.network.info("   ⚠️  \(status.suggestion)")
                }
                LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            }
        }

        pathMonitor.start(queue: monitorQueue)
        LoggingService.network.info("🔍 NetworkConfigurationDetector: Started monitoring")
    }

    /// Stop monitoring
    func stopMonitoring() {
        pathMonitor.cancel()
        LoggingService.network.info("🔍 NetworkConfigurationDetector: Stopped monitoring")
    }

    /// Perform immediate check (synchronous)
    func performImmediateCheck() -> NetworkStatus {
        let semaphore = DispatchSemaphore(value: 0)
        var detectedStatus: NetworkStatus = .unknown

        let tempMonitor = NWPathMonitor()
        tempMonitor.pathUpdateHandler = { path in
            detectedStatus = self.analyzeNetworkPath(path)
            semaphore.signal()
        }

        let tempQueue = DispatchQueue(label: "com.meshred.network-check-temp")
        tempMonitor.start(queue: tempQueue)

        // Wait max 1 second
        _ = semaphore.wait(timeout: .now() + 1.0)
        tempMonitor.cancel()

        return detectedStatus
    }

    /// Can this configuration be auto-fixed?
    func canAutoFix() -> Bool {
        return false  // iOS doesn't allow programmatic WiFi/BT control
    }

    /// Open Settings to fix the issue
    func openSettingsToFix() {
        guard let settingsURL = URL(string: "App-Prefs:root=WIFI") else { return }

        #if canImport(UIKit)
        if UIApplication.shared.canOpenURL(settingsURL) {
            UIApplication.shared.open(settingsURL)
        }
        #endif
    }

    // MARK: - Private Methods

    private func analyzeNetworkPath(_ path: NWPath) -> NetworkStatus {
        let hasWiFi = path.availableInterfaces.contains { $0.type == .wifi }
        let isWiFiConnected = path.status == .satisfied && path.usesInterfaceType(.wifi)
        let hasCellular = path.availableInterfaces.contains { $0.type == .cellular }
        let isCellularConnected = path.status == .satisfied && path.usesInterfaceType(.cellular)

        // Check if path is expensive (typically means limited connectivity)
        let isExpensivePath = path.isExpensive
        let isConstrainedPath = path.isConstrained

        // CRITICAL PROBLEM: WiFi enabled but not connected
        // This causes Socket Error 61 because iOS tries WiFi Direct but fails
        if hasWiFi && !isWiFiConnected && !isCellularConnected {
            return .wifiEnabledButNotConnected
        }

        // GOOD: WiFi connected
        if isWiFiConnected {
            // Check for constrained WiFi (captive portal, limited connectivity)
            if isConstrainedPath {
                LoggingService.network.warning("⚠️ WiFi connected but constrained (captive portal or limited)")
            }
            return .wifiConnected
        }

        // GOOD: Cellular (Bluetooth will be used for P2P)
        if isCellularConnected {
            if isExpensivePath {
                LoggingService.network.info("💰 Cellular connection is expensive")
            }
            return .cellularOnly
        }

        // GOOD: WiFi and Cellular disabled - Bluetooth-only mode
        // FIXED: This is VALID for MultipeerConnectivity (Bluetooth pure works)
        // Not a problem - don't report as .noNetworkAtAll
        if !hasWiFi && !hasCellular {
            return .bluetoothOnly
        }

        // Unknown configuration
        return .unknown
    }
}

// MARK: - Network Status Enum

enum NetworkStatus: String, Codable {
    case optimal = "Optimal"
    case wifiConnected = "WiFi Connected"
    case cellularOnly = "Cellular Only"
    case bluetoothOnly = "Bluetooth Only"
    case wifiEnabledButNotConnected = "WiFi Enabled But Not Connected"
    case noNetworkAtAll = "No Network"
    case unknown = "Unknown"

    /// Is this configuration problematic for MultipeerConnectivity?
    var isProblematic: Bool {
        switch self {
        case .wifiEnabledButNotConnected:
            return true  // CRITICAL: Causes Socket Error 61
        // REMOVED: .noNetworkAtAll is now unused (replaced by .bluetoothOnly)
        // FIXED: .bluetoothOnly is VALID for MultipeerConnectivity
        default:
            return false
        }
    }

    /// User-friendly explanation
    var explanation: String {
        switch self {
        case .wifiConnected:
            return "WiFi conectado - MultipeerConnectivity usará WiFi Direct para conexiones rápidas."
        case .cellularOnly:
            return "Datos celulares activos - MultipeerConnectivity usará Bluetooth para conexiones P2P."
        case .bluetoothOnly:
            return "✅ Modo Bluetooth puro - Configuración ÓPTIMA para MultipeerConnectivity (conexiones estables)."
        case .wifiEnabledButNotConnected:
            return "WiFi habilitado pero NO conectado - Esto causa fallos de conexión. iOS intenta usar WiFi Direct pero falla porque no hay red."
        case .noNetworkAtAll:
            return "Sin red detectada - Configuración inusual."
        case .unknown, .optimal:
            return "Configuración desconocida"
        }
    }

    /// Suggestion to fix the problem
    var suggestion: String {
        switch self {
        case .wifiEnabledButNotConnected:
            return "SOLUCIÓN: Desactiva WiFi completamente O conéctate a una red WiFi"
        // REMOVED: .noNetworkAtAll suggestion (false positive eliminated)
        default:
            return ""
        }
    }

    /// Severity level
    var severity: NetworkConfigSeverity {
        switch self {
        case .wifiEnabledButNotConnected:
            return .critical
        // REMOVED: .noNetworkAtAll warning (false positive eliminated)
        default:
            return .ok
        }
    }
}

enum NetworkConfigSeverity {
    case ok
    case warning
    case critical
}
