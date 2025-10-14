#!/bin/bash

# Script rápido para migrar print() a LoggingService
# Para que los logs aparezcan en Console.app

echo "🔄 Migrando prints críticos a LoggingService..."

# Archivos más importantes a migrar
FILES=(
    "MeshRed/Services/NetworkManager.swift"
    "MeshRed/Services/SessionManager.swift"
    "MeshRed/Services/ConnectionOrchestrator.swift"
    "MeshRed/Services/LinkFinderSessionManager.swift"
    "MeshRed/Services/PeerHealthMonitor.swift"
)

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "📝 Procesando: $file"

        # Backup
        cp "$file" "$file.backup"

        # Reemplazos básicos (necesitarás ajustar manualmente algunos)
        # Estos son ejemplos - el script completo sería más complejo

        # Para prints de network
        sed -i '' 's/print("📡/LoggingService.network.info("📡/g' "$file"
        sed -i '' 's/print("🔄/LoggingService.network.info("🔄/g' "$file"
        sed -i '' 's/print("✅/LoggingService.network.info("✅/g' "$file"
        sed -i '' 's/print("❌/LoggingService.network.error("❌/g' "$file"
        sed -i '' 's/print("⚠️/LoggingService.network.warning("⚠️/g' "$file"

        # Para prints de mesh
        sed -i '' 's/print("🕸️/LoggingService.mesh.info("🕸️/g' "$file"
        sed -i '' 's/print("💬/LoggingService.mesh.info("💬/g' "$file"

        # Para prints de UWB
        sed -i '' 's/print("📍/LoggingService.uwb.info("📍/g' "$file"
        sed -i '' 's/print("📏/LoggingService.uwb.info("📏/g' "$file"

        echo "✅ Migrado: $file"
    fi
done

echo ""
echo "⚠️  IMPORTANTE:"
echo "1. Revisa los archivos .backup antes de compilar"
echo "2. Algunos prints pueden necesitar ajuste manual"
echo "3. Agrega 'import os' si no está presente"
echo ""
echo "Para revertir: rename all .backup files back"