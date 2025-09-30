#!/bin/bash

# 🧪 Script de Testing Multi-Hop para MeshRed
# Este script ayuda a buildear y verificar la configuración

echo "🧪 MeshRed Multi-Hop Testing Helper"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Verificar que TestingConfig está configurado
echo "📋 Verificando TestingConfig..."
if grep -q "forceMultiHop = true" MeshRed/TestingConfig.swift; then
    echo "✅ forceMultiHop está activado"
else
    echo "⚠️  forceMultiHop está desactivado"
    echo "   Para testing multi-hop, edita MeshRed/TestingConfig.swift"
fi

# Verificar si hay conexiones bloqueadas configuradas
if grep -q "blockedDirectConnections: \[String: \[String\]\] = \[\]" MeshRed/TestingConfig.swift; then
    echo "⚠️  No hay conexiones bloqueadas configuradas"
    echo "   Edita MeshRed/TestingConfig.swift para agregar pares de dispositivos"
else
    echo "✅ Conexiones bloqueadas configuradas"
    echo ""
    echo "Configuración actual:"
    grep -A 5 "blockedDirectConnections" MeshRed/TestingConfig.swift | grep -v "^--"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Listar dispositivos disponibles
echo "📱 Dispositivos disponibles para testing:"
echo ""
xcrun xctrace list devices 2>&1 | grep -E "iPhone|iPad|Mac" | head -10

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Preguntar si hacer build
read -p "¿Quieres hacer clean build? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🧹 Limpiando build anterior..."
    xcodebuild clean -scheme MeshRed -quiet

    echo "🔨 Building MeshRed..."
    xcodebuild -scheme MeshRed -destination "generic/platform=iOS" -quiet

    if [ $? -eq 0 ]; then
        echo "✅ Build exitoso!"
    else
        echo "❌ Build falló. Revisa errores arriba."
        exit 1
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📖 Instrucciones de Testing:"
echo ""
echo "1. Abre TESTING_MULTIHOP.md para guía completa"
echo "2. Configura TestingConfig con nombres de tus dispositivos"
echo "3. Ejecuta app en 3 dispositivos (A, B, C)"
echo "4. Verifica conexiones: A↔B, B↔C, pero NO A↔C"
echo "5. Envía mensaje de A a C y observa logs"
echo ""
echo "🔍 Para ver logs en tiempo real:"
echo "   xcrun simctl spawn booted log stream --predicate 'subsystem contains \"meshred\"'"
echo ""
echo "✅ Todo listo para testing!"
echo ""