# Cómo Crear la Apple Watch App para StadiumConnect Pro

## 🎯 Objetivo
Crear una aplicación companion para Apple Watch que permita:
1. **Detección automática de emergencias** (caídas, heart rate anormal)
2. **Botón SOS rápido** desde la muñeca
3. **Notificaciones de emergencias familiares**
4. **Navegación háptica básica** hacia familiares

---

## 📱 Paso a Paso: Agregar Target watchOS

### Método 1: Usando Xcode GUI (RECOMENDADO)

#### 1. Abrir el Proyecto
```bash
open MeshRed.xcodeproj
```

#### 2. Agregar watchOS Target
1. En Xcode, ve a **File → New → Target**
2. Selecciona **watchOS** en la barra lateral izquierda
3. Elige **Watch App for iOS App**
4. Click **Next**

#### 3. Configurar el Target
- **Product Name**: `MeshRed Watch App`
- **Team**: QF2R75VM2Y (tu equipo actual)
- **Bundle Identifier**: `EmilioContreras.MeshRed.watchkitapp`
- **Language**: Swift
- **User Interface**: SwiftUI
- **Include Notification Scene**: ✅ (Sí, para notificaciones)
- **Host Application**: MeshRed (selecciona tu app iOS)

#### 4. Embed Watch App
- Xcode preguntará si quieres **Embed** la Watch App en tu app iOS
- Selecciona **Activate** (esto hace que el scheme watchOS esté disponible)

---

## 📁 Estructura de Archivos Creada

Después de crear el target, Xcode creará:

```
MeshRed/
├── MeshRed/                          # App iOS existente
├── MeshRed Watch App/                # Nueva carpeta Watch App
│   ├── MeshRedWatchApp.swift        # Entry point watchOS
│   ├── ContentView.swift            # Vista principal Watch
│   ├── Assets.xcassets              # Recursos Watch
│   └── Preview Content/
├── MeshRed Watch App Extension/     # (Opcional, solo si usas WatchKit)
└── MeshRed.xcodeproj
```

---

## 🔧 Configuración Manual Adicional

### 1. Compartir Código entre iOS y watchOS

Para compartir modelos y servicios, necesitas agregar archivos al target watchOS:

1. Selecciona los archivos que quieres compartir (ej: `SOSType.swift`, `FamilyGroup.swift`)
2. En **File Inspector** (panel derecho), marca el checkbox **MeshRed Watch App**
3. Archivos a compartir:
   - `Models/SOSType.swift` ✅
   - `Models/FamilyGroup.swift` ✅
   - `Models/FamilyMember.swift` ✅
   - `Models/EmergencyMedicalProfile.swift` ✅ (cuando lo creemos)
   - `Services/EmergencyDetectionService.swift` ✅ (cuando lo creemos)
   - `Theme/Mundial2026Theme.swift` ✅

### 2. Configurar Capabilities para watchOS

En **Signing & Capabilities** del target watchOS:
1. **HealthKit** ✅
2. **Background Modes**:
   - Workout Processing ✅
   - Background Sensor Recording ✅
3. **Push Notifications** ✅ (para alertas familiares)

### 3. Actualizar Info.plist de Watch App

```xml
<!-- MeshRed Watch App/Info.plist -->
<key>NSHealthShareUsageDescription</key>
<string>Monitorea tu ritmo cardíaco para detectar emergencias automáticamente</string>

<key>NSHealthUpdateUsageDescription</key>
<string>Necesitamos acceso a tu frecuencia cardíaca para tu seguridad</string>

<key>WKSupportsAlwaysOnDisplay</key>
<true/>

<key>WKApplication</key>
<true/>
```

---

## 🏗️ Estructura de la Watch App

### Archivos a Crear Manualmente

```
MeshRed Watch App/
├── MeshRedWatchApp.swift              # Entry point
├── Views/
│   ├── WatchContentView.swift         # Dashboard principal
│   ├── WatchSOSView.swift             # Botón SOS grande
│   ├── WatchFamilyStatusView.swift    # Estado de familia
│   ├── WatchEmergencyCountdownView.swift # Countdown auto-detección
│   └── WatchNavigationView.swift      # Navegación háptica
├── Services/
│   ├── WatchConnectivityManager.swift # Comunicación iOS ↔ Watch
│   └── WatchEmergencyDetector.swift   # Detección específica Watch
├── Models/
│   └── (Compartidos con iOS)
└── Assets.xcassets/
    └── ComplicationAssets/            # Para complications
```

---

## 🔌 Comunicación iOS ↔ Watch

### Watch Connectivity Framework

La Watch App necesita comunicarse con la app iOS para:
- Enviar alertas SOS
- Recibir estado de familia
- Sincronizar configuración

**WatchConnectivityManager.swift:**
```swift
import WatchConnectivity

class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()

    private var session: WCSession?

    @Published var familyEmergencies: [FamilyEmergencyAlert] = []
    @Published var connectedPeersCount: Int = 0

    override init() {
        super.init()

        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    // Enviar SOS desde Watch → iPhone
    func sendSOSAlert(_ alert: SOSAlert) {
        guard let session = session, session.isReachable else {
            LoggingService.network.info("⚠️ iPhone no alcanzable")
            return
        }

        let message = ["type": "sos", "alert": alert.encode()]
        session.sendMessage(message, replyHandler: nil)
    }

    // Delegates de WCSession
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        LoggingService.network.info("Watch session activated: \(activationState.rawValue)")
    }

    func session(_ session: WCSession,
                 didReceiveMessage message: [String : Any]) {
        // Recibir actualizaciones desde iPhone
        if let type = message["type"] as? String {
            switch type {
            case "familyEmergency":
                // Actualizar estado de emergencias familiares
                break
            case "networkStatus":
                // Actualizar estado de red mesh
                break
            default:
                break
            }
        }
    }
}
```

---

## 🎨 UI Específica de Watch

### WatchSOSView.swift - Botón SOS Gigante

```swift
import SwiftUI
import WatchKit

struct WatchSOSView: View {
    @StateObject private var connectivity = WatchConnectivityManager.shared
    @State private var isPressed = false
    @State private var showCountdown = false

    var body: some View {
        ZStack {
            // Botón SOS que ocupa toda la pantalla
            Button(action: triggerSOS) {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .opacity(isPressed ? 0.8 : 1.0)

                    VStack(spacing: 4) {
                        Image(systemName: "sos.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)

                        Text("SOS")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
        }
        .edgesIgnoringSafeArea(.all)
        .sheet(isPresented: $showCountdown) {
            WatchEmergencyCountdownView()
        }
    }

    private func triggerSOS() {
        // Haptic fuerte
        WKInterfaceDevice.current().play(.notification)

        showCountdown = true
    }
}
```

### WatchEmergencyCountdownView.swift

```swift
import SwiftUI
import WatchKit

struct WatchEmergencyCountdownView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var connectivity = WatchConnectivityManager.shared

    @State private var countdown = 3
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 12) {
            Text("Enviando SOS")
                .font(.headline)
                .foregroundColor(.red)

            // Countdown circular
            ZStack {
                Circle()
                    .stroke(Color.red.opacity(0.3), lineWidth: 8)
                    .frame(width: 80, height: 80)

                Text("\(countdown)")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.red)
            }

            Button("CANCELAR") {
                cancelSOS()
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .onAppear {
            startCountdown()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func startCountdown() {
        // Haptic cada segundo
        WKInterfaceDevice.current().play(.start)

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if countdown > 0 {
                countdown -= 1
                WKInterfaceDevice.current().play(.click)
            } else {
                sendSOS()
            }
        }
    }

    private func cancelSOS() {
        timer?.invalidate()
        dismiss()
    }

    private func sendSOS() {
        timer?.invalidate()

        // Crear alerta SOS
        let alert = SOSAlert(
            type: .emergenciaMedica,
            senderID: "Watch-User",
            senderName: "Apple Watch",
            location: nil,
            message: "Emergencia desde Apple Watch"
        )

        // Enviar a iPhone
        connectivity.sendSOSAlert(alert)

        // Haptic de confirmación
        WKInterfaceDevice.current().play(.success)

        dismiss()
    }
}
```

---

## ⌚ Detección de Emergencias en Watch

### Ventajas del Apple Watch:
1. **Heart Rate siempre activo** (más preciso que iPhone)
2. **Detección de caídas nativa** (watchOS 4+)
3. **Accelerómetro de alta frecuencia**
4. **Siempre en la muñeca** (mejor para emergencias)

### WatchEmergencyDetector.swift

```swift
import HealthKit
import WatchKit

class WatchEmergencyDetector: NSObject, ObservableObject {
    private let healthStore = HKHealthStore()

    @Published var currentHeartRate: Double = 0
    @Published var emergencyDetected: Bool = false

    private var heartRateQuery: HKAnchoredObjectQuery?

    // Umbrales
    private let highHeartRateThreshold: Double = 150  // BPM
    private let lowHeartRateThreshold: Double = 40    // BPM

    func startMonitoring() {
        requestAuthorization()
        startHeartRateMonitoring()
    }

    private func requestAuthorization() {
        let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!

        healthStore.requestAuthorization(toShare: nil, read: [heartRateType]) { success, error in
            if success {
                LoggingService.network.info("✅ HealthKit authorized on Watch")
            } else {
                LoggingService.network.info("❌ HealthKit authorization failed: \(error?.localizedDescription ?? "")")
            }
        }
    }

    private func startHeartRateMonitoring() {
        let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!

        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: nil,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] query, samples, deletedObjects, anchor, error in
            self?.processHeartRateSamples(samples)
        }

        query.updateHandler = { [weak self] query, samples, deletedObjects, anchor, error in
            self?.processHeartRateSamples(samples)
        }

        healthStore.execute(query)
        heartRateQuery = query
    }

    private func processHeartRateSamples(_ samples: [HKSample]?) {
        guard let heartRateSamples = samples as? [HKQuantitySample] else { return }

        for sample in heartRateSamples {
            let bpm = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))

            DispatchQueue.main.async {
                self.currentHeartRate = bpm
                self.checkForAbnormalHeartRate(bpm)
            }
        }
    }

    private func checkForAbnormalHeartRate(_ bpm: Double) {
        if bpm > highHeartRateThreshold || bpm < lowHeartRateThreshold {
            LoggingService.network.info("⚠️ ABNORMAL HEART RATE: \(bpm) BPM")
            triggerEmergencyDetection()
        }
    }

    private func triggerEmergencyDetection() {
        emergencyDetected = true

        // Haptic de advertencia
        WKInterfaceDevice.current().play(.notification)
    }
}
```

---

## 🚀 Build y Testing

### 1. Seleccionar Scheme
En Xcode, cambia el scheme a **MeshRed Watch App**

### 2. Seleccionar Simulador
- iPhone 15 Pro + Apple Watch Series 9 (pareado)
- O dispositivo físico (requiere Apple Watch físico pareado)

### 3. Build y Run
```bash
# Desde terminal (opcional)
xcodebuild -scheme "MeshRed Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)"
```

---

## 📋 Checklist de Implementación

### Configuración Inicial:
- [ ] Crear target watchOS en Xcode
- [ ] Configurar Bundle IDs correctamente
- [ ] Agregar capabilities (HealthKit, Background Modes)
- [ ] Actualizar Info.plist con permisos

### Código Compartido:
- [ ] Marcar modelos como compartidos (SOSType, FamilyGroup)
- [ ] Crear WatchConnectivityManager
- [ ] Sincronizar configuración entre iOS y Watch

### UI Watch:
- [ ] WatchContentView (dashboard)
- [ ] WatchSOSView (botón SOS)
- [ ] WatchEmergencyCountdownView (countdown)
- [ ] WatchFamilyStatusView (estado familia)

### Funcionalidad:
- [ ] Detección de emergencias (heart rate)
- [ ] Envío de SOS a iPhone
- [ ] Recepción de alertas familiares
- [ ] Haptic patterns específicos

### Testing:
- [ ] Probar en simulador
- [ ] Probar en dispositivo real (ideal)
- [ ] Verificar comunicación iPhone ↔ Watch
- [ ] Verificar HealthKit en Watch

---

## 🎯 Prioridad de Funcionalidades Watch

### MVP (Mínimo Viable):
1. ✅ Botón SOS gigante
2. ✅ Countdown de 3 segundos
3. ✅ Envío a iPhone via WatchConnectivity
4. ✅ Haptic feedback

### Fase 2:
1. ⭐ Heart rate monitoring
2. ⭐ Auto-detección de emergencias
3. ⭐ Notificaciones de familia

### Fase 3:
1. 🚀 Navegación háptica básica
2. 🚀 Complications (widget en carátula)
3. 🚀 Standalone mode (sin iPhone cerca)

---

## 💡 Notas Importantes

### Limitaciones watchOS:
- **No MultipeerConnectivity**: Watch no puede hacer mesh networking directamente
- **Requiere iPhone cerca**: Para enviar mensajes a la red mesh
- **Batería limitada**: Monitoreo continuo consume batería rápido
- **Pantalla pequeña**: UI debe ser MUY simple

### Ventajas watchOS:
- ✅ **Siempre en la muñeca**: Más rápido que sacar iPhone
- ✅ **HealthKit mejor**: Sensores de salud más precisos
- ✅ **Detección de caídas**: API nativa de Apple
- ✅ **Haptics excelentes**: Taptic Engine muy preciso

---

## 🔗 Siguiente Paso

Después de crear el target watchOS, continuar con:
1. Implementar `EmergencyDetectionService.swift` (iOS)
2. Compartir ese código con Watch target
3. Crear UI específica de Watch
4. Integrar WatchConnectivity

¿Quieres que proceda a crear el target manualmente o prefieres hacerlo desde Xcode GUI?
