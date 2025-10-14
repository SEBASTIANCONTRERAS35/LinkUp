#!/bin/bash

echo "🔧 Corrigiendo últimos errores específicos..."
echo ""

# ARKitResourceManager.swift línea 361 - ThermalState no se puede convertir
echo "  ✅ Corrigiendo ARKitResourceManager.swift línea 361"
sed -i '' '361s/\(thermalState\)/String(describing: \1)/' MeshRed/Services/ARKitResourceManager.swift

# AudioManager.swift línea 162 - AudioPriority no se puede convertir
echo "  ✅ Corrigiendo AudioManager.swift línea 162"
sed -i '' '162s/\(priority\)/String(describing: \1)/' MeshRed/Services/AudioManager.swift

# AudioManager.swift línea 195 - self.messageQueue
echo "  ✅ Corrigiendo AudioManager.swift línea 195"
sed -i '' '195s/messageQueue/self.messageQueue/' MeshRed/Services/AudioManager.swift

# HapticManager.swift líneas 119-120, 177 - self.settings
echo "  ✅ Corrigiendo HapticManager.swift líneas 119, 120, 177"
sed -i '' '119s/settings\.hapticsEnabled/self.settings.hapticsEnabled/' MeshRed/Services/HapticManager.swift
sed -i '' '120s/settings\.hapticIntensity/self.settings.hapticIntensity/' MeshRed/Services/HapticManager.swift
sed -i '' '177s/settings\.hapticsEnabled/self.settings.hapticsEnabled/' MeshRed/Services/HapticManager.swift

# HapticManager.swift línea 137 - CHHapticEngine.StoppedReason
echo "  ✅ Corrigiendo HapticManager.swift línea 137"
sed -i '' '137s/\(reason\)/String(describing: \1)/' MeshRed/Services/HapticManager.swift

# LightningMeshManager.swift líneas 106, 258 - self.config
echo "  ✅ Corrigiendo LightningMeshManager.swift líneas 106, 258"
sed -i '' '106s/config\.maxConnections/self.config.maxConnections/' MeshRed/Services/LightningMeshManager.swift
sed -i '' '258s/config\.maxRetries/self.config.maxRetries/' MeshRed/Services/LightningMeshManager.swift

# LinkFenceManager.swift línea 123 - self.activeGeofences
echo "  ✅ Corrigiendo LinkFenceManager.swift línea 123"
sed -i '' '123s/activeGeofences/self.activeGeofences/' MeshRed/Services/LinkFenceManager.swift

# Corregir errores de CustomStringConvertible agregando String(describing:)
echo ""
echo "🔧 Corrigiendo errores de CustomStringConvertible..."

# HapticManager - BasicHapticType y otros
sed -i '' 's/\\(\(BasicHapticType\|GeofenceTransitionType\|HapticPatternType\)[^,)]*\)/String(describing: \\(\1\))/g' MeshRed/Services/HapticManager.swift 2>/dev/null || true

# LightningMeshManager - ConnectionStrategy
sed -i '' 's/\\(\(ConnectionStrategy\)[^,)]*\)/String(describing: \\(\1\))/g' MeshRed/Services/LightningMeshManager.swift 2>/dev/null || true

echo ""
echo "✅ Correcciones finales aplicadas"