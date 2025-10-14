//
//  OfflineTileOverlay.swift
//  MeshRed
//
//  Custom MKTileOverlay that prioritizes local cache over network
//  Enables offline map functionality for LinkFence system
//  Auto-caches downloaded tiles for future offline use
//

import Foundation
import MapKit
import os

/// Custom tile overlay that works offline using local cache
class OfflineTileOverlay: MKTileOverlay {

    // MARK: - Properties

    /// Local tile cache
    private let cache = MapTileCache.shared

    /// Whether to allow network fallback when tile not in cache
    var allowNetworkFallback: Bool = true

    /// Whether to auto-save downloaded tiles to cache
    var autoCache: Bool = true

    /// OpenStreetMap tile URL template
    private let tileURLTemplate = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"

    /// URL session for downloading tiles
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 10.0
        return URLSession(configuration: config)
    }()

    /// Download statistics
    private(set) var downloadStats = DownloadStats()

    struct DownloadStats {
        var cacheHits: Int = 0
        var cacheMisses: Int = 0
        var networkDownloads: Int = 0
        var networkErrors: Int = 0

        var totalRequests: Int {
            return cacheHits + cacheMisses
        }

        var cacheHitRate: Double {
            return totalRequests > 0 ? Double(cacheHits) / Double(totalRequests) : 0.0
        }
    }

    // MARK: - Initialization

    override init(urlTemplate: String?) {
        // Initialize with blank template (we'll handle URLs ourselves)
        super.init(urlTemplate: nil)

        // Configure overlay
        self.canReplaceMapContent = true
        self.minimumZ = 0
        self.maximumZ = 18

        LoggingService.network.info("🗺️ [OfflineTileOverlay] Initialized")
        LoggingService.network.info("   Cache enabled: true")
        LoggingService.network.info("   Network fallback: \(self.allowNetworkFallback)")
        LoggingService.network.info("   Auto-cache: \(self.autoCache)")
    }

    // MARK: - MKTileOverlay Override

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let z = path.z
        let x = path.x
        let y = path.y

        // Step 1: Try to load from cache
        if let cachedData = cache.loadTile(z: z, x: x, y: y) {
            downloadStats.cacheHits += 1
            result(cachedData, nil)
            return
        }

        downloadStats.cacheMisses += 1

        // Step 2: If network fallback disabled, return error
        guard allowNetworkFallback else {
            LoggingService.network.info("⚠️ [OfflineTileOverlay] Tile not in cache and network fallback disabled z=\(z) x=\(x) y=\(y)")
            let error = NSError(domain: "OfflineTileOverlay", code: 404, userInfo: [NSLocalizedDescriptionKey: "Tile not available offline"])
            downloadStats.networkErrors += 1
            result(nil, error)
            return
        }

        // Step 3: Download from network
        downloadTile(z: z, x: x, y: y) { [weak self] data, error in
            guard let self = self else { return }

            if let data = data {
                // Success: save to cache if enabled
                if self.autoCache {
                    self.cache.saveTile(data: data, z: z, x: x, y: y)
                }

                self.downloadStats.networkDownloads += 1
                result(data, nil)
            } else {
                // Error: return error
                self.downloadStats.networkErrors += 1
                result(nil, error)
            }
        }
    }

    // MARK: - Download Methods

    /// Download a tile from OpenStreetMap
    private func downloadTile(z: Int, x: Int, y: Int, completion: @escaping (Data?, Error?) -> Void) {
        // Build URL
        let urlString = tileURLTemplate
            .replacingOccurrences(of: "{z}", with: "\(z)")
            .replacingOccurrences(of: "{x}", with: "\(x)")
            .replacingOccurrences(of: "{y}", with: "\(y)")

        guard let url = URL(string: urlString) else {
            let error = NSError(domain: "OfflineTileOverlay", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            completion(nil, error)
            return
        }

        // Create request with User-Agent (required by OSM)
        var request = URLRequest(url: url)
        request.setValue("MeshRed/1.0 (StadiumConnect Pro)", forHTTPHeaderField: "User-Agent")

        // Download
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                LoggingService.network.info("❌ [OfflineTileOverlay] Download failed z=\(z) x=\(x) y=\(y): \(error.localizedDescription)")
                completion(nil, error)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                let error = NSError(domain: "OfflineTileOverlay", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                completion(nil, error)
                return
            }

            guard httpResponse.statusCode == 200 else {
                LoggingService.network.info("❌ [OfflineTileOverlay] Download failed z=\(z) x=\(x) y=\(y): HTTP \(httpResponse.statusCode)")
                let error = NSError(domain: "OfflineTileOverlay", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP error \(httpResponse.statusCode)"])
                completion(nil, error)
                return
            }

            guard let data = data, !data.isEmpty else {
                let error = NSError(domain: "OfflineTileOverlay", code: 204, userInfo: [NSLocalizedDescriptionKey: "Empty tile data"])
                completion(nil, error)
                return
            }

            completion(data, nil)
        }

        task.resume()
    }

    // MARK: - Configuration Methods

    /// Set offline-only mode (no network downloads)
    func setOfflineOnly() {
        allowNetworkFallback = false
        LoggingService.network.info("🔒 [OfflineTileOverlay] Offline-only mode enabled")
    }

    /// Set hybrid mode (cache + network fallback)
    func setHybridMode() {
        allowNetworkFallback = true
        LoggingService.network.info("🌐 [OfflineTileOverlay] Hybrid mode enabled")
    }

    /// Get current download statistics
    func getStats() -> DownloadStats {
        return downloadStats
    }

    /// Reset download statistics
    func resetStats() {
        downloadStats = DownloadStats()
    }

    /// Print detailed statistics
    func printStats() {
        let stats = downloadStats
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        LoggingService.network.info("📊 OFFLINE TILE OVERLAY STATISTICS")
        LoggingService.network.info("   Total requests: \(stats.totalRequests)")
        LoggingService.network.info("   Cache hits: \(stats.cacheHits) (\(String(format: "%.1f", stats.cacheHitRate * 100))%)")
        LoggingService.network.info("   Cache misses: \(stats.cacheMisses)")
        LoggingService.network.info("   Network downloads: \(stats.networkDownloads)")
        LoggingService.network.info("   Network errors: \(stats.networkErrors)")
        LoggingService.network.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}

// MARK: - Tile Coordinate Helpers

extension OfflineTileOverlay {

    /// Calculate tile coordinates for a geographic coordinate at a given zoom level
    static func tileCoordinates(for coordinate: CLLocationCoordinate2D, zoom: Int) -> (x: Int, y: Int) {
        let n = pow(2.0, Double(zoom))

        let x = Int(floor((coordinate.longitude + 180.0) / 360.0 * n))

        let latRad = coordinate.latitude * .pi / 180.0
        let y = Int(floor((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n))

        return (x, y)
    }

    /// Calculate number of tiles needed for a region at a specific zoom level
    static func tileCount(for region: MKCoordinateRegion, zoom: Int) -> Int {
        // Calculate corners
        let northWest = CLLocationCoordinate2D(
            latitude: region.center.latitude + region.span.latitudeDelta / 2,
            longitude: region.center.longitude - region.span.longitudeDelta / 2
        )
        let southEast = CLLocationCoordinate2D(
            latitude: region.center.latitude - region.span.latitudeDelta / 2,
            longitude: region.center.longitude + region.span.longitudeDelta / 2
        )

        // Get tile ranges
        let nwTile = tileCoordinates(for: northWest, zoom: zoom)
        let seTile = tileCoordinates(for: southEast, zoom: zoom)

        // Calculate count
        let xRange = abs(seTile.x - nwTile.x) + 1
        let yRange = abs(seTile.y - nwTile.y) + 1

        return xRange * yRange
    }

    /// Get all tile coordinates for a region at a specific zoom level
    static func tiles(for region: MKCoordinateRegion, zoom: Int) -> [(x: Int, y: Int, z: Int)] {
        // Calculate corners
        let northWest = CLLocationCoordinate2D(
            latitude: region.center.latitude + region.span.latitudeDelta / 2,
            longitude: region.center.longitude - region.span.longitudeDelta / 2
        )
        let southEast = CLLocationCoordinate2D(
            latitude: region.center.latitude - region.span.latitudeDelta / 2,
            longitude: region.center.longitude + region.span.longitudeDelta / 2
        )

        // Get tile ranges
        let nwTile = tileCoordinates(for: northWest, zoom: zoom)
        let seTile = tileCoordinates(for: southEast, zoom: zoom)

        // Generate all tiles
        var tiles: [(x: Int, y: Int, z: Int)] = []

        let minX = min(nwTile.x, seTile.x)
        let maxX = max(nwTile.x, seTile.x)
        let minY = min(nwTile.y, seTile.y)
        let maxY = max(nwTile.y, seTile.y)

        for x in minX...maxX {
            for y in minY...maxY {
                tiles.append((x, y, zoom))
            }
        }

        return tiles
    }
}
