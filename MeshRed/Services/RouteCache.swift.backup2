//
//  RouteCache.swift
//  MeshRed
//
//  Route discovery and caching system for intelligent mesh routing
//  Implements AODV-like protocol for efficient message delivery
//  Complementary to topology-based RoutingTable
//

import Foundation
import os

/// Information about a discovered route to a destination peer
struct RouteInfo {
    /// Destination peer ID
    let destination: String

    /// Next hop peer ID to reach destination
    let nextHop: String

    /// Number of hops to destination
    let hopCount: Int

    /// When this route was learned/updated
    let timestamp: Date

    /// Full path to destination (for debugging)
    let fullPath: [String]?

    /// Whether this route is currently valid
    var isValid: Bool {
        // Route expires after 5 minutes
        return Date().timeIntervalSince(timestamp) < 300
    }

    init(destination: String, nextHop: String, hopCount: Int, timestamp: Date = Date(), fullPath: [String]? = nil) {
        self.destination = destination
        self.nextHop = nextHop
        self.hopCount = hopCount
        self.timestamp = timestamp
        self.fullPath = fullPath
    }
}

/// Manages route discovery cache for efficient mesh network routing (AODV-like)
/// Complementary to topology-based RoutingTable - this uses on-demand route discovery
class RouteCache {

    // MARK: - Properties

    /// Cache of known routes indexed by destination peer ID
    private var routes: [String: RouteInfo] = [:]

    /// Expiration time for routes (5 minutes)
    private let expirationTime: TimeInterval = 300

    /// Thread-safe access queue
    private let queue = DispatchQueue(label: "com.meshred.routingtable", attributes: .concurrent)

    /// Timer for periodic cleanup
    private var cleanupTimer: Timer?

    // MARK: - Initialization

    init() {
        startPeriodicCleanup()
    }

    deinit {
        cleanupTimer?.invalidate()
    }

    // MARK: - Public Methods

    /// Find a route to the specified destination
    /// - Parameter destination: Destination peer ID
    /// - Returns: RouteInfo if valid route exists, nil otherwise
    func findRoute(to destination: String) -> RouteInfo? {
        queue.sync {
            guard let route = routes[destination] else {
                return nil
            }

            // Check if route has expired
            if !route.isValid {
                // Remove expired route
                routes.removeValue(forKey: destination)
                LoggingService.network.info("🗑️ [RouteCache] Expired route to \(destination) removed")
                return nil
            }

            return route
        }
    }

    /// Add or update a route in the table
    /// - Parameter route: RouteInfo to add
    func addRoute(_ route: RouteInfo) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            // Check if we should update existing route
            if let existingRoute = self.routes[route.destination] {
                // Only update if new route is better (fewer hops) or fresher
                let shouldUpdate = route.hopCount < existingRoute.hopCount ||
                                 (route.hopCount == existingRoute.hopCount &&
                                  route.timestamp > existingRoute.timestamp)

                if shouldUpdate {
                    self.routes[route.destination] = route
                    LoggingService.network.info("📍 [RouteCache] Updated route to \(route.destination): \(route.hopCount) hops via \(route.nextHop)")
                } else {
                    LoggingService.network.info("⏭️ [RouteCache] Keeping existing better route to \(route.destination)")
                }
            } else {
                // New route
                self.routes[route.destination] = route
                LoggingService.network.info("📍 [RouteCache] Added route to \(route.destination): \(route.hopCount) hops via \(route.nextHop)")
            }
        }
    }

    /// Remove a route from the table (e.g., when connection fails)
    /// - Parameter destination: Destination peer ID
    func removeRoute(to destination: String) {
        queue.async(flags: .barrier) { [weak self] in
            if self?.routes.removeValue(forKey: destination) != nil {
                LoggingService.network.info("🗑️ [RouteCache] Removed route to \(destination)")
            }
        }
    }

    /// Remove all routes that use a specific peer as next hop
    /// - Parameter nextHop: Next hop peer ID
    func removeRoutesVia(nextHop: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let routesToRemove = self.routes.filter { $0.value.nextHop == nextHop }
            for (destination, _) in routesToRemove {
                self.routes.removeValue(forKey: destination)
                LoggingService.network.info("🗑️ [RouteCache] Removed route to \(destination) (via disconnected peer \(nextHop))")
            }
        }
    }

    /// Clear all expired routes from the table
    func clearExpiredRoutes() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let now = Date()
            let initialCount = self.routes.count

            self.routes = self.routes.filter { _, route in
                let isValid = now.timeIntervalSince(route.timestamp) < self.expirationTime
                return isValid
            }

            let removedCount = initialCount - self.routes.count
            if removedCount > 0 {
                LoggingService.network.info("🗑️ [RouteCache] Cleared \(removedCount) expired routes")
            }
        }
    }

    /// Clear all routes from the table
    func clearAll() {
        queue.async(flags: .barrier) { [weak self] in
            let count = self?.routes.count ?? 0
            self?.routes.removeAll()
            LoggingService.network.info("🗑️ [RouteCache] Cleared all \(count) routes")
        }
    }

    /// Get all current routes (for debugging)
    /// - Returns: Array of all routes
    func getAllRoutes() -> [RouteInfo] {
        queue.sync {
            return Array(routes.values)
        }
    }

    /// Get statistics about the routing table
    /// - Returns: Tuple with total routes and average hop count
    func getStats() -> (totalRoutes: Int, avgHops: Double) {
        queue.sync {
            let total = routes.count
            let avgHops = routes.isEmpty ? 0.0 : Double(routes.values.reduce(0) { $0 + $1.hopCount }) / Double(total)
            return (total, avgHops)
        }
    }

    // MARK: - Private Methods

    /// Start periodic cleanup timer
    private func startPeriodicCleanup() {
        // Run cleanup every 60 seconds
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.clearExpiredRoutes()
        }
    }
}
