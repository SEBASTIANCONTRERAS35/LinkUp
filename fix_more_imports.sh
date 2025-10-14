#!/bin/bash

# Agregar import os a archivos adicionales

FILES=(
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
    "MeshRed/ContentView.swift"
    "MeshRed/Views/LinkFinderNavigationView.swift"
    "MeshRed/Views/LinkFinderHubView.swift"
    "MeshRed/Views/NetworkOrchestratorView.swift"
    "MeshRed/Views/LinkFenceCreatorView.swift"
    "MeshRed/Views/Components/OfflineMapBanner.swift"
    "MeshRed Watch App Watch App/WatchEmergencyDetector.swift"
    "MeshRed Watch App Watch App/WatchSOSView.swift"
)

echo "🔧 Agregando import os a archivos adicionales..."

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        if ! grep -q "^import os" "$file"; then
            echo "  ✅ $file"
            last_import_line=$(grep -n "^import " "$file" | tail -1 | cut -d: -f1)
            if [ -n "$last_import_line" ]; then
                sed -i '' "${last_import_line}a\\
import os" "$file"
            fi
        fi
    fi
done

echo "✅ Completado"