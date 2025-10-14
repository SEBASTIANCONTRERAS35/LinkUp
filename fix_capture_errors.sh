#!/bin/bash

# Script para arreglar errores de capture semantics en NetworkManager.swift

FILE="/Users/emiliocontreras/Downloads/MeshRed/MeshRed/Services/NetworkManager.swift"

# Arreglar errores de referencias a propiedades que necesitan self.
sed -i '' 's/\$(\([^)]*\)advertiser \?\([^)]*\))$/\$(self.advertiser \2)/g' "$FILE"
sed -i '' 's/\$(\([^)]*\)connectedPeers\.count\([^)]*\))$/\$(self.connectedPeers.count\2)/g' "$FILE"
sed -i '' 's/\$(\([^)]*\)config\.maxConnections\([^)]*\))$/\$(self.config.maxConnections\2)/g' "$FILE"
sed -i '' 's/\$(\([^)]*\)locationSharingInterval\([^)]*\))$/\$(self.locationSharingInterval\2)/g' "$FILE"
sed -i '' 's/\$(\([^)]*\)connectedPeers \?\([^)]*\))$/\$(self.connectedPeers \2)/g' "$FILE"
sed -i '' 's/\$(\([^)]*\)localPeerID\.displayName\([^)]*\))$/\$(self.localPeerID.displayName\2)/g' "$FILE"
sed -i '' 's/\$(\([^)]*\)session \?\([^)]*\))$/\$(self.session \2)/g' "$FILE"
sed -i '' 's/\$(\([^)]*\)messageStore \?\([^)]*\))$/\$(self.messageStore \2)/g' "$FILE"

echo "Errores de capture arreglados en NetworkManager.swift"
