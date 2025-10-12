//
//  OfflineMapManager.swift
//  MeshRed
//
//  Coordinator for offline map system
//  Manages download, cache, and offline state for LinkFence maps
//

import Foundation
import MapKit
import Combine

/// Manages offline map functionality for the entire app
class OfflineMapManager: ObservableObject {

    // MARK: - Singleton

    static let shared = OfflineMapManager()

    // MARK: - Published Properties

    @Published var isOfflineModeEnabled: Bool = false
    @Published var downloadedRegions: [DownloadedRegion] = []
    @Published var currentRegionStatus: RegionStatus = .notDownloaded

    // MARK: - Properties

    private let cache = MapTileCache.shared
    private let downloader = OfflineMapDownloader()
    private let locationService = LocationService()

    // MARK: - Data Models

    struct DownloadedRegion: Identifiable, Codable {
        let id: UUID
        let name: String
        let center: Coordinate
        let radiusKm: Double
        let downloadDate: Date
        var lastAccessDate: Date
        let sizeBytes: Int64

        struct Coordinate: Codable {
            let latitude: Double
            let longitude: Double

            var clCoordinate: CLLocationCoordinate2D {
                CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }
        }

        var sizeMB: Double {
            return Double(sizeBytes) / 1_048_576.0
        }
    }

    enum RegionStatus {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case partiallyDownloaded
    }

    // MARK: - Initialization

    private init() {
        loadDownloadedRegions()
    }

    // MARK: - Public Methods

    /// Download map for current location (20km radius)
    func downloadCurrentLocation() {
        guard let location = locationService.currentLocation else {
            print("⚠️ [OfflineMapManager] No location available")
            return
        }

        let coordinate = CLLocationCoordinate2D(
            latitude: location.latitude,
            longitude: location.longitude
        )

        downloadRegion(center: coordinate, name: "Mi ubicación", radiusKm: 20.0)
    }

    /// Download map for a specific region
    func downloadRegion(center: CLLocationCoordinate2D, name: String, radiusKm: Double = 20.0) {
        print("🌍 [OfflineMapManager] Downloading region: \(name)")

        currentRegionStatus = .downloading(progress: 0.0)

        downloader.downloadRegion(center: center, radiusKm: radiusKm)

        // Monitor progress
        let cancellable = downloader.$progress.sink { [weak self] progress in
            self?.currentRegionStatus = .downloading(progress: progress)

            if progress >= 1.0 {
                // Download complete
                self?.saveDownloadedRegion(
                    name: name,
                    center: center,
                    radiusKm: radiusKm,
                    sizeBytes: self?.downloader.downloadedBytes ?? 0
                )
                self?.currentRegionStatus = .downloaded
            }
        }

        // Store cancellable (in real implementation, manage this properly)
        _ = cancellable
    }

    /// Check if a region is downloaded
    func isRegionDownloaded(center: CLLocationCoordinate2D, radiusKm: Double) -> Bool {
        // Simplified check: see if any downloaded region is close enough
        return downloadedRegions.contains { region in
            let distance = self.distance(from: center, to: region.center.clCoordinate)
            return distance < radiusKm * 1.5 // 1.5x for overlap
        }
    }

    /// Enable offline-only mode
    func enableOfflineMode() {
        isOfflineModeEnabled = true
        print("🔒 [OfflineMapManager] Offline mode enabled")
    }

    /// Enable hybrid mode (cache + network)
    func enableHybridMode() {
        isOfflineModeEnabled = false
        print("🌐 [OfflineMapManager] Hybrid mode enabled")
    }

    /// Delete a downloaded region
    func deleteRegion(_ region: DownloadedRegion) {
        // Remove from list
        downloadedRegions.removeAll { $0.id == region.id }
        saveDownloadedRegions()

        print("🗑️ [OfflineMapManager] Deleted region: \(region.name)")
    }

    /// Get cache statistics
    func getCacheStats() -> MapTileCache.CacheStats {
        return cache.getCacheStats()
    }

    /// Clear all cached tiles
    func clearAllCache() {
        cache.clearCache()
        downloadedRegions.removeAll()
        saveDownloadedRegions()

        print("🗑️ [OfflineMapManager] All cache cleared")
    }

    // MARK: - Private Methods

    private func saveDownloadedRegion(name: String, center: CLLocationCoordinate2D, radiusKm: Double, sizeBytes: Int64) {
        let region = DownloadedRegion(
            id: UUID(),
            name: name,
            center: DownloadedRegion.Coordinate(latitude: center.latitude, longitude: center.longitude),
            radiusKm: radiusKm,
            downloadDate: Date(),
            lastAccessDate: Date(),
            sizeBytes: sizeBytes
        )

        downloadedRegions.append(region)
        saveDownloadedRegions()

        print("✅ [OfflineMapManager] Region saved: \(name)")
    }

    private func saveDownloadedRegions() {
        if let encoded = try? JSONEncoder().encode(downloadedRegions) {
            UserDefaults.standard.set(encoded, forKey: "downloadedMapRegions")
        }
    }

    private func loadDownloadedRegions() {
        if let data = UserDefaults.standard.data(forKey: "downloadedMapRegions"),
           let decoded = try? JSONDecoder().decode([DownloadedRegion].self, from: data) {
            downloadedRegions = decoded
        }
    }

    private func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLocation.distance(from: toLocation) / 1000.0 // km
    }
}
