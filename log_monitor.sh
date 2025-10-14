#!/bin/bash

# 📡 MeshRed/StadiumConnect Pro - Sistema de Monitoreo de Logs en Tiempo Real
# Este script captura y analiza logs de la aplicación iOS para debugging automático
# Compatible con Claude Code para análisis automático sin copiar/pegar

set -e

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# CONFIGURACIÓN
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

LOG_DIR="logs"
CURRENT_LOG="$LOG_DIR/current_session.log"
ERROR_LOG="$LOG_DIR/errors.log"
JSON_LOG="$LOG_DIR/session.json"
STATS_LOG="$LOG_DIR/stats.log"
SUBSYSTEM="EmilioContreras.MeshRed"
LOG_LEVEL="debug"
MAX_LOG_LINES=1000

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# FUNCIONES
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Función para imprimir con formato
LoggingService.network.info_header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}$1${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Función para detectar simulador activo
detect_simulator() {
    local simulator_id=$(xcrun simctl list devices | grep -E "Booted" | head -1 | grep -oE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}")

    if [ -z "$simulator_id" ]; then
        echo ""
    else
        echo "$simulator_id"
    fi
}

# Función para detectar dispositivo físico conectado
detect_physical_device() {
    local device_id=$(xcrun devicectl list devices | grep -E "iPhone|iPad" | grep -v "Simulator" | head -1 | awk '{LoggingService.network.info $NF}')

    if [ -z "$device_id" ]; then
        echo ""
    else
        echo "$device_id"
    fi
}

# Función para limpiar logs antiguos
cleanup_old_logs() {
    if [ -d "$LOG_DIR" ]; then
        # Mantener solo los últimos 5 archivos de sesión
        ls -t "$LOG_DIR"/session_*.log 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
    fi
}

# Función para crear estructura de directorios
setup_directories() {
    mkdir -p "$LOG_DIR"
    mkdir -p "$LOG_DIR/sessions"
    mkdir -p "$LOG_DIR/analysis"

    # Crear archivos si no existen
    touch "$CURRENT_LOG"
    touch "$ERROR_LOG"
    touch "$STATS_LOG"

    echo -e "${GREEN}✅ Directorio de logs creado: $LOG_DIR${NC}"
}

# Función para mostrar estadísticas en tiempo real
show_stats() {
    local total_logs=$(wc -l < "$CURRENT_LOG" 2>/dev/null || echo 0)
    local error_count=$(grep -c "error\|failed\|timeout" "$CURRENT_LOG" 2>/dev/null || echo 0)
    local connection_count=$(grep -c "peer.*connected" "$CURRENT_LOG" 2>/dev/null || echo 0)
    local mesh_messages=$(grep -c "routing\|relay\|hop" "$CURRENT_LOG" 2>/dev/null || echo 0)
    local uwb_sessions=$(grep -c "UWB.*session" "$CURRENT_LOG" 2>/dev/null || echo 0)

    echo -e "${BLUE}📊 Estadísticas de la sesión:${NC}"
    echo "   Total logs: $total_logs"
    echo "   Errores detectados: $error_count"
    echo "   Conexiones P2P: $connection_count"
    echo "   Mensajes mesh: $mesh_messages"
    echo "   Sesiones UWB: $uwb_sessions"
}

# Función para analizar logs en tiempo real
analyze_realtime() {
    local line="$1"

    # Detectar errores críticos
    if echo "$line" | grep -qE "error|Error|ERROR|failed|Failed|FAILED"; then
        echo -e "${RED}🔴 ERROR DETECTADO${NC}" >> "$ERROR_LOG"
        echo "$line" >> "$ERROR_LOG"
        echo "" >> "$ERROR_LOG"

        # Notificar en terminal
        echo -e "\n${RED}⚠️  Error capturado - ver $ERROR_LOG${NC}"
    fi

    # Detectar timeouts
    if echo "$line" | grep -qE "timeout|Timeout|TIMEOUT"; then
        echo -e "${YELLOW}⏱️  TIMEOUT DETECTADO: $line${NC}" >> "$ERROR_LOG"
    fi

    # Detectar conexiones exitosas
    if echo "$line" | grep -qE "peer.*connected|connection.*established"; then
        echo -e "${GREEN}✅ Nueva conexión establecida${NC}"
    fi

    # Detectar desconexiones
    if echo "$line" | grep -qE "peer.*disconnected|connection.*lost"; then
        echo -e "${YELLOW}⚠️  Conexión perdida${NC}"
    fi

    # Detectar mensajes de emergencia
    if echo "$line" | grep -qE "EMERGENCY|emergency|🚨"; then
        echo -e "${RED}🚨 ALERTA DE EMERGENCIA DETECTADA${NC}"
        echo "$line" >> "$LOG_DIR/emergencies.log"
    fi
}

# Función principal de captura
start_monitoring() {
    local device_type="$1"
    local device_id="$2"

    LoggingService.network.info_header "🚀 Iniciando monitoreo de logs"

    echo -e "${BLUE}Dispositivo:${NC} $device_type"
    echo -e "${BLUE}ID:${NC} $device_id"
    echo -e "${BLUE}Subsystem:${NC} $SUBSYSTEM"
    echo -e "${BLUE}Nivel:${NC} $LOG_LEVEL"
    echo ""
    echo -e "${YELLOW}Presiona Ctrl+C para detener el monitoreo${NC}"
    echo ""

    # Guardar sesión con timestamp
    local session_file="$LOG_DIR/sessions/session_$(date +%Y%m%d_%H%M%S).log"

    if [ "$device_type" == "simulator" ]; then
        # Monitoreo para simulador
        echo -e "${CYAN}📱 Monitoreando simulador iOS...${NC}"

        xcrun simctl spawn "$device_id" log stream \
            --level "$LOG_LEVEL" \
            --style json \
            --predicate "subsystem == \"$SUBSYSTEM\"" \
            | while IFS= read -r line; do
                # Guardar en archivo actual
                echo "$line" >> "$CURRENT_LOG"
                echo "$line" >> "$session_file"

                # Analizar en tiempo real
                analyze_realtime "$line"

                # Mostrar en consola con formato
                if echo "$line" | grep -q "network"; then
                    echo -e "${BLUE}[NETWORK]${NC} $line"
                elif echo "$line" | grep -q "mesh"; then
                    echo -e "${PURPLE}[MESH]${NC} $line"
                elif echo "$line" | grep -q "uwb"; then
                    echo -e "${CYAN}[UWB]${NC} $line"
                elif echo "$line" | grep -q "emergency"; then
                    echo -e "${RED}[EMERGENCY]${NC} $line"
                else
                    echo "$line"
                fi

                # Mantener buffer circular
                if [ $(wc -l < "$CURRENT_LOG") -gt $MAX_LOG_LINES ]; then
                    tail -$MAX_LOG_LINES "$CURRENT_LOG" > "$CURRENT_LOG.tmp"
                    mv "$CURRENT_LOG.tmp" "$CURRENT_LOG"
                fi
            done

    elif [ "$device_type" == "device" ]; then
        # Monitoreo para dispositivo físico
        echo -e "${CYAN}📱 Monitoreando dispositivo físico iOS...${NC}"
        echo -e "${YELLOW}⚠️  Nota: Asegúrate de que el dispositivo esté conectado y confiado${NC}"

        # Para dispositivos físicos, usar Console.app o cfgutil
        # Por ahora, mostrar instrucciones
        echo ""
        echo "Para dispositivos físicos, puedes usar:"
        echo "1. Abre Console.app en tu Mac"
        echo "2. Selecciona tu dispositivo en la barra lateral"
        echo "3. Filtra por: $SUBSYSTEM"
        echo ""
        echo "O ejecuta:"
        echo "cfgutil syslog -d \"$device_id\" | grep \"$SUBSYSTEM\""

    else
        echo -e "${RED}❌ No se pudo detectar el tipo de dispositivo${NC}"
        exit 1
    fi
}

# Función para modo interactivo
interactive_mode() {
    LoggingService.network.info_header "🔧 MeshRed Log Monitor - Modo Interactivo"

    echo "Selecciona el dispositivo a monitorear:"
    echo ""

    # Detectar simuladores
    echo -e "${CYAN}Simuladores disponibles:${NC}"
    xcrun simctl list devices | grep -E "iPhone|iPad" | grep "Booted" || echo "   Ningún simulador activo"
    echo ""

    # Detectar dispositivos físicos
    echo -e "${CYAN}Dispositivos físicos conectados:${NC}"
    xcrun devicectl list devices 2>/dev/null | grep -E "iPhone|iPad" | grep -v "Simulator" || echo "   Ningún dispositivo conectado"
    echo ""

    echo "Opciones:"
    echo "  1) Monitorear simulador activo"
    echo "  2) Monitorear dispositivo físico"
    echo "  3) Ver logs guardados"
    echo "  4) Analizar sesión anterior"
    echo "  5) Limpiar todos los logs"
    echo "  6) Salir"
    echo ""

    read -p "Selección (1-6): " choice

    case $choice in
        1)
            local sim_id=$(detect_simulator)
            if [ -z "$sim_id" ]; then
                echo -e "${RED}❌ No hay simuladores activos${NC}"
                echo "Por favor, inicia un simulador desde Xcode primero"
                exit 1
            fi
            start_monitoring "simulator" "$sim_id"
            ;;
        2)
            local dev_id=$(detect_physical_device)
            if [ -z "$dev_id" ]; then
                echo -e "${RED}❌ No hay dispositivos conectados${NC}"
                echo "Conecta tu iPhone/iPad y confía en esta computadora"
                exit 1
            fi
            start_monitoring "device" "$dev_id"
            ;;
        3)
            echo -e "${CYAN}📂 Logs guardados:${NC}"
            ls -la "$LOG_DIR"/*.log 2>/dev/null || echo "No hay logs guardados"
            ;;
        4)
            if [ -f "$CURRENT_LOG" ]; then
                show_stats
                echo ""
                echo -e "${CYAN}Últimas 20 líneas del log:${NC}"
                tail -20 "$CURRENT_LOG"
            else
                echo -e "${YELLOW}No hay sesión anterior${NC}"
            fi
            ;;
        5)
            read -p "¿Estás seguro de que quieres borrar todos los logs? (y/n): " confirm
            if [ "$confirm" == "y" ]; then
                rm -rf "$LOG_DIR"/*
                echo -e "${GREEN}✅ Logs limpiados${NC}"
            fi
            ;;
        6)
            echo "Saliendo..."
            exit 0
            ;;
        *)
            echo -e "${RED}Opción inválida${NC}"
            exit 1
            ;;
    esac
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# MAIN
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Verificar dependencias
if ! command -v xcrun &> /dev/null; then
    echo -e "${RED}❌ xcrun no encontrado. Instala Xcode Command Line Tools${NC}"
    exit 1
fi

# Crear directorios
setup_directories

# Limpiar logs antiguos
cleanup_old_logs

# Procesar argumentos
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "Uso: $0 [opciones]"
    echo ""
    echo "Opciones:"
    echo "  --auto         Detecta y monitorea automáticamente"
    echo "  --simulator    Monitorea el simulador activo"
    echo "  --device       Monitorea dispositivo físico"
    echo "  --stats        Muestra estadísticas de la última sesión"
    echo "  --clean        Limpia todos los logs"
    echo "  --help         Muestra esta ayuda"
    echo ""
    echo "Sin argumentos: Modo interactivo"
    exit 0
elif [ "$1" == "--auto" ]; then
    # Modo automático - detecta y monitorea
    sim_id=$(detect_simulator)
    if [ -n "$sim_id" ]; then
        start_monitoring "simulator" "$sim_id"
    else
        dev_id=$(detect_physical_device)
        if [ -n "$dev_id" ]; then
            start_monitoring "device" "$dev_id"
        else
            echo -e "${RED}❌ No se detectó ningún dispositivo${NC}"
            echo "Inicia un simulador o conecta un dispositivo"
            exit 1
        fi
    fi
elif [ "$1" == "--simulator" ]; then
    sim_id=$(detect_simulator)
    if [ -z "$sim_id" ]; then
        echo -e "${RED}❌ No hay simuladores activos${NC}"
        exit 1
    fi
    start_monitoring "simulator" "$sim_id"
elif [ "$1" == "--device" ]; then
    dev_id=$(detect_physical_device)
    if [ -z "$dev_id" ]; then
        echo -e "${RED}❌ No hay dispositivos conectados${NC}"
        exit 1
    fi
    start_monitoring "device" "$dev_id"
elif [ "$1" == "--stats" ]; then
    show_stats
elif [ "$1" == "--clean" ]; then
    rm -rf "$LOG_DIR"/*
    echo -e "${GREEN}✅ Logs limpiados${NC}"
else
    # Modo interactivo por defecto
    interactive_mode
fi