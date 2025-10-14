# 🔧 LinkFinder Troubleshooting Guide - MeshRed

## Problema Actual: "Not in connected state, so giving up for participant"

Este error ocurre cuando las sesiones LinkFinder no pueden establecer ranging entre dispositivos. La sesión se crea pero no recibe datos de distancia.

## ✅ Soluciones Implementadas

### 1. **Sistema de Reintentos Automáticos**
- Health check cada 5 segundos después de crear sesión
- Reinicio automático si no hay datos de ranging después de 10 segundos
- Máximo 3 reintentos antes de abandonar

### 2. **Mejoras en el Intercambio de Tokens**
- Sesión local persistente para tokens válidos
- Delays apropiados (2s inicial, 1s respuesta)
- Prevención de intercambios duplicados

### 3. **Diagnóstico Mejorado**
- Método `getUWBStatus()` muestra estado detallado
- Logs más descriptivos con emojis
- Estados de sesión rastreados (initializing → connected → ranging)

## 🔍 Diagnóstico del Problema

### Síntomas Actuales
```
✅ Conexión P2P establecida
✅ Tokens LinkFinder intercambiados
✅ Sesión LinkFinder creada (Session=true)
❌ Sin datos de ranging (Distance=nil)
❌ Error: "Not in connected state"
```

### Causas Posibles

1. **Permisos de Nearby Interaction**
   - Verificar: Settings → Privacy & Security → Nearby Interaction
   - MeshRed debe estar autorizado en AMBOS dispositivos

2. **Limitaciones de Hardware**
   - iPhone 11+ con chip U1/U2 requerido
   - Distancia máxima: 9 metros
   - Línea de vista preferible

3. **Interferencia o Configuración iOS**
   - Bluetooth y WiFi deben estar activos
   - Modo avión debe estar desactivado
   - No usar Low Power Mode

4. **Bug de iOS 18**
   - Comportamiento inconsistente en iOS 18.0-18.2
   - Algunas veces tarda hasta 10 minutos en conectar

## 🛠️ Pasos para Resolver

### Solución Rápida (Reinicio Manual)

1. **En ambos dispositivos**:
   ```
   - Cerrar completamente MeshRed
   - Abrir Settings → Privacy & Security → Nearby Interaction
   - Verificar que MeshRed esté autorizado
   - Reiniciar la app
   ```

2. **Si persiste el problema**:
   ```
   - Desactivar y reactivar Bluetooth
   - Desactivar y reactivar WiFi
   - Reiniciar ambos dispositivos
   ```

### Solución Técnica (Force Restart)

La app ahora incluye reinicio automático de sesiones fallidas:

```swift
// Se ejecuta automáticamente cada 5-10 segundos si no hay ranging
if state == .connected && !hasObject {
    // Force session restart
    session.invalidate()
    // Create new session
    newSession.run(config)
}
```

### Debugging Avanzado

Para ver el estado detallado de LinkFinder:

```swift
// En ContentView, cuando se detecta sesión sin ranging:
LoggingService.network.info(uwbManager.getUWBStatus(for: peer))
// Output:
// LinkFinder Status for iphone-de-bichotee.local:
//   • Session: ✅
//   • State: connected
//   • Ranging: ❌
//   • Distance: N/A
```

## 📊 Logs Esperados cuando Funciona Correctamente

```
📡 LinkFinder SESSION CREATION
   Peer: iphone-de-bichotee.local
   Session delegate: ✓
   Discovery token: ✓
   Configuration: ✓
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 LinkFinderSessionManager: didUpdate called for iphone-de-bichotee.local with 1 objects
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎉 LinkFinder RANGING ESTABLISHED
   Peer: iphone-de-bichotee.local
   First ranging data received!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📡 LinkFinder: iphone-de-bichotee.local - 2.45m (with direction)
```

## 🔄 Estado Actual del Fix

- ✅ Token exchange mejorado
- ✅ Health monitoring implementado
- ✅ Auto-restart en caso de fallo
- ✅ Mejor logging para debugging
- ⏳ Esperando confirmación de ranging exitoso

## 📱 Prueba Manual Recomendada

1. Instalar app en 2 iPhones con U1/U2 chip
2. Autorizar Nearby Interaction cuando se solicite
3. Conectar dispositivos via P2P
4. Esperar 5-15 segundos para ranging
5. Si falla, la app reintentará automáticamente
6. Verificar logs para "LinkFinder RANGING ESTABLISHED"

## 🚨 Si Todo Falla

Si después de todos los intentos no funciona:

1. **Verificar compatibilidad**: iPhone 11+ requerido
2. **Verificar permisos**: DEBEN estar autorizados
3. **Verificar distancia**: < 9 metros
4. **Reportar bug a Apple**: iOS 18 tiene problemas conocidos con NearbyInteraction

## 📝 Notas Técnicas

- El error "Not in connected state" es del framework interno de Apple
- No es un error de la app, sino del establecimiento de canal LinkFinder
- iOS intenta conectar en canales 0,1,2,5,6 antes de fallar
- El reinicio de sesión a veces resuelve el problema

---

**Última actualización**: 29 Sept 2025
**Versión iOS testeada**: iOS 18.0
**Dispositivos testeados**: iPhone con chip U1/U2