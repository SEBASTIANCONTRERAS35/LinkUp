#!/bin/bash

# 📱 Monitor de Logs para iPhones Físicos - MeshRed/StadiumConnect Pro
# Script especializado para capturar logs de dispositivos físicos

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

LOG_DIR="logs"
DEVICE_LOG_1="$LOG_DIR/device1.log"
DEVICE_LOG_2="$LOG_DIR/device2.log"
COMBINED_LOG="$LOG_DIR/devices_combined.log"

# Crear directorio de logs
mkdir -p "$LOG_DIR"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${CYAN}📱 Monitor de Dispositivos Físicos${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Detectar dispositivos conectados
echo -e "${BLUE}Detectando iPhones conectados...${NC}"
echo ""

# Listar dispositivos
DEVICES=$(xcrun devicectl list devices 2>/dev/null | grep -E "iPhone.*connected" || true)

if [ -z "$DEVICES" ]; then
    # Intentar método alternativo
    DEVICES=$(xcrun xctrace list devices 2>&1 | grep -E "iPhone.*\(" | grep -v "Simulator" || true)
fi

if [ -z "$DEVICES" ]; then
    echo -e "${RED}❌ No se detectaron iPhones conectados${NC}"
    echo ""
    echo "Asegúrate de:"
    echo "1. Conectar los iPhones por USB"
    echo "2. Confiar en esta computadora desde cada iPhone"
    echo "3. Tener Xcode abierto"
    exit 1
fi

echo -e "${GREEN}✅ Dispositivos detectados:${NC}"
echo "$DEVICES"
echo ""

# Extraer UDIDs
DEVICE_COUNT=$(echo "$DEVICES" | wc -l | tr -d ' ')

if [ "$DEVICE_COUNT" -lt 2 ]; then
    echo -e "${YELLOW}⚠️  Solo se detectó 1 dispositivo. Conecta el segundo iPhone.${NC}"
    echo ""
    echo "Continuando con monitoreo de 1 dispositivo..."
    echo ""
fi

# Función para monitorear con Console.app
monitor_with_console() {
    echo -e "${CYAN}📱 Abriendo Console.app para monitoreo visual...${NC}"
    open -a Console.app

    echo ""
    echo -e "${YELLOW}Instrucciones para Console.app:${NC}"
    echo "1. Selecciona tu iPhone en la barra lateral"
    echo "2. En el campo de búsqueda, escribe: EmilioContreras.MeshRed"
    echo "3. Haz clic en 'Start' para comenzar streaming"
    echo "4. Repite para el segundo iPhone"
    echo ""
    echo "Los logs se mostrarán en tiempo real en Console.app"
}

# Función para monitorear con cfgutil (si está instalible)
monitor_with_cfgutil() {
    if ! command -v cfgutil &> /dev/null; then
        echo -e "${YELLOW}⚠️  cfgutil no está instalado${NC}"
        echo "Instala Apple Configurator 2 desde Mac App Store para mejor soporte"
        return 1
    fi

    echo -e "${CYAN}Monitoreando con cfgutil...${NC}"

    # Obtener lista de dispositivos
    cfgutil list | while read line; do
        if echo "$line" | grep -q "iPhone"; then
            UDID=$(echo "$line" | awk '{LoggingService.network.info $1}')
            NAME=$(echo "$line" | awk '{$1=""; LoggingService.network.info $0}')

            echo -e "${GREEN}Monitoreando: $NAME${NC}"
            cfgutil syslog -d "$UDID" | grep "MeshRed" > "$LOG_DIR/device_$UDID.log" &
        fi
    done
}

# Función para análisis en tiempo real
analyze_realtime() {
    echo -e "${CYAN}📊 Análisis en tiempo real activado${NC}"
    echo ""

    tail -f "$COMBINED_LOG" 2>/dev/null | while read line; do
        # Detectar tipos de eventos
        if echo "$line" | grep -q "connected"; then
            echo -e "${GREEN}✅ CONEXIÓN: $line${NC}"
        elif echo "$line" | grep -q "error\|failed"; then
            echo -e "${RED}❌ ERROR: $line${NC}"
        elif echo "$line" | grep -q "UWB\|distance"; then
            echo -e "${CYAN}📍 UWB: $line${NC}"
        elif echo "$line" | grep -q "emergency"; then
            echo -e "${RED}🚨 EMERGENCIA: $line${NC}"
        fi
    done
}

# Menú de opciones
echo "Selecciona método de monitoreo:"
echo ""
echo "1) Console.app (Visual, Recomendado)"
echo "2) Logs en Terminal (Si tienes cfgutil)"
echo "3) Instrucciones para captura manual"
echo "4) Salir"
echo ""

read -p "Opción (1-4): " choice

case $choice in
    1)
        monitor_with_console
        ;;
    2)
        monitor_with_cfgutil || monitor_with_console
        ;;
    3)
        echo ""
        echo -e "${CYAN}📝 Instrucciones para Captura Manual:${NC}"
        echo ""
        echo "OPCIÓN A - Desde Xcode:"
        echo "1. Conecta iPhone 1"
        echo "2. Run app (⌘R)"
        echo "3. Window > Devices and Simulators"
        echo "4. Selecciona el dispositivo"
        echo "5. Click en 'Open Console'"
        echo "6. Filtra por: EmilioContreras.MeshRed"
        echo "7. Repite para iPhone 2"
        echo ""
        echo "OPCIÓN B - Desde Terminal:"
        echo "1. Instala libimobiledevice:"
        echo "   brew install libimobiledevice"
        echo "2. Lista dispositivos:"
        echo "   idevice_id -l"
        echo "3. Ver logs:"
        echo "   idevicesyslog -u UDID | grep MeshRed"
        echo ""
        echo "OPCIÓN C - Con log stream (macOS 12+):"
        echo "   log stream --device 'iPhone de [Nombre]' --predicate 'subsystem == \"EmilioContreras.MeshRed\"'"
        ;;
    4)
        echo "Saliendo..."
        exit 0
        ;;
    *)
        echo -e "${RED}Opción inválida${NC}"
        exit 1
        ;;
esac

# Mantener script activo
if [ "$choice" != "4" ]; then
    echo ""
    echo -e "${YELLOW}Presiona Ctrl+C para detener el monitoreo${NC}"
    echo ""

    # Esperar
    while true; do
        sleep 1
    done
fi