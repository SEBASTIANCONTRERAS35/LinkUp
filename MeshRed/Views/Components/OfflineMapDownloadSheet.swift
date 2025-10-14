//
//  OfflineMapDownloadSheet.swift
//  MeshRed
//
//  Created for StadiumConnect Pro - Offline Maps System
//  Pop-up sheet to prompt user to download offline map tiles
//

import SwiftUI
import MapKit

struct OfflineMapDownloadSheet: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var manager = OfflineMapManager.shared

    let center: CLLocationCoordinate2D
    let locationName: String
    let radiusKm: Double

    @State private var isDownloading = false
    @State private var showDownloadComplete = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 100, height: 100)

                    Image(systemName: isDownloading ? "arrow.down.circle.fill" : "map.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                        .symbolEffect(.bounce, value: isDownloading)
                }
                .padding(.top, 20)

                // Title
                VStack(spacing: 8) {
                    Text(isDownloading ? "Descargando Mapa..." : "Mapa Offline No Disponible")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text(isDownloading ? "Esto puede tardar varios minutos" : "Descarga mapas para usar sin internet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Info cards
                if !isDownloading {
                    VStack(spacing: 12) {
                        InfoCard(
                            icon: "mappin.circle.fill",
                            title: "Área de Descarga",
                            value: "\(Int(radiusKm)) km alrededor",
                            color: .green
                        )

                        InfoCard(
                            icon: "square.and.arrow.down.fill",
                            title: "Tamaño de Descarga",
                            value: "~500 MB",
                            color: .orange
                        )

                        InfoCard(
                            icon: "wifi.slash",
                            title: "Uso Sin Internet",
                            value: "100% funcional offline",
                            color: .blue
                        )
                    }
                }

                // Progress bar (shown during download)
                if isDownloading {
                    VStack(spacing: 12) {
                        ProgressView(value: manager.downloader.progress)
                            .progressViewStyle(.linear)
                            .tint(.blue)

                        HStack {
                            Text("\(manager.downloader.downloadedTiles) / \(manager.downloader.totalTiles) tiles")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text("\(Int(manager.downloader.progress * 100))%")
                                .font(.caption.bold())
                                .foregroundColor(.blue)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    if !isDownloading {
                        // Download button
                        Button(action: startDownload) {
                            Label("Descargar Mapa Offline", systemImage: "arrow.down.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(14)
                        }

                        // Not now button
                        Button(action: { dismiss() }) {
                            Text("Ahora No")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    } else {
                        // Cancel button
                        Button(action: cancelDownload) {
                            Text("Cancelar Descarga")
                                .font(.subheadline)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("Mapas Offline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isDownloading {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Cerrar") {
                            dismiss()
                        }
                    }
                }
            }
            .alert("¡Descarga Completa!", isPresented: $showDownloadComplete) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Los mapas offline están listos para usar. Ahora puedes usar la app sin conexión a internet.")
            }
        }
    }

    private func startDownload() {
        isDownloading = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        manager.downloadRegion(
            center: center,
            name: locationName,
            radiusKm: radiusKm
        )

        // Monitor progress
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if manager.downloader.progress >= 1.0 {
                timer.invalidate()
                isDownloading = false
                showDownloadComplete = true
            }
        }
    }

    private func cancelDownload() {
        manager.downloader.cancelDownload()
        isDownloading = false
        dismiss()
    }
}

// MARK: - Info Card Component
struct InfoCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 50, height: 50)

                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
            }

            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Preview
#Preview {
    OfflineMapDownloadSheet(
        center: CLLocationCoordinate2D(latitude: 19.302778, longitude: -99.150556),
        locationName: "Estadio Azteca",
        radiusKm: 20.0
    )
}
