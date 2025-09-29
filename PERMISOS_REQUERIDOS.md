# Permisos requeridos para MeshRed

Para solucionar el error `-72008` de MultipeerConnectivity, necesitas agregar los siguientes permisos manualmente en Xcode:

## 📱 Cómo agregar los permisos en Xcode:

### Método 1: A través del Info.plist del proyecto

1. **Abre el proyecto en Xcode**
2. **Selecciona el target "MeshRed"** en el navegador del proyecto
3. **Ve a la pestaña "Info"**
4. **Agrega las siguientes entradas**:

### Permisos necesarios:

```
Key: NSLocalNetworkUsageDescription
Type: String
Value: MeshRed necesita acceso a la red local para encontrar y conectarse con otros dispositivos cercanos para comunicación sin internet en estadios.

Key: NSBonjourServices
Type: Array
    Item 0: _meshred-chat._tcp
    Item 1: _meshred-chat._udp

Key: NSBluetoothAlwaysUsageDescription
Type: String
Value: MeshRed utiliza Bluetooth para descubrir y conectarse con dispositivos cercanos para comunicación peer-to-peer.

Key: NSBluetoothPeripheralUsageDescription
Type: String
Value: MeshRed necesita Bluetooth para anunciar su disponibilidad a otros dispositivos cercanos.
```

### Método 2: Editar directamente el Info.plist

Si tienes acceso al archivo Info.plist en Xcode:

1. **Encuentra el archivo Info.plist** en el navegador del proyecto
2. **Agrega las mismas entradas** listadas arriba
3. **Guarda el archivo**

## 🔧 Pasos adicionales (si es necesario):

1. **Verifica las capacidades del proyecto**:
   - Ve a Project Settings > Capabilities
   - Asegúrate de que no haya conflictos

2. **Limpia y reconstruye**:
   ```bash
   Product > Clean Build Folder
   Product > Build
   ```

## ✅ Verificación:

Después de agregar estos permisos, cuando instales la app en dispositivos físicos:

1. **La primera vez** que abras la app, iOS pedirá permisos para:
   - Acceso a red local
   - Bluetooth (si es necesario)

2. **En los logs**, deberías ver:
   ```
   🚀 MeshRed: App started with device: [nombre-dispositivo]
   📡 NetworkManager: Started advertising with service type: meshred-chat
   🔍 NetworkManager: Started browsing for peers
   ```

3. **En lugar de los errores** `-72008`

## 🎯 Resultado esperado:

Una vez configurados los permisos correctamente, la app debería:
- ✅ Iniciar advertising y browsing sin errores
- ✅ Descubrir otros dispositivos automáticamente
- ✅ Conectarse y enviar mensajes en tiempo real

---

**Nota**: Estos permisos son requeridos por iOS 14+ para cualquier app que use servicios de red local o Bonjour.