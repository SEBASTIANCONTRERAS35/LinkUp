#!/bin/bash

echo "🔧 Corrigiendo errores de self en LoggingService..."

# OfflineMapDownloader.swift línea 69
sed -i '' '69s/zoomLevels/self.zoomLevels/' MeshRed/Services/OfflineMapDownloader.swift

# OfflineTileOverlay.swift líneas 70-71
sed -i '' '70s/allowNetworkFallback/self.allowNetworkFallback/' MeshRed/Services/OfflineTileOverlay.swift
sed -i '' '71s/autoCache/self.autoCache/' MeshRed/Services/OfflineTileOverlay.swift

echo "✅ Correcciones aplicadas"