# Live Activities Setup Instructions

## 📋 Archivos Creados

La implementación de Live Activities ha sido completada con los siguientes archivos:

### Modelos
- ✅ `MeshRed/Models/MeshActivityAttributes.swift` - Modelo de datos para Live Activity

### Servicios
- ✅ `MeshRed/Services/NetworkManager+LiveActivity.swift` - Integración con NetworkManager

### Widget Extension
- ✅ `MeshRedLiveActivity/MeshRedLiveActivityBundle.swift` - Bundle del widget
- ✅ `MeshRedLiveActivity/MeshActivityWidget.swift` - Widget principal con todas las vistas
- ✅ `MeshRedLiveActivity/Info.plist` - Configuración del widget

### Configuración
- ✅ `MeshRed/Info.plist` - Actualizado con soporte de Live Activities
- ✅ `MeshRed/MeshRedApp.swift` - Hooks de lifecycle agregados

---

## 🔧 Pasos Pendientes en Xcode

Los archivos están creados, pero necesitas agregar el **Widget Extension Target** manualmente en Xcode:

### 1. Agregar Widget Extension Target

1. Abre `MeshRed.xcodeproj` en Xcode
2. Ve a **File → New → Target...**
3. Selecciona **Widget Extension**
4. Configuración:
   - **Product Name**: `MeshRedLiveActivity`
   - **Include Live Activity**: ✅ **Marcado**
   - **Team**: Tu equipo de desarrollo
   - **Bundle Identifier**: `EmilioContreras.MeshRed.MeshRedLiveActivity`
5. Click **Finish**
6. Cuando pregunte "Activate scheme?", click **Activate**

### 2. Reemplazar Archivos Generados

Xcode generará archivos de ejemplo. Debes reemplazarlos con los que ya creamos:

1. En el Project Navigator, **elimina** estos archivos generados automáticamente:
   - `MeshRedLiveActivity/MeshRedLiveActivity.swift`
   - `MeshRedLiveActivity/MeshRedLiveActivityBundle.swift` (si existe)
   - `MeshRedLiveActivity/MeshRedLiveActivityLiveActivity.swift` (si existe)

2. **Arrastra** estos archivos desde Finder al grupo `MeshRedLiveActivity` en Xcode:
   - `MeshRedLiveActivity/MeshRedLiveActivityBundle.swift`
   - `MeshRedLiveActivity/MeshActivityWidget.swift`
   - `MeshRedLiveActivity/Info.plist`

3. Asegúrate de **marcar** el target membership:
   - Selecciona cada archivo
   - En File Inspector (lado derecho)
   - Target Membership: ✅ `MeshRedLiveActivity`

### 3. Compartir MeshActivityAttributes

El modelo de datos necesita ser compartido entre app y widget:

1. Selecciona `MeshRed/Models/MeshActivityAttributes.swift`
2. En **File Inspector** → **Target Membership**:
   - ✅ `MeshRed` (ya marcado)
   - ✅ `MeshRedLiveActivity` (marca este también)

### 4. Configurar App Groups (Opcional pero Recomendado)

Para compartir datos entre app y widget:

1. Selecciona el target **MeshRed**
2. Ve a **Signing & Capabilities**
3. Click **+ Capability** → **App Groups**
4. Agrega un grupo: `group.EmilioContreras.MeshRed`

5. Repite para el target **MeshRedLiveActivity**
6. Usa el **mismo** App Group ID

### 5. Verificar Build Settings

Para el target **MeshRedLiveActivity**:

- **iOS Deployment Target**: 16.1 o superior (para Live Activities)
- **Swift Language Version**: Swift 5
- **Product Bundle Identifier**: `EmilioContreras.MeshRed.MeshRedLiveActivity`

---

## 🚀 Compilar y Probar

### Build
```bash
xcodebuild -scheme MeshRed -destination "platform=iOS Simulator,name=iPhone 16 Pro"
```

### Problemas Comunes

#### Error: "ActivityKit not found"
- Verifica que Deployment Target sea iOS 16.1+
- Clean build: Product → Clean Build Folder (⌘⇧K)

#### Error: "MeshActivityAttributes not found" en widget
- Asegúrate de que `MeshActivityAttributes.swift` tenga Target Membership en ambos targets

#### Widget no aparece
- Solo funciona en dispositivos físicos con iOS 16.1+
- En simulador puede no mostrarse la Isla Dinámica (limitación del simulador)

---

## 📱 Testing en Dispositivo Real

### 1. Conectar iPhone
- iPhone 11 o superior (para UWB)
- iOS 16.1+ (para Live Activities)

### 2. Build & Run
```bash
xcodebuild -scheme MeshRed -destination "platform=iOS,name=iPhone de [Tu Nombre]"
```

### 3. Verificar Live Activity

1. Abre la app
2. Conéctate a otro dispositivo (aparecerán peers)
3. La Live Activity debería iniciar automáticamente
4. Minimiza la app → verás la Isla Dinámica
5. Toca la Isla Dinámica para expandir

### 4. Estados a Probar

- **Red Normal**: Con peers conectados
- **Tracking**: Activa navegación UWB a un peer
- **Geofence**: Crea un geofence y entra/sale
- **Emergencia**: (Si implementas detección de emergencias)

---

## 🐛 Debugging

### Ver Logs de Live Activity
```bash
# En Terminal mientras la app corre
log stream --predicate 'subsystem == "com.apple.ActivityKit"' --level debug
```

### Verificar Activity Activa
```swift
// En Xcode debug console
po Activity<MeshActivityAttributes>.activities
```

### Forzar Actualización
La Live Activity se actualiza automáticamente cada vez que:
- Cambian los `connectedPeers`
- Cambia el `connectionQuality`
- Cada 2 segundos si hay UWB tracking activo

---

## 📖 Referencia Rápida

### Iniciar Live Activity
```swift
networkManager.startLiveActivity()
```

### Actualizar Manualmente
```swift
networkManager.updateLiveActivity()
```

### Detener Live Activity
```swift
networkManager.stopLiveActivity()
```

### Verificar si está Activa
```swift
if networkManager.hasActiveLiveActivity {
    LoggingService.network.info("Live Activity running")
}
```

---

## ✅ Checklist Final

- [ ] Widget Extension target agregado en Xcode
- [ ] Archivos del widget agregados al target correcto
- [ ] `MeshActivityAttributes.swift` compartido entre targets
- [ ] App Groups configurados (opcional)
- [ ] Build exitoso sin errores
- [ ] Probado en dispositivo real
- [ ] Live Activity aparece al minimizar app
- [ ] Dynamic Island muestra información correcta
- [ ] Actualización automática funciona

---

## 🎯 Próximos Pasos

1. **Agregar Widget Extension** en Xcode (paso crítico)
2. **Compilar** y verificar no hay errores
3. **Probar** en dispositivo real
4. **Iterar** en diseño de UI según feedback
5. **Documentar** para presentación CSC 2025

---

## 📚 Recursos

- [ActivityKit Documentation](https://developer.apple.com/documentation/activitykit)
- [Live Activities Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/live-activities)
- [Dynamic Island Guidelines](https://developer.apple.com/design/human-interface-guidelines/components/system-experiences/live-activities#Dynamic-Island)

---

**¿Preguntas?** Consulta la documentación en [README.md](README.md) sección "Live Activities + Isla Dinámica"
