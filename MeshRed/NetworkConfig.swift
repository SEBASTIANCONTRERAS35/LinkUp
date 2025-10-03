import Foundation
import Combine

enum NetworkMode: String, CaseIterable, Codable {
    case standard = "Estándar"
    case powerSaving = "Ahorro de Energía"
    case highAvailability = "Alta Disponibilidad"

    var pingInterval: TimeInterval {
        switch self {
        case .standard: return 30.0
        case .powerSaving: return 60.0
        case .highAvailability: return 15.0
        }
    }

    var maxRetryAttempts: Int {
        switch self {
        case .standard: return 5
        case .powerSaving: return 3
        case .highAvailability: return 10
        }
    }

    var connectionTimeout: TimeInterval {
        switch self {
        case .standard: return 30.0
        case .powerSaving: return 20.0
        case .highAvailability: return 45.0
        }
    }

    var browseInterval: TimeInterval {
        switch self {
        case .standard: return 1.0
        case .powerSaving: return 5.0
        case .highAvailability: return 0.5
        }
    }
}

class NetworkConfig: ObservableObject {
    static let shared = NetworkConfig()

    @Published var networkMode: NetworkMode = .standard {
        didSet {
            UserDefaults.standard.set(networkMode.rawValue, forKey: "networkMode")
            print("🔧 Network mode changed to: \(networkMode.rawValue)")
        }
    }

    @Published var debugMode: Bool = false {
        didSet {
            UserDefaults.standard.set(debugMode, forKey: "debugMode")
            print("🐛 Debug mode: \(debugMode ? "ON" : "OFF")")
        }
    }

    @Published var silentMode: Bool = false {
        didSet {
            UserDefaults.standard.set(silentMode, forKey: "silentMode")
            if silentMode {
                print("🔇 Silent mode: Network logs suppressed")
            }
        }
    }

    @Published var autoReconnect: Bool = true {
        didSet {
            UserDefaults.standard.set(autoReconnect, forKey: "autoReconnect")
        }
    }

    @Published var maxMessageQueueSize: Int = 100 {
        didSet {
            UserDefaults.standard.set(maxMessageQueueSize, forKey: "maxMessageQueueSize")
        }
    }

    @Published var messageCacheTimeout: TimeInterval = 300 {
        didSet {
            UserDefaults.standard.set(messageCacheTimeout, forKey: "messageCacheTimeout")
        }
    }

    // Maximum simultaneous connections (prevents mesh over-optimization)
    // Limited to 5 for optimal performance and user management
    @Published var maxConnections: Int = 5 {
        didSet {
            UserDefaults.standard.set(maxConnections, forKey: "maxConnections")
        }
    }

    // Stop browsing after first connection (prevents auto-optimization)
    // Set to false for multi-hop mesh scenarios where intermediate nodes need discovery
    // ALWAYS FALSE to keep discovering new peers
    @Published var stopBrowsingWhenConnected: Bool = false {
        didSet {
            UserDefaults.standard.set(stopBrowsingWhenConnected, forKey: "stopBrowsingWhenConnected")
        }
    }

    private init() {
        loadSettings()
    }

    private func loadSettings() {
        if let modeRaw = UserDefaults.standard.string(forKey: "networkMode"),
           let mode = NetworkMode(rawValue: modeRaw) {
            networkMode = mode
        }

        debugMode = UserDefaults.standard.bool(forKey: "debugMode")
        silentMode = UserDefaults.standard.bool(forKey: "silentMode")
        autoReconnect = UserDefaults.standard.object(forKey: "autoReconnect") as? Bool ?? true

        if let queueSize = UserDefaults.standard.object(forKey: "maxMessageQueueSize") as? Int {
            maxMessageQueueSize = queueSize
        }

        if let cacheTimeout = UserDefaults.standard.object(forKey: "messageCacheTimeout") as? TimeInterval {
            messageCacheTimeout = cacheTimeout
        }

        if let maxConn = UserDefaults.standard.object(forKey: "maxConnections") as? Int {
            maxConnections = maxConn
        }

        stopBrowsingWhenConnected = UserDefaults.standard.object(forKey: "stopBrowsingWhenConnected") as? Bool ?? false
    }

    func resetToDefaults() {
        networkMode = .standard
        debugMode = false
        silentMode = false
        autoReconnect = true
        maxMessageQueueSize = 100
        messageCacheTimeout = 300
        maxConnections = 5
        stopBrowsingWhenConnected = false

        print("🔧 Settings reset to defaults")
    }

    func getCurrentConfig() -> String {
        """
        Network Configuration:
        - Mode: \(networkMode.rawValue)
        - Debug: \(debugMode)
        - Silent: \(silentMode)
        - Auto Reconnect: \(autoReconnect)
        - Queue Size: \(maxMessageQueueSize)
        - Cache Timeout: \(Int(messageCacheTimeout))s
        """
    }
}