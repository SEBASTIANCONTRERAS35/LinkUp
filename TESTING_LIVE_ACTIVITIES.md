# Guía de Testing - Live Activities

## 🎯 Objetivo

Probar que Live Activities funciona correctamente con MultipeerConnectivity para extender el tiempo de vida en background.

---

## 📋 Pre-requisitos

### Hardware Necesario
- ✅ **2 iPhones físicos** (iOS 16.1+)
  - iPhone 14 Pro/Pro Max para Dynamic Island (opcional)
  - iPhone 11+ para UWB tracking (opcional)
- ✅ **Cable Lightning/USB-C** para cada iPhone
- ✅ **Mac con Xcode 15+**

### Software
- ✅ iOS 16.1 o superior en ambos iPhones
- ✅ Xcode 15.0+
- ✅ Widget Extension target creado

### ⚠️ Por Qué NO Simulador
- Live Activities tiene funcionalidad limitada en simulador
- Dynamic Island NO se muestra en simulador
- MultipeerConnectivity es poco confiable en simulador

---

## 🔧 Setup Inicial

### 1. Crear Widget Extension Target

Si aún no lo has hecho:

```
1. Abre MeshRed.xcodeproj en Xcode
2. File → New → Target → Widget Extension
3. Product Name: MeshRedLiveActivity
4. ✅ Include Live Activity
5. Team: Tu equipo de desarrollo
6. Finish
```

### 2. Configurar Target Membership

**Para `MeshActivityAttributes.swift`**:
```
1. Selecciona el archivo en Project Navigator
2. File Inspector (⌘⌥1)
3. Target Membership:
   ✅ MeshRed
   ✅ MeshRedLiveActivity
```

### 3. Verificar Info.plist

En `MeshRed/Info.plist`:
```xml
<key>NSSupportsLiveActivities</key>
<true/>
<key>NSSupportsLiveActivitiesFrequentUpdates</key>
<true/>
```

### 4. Build y Deploy

**Para iPhone 1**:
```bash
# Conecta iPhone 1
xcodebuild -scheme MeshRed \
  -destination "platform=iOS,name=iPhone de [Nombre]" \
  clean build
```

**Para iPhone 2**:
```bash
# Conecta iPhone 2
xcodebuild -scheme MeshRed \
  -destination "platform=iOS,name=iPhone de [Nombre2]" \
  clean build
```

O usa Xcode:
1. Product → Destination → [Tu iPhone]
2. Product → Run (⌘R)

---

## 🧪 Escenarios de Testing

### Test 1: Live Activity se Inicia Automáticamente

**Objetivo**: Verificar que Live Activity se inicia cuando hay peers conectados

**Pasos**:
1. Abre la app en ambos iPhones
2. Espera 2-3 segundos (conexión MultipeerConnectivity)
3. Verifica que aparece el peer en la lista

**✅ Resultado Esperado**:
- En iPhone 14 Pro+: Aparece la Isla Dinámica con icono 🌐
- En otros iPhones: Aparece banner en la parte superior
- Lock Screen: Aparece widget de Live Activity

**🔍 Verificar en Consola**:
```
🎬 LIVE ACTIVITY STARTED
   Activity ID: [UUID]
   Connected Peers: 1
```

**❌ Si NO aparece**:
- Verifica que `connectedPeers.count > 0`
- Revisa permisos: Settings → MeshRed → Live Activities (debe estar ON)
- Checa logs: `log stream --predicate 'subsystem == "com.apple.ActivityKit"'`

---

### Test 2: Actualización en Tiempo Real

**Objetivo**: Verificar que Live Activity se actualiza cuando cambia el número de peers

**Pasos**:
1. Con 2 iPhones conectados (Test 1 completado)
2. Observa la Isla Dinámica/Lock Screen
3. Cierra la app en iPhone 2 (simula desconexión)
4. Observa el cambio en iPhone 1

**✅ Resultado Esperado**:
- Isla Dinámica actualiza de "2 conectados" → "1 conectado"
- Cambio ocurre en < 1 segundo

**🔍 Verificar en Consola**:
```
🔄 Live Activity updated - Peers: 1, Tracking: none
```

---

### Test 3: Estado de Background Extendido

**Objetivo**: Verificar que MultipeerConnectivity se mantiene más tiempo con Live Activity

**Pasos**:
1. Ambos iPhones con app abierta y conectados
2. **iPhone 1**: Minimiza la app (botón Home)
3. **iPhone 2**: Deja la app abierta
4. Espera 5 minutos
5. Revisa si siguen conectados

**✅ Resultado Esperado**:
- **Con Live Activity**: Conexión se mantiene ~30-60 min
- **Sin Live Activity**: Conexión se pierde en 3-10 min

**📊 Comparación**:
| Tiempo | Sin Live Activity | Con Live Activity |
|--------|-------------------|-------------------|
| 1 min  | ✅ Conectado      | ✅ Conectado      |
| 5 min  | ❌ Desconectado   | ✅ Conectado      |
| 15 min | ❌ Desconectado   | ✅ Conectado      |
| 30 min | ❌ Desconectado   | ⚠️ Puede estar conectado |

**🔍 Cómo Verificar**:
- Isla Dinámica sigue mostrando "X conectados"
- Al abrir app, el peer sigue en la lista
- No hay reconexión (sin "peer found" event)

---

### Test 4: Tracking UWB con Live Activity

**Objetivo**: Verificar que distancia y dirección se actualizan en Live Activity

**Pre-requisitos**: iPhone 11+ (ambos con chip U1/U2)

**Pasos**:
1. Abre la app en ambos iPhones
2. **iPhone 1**: Ve a "LinkFinder Hub"
3. Selecciona el peer del iPhone 2
4. Activa navegación UWB
5. Minimiza la app (botón Home)
6. **iPhone 2**: Deja app abierta
7. Camina con iPhone 1 (alejándote/acercándote)

**✅ Resultado Esperado**:
- Isla Dinámica muestra: "Buscando a [Nombre] · 23m ↗️"
- Distancia actualiza cada 2 segundos
- Dirección cambia según movimiento (N, NE, E, SE, S, SW, W, NW)

**Vista Expandida** (tap en Isla Dinámica):
```
┌─────────────────────────┐
│ 📍 Buscando a iPhone2   │
│                         │
│  23m     ↗️ NE          │
│  ✨ Precisión UWB       │
└─────────────────────────┘
```

---

### Test 5: Geofence en Live Activity

**Objetivo**: Verificar que estado de geofence aparece en Live Activity

**Pasos**:
1. Crea un geofence: "Punto de Encuentro"
2. Radio: 50 metros
3. Activa el geofence
4. Minimiza la app
5. Camina (entra/sale del área)

**✅ Resultado Esperado**:
- **Dentro**: Isla Dinámica muestra "📍 Punto de Encuentro · ✅ Dentro"
- **Fuera**: Cambia a "🔴 Fuera"
- Transiciones: "🔵 Entrando" / "🟠 Saliendo"

---

### Test 6: Múltiples Peers

**Objetivo**: Verificar Live Activity con red mesh de 3+ dispositivos

**Pre-requisitos**: 3 o más iPhones

**Pasos**:
1. Abre app en 3 iPhones
2. Espera a que todos se conecten
3. Minimiza app en iPhone 1 y 2
4. Deja iPhone 3 abierto
5. Observa Isla Dinámica en todos

**✅ Resultado Esperado**:
- iPhone 1: "2 conectados"
- iPhone 2: "2 conectados"
- iPhone 3: "2 conectados"
- Todos mantienen conexión en background

---

### Test 7: Emergency State (Futuro)

**Nota**: Requiere integración con sistema de emergencias

**Pasos simulados**:
1. Simula emergencia (cuando esté implementado)
2. Minimiza la app

**✅ Resultado Esperado**:
- Isla Dinámica cambia a rojo: "🚨 Alerta Médica"
- Lock Screen: Banner rojo prominente
- Tap: Abre app en vista de emergencia

---

## 🐛 Debugging

### Ver Logs de Live Activity

**Terminal 1** (ActivityKit logs):
```bash
log stream --predicate 'subsystem == "com.apple.ActivityKit"' --level debug
```

**Terminal 2** (App logs):
```bash
log stream --predicate 'process == "MeshRed"' --level debug
```

### Verificar Activity Activa

En Xcode Debug Console (mientras app corre):
```swift
po Activity<MeshActivityAttributes>.activities
```

### Forzar Actualización Manual

En código (temporal para testing):
```swift
// En ContentView o cualquier vista
Button("Forzar Update") {
    networkManager.updateLiveActivity()
}
```

### Reiniciar Live Activity

Si se queda "stuck":
```swift
// En Settings o vista de debug
Button("Reiniciar Live Activity") {
    networkManager.stopLiveActivity()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        networkManager.startLiveActivity()
    }
}
```

---

## 📊 Checklist de Testing

- [ ] Live Activity inicia automáticamente con peers
- [ ] Actualización en tiempo real de peer count
- [ ] Background extendido (>5 min con conexión)
- [ ] Tracking UWB con distancia/dirección
- [ ] Geofence status visible
- [ ] Múltiples peers (3+)
- [ ] Isla Dinámica (iPhone 14 Pro+)
- [ ] Lock Screen widget
- [ ] Tap para abrir app
- [ ] Activity termina al desconectar todos

---

## 🎥 Capturas para Demo/Presentación

### Screenshots Necesarios

1. **Isla Dinámica - Compact**
   - Estado normal: "15 conectados"
   - Tracking: "23m ↗️"

2. **Isla Dinámica - Expanded**
   - Vista completa con todos los detalles

3. **Lock Screen**
   - Widget de Live Activity con información

4. **Comparison**
   - Sin Live Activity: Desconectado a los 5 min
   - Con Live Activity: Conectado a los 30 min

### Video Demo (30 segundos)

1. **0-5s**: Mostrar conexión inicial, Live Activity aparece
2. **5-10s**: Minimizar app, Isla Dinámica visible
3. **10-15s**: Tracking UWB, distancia actualiza
4. **15-20s**: Expandir Isla Dinámica (tap)
5. **20-25s**: Lock Screen con widget
6. **25-30s**: Volver a app, conexión intacta

---

## 🏆 Resultados Esperados para CSC 2025

### Métricas Clave

- **Background Time**: 30-60 min (vs 3-10 min sin Live Activity)
- **Update Frequency**: Cada 2 segundos para UWB
- **Connection Stability**: 95%+ durante Live Activity
- **User Experience**: Estado visible sin abrir app

### Diferenciación

- ✅ **Único**: Ningún otro equipo combinará estas tecnologías
- ✅ **Técnico**: Demuestra conocimiento profundo de iOS
- ✅ **Práctico**: Resuelve problema real de background
- ✅ **Innovador**: Usa tecnología 2024-2025

---

## 🚨 Problemas Comunes

### Live Activity no aparece

**Causa**: Permisos desactivados
**Solución**: Settings → MeshRed → Live Activities → ON

### Activity se detiene inmediatamente

**Causa**: No hay peers conectados al iniciar
**Solución**: Espera 2-3 segundos para conexión antes de minimizar

### Distancia no actualiza

**Causa**: Timer no configurado
**Solución**: Verifica que `setupLiveActivityUpdates()` se llamó

### Isla Dinámica no visible

**Causa**: Dispositivo no soportado
**Solución**: Usa iPhone 14 Pro o superior

---

## 📞 Ayuda Adicional

Si encuentras problemas:

1. **Revisa**: [LIVE_ACTIVITIES_SETUP.md](LIVE_ACTIVITIES_SETUP.md)
2. **Errores**: [ERRORES_CORREGIDOS.md](ERRORES_CORREGIDOS.md)
3. **Logs**: Usa `log stream` como se mostró arriba
4. **Clean Build**: Product → Clean Build Folder (⌘⇧K)

---

**¡Buena suerte con el testing! 🚀**
