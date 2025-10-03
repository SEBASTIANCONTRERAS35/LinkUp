# 🧪 Guía de Testing Multi-Hop: A → B → C

Esta guía te ayudará a probar que tu LinkMesh funciona correctamente con routing multi-hop.

---

## 📱 Requisitos

Necesitas **3 dispositivos iOS**:
- **Dispositivo A**: iPhone/iPad/Mac (emisor)
- **Dispositivo B**: iPhone/iPad/Mac (intermediario/relay)
- **Dispositivo C**: iPhone/iPad/Mac (receptor)

**Nota**: Puedes usar combinación de dispositivos físicos y simuladores, pero físicos son mejores para testing real.

---

## ⚙️ Configuración Previa

### Paso 1: Identificar los Nombres de tus Dispositivos

1. Abre la app en cada dispositivo
2. Anota el nombre que aparece en el header (ej: "MacBook-Pro-de-Juan")
3. Estos nombres serán usados en TestingConfig

### Paso 2: Configurar TestingConfig

Edita `MeshRed/TestingConfig.swift`:

```swift
struct TestingConfig {
    // ✅ Activar modo testing
    static let forceMultiHop = true

    // ✅ Configurar qué conexiones bloquear
    static let blockedDirectConnections: [String: [String]] = [
        // A no puede enviar directamente a C
        "MacBook-Pro-de-Juan": ["iPhone-de-Maria"],

        // C no puede enviar directamente a A (bidireccional)
        "iPhone-de-Maria": ["MacBook-Pro-de-Juan"]
    ]

    static func shouldBlockDirectConnection(from: String, to: String) -> Bool {
        guard forceMultiHop else { return false }
        return blockedDirectConnections[from]?.contains(to) ?? false
    }
}
```

**⚠️ IMPORTANTE**: Reemplaza los nombres con los nombres reales de tus dispositivos del Paso 1.

### Paso 3: Build en todos los dispositivos

```bash
# Limpiar build anterior
xcodebuild clean -scheme MeshRed

# Build para cada dispositivo
xcodebuild -scheme MeshRed -destination "name=Tu-Dispositivo-A"
xcodebuild -scheme MeshRed -destination "name=Tu-Dispositivo-B"
xcodebuild -scheme MeshRed -destination "name=Tu-Dispositivo-C"
```

---

## 🎯 Escenario de Prueba 1: Multi-Hop Básico (A → B → C)

### Topología Deseada:
```
A ←→ B ←→ C

- A y B: Conectados directamente ✅
- B y C: Conectados directamente ✅
- A y C: NO conectados (bloqueado por TestingConfig) ❌
```

### Pasos:

#### 1. Iniciar Apps en Orden

```
Dispositivo B (intermediario):
  1. Abrir app primero
  2. Esperar a que aparezca "Started advertising and browsing"
  3. ✅ Debe mostrar "Buscando dispositivos..."

Dispositivo A (emisor):
  2. Abrir app
  3. Esperar a que descubra a B
  4. ✅ Debe aparecer B en "Dispositivos Disponibles"
  5. ✅ Luego B debe pasar a "Dispositivos Conectados"

Dispositivo C (receptor):
  3. Abrir app
  4. Esperar a que descubra a B
  5. ✅ Debe aparecer B en "Dispositivos Disponibles"
  6. ✅ Luego B debe pasar a "Dispositivos Conectados"
```

#### 2. Verificar Estado de Conexiones

```
Dispositivo A debe mostrar:
  Disponibles: 1 (B)
  Conectados: 1 (B)

Dispositivo B debe mostrar:
  Disponibles: 2 (A, C)
  Conectados: 2 (A, C)

Dispositivo C debe mostrar:
  Disponibles: 1 (B)
  Conectados: 1 (B)
```

**⚠️ IMPORTANTE**: Si A y C se conectan directamente, el TestingConfig no está funcionando. Verifica los nombres en Step 2.

#### 3. Enviar Mensaje de A a C

```
En Dispositivo A:
  1. Toca "Opciones Avanzadas"
  2. En "Destinatario" selecciona el nombre de C (ej: "iPhone-de-Maria")
  3. Escribe mensaje: "Hola C, soy A"
  4. Presiona enviar
```

#### 4. Observar Logs en Xcode

**🔴 Dispositivo A (Emisor)**:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📤 SENDING NEW MESSAGE
   From: MacBook-Pro-de-Juan
   To: iPhone-de-Maria
   Content: "Hola C, soy A"
   Type: Chat
   Priority: 4
   Requires ACK: false
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🧪 TEST MODE: Forcing multi-hop by limiting direct connections
🧪 Connected peers: ["iPad-Relay"]
🧪 Allowed peers: ["iPad-Relay"]

📤 Sent to 1 peers - Type: Chat
```

**🟡 Dispositivo B (Intermediario/Relay)**:
```
📦 Message received:
   From: MacBook-Pro-de-Juan → To: iPhone-de-Maria
   Route: MacBook-Pro-de-Juan → iPad-Relay
   Hop: 1/5
   For me? ❌ NO (will relay)

🔄 RELAYING message to 2 peers - Hop 1/5
   Next hops: MacBook-Pro-de-Juan, iPhone-de-Maria

📤 Sent to 2 peers - Type: Chat
```

**🟢 Dispositivo C (Receptor)**:
```
📦 Message received:
   From: MacBook-Pro-de-Juan → To: iPhone-de-Maria
   Route: MacBook-Pro-de-Juan → iPad-Relay → iPhone-de-Maria
   Hop: 2/5
   For me? ✅ YES

📨 ✅ DELIVERED - Type: Chat, Hops: 2, Route: MacBook-Pro-de-Juan → iPad-Relay → iPhone-de-Maria

✅ NetworkManager: Message for me - Type: Chat, Hops: 2
```

#### 5. Verificar en UI

**Dispositivo A**: Debe mostrar tu mensaje enviado

**Dispositivo B**:
  - ⚠️ Debe mostrar indicador "Reenviando..." brevemente
  - ❌ NO debe mostrar el mensaje en su lista (no es para él)

**Dispositivo C**:
  - ✅ Debe recibir mensaje de A
  - ✅ Debe aparecer en lista de mensajes

---

## 🧪 Escenario de Prueba 2: Loop Prevention

### Objetivo: Verificar que mensajes no circulan infinitamente

### Topología:
```
    A ←→ B
    ↕    ↕
    C ←→ D
```

### Pasos:

1. Conecta 4 dispositivos en cuadrado
2. NO uses TestingConfig (déjalos conectar libremente)
3. Desde A, envía mensaje broadcast
4. Observa logs

### Resultado Esperado:

Cada dispositivo debe procesar el mensaje **solo 1 vez**:

```
Dispositivo B:
📦 Message received: (primera vez)
   Route: A → B

💭 Ignoring duplicate message (segunda vez que llega via C)
💭 Ignoring duplicate message (tercera vez que llega via D)
```

---

## 🧪 Escenario de Prueba 3: TTL Limit

### Objetivo: Verificar que mensajes no saltan infinitamente

### Setup:
```swift
// Temporal: Edita NetworkMessage.swift para reducir TTL
ttl: Int = 2  // Reducir de 5 a 2
```

### Topología:
```
A ←→ B ←→ C ←→ D
```

### Pasos:

1. Configura TestingConfig para bloquear: A→C, A→D, B→D
2. Envía de A a D
3. Observa logs

### Resultado Esperado:

```
A: 📤 Sent (hop 0)
B: 🔄 RELAYING (hop 1/2)
C: 🔄 RELAYING (hop 2/2)
D: ⏹️ Message reached hop limit: 2/2

❌ D NO recibe el mensaje (TTL expiró)
```

---

## 📊 Checklist de Resultados

Marca cada item cuando lo verifiques:

- [ ] **A se conecta con B**
- [ ] **B se conecta con C**
- [ ] **A NO se conecta directamente con C** (gracias a TestingConfig)
- [ ] **Mensaje de A aparece en logs de B con "RELAYING"**
- [ ] **Mensaje de A llega a C con hop count = 2**
- [ ] **Route path muestra: A → B → C**
- [ ] **UI de B muestra "Reenviando..." brevemente**
- [ ] **Loop prevention funciona** (mensajes no circulan infinito)
- [ ] **TTL funciona** (mensajes se detienen después de X saltos)

---

## 🐛 Troubleshooting

### Problema: A y C se conectan directamente

**Causa**: TestingConfig no está bloqueando conexión

**Solución**:
1. Verifica nombres exactos en TestingConfig
2. Los nombres son case-sensitive
3. Debe coincidir con `networkManager.localDeviceName`
4. Rebuild después de cambiar TestingConfig

### Problema: B no reenvía mensaje

**Causa**: Mensaje es broadcast o routing logic falló

**Solución**:
1. Asegúrate de seleccionar destinatario específico (no "broadcast")
2. Verifica que `recipientId` sea el nombre exacto de C
3. Chequea logs de B buscando "For me? ❌ NO (will relay)"

### Problema: Mensaje nunca llega a C

**Causa**: B no está conectado a C, o TTL expiró

**Solución**:
1. Verifica que B muestre a C en "Conectados"
2. Chequea TTL (default 5 debe ser suficiente)
3. Busca en logs de B: "RELAYING message to X peers"
4. X debe ser ≥1 (debe incluir a C)

### Problema: "Ignoring duplicate message" inmediatamente

**Causa**: MessageCache tiene el mensaje de antes

**Solución**:
1. Reinicia app en B
2. Limpia MessageCache (botón "Limpiar Conexiones")
3. Espera 5 minutos (cache expira automáticamente)

---

## 📹 Grabar Demo para Presentación

Para el hackathon, graba un video mostrando:

1. **Setup**: 3 dispositivos lado a lado
2. **Conexiones**: Mostrar que A→B y B→C pero NO A→C
3. **Logs en Xcode**: Split screen mostrando logs de los 3
4. **Envío**: A envía mensaje dirigido a C
5. **Relay**: B muestra "Reenviando..."
6. **Entrega**: C recibe mensaje con route path visible

**Tip**: Usa QuickTime Player para grabar pantalla de iOS devices conectados a Mac

---

## ✅ Verificación Final

Si todo funciona correctamente, deberías ver:

```
✅ Mensajes viajan de A a C a través de B
✅ Route path correcto en logs
✅ Hop count incrementa correctamente
✅ Loop prevention funciona
✅ TTL limita propagación
✅ UI muestra indicador "Reenviando..."
✅ MessageCache previene duplicados
```

**🎉 Si ves todo esto: Tu LinkMesh multi-hop funciona perfectamente!**

---

## 🚀 Siguientes Pasos

Una vez verificado el multi-hop:

1. Restaura TestingConfig a valores normales:
   ```swift
   static let forceMultiHop = false
   static let blockedDirectConnections: [String: [String]] = [:]
   ```

2. Continúa con implementación de:
   - Core Location + LinkFencing
   - Nearby Interaction (LinkFinder)
   - Stadium Mode UI

3. En la presentación, menciona:
   > "Implementamos y verificamos multi-hop routing con pruebas reales en 3 dispositivos.
   > Los mensajes pueden viajar a través de hasta 5 saltos intermedios, con prevención
   > de loops y eliminación de duplicados automática."