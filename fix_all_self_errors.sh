#!/bin/bash

echo "🔧 Corrigiendo TODOS los errores de self en LoggingService..."
echo ""

# Array de correcciones basadas en los errores encontrados
declare -a fixes=(
    # FirstMessageTracker.swift
    "MeshRed/Services/FirstMessageTracker.swift:89:s/sentFirstMessages/self.sentFirstMessages/"
    "MeshRed/Services/FirstMessageTracker.swift:100:s/activeConversations/self.activeConversations/"
    "MeshRed/Services/FirstMessageTracker.swift:283:s/sentFirstMessages/self.sentFirstMessages/"
    "MeshRed/Services/FirstMessageTracker.swift:289:s/activeConversations/self.activeConversations/"
    "MeshRed/Services/FirstMessageTracker.swift:297:s/pendingRequests/self.pendingRequests/"
    "MeshRed/Services/FirstMessageTracker.swift:303:s/rejectedRequests/self.rejectedRequests/"
    "MeshRed/Services/FirstMessageTracker.swift:309:s/deferredRequests/self.deferredRequests/"
    "MeshRed/Services/FirstMessageTracker.swift:342:s/sentFirstMessages/self.sentFirstMessages/"
    "MeshRed/Services/FirstMessageTracker.swift:343:s/activeConversations/self.activeConversations/"

    # HapticManager.swift
    "MeshRed/Services/HapticManager.swift:118:s/supportsHaptics/self.supportsHaptics/"
    "MeshRed/Services/HapticManager.swift:119:s/settings\.hapticIntensity/self.settings.hapticIntensity/"
    "MeshRed/Services/HapticManager.swift:120:s/settings\.hapticEnabled/self.settings.hapticEnabled/"
    "MeshRed/Services/HapticManager.swift:177:s/settings\.hapticIntensity/self.settings.hapticIntensity/"

    # KeepAliveManager.swift
    "MeshRed/Services/KeepAliveManager.swift:73:s/pingInterval/self.pingInterval/"
    "MeshRed/Services/KeepAliveManager.swift:88:s/pingCount/self.pingCount/"
    "MeshRed/Services/KeepAliveManager.swift:141:s/pingCount/self.pingCount/"

    # LightningMeshManager.swift
    "MeshRed/Services/LightningMeshManager.swift:106:s/config\.maxConnections/self.config.maxConnections/"
    "MeshRed/Services/LightningMeshManager.swift:171:s/advertisers/self.advertisers/"
    "MeshRed/Services/LightningMeshManager.swift:186:s/browsers/self.browsers/"
    "MeshRed/Services/LightningMeshManager.swift:255:s/config\.connectionTimeout/self.config.connectionTimeout/"
    "MeshRed/Services/LightningMeshManager.swift:258:s/config\.maxRetries/self.config.maxRetries/"

    # LinkFenceManager.swift
    "MeshRed/Services/LinkFenceManager.swift:63:s/myGeofences/self.myGeofences/"
    "MeshRed/Services/LinkFenceManager.swift:64:s/activeGeofences/self.activeGeofences/"
)

# Aplicar cada corrección
for fix in "${fixes[@]}"; do
    # Extraer archivo y línea
    file=$(echo "$fix" | cut -d: -f1)
    line=$(echo "$fix" | cut -d: -f2)
    pattern=$(echo "$fix" | cut -d: -f3)

    if [ -f "$file" ]; then
        echo "  ✅ Corrigiendo $file línea $line"
        # Aplicar sed en la línea específica
        sed -i '' "${line}${pattern}" "$file"
    else
        echo "  ⚠️  Archivo no encontrado: $file"
    fi
done

echo ""
echo "🔧 Corrigiendo más archivos encontrados..."

# Más archivos con errores de self
FILES=(
    "MeshRed/Services/LocationRequestManager.swift"
    "MeshRed/Services/LocationService.swift"
    "MeshRed/Services/MapTileCache.swift"
    "MeshRed/Services/MockConnectionManager.swift"
    "MeshRed/Services/NavigationCalculator.swift"
    "MeshRed/Services/NetworkManager+Lightning.swift"
    "MeshRed/Services/NetworkManager+LiveActivity.swift"
    "MeshRed/Services/NetworkManager+Orchestrator.swift"
    "MeshRed/Services/OfflineMapManager.swift"
    "MeshRed/Services/PeerHealthMonitor.swift"
    "MeshRed/Services/PeerLocationTracker.swift"
    "MeshRed/Services/PeerReputationSystem.swift"
    "MeshRed/Services/RouteCache.swift"
    "MeshRed/Services/SessionManager.swift"
    "MeshRed/Services/StadiumModeManager.swift"
    "MeshRed/Services/UWBPriorityManager.swift"
    "MeshRed/Services/AdaptiveBackoffManager.swift"
    "MeshRed/Services/LeaderElection.swift"
    "MeshRed/Services/AudioManager.swift"
    "MeshRed/Services/MessageStore.swift"
    "MeshRed/Services/DataCleaner.swift"
    "MeshRed/Services/FastTrackSessionManager.swift"
    "MeshRed/Services/LinkFinderSessionManager.swift"
    "MeshRed/Services/MotionPermissionManager.swift"
    "MeshRed/Services/ARKitResourceManager.swift"
)

echo ""
echo "📝 Analizando y corrigiendo archivos adicionales..."

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        # Buscar líneas con LoggingService que puedan necesitar self
        if grep -q "LoggingService" "$file"; then
            echo "  🔍 Procesando: $file"

            # Hacer backup
            cp "$file" "$file.backup2"

            # Agregar self. donde sea necesario en interpolaciones
            # Este es un patrón genérico que intenta ser conservador
            sed -i '' -E 's/\\([^)]+ ([a-z][a-zA-Z0-9_]*)\)/\\(\1 self.\2)/g' "$file" 2>/dev/null || true

            # Revertir algunos cambios incorrectos
            sed -i '' 's/self\.self\./self./g' "$file"
            sed -i '' 's/self\.String(/String(/g' "$file"
            sed -i '' 's/self\.Date(/Date(/g' "$file"
            sed -i '' 's/self\.UUID(/UUID(/g' "$file"
            sed -i '' 's/self\.true/true/g' "$file"
            sed -i '' 's/self\.false/false/g' "$file"
            sed -i '' 's/self\.nil/nil/g' "$file"
        fi
    fi
done

echo ""
echo "✅ Correcciones de self aplicadas"
echo ""
echo "⚠️  NOTA: Algunos errores pueden requerir ajuste manual"
echo "   - Errores de CustomStringConvertible"
echo "   - Errores de tipos no convertibles"