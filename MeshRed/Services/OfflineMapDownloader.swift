//
//  OfflineMapDownloader.swift
//  MeshRed
//
//  Proactive downloader for map tiles in 20km radius
//  Enables complete offline map functionality for stadium use
//  Downloads ~500-600MB of tiles for offline use
//

import Foundation
import MapKit
import Combine

/// Downloads map tiles for offline use in a specific region
class OfflineMapDownloader: ObservableObject {

    // MARK: - Published Properties

    @Published var isDownloading: Bool = false
    @Published var progress: Double = 0.0
    @Published var downloadedTiles: Int = 0
    @Published var totalTiles: Int = 0
    @Published var downloadedBytes: Int64 = 0
    @Published var estimatedTotalBytes: Int64 = 0
    @Published var error: String?

    // MARK: - Properties

    private let cache = MapTileCache.shared
    private let session: URLSession
    private var downloadTasks: [URLSessionDataTask] = []
    private let queue = DispatchQueue(label: "com.meshred.mapdownloader", attributes: .concurrent)

    /// Zoom levels to download (13-17 for 20km radius)
    private let zoomLevels = [13, 14, 15, 16, 17]

    /// Rate limit: 2 requests per second (OSM requirement)
    private let rateLimitDelay: TimeInterval = 0.5

    /// Average tile size for estimation (bytes)
    private let averageTileSize: Int64 = 80_000 // 80 KB

    // MARK: - Initialization

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public Methods

    /// Download tiles for a 20km radius around center coordinate
    /// - Parameters:
    ///   - center: Center coordinate
    ///   - radiusKm: Radius in kilometers (default 20)
    func downloadRegion(center: CLLocationCoordinate2D, radiusKm: Double = 20.0) {
        guard !isDownloading else {
            print("⚠️ [OfflineMapDownloader] Download already in progress")
            return
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🌍 [OfflineMapDownloader] Starting download")
        print("   Center: \(center.latitude), \(center.longitude)")
        print("   Radius: \(radiusKm) km")
        print("   Zoom levels: \(zoomLevels)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        DispatchQueue.main.async {
            self.isDownloading = true
            self.progress = 0.0
            self.downloadedTiles = 0
            self.downloadedBytes = 0
            self.error = nil
        }

        // Calculate region from radius
        let region = regionFrom(center: center, radiusKm: radiusKm)

        // Calculate all tiles needed
        var allTiles: [(x: Int, y: Int, z: Int)] = []
        for zoom in zoomLevels {
            let tiles = OfflineTileOverlay.tiles(for: region, zoom: zoom)
            allTiles.append(contentsOf: tiles)
        }

        // Filter out already cached tiles
        let tilesToDownload = allTiles.filter { tile in
            !cache.hasTile(z: tile.z, x: tile.x, y: tile.y)
        }

        DispatchQueue.main.async {
            self.totalTiles = tilesToDownload.count
            self.estimatedTotalBytes = Int64(tilesToDownload.count) * self.averageTileSize
        }

        print("📊 [OfflineMapDownloader] Tiles to download: \(tilesToDownload.count)")
        print("   Already cached: \(allTiles.count - tilesToDownload.count)")
        print("   Estimated size: \(String(format: "%.2f", Double(self.estimatedTotalBytes) / 1_048_576.0)) MB")

        // Download tiles sequentially with rate limiting
        downloadTilesSequentially(tiles: tilesToDownload)
    }

    /// Cancel ongoing download
    func cancelDownload() {
        guard isDownloading else { return }

        print("🛑 [OfflineMapDownloader] Cancelling download")

        // Cancel all tasks
        downloadTasks.forEach { $0.cancel() }
        downloadTasks.removeAll()

        DispatchQueue.main.async {
            self.isDownloading = false
            self.progress = 0.0
        }
    }

    // MARK: - Private Methods

    /// Calculate region from center and radius
    private func regionFrom(center: CLLocationCoordinate2D, radiusKm: Double) -> MKCoordinateRegion {
        let radiusMeters = radiusKm * 1000.0
        let region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: radiusMeters * 2,
            longitudinalMeters: radiusMeters * 2
        )
        return region
    }

    /// Download tiles sequentially with rate limiting
    private func downloadTilesSequentially(tiles: [(x: Int, y: Int, z: Int)]) {
        var remainingTiles = tiles
        var downloadedCount = 0

        func downloadNext() {
            guard !remainingTiles.isEmpty else {
                // All tiles downloaded
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.progress = 1.0
                }
                print("✅ [OfflineMapDownloader] Download complete!")
                print("   Total tiles: \(tiles.count)")
                print("   Downloaded: \(String(format: "%.2f", Double(self.downloadedBytes) / 1_048_576.0)) MB")
                return
            }

            let tile = remainingTiles.removeFirst()

            downloadTile(z: tile.z, x: tile.x, y: tile.y) { [weak self] success, bytes in
                guard let self = self else { return }

                if success {
                    downloadedCount += 1

                    DispatchQueue.main.async {
                        self.downloadedTiles = downloadedCount
                        self.downloadedBytes += Int64(bytes)
                        self.progress = Double(downloadedCount) / Double(tiles.count)
                    }
                }

                // Rate limit: wait before next download
                DispatchQueue.global().asyncAfter(deadline: .now() + self.rateLimitDelay) {
                    downloadNext()
                }
            }
        }

        // Start downloading
        downloadNext()
    }

    /// Download a single tile
    private func downloadTile(z: Int, x: Int, y: Int, completion: @escaping (Bool, Int) -> Void) {
        let urlString = "https://tile.openstreetmap.org/\(z)/\(x)/\(y).png"

        guard let url = URL(string: urlString) else {
            completion(false, 0)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("MeshRed/1.0 (StadiumConnect Pro)", forHTTPHeaderField: "User-Agent")

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                print("❌ [OfflineMapDownloader] Failed z=\(z) x=\(x) y=\(y): \(error.localizedDescription)")
                completion(false, 0)
                return
            }

            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                completion(false, 0)
                return
            }

            // Save to cache
            self.cache.saveTile(data: data, z: z, x: x, y: y)
            completion(true, data.count)
        }

        downloadTasks.append(task)
        task.resume()
    }
}
