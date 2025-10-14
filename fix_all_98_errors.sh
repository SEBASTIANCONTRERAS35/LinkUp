#!/bin/bash

echo "🔧 Corrigiendo TODOS los 98 errores de self en MessageStore y otros archivos..."
echo ""

# MessageStore.swift - Todos los errores línea por línea
echo "📝 Procesando MessageStore.swift..."
sed -i '' '188s/activeConversationId/self.activeConversationId/' MeshRed/Services/MessageStore.swift
sed -i '' '258s/activeConversationId/self.activeConversationId/' MeshRed/Services/MessageStore.swift
sed -i '' '308s/activeConversationId/self.activeConversationId/' MeshRed/Services/MessageStore.swift
sed -i '' '310s/conversations\[/self.conversations[/' MeshRed/Services/MessageStore.swift
sed -i '' '310s/\] ?? activeConversationId/] ?? self.activeConversationId/' MeshRed/Services/MessageStore.swift
sed -i '' '311s/conversations\[/self.conversations[/' MeshRed/Services/MessageStore.swift
sed -i '' '376s/conversations/self.conversations/' MeshRed/Services/MessageStore.swift
sed -i '' '377s/activeConversationId/self.activeConversationId/' MeshRed/Services/MessageStore.swift
sed -i '' '395s/metadata/self.metadata/' MeshRed/Services/MessageStore.swift
sed -i '' '518s/conversations/self.conversations/' MeshRed/Services/MessageStore.swift

echo "  ✅ MessageStore.swift procesado"

# Ahora un procesamiento más agresivo para todos los archivos
echo ""
echo "🔧 Aplicando correcciones masivas a todos los archivos..."

FILES=(
    "MeshRed/Services/MessageStore.swift"
    "MeshRed/Services/MockConnectionManager.swift"
    "MeshRed/Services/MotionPermissionManager.swift"
    "MeshRed/Services/NavigationCalculator.swift"
    "MeshRed/Services/NetworkManager.swift"
    "MeshRed/Services/NetworkManager+Lightning.swift"
    "MeshRed/Services/NetworkManager+LiveActivity.swift"
    "MeshRed/Services/NetworkManager+Orchestrator.swift"
    "MeshRed/Services/OfflineMapDownloader.swift"
    "MeshRed/Services/OfflineMapManager.swift"
    "MeshRed/Services/OfflineTileOverlay.swift"
    "MeshRed/Services/PeerHealthMonitor.swift"
    "MeshRed/Services/PeerLocationTracker.swift"
    "MeshRed/Services/ProximityHapticEngine.swift"
    "MeshRed/Services/RouteCache.swift"
    "MeshRed/Services/SessionManager.swift"
    "MeshRed/Services/StadiumMode.swift"
    "MeshRed/Services/StadiumModeManager.swift"
    "MeshRed/Services/UWBPriorityManager.swift"
    "MeshRed/Services/LocationRequestManager.swift"
    "MeshRed/Services/LocationService.swift"
    "MeshRed/Services/MapTileCache.swift"
    "MeshRed/Services/AdaptiveBackoffManager.swift"
    "MeshRed/Services/LeaderElection.swift"
    "MeshRed/Services/AudioManager.swift"
    "MeshRed/Services/ConnectionManager.swift"
    "MeshRed/Services/ConnectionMutex.swift"
    "MeshRed/Services/ConnectionOrchestrator.swift"
    "MeshRed/Services/ConnectionPoolManager.swift"
    "MeshRed/Services/DataCleaner.swift"
    "MeshRed/Services/FallbackDirectionService.swift"
    "MeshRed/Services/FamilyGroupManager.swift"
    "MeshRed/Services/FastTrackSessionManager.swift"
    "MeshRed/Services/FirstMessageTracker.swift"
    "MeshRed/Services/HapticManager.swift"
    "MeshRed/Services/KeepAliveManager.swift"
    "MeshRed/Services/LightningMeshManager.swift"
    "MeshRed/Services/LinkFinderSessionManager.swift"
    "MeshRed/Services/LinkFenceManager.swift"
    "MeshRed/Services/MessageReadStateManager.swift"
    "MeshRed/Services/MotionPermissionManager.swift"
    "MeshRed/Services/ARKitResourceManager.swift"
    "MeshRed/Services/PeerReputationSystem.swift"
    "MeshRed/NetworkConfig.swift"
    "MeshRed/MessageQueue.swift"
    "MeshRed/MessageCache.swift"
    "MeshRed/AckManager.swift"
    "MeshRed/RoutingTable.swift"
    "MeshRed/MeshRedApp.swift"
    "MeshRed/ContentView.swift"
    "MeshRed/Models/EmergencyMedicalProfile.swift"
    "MeshRed/Models/MockDataManager.swift"
    "MeshRed/Models/MockFamilyGroupsManager.swift"
    "MeshRed/Models/RelativeLocation.swift"
    "MeshRed/Settings/UserDisplayNameManager.swift"
    "MeshRed/Settings/StadiumModeSettingsView.swift"
    "MeshRed/Views/MessagingDashboardView.swift"
    "MeshRed/Views/NetworkHubView.swift"
    "MeshRed/Views/MainDashboardContainer.swift"
    "MeshRed/Views/StadiumDashboardView.swift"
    "MeshRed/Views/Components/RequestApprovalPopup.swift"
    "MeshRed/Views/Components/FirstMessagePopup.swift"
    "MeshRed/Views/ImprovedHomeView.swift"
    "MeshRed/Views/NetworkManagementView.swift"
    "MeshRed/Views/SinglePeerRadarView.swift"
    "MeshRed/Views/WalkingTriangulationView.swift"
    "MeshRed/Views/RadarSweepSystem.swift"
    "MeshRed/Views/SOSView.swift"
    "MeshRed/Views/JoinFamilyGroupView.swift"
    "MeshRed/Views/FamilyGroupView.swift"
    "MeshRed/Views/LinkFinderNavigationView.swift"
    "MeshRed/Views/LinkFinderHubView.swift"
    "MeshRed/Views/NetworkOrchestratorView.swift"
    "MeshRed/Views/LinkFenceCreatorView.swift"
    "MeshRed/Views/Components/OfflineMapBanner.swift"
)

# Función para agregar self. a propiedades comunes en LoggingService
add_self_to_properties() {
    local file=$1

    if [ -f "$file" ]; then
        # Backup
        cp "$file" "$file.backup3"

        # Lista de propiedades comunes que necesitan self
        local properties=(
            "messages"
            "activeConversationId"
            "conversations"
            "metadata"
            "conversationSummaries"
            "networkMode"
            "debugMode"
            "connectionPool"
            "networkState"
            "config"
            "settings"
            "motionManager"
            "baseDirectory"
            "stats"
            "historicalMemberPeerIDs"
            "sentFirstMessages"
            "activeConversations"
            "pendingRequests"
            "rejectedRequests"
            "deferredRequests"
            "supportsHaptics"
            "currentPriority"
            "pingInterval"
            "pingCount"
            "advertisers"
            "browsers"
            "myGeofences"
            "activeGeofences"
            "linkfenceHistory"
            "blockedPeers"
            "preferredPeers"
            "slots"
            "slotConfiguration"
            "totalCapacity"
            "messageQueue"
            "batteryLevel"
            "networkLoad"
            "isLeader"
            "lastZone"
            "currentZone"
            "lastDirection"
            "currentDirection"
            "zoomLevels"
            "allowNetworkFallback"
            "autoCache"
            "keepAliveManager"
            "groupStates"
        )

        # Aplicar self. a cada propiedad dentro de LoggingService.network.info
        for prop in "${properties[@]}"; do
            # Solo dentro de líneas que contienen LoggingService
            sed -i '' "/LoggingService/s/\([^.]\)\($prop\)/\1self.\2/g" "$file" 2>/dev/null || true
        done

        # Limpiar self.self. duplicados
        sed -i '' 's/self\.self\./self./g' "$file"

        # Limpiar self en lugares incorrectos
        sed -i '' 's/self\.String(/String(/g' "$file"
        sed -i '' 's/self\.Date(/Date(/g' "$file"
        sed -i '' 's/self\.UUID(/UUID(/g' "$file"
        sed -i '' 's/self\.Int(/Int(/g' "$file"
        sed -i '' 's/self\.Float(/Float(/g' "$file"
        sed -i '' 's/self\.Double(/Double(/g' "$file"
        sed -i '' 's/self\.Bool(/Bool(/g' "$file"
        sed -i '' 's/self\.true/true/g' "$file"
        sed -i '' 's/self\.false/false/g' "$file"
        sed -i '' 's/self\.nil/nil/g' "$file"
        sed -i '' 's/self\.error/error/g' "$file"
        sed -i '' 's/self\.\"/\"/g' "$file"

        echo "  ✅ Procesado: $(basename $file)"
    fi
}

# Procesar cada archivo
for file in "${FILES[@]}"; do
    add_self_to_properties "$file"
done

echo ""
echo "🔧 Aplicando correcciones específicas adicionales..."

# Correcciones específicas que sabemos que fallan
sed -i '' 's/\\(formatDuration(duration)/\\(self.formatDuration(duration)/' MeshRed/Services/StadiumModeManager.swift 2>/dev/null || true
sed -i '' 's/\\(getEstimatedCapacity()/\\(self.getEstimatedCapacity()/' MeshRed/Services/StadiumMode.swift 2>/dev/null || true

echo ""
echo "✅ Todas las correcciones aplicadas"
echo ""
echo "📝 Nota: Es posible que algunos errores requieran ajuste manual adicional"