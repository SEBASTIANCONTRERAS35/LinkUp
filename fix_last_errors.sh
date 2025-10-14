#!/bin/bash

echo "🔧 Corrigiendo últimos errores de self..."

# MessageStore.swift
sed -i '' '119s/messages/self.messages/' MeshRed/Services/MessageStore.swift
sed -i '' '120s/activeConversationId/self.activeConversationId/' MeshRed/Services/MessageStore.swift
sed -i '' '128s/activeConversationId/self.activeConversationId/' MeshRed/Services/MessageStore.swift
sed -i '' '136s/conversationSummaries/self.conversationSummaries/' MeshRed/Services/MessageStore.swift

# NetworkConfig.swift
sed -i '' '57s/networkMode/self.networkMode/' MeshRed/NetworkConfig.swift
sed -i '' '64s/debugMode/self.debugMode/' MeshRed/NetworkConfig.swift

echo "✅ Correcciones aplicadas"