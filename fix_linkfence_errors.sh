#!/bin/bash

echo "🔧 Corrigiendo errores en LinkFenceManager..."

# Línea 353
sed -i '' '353s/activeGeofences/self.activeGeofences/' MeshRed/Services/LinkFenceManager.swift

# Línea 378
sed -i '' '378s/activeGeofences/self.activeGeofences/' MeshRed/Services/LinkFenceManager.swift

# Línea 458
sed -i '' '458s/myGeofences/self.myGeofences/' MeshRed/Services/LinkFenceManager.swift

# Línea 459
sed -i '' '459s/linkfenceHistory/self.linkfenceHistory/' MeshRed/Services/LinkFenceManager.swift

# Línea 460
sed -i '' '460s/activeGeofences/self.activeGeofences/' MeshRed/Services/LinkFenceManager.swift

# Línea 602
sed -i '' '602s/myGeofences/self.myGeofences/' MeshRed/Services/LinkFenceManager.swift

# Línea 648
sed -i '' '648s/activeGeofences/self.activeGeofences/' MeshRed/Services/LinkFenceManager.swift

# Línea 655
sed -i '' '655s/activeGeofences/self.activeGeofences/' MeshRed/Services/LinkFenceManager.swift

# Línea 720 - CLAuthorizationStatus
sed -i '' '720s/\\(status\\)/String(describing: \\1)/' MeshRed/Services/LinkFenceManager.swift

echo "✅ Correcciones aplicadas a LinkFenceManager"