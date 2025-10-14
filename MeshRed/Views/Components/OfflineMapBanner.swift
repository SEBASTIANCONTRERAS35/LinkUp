//
//  OfflineMapBanner.swift
//  MeshRed
//
//  Created for StadiumConnect Pro - Offline Maps System
//  Banner component to prompt user to download offline map tiles
//

import SwiftUI
import os

struct OfflineMapBanner: View {
    let onDownload: () -> Void
    @StateObject private var manager = OfflineMapManager.shared

    var body: some View {
        HStack(spacing: 12) {
            // Download icon
            Image(systemName: "arrow.down.circle.fill")
                .font(.title2)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text("Mapa offline no disponible")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("Descarga ~500MB para uso sin internet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Download button
            Button(action: onDownload) {
                Text("Descargar")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        OfflineMapBanner(onDownload: {
            LoggingService.network.info("Download tapped")
        })

        OfflineMapBanner(onDownload: {})
            .preferredColorScheme(.dark)
    }
    .padding()
}
