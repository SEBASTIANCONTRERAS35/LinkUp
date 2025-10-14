#!/bin/bash

# Script para encontrar colores hardcodeados en el proyecto
# Ejecutar desde la raíz del proyecto: ./find_hardcoded_colors.sh

echo "🔍 Buscando colores hardcodeados en el proyecto MeshRed..."
echo ""
echo "=========================================="
echo "1. Color(hex: ...) - Colores HEX hardcodeados"
echo "=========================================="
grep -rn "Color(hex:" MeshRed/ --include="*.swift" | head -20

echo ""
echo "=========================================="
echo "2. Mundial2026Colors - Colores del tema original"
echo "=========================================="
grep -rn "Mundial2026Colors" MeshRed/ --include="*.swift" | head -30

echo ""
echo "=========================================="
echo "3. Color.blue, Color.green, etc. - Colores del sistema"
echo "=========================================="
grep -rn "Color\.\(blue\|green\|red\|purple\|cyan\|teal\|indigo\|mint\|orange\|yellow\|pink\)" MeshRed/ --include="*.swift" | grep -v "// " | head -30

echo ""
echo "=========================================="
echo "4. UIColor.systemBlue, etc. - UIColors del sistema"
echo "=========================================="
grep -rn "UIColor\.\(systemBlue\|systemGreen\|systemRed\|systemPurple\|systemCyan\|systemTeal\)" MeshRed/ --include="*.swift" | head -20

echo ""
echo "=========================================="
echo "5. Color(.systemBackground) - Fondos del sistema"
echo "=========================================="
grep -rn "Color(\.\(systemBackground\|secondarySystemBackground\|tertiarySystemBackground\))" MeshRed/ --include="*.swift" | head -20

echo ""
echo "=========================================="
echo "📊 Resumen de archivos con colores"
echo "=========================================="
echo "Archivos con Mundial2026Colors:"
grep -rl "Mundial2026Colors" MeshRed/ --include="*.swift" | wc -l

echo "Archivos con Color(hex:):"
grep -rl "Color(hex:" MeshRed/ --include="*.swift" | wc -l

echo "Archivos con colores del sistema (Color.blue, etc.):"
grep -rl "Color\.\(blue\|green\|red\|purple\|cyan\)" MeshRed/ --include="*.swift" | wc -l

echo ""
echo "✅ Búsqueda completada. Revisa los resultados arriba."
echo "💡 Considera reemplazar estos colores con los nuevos del sistema:"
echo "   - Color.appPrimary (Violeta)"
echo "   - Color.appSecondary (Cyan)"
echo "   - Color.appAccent (Teal)"
echo "   - Color.appBackgroundDark (Fondo oscuro)"
echo "   - Color.appBackgroundSecondary (Fondo secundario)"
