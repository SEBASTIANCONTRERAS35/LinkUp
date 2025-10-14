# 🔬 Guía: Testing con 2 Dispositivos Simultáneos

Esta guía te muestra cómo ejecutar StadiumConnect Pro en 2 iPhones al mismo tiempo y ver los logs de ambos.

---

## 🎯 Método 1: 2 Ventanas de Xcode (RECOMENDADO)

### Requisitos
- 2 Macs con Xcode (tuyo + prestado de compañero)
- O 1 Mac con 2 monitores
- 2 iPhones físicos
- Ambos iPhones en la misma red WiFi/Bluetooth

### Pasos

#### En Mac 1 (iPhone A):

1. **Conectar iPhone A via USB**
2. **Abrir proyecto** en Xcode
3. **Seleccionar iPhone A** como destino
   - Product → Destination → [Tu iPhone A]
4. **Ejecutar** (⌘R)
5. **Abrir Console** (⇧⌘Y)
6. **Filtrar logs**: Buscar "🏟️" o "🫀" en la barra de filtro

#### En Mac 2 (iPhone B):

1. **Conectar iPhone B via USB**
2. **Abrir el MISMO proyecto** (copia o Git clone)
3. **Seleccionar iPhone B** como destino
4. **Ejecutar** (⌘R)
5. **Abrir Console** (⇧⌘Y)

#### Probar:

1. **En ambos iPhones**: Activar Modo Estadio
2. **Esperar**: Deberían detectarse mutuamente
3. **Ver logs en ambas Xcode**:
   ```
   Mac 1 Console:
   📡 Found peer: iPhone-B (device-name)
   🫀 Keep-Alive ping #1 → 1 peers

   Mac 2 Console:
   📡 Found peer: iPhone-A (device-name)
   🫀 Keep-Alive ping #1 → 1 peers
   ```

---

## 🎯 Método 2: 1 Mac con Logging Remoto (AVANZADO)

Si solo tienes 1 Mac, puedes usar **Console.app** para ver logs del segundo dispositivo vía WiFi.

### Setup (Solo primera vez):

#### Habilitar Logging Remoto en iPhone:

1. **Conectar iPhone B via USB**
2. **Abrir Xcode** → Window → Devices and Simulators
3. **Seleccionar iPhone B**
4. **Clic en** "View Device Logs"
5. **Importante**: Asegurar que "Connect via network" esté habilitado

#### Configurar Console.app:

1. **Abrir Console.app** (Aplicaciones → Utilidades → Console)
2. **Devices** (sidebar izquierdo) → Seleccionar tu iPhone B
3. **Action** → "Include Info Messages"
4. **Start streaming**

### Workflow:

```
┌─────────────┐         ┌─────────────┐
│   iPhone A  │ ←USB→   │     Mac     │
│  (Xcode)    │         │             │
└─────────────┘         │  ┌────────┐ │
                        │  │ Xcode  │ │  ← Logs iPhone A
┌─────────────┐         │  └────────┘ │
│   iPhone B  │ ←WiFi→  │  ┌────────┐ │
│ (Console)   │         │  │Console │ │  ← Logs iPhone B
└─────────────┘         │  └────────┘ │
                        └─────────────┘
```

### Pasos:

1. **iPhone A**: Conectado via USB, ejecutando desde Xcode (⌘R)
   - Ver logs en Xcode Console (⇧⌘Y)

2. **iPhone B**: Conectado via WiFi, ejecutando la app instalada previamente
   - Ver logs en Console.app

3. **Iniciar prueba**:
   - Activar Modo Estadio en ambos
   - Enviar mensajes
   - Minimizar apps
   - Esperar 15+ minutos

---

## 🎯 Método 3: Logs a Archivo + Análisis Posterior

Si no puedes ver ambos logs simultáneamente, guárdalos y compáralos después.

### En cada iPhone:

#### Script para Capturar Logs:

Crea este script en tu Mac: `capture_logs.sh`

```bash
#!/bin/bash

# Uso: ./capture_logs.sh [device-name] [output-file]
# Ejemplo: ./capture_logs.sh "iPhone-A" logs_iphone_a.txt

DEVICE_NAME=$1
OUTPUT_FILE=$2

echo "📝 Capturando logs de $DEVICE_NAME..."
echo "Presiona Ctrl+C para detener"

# Capturar logs del dispositivo vía xcrun
xcrun xctrace record --device "$DEVICE_NAME" --template "System Trace" --output "trace_$OUTPUT_FILE.trace" &

# Capturar también via simctl (si es simulador) o instrumentsctl
if [[ "$DEVICE_NAME" == *"Simulator"* ]]; then
    xcrun simctl spawn booted log stream --predicate 'processImagePath contains "MeshRed"' > "$OUTPUT_FILE"
else
    # Para dispositivo físico
    idevicesyslog -u "$DEVICE_NAME" | grep -i "meshred\|stadium\|keep-alive" > "$OUTPUT_FILE"
fi
```

#### Uso:

**Terminal 1 (iPhone A):**
```bash
# Conectar iPhone A via USB
./capture_logs.sh "iPhone-de-Usuario-A" logs_iphone_a.txt
```

**Terminal 2 (iPhone B):**
```bash
# Desconectar iPhone A, conectar iPhone B
./capture_logs.sh "iPhone-de-Usuario-B" logs_iphone_b.txt
```

**Análisis:**
```bash
# Después de la prueba, ver logs lado a lado
code logs_iphone_a.txt logs_iphone_b.txt

# O comparar timestamps
grep "Keep-Alive ping" logs_iphone_a.txt
grep "Keep-Alive ping" logs_iphone_b.txt

# Buscar eventos de conexión
grep "Found peer\|Connected to peer" logs_iphone_a.txt
grep "Found peer\|Connected to peer" logs_iphone_b.txt
```

---

## 🎯 Método 4: OSLog + Console.app (iOS 15+)

Usar el sistema de logging nativo de Apple.

### Modificar Código (Opcional - Solo para Debugging):

Agrega esto a `StadiumModeManager.swift`:

```swift
import os.log

class StadiumModeManager {
    // Logger para captura remota
    private let logger = Logger(subsystem: "com.meshred.stadium", category: "StadiumMode")

    func enable() {
        // Usar logger en vez de LoggingService.network.info
        logger.info("🏟️ ENABLING STADIUM MODE")
        logger.info("Estimated time: \\(self.estimatedBackgroundTime) seconds")

        // ... resto del código
    }
}
```

### Capturar con Console.app:

1. **Console.app** → Start streaming
2. **Filter**: `subsystem:com.meshred.stadium`
3. **Ver logs en tiempo real** de cualquier dispositivo conectado vía WiFi

---

## 🧪 Escenario de Prueba Completo

### Setup (5 minutos):

1. **Instalar app** en ambos iPhones
2. **Conectar iPhone A** a Xcode (Mac 1 o Mac principal)
3. **Conectar iPhone B** a Console.app (Mac 2 o WiFi logging)
4. **Verificar**: Ambos en la misma red WiFi

### Test (20 minutos):

#### Minuto 0-2: Conexión
```
iPhone A:
- Abrir app
- Settings → Modo Estadio → Activar
- Ver: "🏟️ ENABLING STADIUM MODE"
- Ver: "📡 Found peer: iPhone-B"

iPhone B:
- Abrir app
- Settings → Modo Estadio → Activar
- Ver: "🏟️ ENABLING STADIUM MODE"
- Ver: "📡 Found peer: iPhone-A"
```

#### Minuto 2-3: Enviar Mensaje Inicial
```
iPhone A:
- Enviar "Hola desde A"
- Ver: "📤 Sent to 1 peers - Type: Chat"

iPhone B:
- Ver: "📥 Received message from iPhone-A"
- Mensaje aparece en UI
```

#### Minuto 3-5: Verificar Keep-Alive
```
Ambos logs cada 15s:
🫀 Keep-Alive ping #1 → 1 peers
🫀 Keep-Alive ping #2 → 1 peers
🫀 Keep-Alive ping #3 → 1 peers
```

#### Minuto 5: Minimizar Apps
```
Ambos iPhones:
- Home button (o swipe up)
- Apps en background
- Logs deberían continuar:
  "🏟️ LocationService: Background updates active"
```

#### Minuto 10: Test Intermedio
```
iPhone A:
- Abrir app
- Enviar "¿Sigues ahí?"
- Ver: "📤 Sent to 1 peers"

iPhone B:
- Verificar que mensaje llegó
- Ver: "📥 Received after 10 min in background"
```

#### Minuto 15: Test Final
```
iPhone A:
- Enviar "15 minutos después"
- Ver: "📤 Sent to 1 peers"

iPhone B:
- Ver: "📥 Received after 15 min"
- ✅ ÉXITO: Sin Modo Estadio, esto hubiera fallado
```

#### Minuto 20: Análisis
```
Comparar logs:
- Contar pings: ~80 pings (20 min ÷ 15s)
- Mensajes entregados: 3/3 ✅
- Conexión mantenida: 20 minutos ✅
```

---

## 📊 Checklist de Éxito

### ✅ Antes de Minimizar (Minuto 0-5):
- [ ] Ambos dispositivos ven "STADIUM MODE ACTIVE"
- [ ] Ambos ven "📡 Found peer: [otro-dispositivo]"
- [ ] Mensaje de prueba llega instantáneamente
- [ ] Keep-alive pings aparecen cada 15s en ambos
- [ ] Live Activity muestra "1 peer connected"

### ✅ Durante Background (Minuto 5-20):
- [ ] Keep-alive pings continúan cada 15s
- [ ] Location updates aparecen periódicamente
- [ ] Live Activity se actualiza (en dispositivo físico)
- [ ] No aparece "⚠️ Connection lost"

### ✅ Test de Mensajes (Minuto 10, 15, 20):
- [ ] Mensajes enviados desde A llegan a B
- [ ] Mensajes enviados desde B llegan a A
- [ ] Latencia < 2 segundos
- [ ] No hay "❌ Failed to send"

### ✅ Después de 20+ Minutos:
- [ ] Conexión TODAVÍA activa
- [ ] Ambos dispositivos en "connectedPeers"
- [ ] Mensajes siguen entregándose
- [ ] ✅ **Comparar**: Sin Modo Estadio hubieran desconectado a los ~10 min

---

## 🎬 Video de Prueba para CSC 2025

### Grabar Esta Secuencia:

**0:00 - Setup**
- Mostrar 2 iPhones
- Abrir app en ambos
- Activar Modo Estadio (mostrar UI)

**0:30 - Conexión**
- Mostrar que se detectan ("1 peer connected")
- Enviar mensaje de prueba
- Mostrar que llega instantáneamente

**1:00 - Minimizar**
- Home button en ambos
- Mostrar tiempo en pantalla: "10:00 AM"
- Acelerar video (time-lapse)

**1:30 - 15 Minutos Después**
- Mostrar tiempo: "10:15 AM"
- Abrir iPhone A
- Enviar mensaje
- Mostrar que llega en iPhone B
- **Texto en pantalla**: "✅ 15 minutos después - SIN Modo Estadio hubiera fallado"

**2:00 - Logs**
- Screen recording de Xcode Console
- Mostrar:
  ```
  🫀 Keep-Alive ping #60 → 1 peers
  📤 Sent to 1 peers - Type: Chat
  [iPhone B] 📥 Received message
  ```

**2:30 - Comparación**
- Gráfica mostrando:
  ```
  Sin Modo Estadio: ──────────X (10 min)
  Con Modo Estadio: ────────────────────✓ (25 min)
  ```

---

## 🛠️ Troubleshooting

### Problema: Dispositivos no se detectan

**Diagnóstico**:
```
# Verificar que ambos están en la misma red
# En cada iPhone, buscar en logs:
grep "Started advertising" logs.txt
grep "Started browsing" logs.txt
```

**Soluciones**:
1. Ambos en la misma WiFi
2. Bluetooth activado en ambos
3. Permisos de "Local Network" concedidos
4. Reiniciar servicios: Settings → Accesibilidad → Limpiar Conexiones

### Problema: Logs no aparecen en Console.app

**Soluciones**:
1. Window → Devices → [iPhone] → "Connect via network"
2. Trust Computer en iPhone
3. Console.app → Action → Include Info Messages
4. Filter: `process:MeshRed` or `subsystem:com.meshred`

### Problema: Keep-Alive se detiene en background

**Diagnóstico**:
```
grep "Keep-Alive" logs.txt | tail -20
# ¿Última ping fue hace >1 minuto?
```

**Soluciones**:
1. Verificar permisos ubicación: "Always"
2. Verificar iOS no está en Low Power Mode
3. No cerrar app (swipe up) - solo minimizar
4. Verificar Live Activity está activa

---

## 📝 Template de Reporte de Prueba

```markdown
# Test Report: Stadium Mode - Dual Device

## Setup
- **Fecha**: [fecha]
- **Dispositivos**:
  - iPhone A: [modelo, iOS version]
  - iPhone B: [modelo, iOS version]
- **Método de logging**: [Xcode + Console.app / 2 Xcode / etc]

## Resultados

### Conexión Inicial (Minuto 0-5)
- ⏱️ Tiempo para detectar peer: ____ segundos
- ✅ Mensaje inicial entregado: Sí / No
- 📊 Keep-alive pings vistos: ____ de 20 esperados

### Background Test (Minuto 5-20)
- ⏱️ Tiempo en background: ____ minutos
- ✅ Conexión mantenida: Sí / No
- 📊 Keep-alive pings vistos: ____ de 60 esperados
- 📨 Mensajes enviados/recibidos: ____ / ____

### Test Final (Minuto 20+)
- ✅ Mensaje entregado después de 20 min: Sí / No
- 📊 Tiempo máximo de conexión alcanzado: ____ minutos
- 🔋 Consumo de batería: ____ %

## Logs Relevantes

### iPhone A:
```
[pegar logs importantes]
```

### iPhone B:
```
[pegar logs importantes]
```

## Conclusión
- ✅ / ❌ El Modo Estadio extendió el tiempo de conexión exitosamente
- Observaciones: [notas adicionales]
```

---

## 🎓 Para Presentación CSC 2025

### Demo en Vivo (Si hay WiFi estable):

**Preparación previa (30 min antes)**:
1. Instalar en 2 iPhones
2. Activar Modo Estadio en ambos
3. Conectar ambos
4. Minimizar apps
5. Esperar 15 minutos

**Durante presentación (2 min)**:
1. Mostrar iPhones con apps minimizadas
2. Mostrar reloj: "15 minutos en background"
3. Enviar mensaje desde iPhone A
4. Mostrar que llega en iPhone B inmediatamente
5. **Impacto**: "Sin Modo Estadio, esto hubiera fallado hace 10 minutos"

### Demo con Video (Si no hay WiFi):

1. Video pre-grabado (2 min)
2. Mostrar todo el proceso en time-lapse
3. Énfasis en:
   - Toggle activándose
   - Conexión establecida
   - 15 minutos pasan (time-lapse)
   - Mensaje entregado exitosamente
   - Gráfica comparativa final

---

**¿Tienes 2 iPhones disponibles para probar ahora? Si no, puedo ayudarte a preparar el video pre-grabado para la presentación.** 📱📱
