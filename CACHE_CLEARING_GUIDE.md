# 🗑️ Guía para Limpiar Caché y Datos - MeshRed

Esta guía explica cómo limpiar completamente los datos y caché de MeshRed en dispositivos físicos.

---

## ✅ Opción 1: Usar la App (Más Fácil)

### Paso a Paso:

1. **Abre MeshRed** en tu iPhone físico
2. **Ve a Settings** (ícono de engranaje)
3. **Navega hacia abajo** hasta la sección **"Herramientas de Desarrollo"**
4. Verás dos opciones:

### 🔴 Borrar TODOS los Datos
- Toca el botón **"Borrar TODOS los Datos"**
- Confirma en el alert
- **Esto elimina:**
  - ✅ Mensajes
  - ✅ Conexiones guardadas
  - ✅ Geofences
  - ✅ Grupos familiares
  - ✅ Configuración de accesibilidad
  - ✅ Caché de UWB
  - ✅ Sistema de reputación
  - ✅ UserDefaults completo
  - ✅ Documentos y caché de archivos

### 🎯 Borrar Componentes Específicos
- Toca **"Borrar Componentes Específicos"**
- Selecciona qué limpiar:
  - Mensajes
  - Conexiones
  - Geofences
  - Grupos Familiares
  - Reputación

### ⚠️ Después de limpiar:
- **Cierra la app completamente** (desliza hacia arriba en el app switcher)
- **Vuelve a abrir la app**
- Los datos estarán frescos y limpios

---

## 🛠️ Opción 2: Reinstalar la App

### Desde Xcode:

```bash
# 1. Desinstalar del iPhone
# Mantén presionado el ícono de MeshRed → "Eliminar App"

# 2. Limpiar build de Xcode (en Mac)
cd /Users/emiliocontreras/Downloads/MeshRed
xcodebuild clean -scheme MeshRed

# 3. Limpiar DerivedData
rm -rf ~/Library/Developer/Xcode/DerivedData/MeshRed-*

# 4. Reinstalar
# En Xcode: Product → Run (⌘R)
```

---

## 🔧 Opción 3: Limpiar Manualmente desde Terminal (Avanzado)

**⚠️ Solo si tienes acceso por USB debugging**

```bash
# Ver contenedores de la app
xcrun simctl get_app_container booted com.EmilioContreras.MeshRed

# Limpiar UserDefaults (solo simulator)
xcrun simctl privacy booted reset all com.EmilioContreras.MeshRed
```

---

## 📋 Qué se limpia exactamente

### UserDefaults Keys:
```
messages
conversationMetadata
lastReadTimestamps
firstMessageSent
activeConversations
blockedPeers
preferredPeers
savedGeofences
geofenceEvents
familyGroup
uwbSessions
peerReputations
```

### Directorios:
- `Documents/` - Archivos de datos persistentes
- `Library/Caches/` - Caché temporal
- `tmp/` - Archivos temporales

---

## 🚨 Advertencias Importantes

1. **Los datos NO se pueden recuperar** después de limpiar
2. **Recomendado para:** Desarrollo, testing, debugging
3. **NO recomendado para:** Producción con datos reales de usuarios
4. **Reinicia la app** después de limpiar para evitar bugs de estado

---

## 🧪 Testing en Dos iPhones

### Para limpiar ambos dispositivos:

```bash
# iPhone 1 (Jose)
1. Abre MeshRed
2. Settings → Herramientas de Desarrollo → Borrar TODOS los Datos
3. Cierra app completamente
4. Vuelve a abrir

# iPhone 2 (Sebastian)
1. Abre MeshRed
2. Settings → Herramientas de Desarrollo → Borrar TODOS los Datos
3. Cierra app completamente
4. Vuelve a abrir

# Ahora ambos dispositivos están limpios y listos para testing
```

---

## 🔍 Verificar que se limpió correctamente

Después de limpiar, deberías ver en los logs:

```
🗑️ DataCleaner: Starting complete data wipe...
🗑️ Clearing UserDefaults...
   ✓ UserDefaults cleared
🗑️ Clearing Documents directory...
   ✓ Deleted: messages.plist
   ✓ Deleted: connections.json
🗑️ Clearing Caches directory...
   ✓ Deleted: routeCache.db
🗑️ Clearing Temporary directory...
✅ DataCleaner: All data cleared successfully!
```

Y en la UI:
- No hay mensajes en conversaciones
- No hay peers preferidos o bloqueados
- No hay geofences creados
- Grupo familiar vacío

---

## 📞 Soporte

Si la limpieza no funciona:
1. Verifica los logs en Xcode Console
2. Intenta reinstalar la app (Opción 2)
3. Revisa que la app tenga permisos de escritura

---

**Última actualización:** 2025-10-11
**Versión de MeshRed:** 1.0
**Compatible con:** iOS 26.0+
