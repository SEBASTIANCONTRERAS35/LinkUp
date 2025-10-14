#!/bin/bash

# Script para agregar import os a todos los archivos que usan LoggingService

echo "🔧 Agregando 'import os' a archivos que usan LoggingService..."

# Lista de archivos que necesitan import os
FILES=(
    "MeshRed/MessageCache.swift"
    "MeshRed/AckManager.swift"
    "MeshRed/MessageQueue.swift"
    "MeshRed/NetworkConfig.swift"
    "MeshRed/Services/MessageStore.swift"
    "MeshRed/Services/AudioManager.swift"
    "MeshRed/Services/ConnectionMutex.swift"
    "MeshRed/Services/ConnectionManager.swift"
    "MeshRed/Services/ConnectionPoolManager.swift"
    "MeshRed/Services/ConnectionOrchestrator.swift"
    "MeshRed/Services/DataCleaner.swift"
    "MeshRed/Services/FallbackDirectionService.swift"
    "MeshRed/Services/FamilyGroupManager.swift"
    "MeshRed/Services/FastTrackSessionManager.swift"
    "MeshRed/Services/GeofenceManager.swift"
    "MeshRed/Services/HapticManager.swift"
    "MeshRed/Services/KeepAliveManager.swift"
    "MeshRed/Services/LeaderElection.swift"
    "MeshRed/Services/LightningMeshManager.swift"
    "MeshRed/Services/LinkFinderSessionManager.swift"
    "MeshRed/Services/LinkFenceManager.swift"
    "MeshRed/Services/LocationRequestManager.swift"
    "MeshRed/Services/LocationService.swift"
    "MeshRed/Services/MapTileCache.swift"
    "MeshRed/Services/MockConnectionManager.swift"
    "MeshRed/Services/MotionPermissionManager.swift"
    "MeshRed/Services/NavigationCalculator.swift"
    "MeshRed/Services/NetworkManager+Lightning.swift"
    "MeshRed/Services/NetworkManager+LiveActivity.swift"
    "MeshRed/Services/NetworkManager+Orchestrator.swift"
    "MeshRed/Services/OfflineMapDownloader.swift"
    "MeshRed/Services/OfflineMapManager.swift"
    "MeshRed/Services/PeerHealthMonitor.swift"
    "MeshRed/Services/PeerLocationTracker.swift"
    "MeshRed/Services/PeerReputationSystem.swift"
    "MeshRed/Services/ProximityHapticEngine.swift"
    "MeshRed/Services/RouteCache.swift"
    "MeshRed/Services/SessionManager.swift"
    "MeshRed/Services/StadiumMode.swift"
    "MeshRed/Services/StadiumModeManager.swift"
    "MeshRed/Services/UWBPriorityManager.swift"
    "MeshRed/Services/ARKitResourceManager.swift"
    "MeshRed/Services/AdaptiveBackoffManager.swift"
)

# Para cada archivo, verificar si existe y agregar import os si no está presente
for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        # Verificar si ya tiene import os
        if ! grep -q "^import os" "$file"; then
            echo "  ✅ Agregando import os a: $file"

            # Buscar la última línea de import y agregar import os después
            if grep -q "^import " "$file"; then
                # Obtener el número de línea del último import
                last_import_line=$(grep -n "^import " "$file" | tail -1 | cut -d: -f1)

                # Insertar import os después del último import
                sed -i '' "${last_import_line}a\\
import os" "$file"
            else
                # Si no hay imports, agregar al principio después de los comentarios
                # Buscar la primera línea que no sea comentario o vacía
                first_code_line=$(grep -n -v "^//" "$file" | grep -v "^$" | head -1 | cut -d: -f1)

                if [ -n "$first_code_line" ]; then
                    sed -i '' "${first_code_line}i\\
import os\\
" "$file"
                fi
            fi
        else
            echo "  ⏭️  Ya tiene import os: $file"
        fi
    else
        echo "  ⚠️  Archivo no encontrado: $file"
    fi
done

echo ""
echo "✅ Proceso completado"
echo ""
echo "Ahora compilando para verificar..."