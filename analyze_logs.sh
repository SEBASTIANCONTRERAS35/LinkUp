#!/bin/bash

# 🔍 MeshRed/StadiumConnect Pro - Analizador Automático de Logs
# Script diseñado para que Claude Code pueda analizar logs automáticamente
# Genera reportes estructurados y detecta patrones problemáticos

set -e

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# CONFIGURACIÓN
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

LOG_DIR="logs"
CURRENT_LOG="$LOG_DIR/current_session.log"
ANALYSIS_DIR="$LOG_DIR/analysis"
REPORT_FILE="$ANALYSIS_DIR/report_$(date +%Y%m%d_%H%M%S).md"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# FUNCIONES DE ANÁLISIS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Crear directorio de análisis
setup_analysis() {
    mkdir -p "$ANALYSIS_DIR"
    echo "# 📊 Reporte de Análisis de Logs - MeshRed" > "$REPORT_FILE"
    echo "**Fecha:** $(date)" >> "$REPORT_FILE"
    echo "**Archivo analizado:** $CURRENT_LOG" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# Analizar errores y problemas
analyze_errors() {
    echo "## 🔴 Errores Detectados" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    local error_count=$(grep -ic "error\|failed\|failure" "$CURRENT_LOG" 2>/dev/null || echo 0)
    local timeout_count=$(grep -ic "timeout" "$CURRENT_LOG" 2>/dev/null || echo 0)
    local crash_count=$(grep -ic "crash\|exception\|fatal" "$CURRENT_LOG" 2>/dev/null || echo 0)

    echo "- **Total errores:** $error_count" >> "$REPORT_FILE"
    echo "- **Timeouts:** $timeout_count" >> "$REPORT_FILE"
    echo "- **Crashes/Excepciones:** $crash_count" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    if [ $error_count -gt 0 ]; then
        echo "### Errores más recientes:" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        grep -i "error\|failed" "$CURRENT_LOG" | tail -5 >> "$REPORT_FILE" 2>/dev/null || true
        echo '```' >> "$REPORT_FILE"
    fi

    echo "" >> "$REPORT_FILE"

    # Retornar código de estado para Claude
    if [ $error_count -gt 10 ]; then
        echo -e "${RED}⚠️  ALERTA: Muchos errores detectados ($error_count)${NC}"
        return 2
    elif [ $error_count -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Se detectaron $error_count errores${NC}"
        return 1
    else
        echo -e "${GREEN}✅ No se detectaron errores${NC}"
        return 0
    fi
}

# Analizar conexiones P2P
analyze_connections() {
    echo "## 📡 Análisis de Conexiones P2P" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    local connections=$(grep -c "peer.*connected" "$CURRENT_LOG" 2>/dev/null || echo 0)
    local disconnections=$(grep -c "peer.*disconnected" "$CURRENT_LOG" 2>/dev/null || echo 0)
    local connection_failures=$(grep -c "connection.*failed\|invitation.*failed" "$CURRENT_LOG" 2>/dev/null || echo 0)

    echo "- **Conexiones exitosas:** $connections" >> "$REPORT_FILE"
    echo "- **Desconexiones:** $disconnections" >> "$REPORT_FILE"
    echo "- **Fallos de conexión:** $connection_failures" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    # Detectar peers únicos
    echo "### Peers detectados:" >> "$REPORT_FILE"
    grep -o "peer.*: [A-Za-z0-9_-]*" "$CURRENT_LOG" 2>/dev/null | sort -u | head -10 >> "$REPORT_FILE" || echo "No se detectaron peers" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    # Análisis de estabilidad
    if [ $disconnections -gt $connections ]; then
        echo -e "${RED}⚠️  Problema de estabilidad: Más desconexiones que conexiones${NC}"
        echo "⚠️ **ALERTA:** Problema de estabilidad detectado" >> "$REPORT_FILE"
    fi
}

# Analizar mensajes mesh
analyze_mesh() {
    echo "## 🕸️ Análisis de Red Mesh" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    local messages_sent=$(grep -c "sending.*message\|message.*sent" "$CURRENT_LOG" 2>/dev/null || echo 0)
    local messages_received=$(grep -c "received.*message\|message.*received" "$CURRENT_LOG" 2>/dev/null || echo 0)
    local messages_relayed=$(grep -c "relay\|forward\|hop" "$CURRENT_LOG" 2>/dev/null || echo 0)
    local ack_received=$(grep -c "ACK.*received\|acknowledgment" "$CURRENT_LOG" 2>/dev/null || echo 0)

    echo "- **Mensajes enviados:** $messages_sent" >> "$REPORT_FILE"
    echo "- **Mensajes recibidos:** $messages_received" >> "$REPORT_FILE"
    echo "- **Mensajes retransmitidos:** $messages_relayed" >> "$REPORT_FILE"
    echo "- **ACKs recibidos:** $ack_received" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    # Análisis de routing
    local routing_loops=$(grep -c "loop.*detected\|circular.*route" "$CURRENT_LOG" 2>/dev/null || echo 0)
    if [ $routing_loops -gt 0 ]; then
        echo "⚠️ **ALERTA:** Se detectaron $routing_loops loops de routing" >> "$REPORT_FILE"
        echo -e "${YELLOW}⚠️  Loops de routing detectados${NC}"
    fi
}

# Analizar UWB/LinkFinder
analyze_uwb() {
    echo "## 📍 Análisis de UWB/LinkFinder" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    local uwb_sessions=$(grep -c "UWB.*session\|NearbyInteraction" "$CURRENT_LOG" 2>/dev/null || echo 0)
    local distance_measurements=$(grep -c "distance:.*meters\|distance.*measurement" "$CURRENT_LOG" 2>/dev/null || echo 0)
    local uwb_errors=$(grep -ic "UWB.*error\|NearbyInteraction.*failed" "$CURRENT_LOG" 2>/dev/null || echo 0)

    echo "- **Sesiones UWB iniciadas:** $uwb_sessions" >> "$REPORT_FILE"
    echo "- **Mediciones de distancia:** $distance_measurements" >> "$REPORT_FILE"
    echo "- **Errores UWB:** $uwb_errors" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    if [ $uwb_sessions -gt 0 ]; then
        echo "### Últimas mediciones de distancia:" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        grep "distance:" "$CURRENT_LOG" | tail -3 >> "$REPORT_FILE" 2>/dev/null || true
        echo '```' >> "$REPORT_FILE"
    fi
}

# Analizar emergencias
analyze_emergencies() {
    echo "## 🚨 Análisis de Emergencias" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    local emergency_alerts=$(grep -c "EMERGENCY\|emergency.*detected" "$CURRENT_LOG" 2>/dev/null || echo 0)
    local heart_rate_alerts=$(grep -c "heart.*rate.*abnormal\|cardiac.*alert" "$CURRENT_LOG" 2>/dev/null || echo 0)
    local fall_detections=$(grep -c "fall.*detected\|impact.*detected" "$CURRENT_LOG" 2>/dev/null || echo 0)

    echo "- **Alertas de emergencia:** $emergency_alerts" >> "$REPORT_FILE"
    echo "- **Alertas cardíacas:** $heart_rate_alerts" >> "$REPORT_FILE"
    echo "- **Detecciones de caída:** $fall_detections" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    if [ $emergency_alerts -gt 0 ]; then
        echo -e "${RED}🚨 EMERGENCIAS DETECTADAS EN LA SESIÓN${NC}"
        echo "### ⚠️ Detalles de emergencias:" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        grep -i "emergency" "$CURRENT_LOG" | tail -5 >> "$REPORT_FILE" 2>/dev/null || true
        echo '```' >> "$REPORT_FILE"
    fi
}

# Análisis de performance
analyze_performance() {
    echo "## ⚡ Análisis de Performance" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    local memory_warnings=$(grep -c "memory.*warning\|low.*memory" "$CURRENT_LOG" 2>/dev/null || echo 0)
    local cpu_warnings=$(grep -c "cpu.*high\|performance.*degraded" "$CURRENT_LOG" 2>/dev/null || echo 0)
    local battery_warnings=$(grep -c "battery.*low\|power.*saving" "$CURRENT_LOG" 2>/dev/null || echo 0)

    echo "- **Advertencias de memoria:** $memory_warnings" >> "$REPORT_FILE"
    echo "- **Advertencias de CPU:** $cpu_warnings" >> "$REPORT_FILE"
    echo "- **Advertencias de batería:** $battery_warnings" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    # Análisis de latencia
    local high_latency=$(grep -c "latency.*high\|ping.*>.*1000" "$CURRENT_LOG" 2>/dev/null || echo 0)
    if [ $high_latency -gt 0 ]; then
        echo "⚠️ **ALERTA:** Alta latencia detectada en $high_latency ocasiones" >> "$REPORT_FILE"
    fi
}

# Generar resumen ejecutivo
generate_summary() {
    echo "## 📋 Resumen Ejecutivo" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    local total_lines=$(wc -l < "$CURRENT_LOG" 2>/dev/null || echo 0)
    local session_duration="N/A"

    if [ -f "$CURRENT_LOG" ]; then
        local first_timestamp=$(head -1 "$CURRENT_LOG" | grep -oE "[0-9]{2}:[0-9]{2}:[0-9]{2}" | head -1)
        local last_timestamp=$(tail -1 "$CURRENT_LOG" | grep -oE "[0-9]{2}:[0-9]{2}:[0-9]{2}" | head -1)
        if [ -n "$first_timestamp" ] && [ -n "$last_timestamp" ]; then
            session_duration="$first_timestamp - $last_timestamp"
        fi
    fi

    echo "- **Total de líneas de log:** $total_lines" >> "$REPORT_FILE"
    echo "- **Duración de sesión:** $session_duration" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    # Recomendaciones basadas en el análisis
    echo "### 🎯 Recomendaciones:" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    local has_issues=false

    if [ $(grep -c "error" "$CURRENT_LOG" 2>/dev/null || echo 0) -gt 10 ]; then
        echo "1. ⚠️ Revisar y corregir los errores frecuentes detectados" >> "$REPORT_FILE"
        has_issues=true
    fi

    if [ $(grep -c "timeout" "$CURRENT_LOG" 2>/dev/null || echo 0) -gt 5 ]; then
        echo "2. ⚠️ Optimizar timeouts de conexión - muchos timeouts detectados" >> "$REPORT_FILE"
        has_issues=true
    fi

    if [ $(grep -c "connection.*failed" "$CURRENT_LOG" 2>/dev/null || echo 0) -gt 3 ]; then
        echo "3. ⚠️ Revisar configuración de red - fallos de conexión frecuentes" >> "$REPORT_FILE"
        has_issues=true
    fi

    if [ "$has_issues" = false ]; then
        echo "✅ La sesión transcurrió sin problemas significativos" >> "$REPORT_FILE"
    fi

    echo "" >> "$REPORT_FILE"
}

# Exportar para Claude Code
export_for_claude() {
    local claude_file="$ANALYSIS_DIR/claude_analysis.json"

    echo "{" > "$claude_file"
    echo "  \"timestamp\": \"$(date -Iseconds)\"," >> "$claude_file"
    echo "  \"log_file\": \"$CURRENT_LOG\"," >> "$claude_file"
    echo "  \"metrics\": {" >> "$claude_file"
    echo "    \"total_lines\": $(wc -l < "$CURRENT_LOG" 2>/dev/null || echo 0)," >> "$claude_file"
    echo "    \"errors\": $(grep -ic "error" "$CURRENT_LOG" 2>/dev/null || echo 0)," >> "$claude_file"
    echo "    \"warnings\": $(grep -ic "warning" "$CURRENT_LOG" 2>/dev/null || echo 0)," >> "$claude_file"
    echo "    \"connections\": $(grep -c "connected" "$CURRENT_LOG" 2>/dev/null || echo 0)," >> "$claude_file"
    echo "    \"messages\": $(grep -c "message" "$CURRENT_LOG" 2>/dev/null || echo 0)," >> "$claude_file"
    echo "    \"emergencies\": $(grep -c "emergency" "$CURRENT_LOG" 2>/dev/null || echo 0)" >> "$claude_file"
    echo "  }," >> "$claude_file"
    echo "  \"recent_errors\": [" >> "$claude_file"

    # Exportar últimos 5 errores
    grep -i "error" "$CURRENT_LOG" 2>/dev/null | tail -5 | while read line; do
        echo "    \"$(echo $line | sed 's/"/\\"/g')\"," >> "$claude_file"
    done || echo "    \"No errors found\"" >> "$claude_file"

    echo "  ]" >> "$claude_file"
    echo "}" >> "$claude_file"

    echo -e "${GREEN}✅ Análisis exportado para Claude: $claude_file${NC}"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# FUNCIONES DE UTILIDAD
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Mostrar progreso
show_progress() {
    echo -e "${CYAN}$1...${NC}"
}

# Verificar si hay logs para analizar
check_logs() {
    if [ ! -f "$CURRENT_LOG" ]; then
        echo -e "${RED}❌ No se encontró archivo de logs: $CURRENT_LOG${NC}"
        echo "Ejecuta primero: ./log_monitor.sh"
        exit 1
    fi

    local lines=$(wc -l < "$CURRENT_LOG")
    if [ $lines -eq 0 ]; then
        echo -e "${YELLOW}⚠️  El archivo de logs está vacío${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ Archivo de logs encontrado: $lines líneas${NC}"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# MAIN
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

main() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}🔍 MeshRed Log Analyzer${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Verificar logs
    check_logs

    # Configurar análisis
    setup_analysis

    # Ejecutar análisis
    show_progress "Analizando errores"
    analyze_errors || true

    show_progress "Analizando conexiones P2P"
    analyze_connections

    show_progress "Analizando red mesh"
    analyze_mesh

    show_progress "Analizando UWB/LinkFinder"
    analyze_uwb

    show_progress "Analizando emergencias"
    analyze_emergencies

    show_progress "Analizando performance"
    analyze_performance

    show_progress "Generando resumen"
    generate_summary

    # Exportar para Claude
    export_for_claude

    # Mostrar resultados
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}✅ Análisis completado${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📄 Reporte guardado en: $REPORT_FILE"
    echo "📊 JSON para Claude en: $ANALYSIS_DIR/claude_analysis.json"
    echo ""

    # Mostrar resumen rápido
    echo -e "${CYAN}Resumen rápido:${NC}"
    grep -A 10 "Resumen Ejecutivo" "$REPORT_FILE" | tail -9

    # Opción de ver el reporte completo
    echo ""
    read -p "¿Ver reporte completo? (y/n): " show_report
    if [ "$show_report" == "y" ]; then
        cat "$REPORT_FILE"
    fi
}

# Procesar argumentos
case "$1" in
    --help|-h)
        echo "Uso: $0 [opciones]"
        echo ""
        echo "Opciones:"
        echo "  --quick    Análisis rápido (solo errores y conexiones)"
        echo "  --full     Análisis completo (por defecto)"
        echo "  --json     Solo exportar JSON para Claude"
        echo "  --help     Muestra esta ayuda"
        echo ""
        echo "El script analiza: $CURRENT_LOG"
        exit 0
        ;;
    --quick)
        check_logs
        setup_analysis
        analyze_errors
        analyze_connections
        export_for_claude
        echo -e "${GREEN}✅ Análisis rápido completado${NC}"
        echo "📊 JSON: $ANALYSIS_DIR/claude_analysis.json"
        ;;
    --json)
        check_logs
        export_for_claude
        ;;
    *)
        main
        ;;
esac