import Foundation

struct TestingConfig {
    // Set to true to force multi-hop even when devices are in direct range
    static let forceMultiHop = false  // DISABLED - Allow all direct connections

    // Disable health monitoring during tests (prevents aggressive disconnections)
    static let disableHealthMonitoring = false  // ENABLED - Allow health monitoring

    // Devices that should NOT connect directly (for testing relay)
    // Topology: iphone-de-bichotee ↔ macbook-pro-de-sebastian ↔ iphone-de-jose-guadalupe
    // Block A↔C connections to force multi-hop through B
    // EMPTY - No blocked connections, allow full mesh
    static let blockedDirectConnections: [String: [String]] = [:]

    static func shouldBlockDirectConnection(from: String, to: String) -> Bool {
        guard forceMultiHop else { return false }
        return blockedDirectConnections[from]?.contains(to) ?? false
    }
}