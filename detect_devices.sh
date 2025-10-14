#!/bin/bash

# Script mejorado para detectar y mostrar dispositivos iOS correctamente

echo "🔍 Detectando dispositivos iOS conectados..."
echo ""

# Método 1: devicectl (más confiable)
echo "=== Usando devicectl ==="
xcrun devicectl list devices 2>/dev/null | grep -E "iPhone|iPad" | while IFS= read -r line; do
    if [[ ! "$line" =~ "Simulator" ]]; then
        echo "$line"
        # Extraer UDID (último elemento que parece un UUID)
        UDID=$(echo "$line" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | tail -1)
        if [ -n "$UDID" ]; then
            echo "   UDID: $UDID"
            echo "   Comando para logs: xcrun devicectl syslog --device $UDID | grep MeshRed"
        fi
        echo ""
    fi
done

echo ""
echo "=== Usando xctrace ==="
xcrun xctrace list devices 2>&1 | grep -E "iPhone|iPad" | grep -v Simulator | head -5

echo ""
echo "=== Dispositivos USB conectados ==="
system_profiler SPUSBDataType 2>/dev/null | grep -A 10 -E "iPhone|iPad" | grep -E "Serial Number:|Version:|Manufacturer:" || echo "No se detectaron dispositivos USB"

echo ""
echo "📝 Para obtener el UDID desde Xcode:"
echo "1. Abre Xcode"
echo "2. Window → Devices and Simulators"
echo "3. Selecciona tu dispositivo"
echo "4. Copia el 'Identifier' (UDID)"

echo ""
echo "🎯 Para monitorear logs de un dispositivo específico:"
echo "log stream --device 'Nombre del iPhone' --predicate 'subsystem == \"EmilioContreras.MeshRed\"'"