# 🚨 ERROR: NSHealthShareUsageDescription no configurado

## Error Completo:
```
NSInvalidArgumentException: NSHealthShareUsageDescription must be set in the app's Info.plist
in order to request read authorization for HKQuantityTypeIdentifierHeartRate
```

## ✅ SOLUCIÓN - Agregar permisos HealthKit al Watch App

### Opción 1: Desde Xcode GUI (RECOMENDADO)

1. **Selecciona el target Watch App**:
   - En Project Navigator → click en el proyecto `MeshRed`
   - En la lista de targets, selecciona **"MeshRed Watch App Watch App"**

2. **Ve a la pestaña "Info"**:
   - Click en la pestaña **"Info"** (al lado de "Build Settings")

3. **Agregar Custom iOS Target Properties**:
   - En la sección "Custom iOS Target Properties"
   - Click en el botón **"+"**
   - Busca y agrega: **"Privacy - Health Share Usage Description"**
   - Valor: `Monitoreamos tu ritmo cardíaco para detectar emergencias automáticamente y ayudarte en situaciones críticas durante eventos masivos.`

4. **Agregar segundo permiso**:
   - Click en el botón **"+"** nuevamente
   - Busca y agrega: **"Privacy - Health Update Usage Description"**
   - Valor: `Necesitamos acceso a HealthKit para tu seguridad durante eventos del Mundial 2026.`

5. **Guardar**:
   - ⌘S para guardar
   - Product → Clean Build Folder (⇧⌘K)
   - Product → Run (⌘R)

---

### Opción 2: Editar Info.plist como Source Code

Si el Watch App tiene un archivo Info.plist físico:

1. **Buscar el archivo Info.plist del Watch**:
   - En Project Navigator
   - Carpeta: `MeshRed Watch App Watch App`
   - Si no existe, créalo: File → New → File → Property List

2. **Editar como Source Code**:
   - Click derecho en Info.plist → Open As → Source Code

3. **Agregar estos keys** (dentro del `<dict>`):

```xml
<key>NSHealthShareUsageDescription</key>
<string>Monitoreamos tu ritmo cardíaco para detectar emergencias automáticamente y ayudarte en situaciones críticas durante eventos masivos.</string>

<key>NSHealthUpdateUsageDescription</key>
<string>Necesitamos acceso a HealthKit para tu seguridad durante eventos del Mundial 2026.</string>

<key>WKApplication</key>
<true/>

<key>WKSupportsAlwaysOnDisplay</key>
<true/>
```

4. **Guardar** y recompilar.

---

### Opción 3: Desde Build Settings (Alternativa)

1. Selecciona el target **"MeshRed Watch App Watch App"**
2. Pestaña **"Build Settings"**
3. Busca: `INFOPLIST_KEY_NSHealthShareUsageDescription`
4. Agrega el valor: `Monitoreamos tu ritmo cardíaco...`
5. Busca: `INFOPLIST_KEY_NSHealthUpdateUsageDescription`
6. Agrega el valor: `Necesitamos acceso a HealthKit...`

---

## 🎯 Valores Recomendados (Copia y pega)

### NSHealthShareUsageDescription:
```
Monitoreamos tu ritmo cardíaco para detectar emergencias automáticamente y ayudarte en situaciones críticas durante eventos masivos del Mundial 2026.
```

### NSHealthUpdateUsageDescription:
```
Necesitamos acceso a HealthKit para tu seguridad. La detección automática de emergencias puede salvar vidas en el estadio.
```

---

## ✅ Verificar que funcionó

Después de agregar los permisos:

1. **Clean Build Folder**: Product → Clean Build Folder (⇧⌘K)
2. **Run**: Product → Run (⌘R)
3. **Permitir HealthKit**:
   - En el Watch Simulator, aparecerá un prompt pidiendo permiso
   - Click **"Permitir"** o **"Allow"**
4. **Verificar monitoreo**:
   - Deberías ver el heart rate en la esquina superior (será 0 en simulador)
   - En dispositivo real mostrará tu HR real

---

## 🐛 Si el error persiste

### Verificar que el permiso se agregó correctamente:

```bash
# Desde terminal:
cd /Users/emiliocontreras/Downloads/MeshRed
plutil -p "build/Debug-watchsimulator/MeshRed Watch App Watch App.app/Info.plist" | grep -i health
```

Debería mostrar:
```
"NSHealthShareUsageDescription" => "Monitoreamos..."
"NSHealthUpdateUsageDescription" => "Necesitamos..."
```

### Si no aparece:
- El archivo Info.plist del target Watch NO se está usando
- Agrega los permisos en Build Settings como en Opción 3

---

## 📱 Capabilities también necesarios

Asegúrate de tener **HealthKit capability** agregado:

1. Target: **"MeshRed Watch App Watch App"**
2. Pestaña: **"Signing & Capabilities"**
3. Click: **"+ Capability"**
4. Buscar: **"HealthKit"**
5. Agregarlo

Y también:

6. **"+ Capability"** nuevamente
7. Buscar: **"Background Modes"**
8. Marcar: ✅ **"Workout Processing"**

---

¿Qué método prefieres? Te recomiendo **Opción 1** (Xcode GUI) porque es más seguro.
