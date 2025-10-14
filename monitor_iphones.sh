#!/bin/bash

# Monitor específico para tus 2 iPhones

echo "📱 Monitor de Logs para Testing P2P"
echo "===================================="
echo ""
echo "Dispositivos detectados:"
echo "1. iPhone 17 Pro (BICHOTEE)"
echo "2. iPhone 11 (Jose Guadalupe)"
echo ""

# UDIDs de tus dispositivos
IPHONE_17_PRO="7AE60277-61C6-5CBE-8CCC-2E099AAA989A"
IPHONE_11="0D523323-EB8A-5F17-87DF-C954A13DC4E7"

LOG_DIR="logs"
mkdir -p "$LOG_DIR"

echo "Selecciona opción:"
echo "1) Monitorear iPhone 17 Pro"
echo "2) Monitorear iPhone 11"
echo "3) Monitorear AMBOS (split screen)"
echo "4) Guardar logs de ambos en archivos"
echo ""
read -p "Opción (1-4): " choice

case $choice in
    1)
        echo "📱 Monitoreando iPhone 17 Pro..."
        echo "Presiona Ctrl+C para detener"
        echo ""
        xcrun devicectl syslog --device "$IPHONE_17_PRO" | grep --line-buffered "MeshRed"
        ;;
    2)
        echo "📱 Monitoreando iPhone 11..."
        echo "Presiona Ctrl+C para detener"
        echo ""
        xcrun devicectl syslog --device "$IPHONE_11" | grep --line-buffered "MeshRed"
        ;;
    3)
        echo "📱 Monitoreando AMBOS dispositivos..."
        echo "Abriendo en terminales separadas..."

        # Terminal 1
        osascript -e 'tell app "Terminal" to do script "xcrun devicectl syslog --device '"$IPHONE_17_PRO"' | grep --line-buffered MeshRed | sed \"s/^/[iPhone 17 Pro] /\""'

        # Terminal 2
        osascript -e 'tell app "Terminal" to do script "xcrun devicectl syslog --device '"$IPHONE_11"' | grep --line-buffered MeshRed | sed \"s/^/[iPhone 11] /\""'

        echo ""
        echo "✅ Abrí 2 ventanas de Terminal con los logs"
        echo "Presiona Ctrl+C en cada ventana para detener"
        ;;
    4)
        echo "💾 Guardando logs en archivos..."
        echo "iPhone 17 Pro → logs/iphone17pro.log"
        echo "iPhone 11 → logs/iphone11.log"
        echo ""
        echo "Presiona Ctrl+C para detener"

        # Iniciar ambos en background
        xcrun devicectl syslog --device "$IPHONE_17_PRO" | grep --line-buffered "MeshRed" > "$LOG_DIR/iphone17pro.log" 2>&1 &
        PID1=$!

        xcrun devicectl syslog --device "$IPHONE_11" | grep --line-buffered "MeshRed" > "$LOG_DIR/iphone11.log" 2>&1 &
        PID2=$!

        # Mostrar logs combinados en tiempo real
        tail -f "$LOG_DIR/iphone17pro.log" "$LOG_DIR/iphone11.log"

        # Cleanup al salir
        trap "kill $PID1 $PID2 2>/dev/null" EXIT
        ;;
    *)
        echo "Opción inválida"
        exit 1
        ;;
esac