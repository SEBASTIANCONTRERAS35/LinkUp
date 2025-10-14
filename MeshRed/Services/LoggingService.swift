//
//  LoggingService.swift
//  MeshRed
//
//  Sistema centralizado de logging con OSLog framework
//  Permite captura automática y análisis por Claude Code
//

import Foundation
import os

/// Sistema moderno de logging usando OSLog framework de Apple
/// Reemplaza los LoggingService.network.info() statements con loggers categorizados
public class LoggingService {

    // MARK: - Constants

    /// Bundle identifier usado como subsystem para todos los logs
    private static let subsystem = Bundle.main.bundleIdentifier ?? "EmilioContreras.MeshRed"

    // MARK: - Logger Instances

    /// Logger para operaciones de red P2P y MultipeerConnectivity
    public static let network = Logger(subsystem: subsystem, category: "network")

    /// Logger para routing mesh y multi-hop messaging
    public static let mesh = Logger(subsystem: subsystem, category: "mesh")

    /// Logger para UWB/NearbyInteraction y localización
    public static let uwb = Logger(subsystem: subsystem, category: "uwb")

    /// Logger para geofencing y zonas del estadio
    public static let geofence = Logger(subsystem: subsystem, category: "geofence")

    /// Logger para detección de emergencias
    public static let emergency = Logger(subsystem: subsystem, category: "emergency")

    /// Logger para eventos de UI y user interaction
    public static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Logger para sistema de LiveActivity
    public static let activity = Logger(subsystem: subsystem, category: "activity")

    /// Logger general para otros eventos
    public static let general = Logger(subsystem: subsystem, category: "general")

    // MARK: - Convenience Methods

    /// Wrapper para mantener compatibilidad con LoggingService.network.infos existentes
    /// También envía el mensaje al Logger apropiado
    public static func log(
        _ message: String,
        category: LogCategory = .general,
        level: OSLogType = .info,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        // Mantener LoggingService.network.info para debugging local (con formato mejorado)
        let filename = URL(fileURLWithPath: file).lastPathComponent
        let location = "[\(filename):\(line)]"
        LoggingService.network.info("\(location) \(message)")

        // Enviar a Logger apropiado con metadata
        let logger = getLogger(for: category)

        switch level {
        case .debug:
            logger.debug("\(message, privacy: .public) [\(function, privacy: .public)]")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .default:
            logger.log("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public) [\(filename, privacy: .public):\(line, privacy: .public)]")
        case .fault:
            logger.fault("\(message, privacy: .public) [\(filename, privacy: .public):\(line, privacy: .public)]")
        default:
            logger.log("\(message, privacy: .public)")
        }
    }

    /// Obtiene el Logger correcto basado en la categoría
    private static func getLogger(for category: LogCategory) -> Logger {
        switch category {
        case .network: return network
        case .mesh: return mesh
        case .uwb: return uwb
        case .geofence: return geofence
        case .emergency: return emergency
        case .ui: return ui
        case .activity: return activity
        case .general: return general
        }
    }

    // MARK: - Performance Logging

    /// Inicia medición de performance para una operación
    public static func startMeasurement(label: String) -> OSSignpostID {
        let osLog = OSLog(subsystem: subsystem, category: "performance")
        let signpostID = OSSignpostID(log: osLog)
        os_signpost(.begin, log: osLog, name: "Performance", signpostID: signpostID, "%{public}s", label)
        return signpostID
    }

    /// Finaliza medición de performance
    public static func endMeasurement(label: String, signpostID: OSSignpostID) {
        let osLog = OSLog(subsystem: subsystem, category: "performance")
        os_signpost(.end, log: osLog, name: "Performance", signpostID: signpostID, "%{public}s", label)
    }

    // MARK: - Network Specific Logging

    /// Log especializado para conexiones P2P
    public static func logConnection(_ peer: String, connected: Bool) {
        let status = connected ? "connected" : "disconnected"
        network.info("📡 Peer \(peer, privacy: .public) \(status, privacy: .public)")
    }

    /// Log especializado para mensajes mesh
    public static func logMessage(_ messageType: String, from: String, to: String? = nil, hopCount: Int = 0) {
        if let to = to {
            mesh.info("💬 \(messageType, privacy: .public) from \(from, privacy: .public) to \(to, privacy: .public) [hops: \(hopCount)]")
        } else {
            mesh.info("💬 \(messageType, privacy: .public) from \(from, privacy: .public) [broadcast]")
        }
    }

    /// Log especializado para errores de red
    public static func logNetworkError(_ error: Error, context: String) {
        network.error("❌ Network error in \(context, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }

    // MARK: - UWB Specific Logging

    /// Log especializado para sesiones UWB
    public static func logUWBSession(_ event: String, peer: String? = nil) {
        if let peer = peer {
            uwb.info("📍 UWB \(event, privacy: .public) with \(peer, privacy: .public)")
        } else {
            uwb.info("📍 UWB \(event, privacy: .public)")
        }
    }

    /// Log especializado para mediciones de distancia
    public static func logDistance(_ distance: Float, azimuth: Float?, elevation: Float?, to peer: String) {
        var details = "distance: \(String(format: "%.2f", distance))m"
        if let azimuth = azimuth {
            details += ", azimuth: \(String(format: "%.1f", azimuth))°"
        }
        if let elevation = elevation {
            details += ", elevation: \(String(format: "%.1f", elevation))°"
        }
        uwb.debug("📏 To \(peer, privacy: .public): \(details, privacy: .public)")
    }

    // MARK: - Emergency Specific Logging

    /// Log especializado para eventos de emergencia
    public static func logEmergency(_ type: String, severity: String, location: String? = nil) {
        var message = "🚨 EMERGENCY: \(type) [severity: \(severity)]"
        if let location = location {
            message += " at \(location)"
        }
        emergency.critical("\(message, privacy: .public)")
    }

    /// Log especializado para detección de emergencias
    public static func logEmergencyDetection(_ sensor: String, value: String, threshold: String) {
        emergency.warning("⚠️ \(sensor, privacy: .public) detection: \(value, privacy: .public) (threshold: \(threshold, privacy: .public))")
    }
}

// MARK: - Log Categories

/// Categorías de logging para organización y filtrado
public enum LogCategory {
    case network    // P2P connections, MultipeerConnectivity
    case mesh       // Message routing, multi-hop
    case uwb        // NearbyInteraction, positioning
    case geofence   // Zone management, location
    case emergency  // Emergency detection and alerts
    case ui         // User interface events
    case activity   // LiveActivity updates
    case general    // Other events
}

// MARK: - Convenience Extensions

/// Extension para facilitar logging desde cualquier parte del código
public extension Logger {

    /// Log con información de ubicación automática
    func logWithLocation(
        _ message: String,
        level: OSLogType = .info,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let filename = URL(fileURLWithPath: file).lastPathComponent
        let location = "[\(filename):\(line)]"

        switch level {
        case .debug:
            self.debug("\(location, privacy: .public) \(message, privacy: .public)")
        case .info:
            self.info("\(location, privacy: .public) \(message, privacy: .public)")
        case .error:
            self.error("\(location, privacy: .public) \(message, privacy: .public)")
        default:
            self.log("\(location, privacy: .public) \(message, privacy: .public)")
        }
    }
}

// MARK: - Debug Helpers

#if DEBUG
/// Helpers adicionales solo disponibles en modo DEBUG
extension LoggingService {

    /// Dump completo de un objeto para debugging
    public static func dumpObject<T>(_ object: T, label: String = "Object") {
        general.debug("📦 Dump of \(label, privacy: .public):")
        dump(object)
    }

    /// Log de entrada a función
    public static func functionEntry(file: String = #file, function: String = #function) {
        let filename = URL(fileURLWithPath: file).lastPathComponent
        general.debug("→ Entering \(filename, privacy: .public).\(function, privacy: .public)")
    }

    /// Log de salida de función
    public static func functionExit(file: String = #file, function: String = #function) {
        let filename = URL(fileURLWithPath: file).lastPathComponent
        general.debug("← Exiting \(filename, privacy: .public).\(function, privacy: .public)")
    }
}
#endif