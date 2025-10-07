# LinkUp

[![Swift Version](https://img.shields.io/badge/Swift-5.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20macOS%20%7C%20watchOS-lightgrey.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> **Solución integral para eventos masivos del Mundial FIFA 2026** - Comunicación P2P, localización ultra-precisa y accesibilidad universal sin depender de infraestructura de red.

Proyecto desarrollado para el **Changemakers Social Challenge (CSC) 2025** de la Facultad de Ingeniería UNAM.

---

## 🎯 Concepto

**LinkUp** combina tecnologías de vanguardia de iOS para resolver problemas críticos durante eventos masivos:

- 🌐 **Comunicación resiliente** vía mesh networking (sin internet)
- 📍 **Localización centimétrica** con Ultra Wideband (UWB)
- 🔔 **Geofencing inteligente** para zonas del estadio
- 🚨 **Detección de emergencias** multi-sensor
- ♿ **Accesibilidad total** para personas con discapacidad

---

## 🏗️ Arquitectura Tecnológica

### Frameworks iOS Principales

```swift
import MultipeerConnectivity  // Mesh P2P networking
import NearbyInteraction      // UWB localización ultra-precisa
import CoreLocation          // GPS y geofencing
import HealthKit            // Monitoreo biométrico
import AVFoundation         // Análisis de audio
import SwiftUI              // Interfaz moderna
```

### Componentes Core

#### 1. **Mesh Networking**
- **NetworkManager**: Coordinador central de comunicación P2P
- **Multi-hop routing**: Mensajes atraviesan hasta 5 peers intermedios
- **Priority Queue**: Sistema de prioridades (Emergency → Alert → Meetup → Location → Chat)
- **AckManager**: Confirmaciones con 3 reintentos automáticos
- **MessageCache**: Prevención de duplicados
- **PeerHealthMonitor**: Monitoreo de calidad de conexión

#### 2. **UWB LinkFinder (Localización Precisa)**
- **LinkFinderSessionManager**: Gestión de sesiones NearbyInteraction
- **Precisión**: Centimétrica con dirección 3D
- **Requisitos**: iPhone 11+ con chip U1/U2
- **NavigationCalculator**: Rutas en tiempo real
- **ProximityHapticEngine**: Feedback táctil direccional

#### 3. **Geofencing Inteligente**
- **LinkFenceManager**: Hasta 20 geofences simultáneas
- **Categorías**: Entradas, baños, concesiones, primeros auxilios, puntos de encuentro
- **Eventos**: Notificaciones automáticas entrada/salida
- **Compartir**: Sincronización con familia vía mesh

#### 4. **Family Groups**
- **FamilyGroupManager**: Grupos con códigos de 6 dígitos
- **Sincronización**: Estado en tiempo real vía mesh
- **Members tracking**: Ubicación de todos los miembros

#### 5. **Emergency Detection (Apple Watch)**
- **WatchEmergencyDetector**: Monitoreo multi-sensor
- **Heart Rate**: Detección de anomalías cardíacas
- **Audio Analysis**: Reconocimiento de gritos
- **SOS Manual**: Botón de emergencia
- **Validación**: Alerta a personal médico del estadio (NO 911 directo)

#### 6. **Accesibilidad**
- **VoiceOver**: Navegación completa por voz
- **Dynamic Type**: Tamaños de texto adaptativos
- **HapticManager**: Feedback táctil rico
- **AudioManager**: Guías de navegación audibles
- **High Contrast**: Temas WCAG AA compliant

---

## 📡 Sistema de Mensajería

### Tipos de Mensajes (Prioridad)

| Tipo | Prioridad | Uso |
|------|-----------|-----|
| Emergency | 0 | Alertas críticas (SOS médico) |
| Alert | 1 | Avisos importantes |
| Meetup | 2 | Coordinación de encuentros |
| Location | 3 | Compartir ubicación |
| Chat | 4 | Conversación normal |

### Network Payloads

```swift
enum NetworkPayload {
    case message(NetworkMessage)           // Chat messages
    case ack(AckMessage)                  // Confirmaciones
    case ping/pong                        // Health checks
    case locationRequest/Response         // GPS sharing
    case uwbDiscoveryToken               // UWB token exchange
    case familySync/JoinRequest          // Family coordination
    case topology                        // Network map
    case linkfenceEvent/Share           // Geofence events
}
```

### Routing Multi-Hop

```
Peer A → Peer B → Peer C → Peer D
        (relay)  (relay)   (destination)
```

Características:
- TTL: 5 hops máximo
- Route path tracking: Previene loops
- Cache: 5 minutos para evitar duplicados

---

## 🚀 Caso de Uso: Mundial 2026

### Escenario: Familia en Estadio Azteca (87,000 personas)

**1. Setup Inicial**
```
📱 Papá crea grupo "Familia González"
👨‍👩‍👧‍👦 Mamá, hijo, hija se unen con código 482951
📍 Crean geofence "Punto de Encuentro" en Sección 120
```

**2. Niño Perdido**
```
🔍 Hijo se pierde buscando baño
📡 Papá activa LinkFinder
📏 Distancia: 47m | Dirección: Noreste
🎯 Navegación con radar + feedback háptico
⏱️ Encuentro en 3 minutos
```

**3. Emergencia Médica**
```
⚠️ Abuelo sufre episodio cardíaco
⌚ Apple Watch detecta HR anormal (150 bpm)
🚨 SOS automático vía mesh a familia
👨‍⚕️ Personal médico del estadio alertado
⏱️ Tiempo respuesta: 2 min (vs 8-10 típico)
```

**4. Red Saturada**
```
📶 80,000+ usuarios colapsan LTE/5G
✅ StadiumConnect sigue funcionando (Bluetooth/WiFi Direct)
🔄 Mensajes retransmitidos vía multi-hop
💬 Familia mantiene comunicación sin internet
```

---

## 💻 Instalación y Setup

### Requisitos

- **Xcode**: 15.0+
- **iOS**: 18.0+ (iOS 14.0+ para UWB)
- **macOS**: 14.0+ (Sonoma)
- **watchOS**: 10.0+
- **Swift**: 5.0+
- **Dispositivos**: iPhone 11+ para UWB (U1/U2 chip)

### Clonar Repositorio

```bash
git clone git@github.com:SEBASTIANCONTRERAS35/LinkUp.git
cd LinkUp
```

### Configuración de Permisos

El proyecto requiere los siguientes permisos en `Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Comunicación P2P con otros dispositivos cercanos</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Localización para geofencing y navegación</string>

<key>NSHealthShareUsageDescription</key>
<string>Monitoreo de frecuencia cardíaca para emergencias</string>

<key>NSMicrophoneUsageDescription</key>
<string>Detección de audio para emergencias</string>

<key>NSLocalNetworkUsageDescription</key>
<string>Comunicación local mesh networking</string>

<key>NSBonjourServices</key>
<array>
    <string>_meshred-chat._tcp</string>
    <string>_meshred-chat._udp</string>
</array>
```

### Build y Run

```bash
# Build para iOS Simulator
xcodebuild -scheme MeshRed -destination "platform=iOS Simulator,name=iPhone 16 Pro"

# Build para dispositivo físico
xcodebuild -scheme MeshRed -destination "platform=iOS,name=Any iOS Device"

# Run tests
xcodebuild test -scheme MeshRed -destination "platform=macOS"
```

---

## 📱 Uso

### 1. Crear Grupo Familiar

```swift
// En NetworkManager
familyGroupManager.createGroup(
    name: "Mi Familia",
    creatorPeerID: localPeerID.displayName,
    creatorNickname: "Papá"
)
```

### 2. Unirse a Grupo

```swift
// Ingresar código de 6 dígitos
familyGroupManager.joinGroup(
    code: FamilyGroupCode(rawCode: "482951"),
    groupName: "Mi Familia",
    memberPeerID: localPeerID.displayName,
    memberNickname: "Hijo"
)
```

### 3. Crear Geofence

```swift
linkfenceManager.createGeofence(
    name: "Punto de Encuentro",
    center: CLLocationCoordinate2D(latitude: 19.4326, longitude: -99.1332),
    radius: 50, // metros
    shareWithFamily: true,
    category: .meetingPoint
)
```

### 4. Iniciar Navegación UWB

```swift
// En LinkFinderHubView
uwbSessionManager?.prepareSession(for: targetPeer)
// Token exchange automático vía mesh
// Navegación inicia cuando ambos peers tienen tokens
```

### 5. Enviar Mensaje de Emergencia

```swift
networkManager.sendMessage(
    "Necesito ayuda médica",
    type: .emergency,
    to: "broadcast",
    requiresAck: true
)
```

---

## 🏆 Innovación y Diferenciación

### Tecnológica
- ✅ Primera app que combina MultipeerConnectivity + NearbyInteraction + CoreLocation
- ✅ Routing multi-hop con cola de prioridades
- ✅ Sistema de emergencias con validación humana (no 911 directo)
- ✅ Arquitectura 100% descentralizada

### Social
- ✅ Resuelve problema real del Mundial 2026
- ✅ Diseñada desde el inicio para accesibilidad
- ✅ Beneficia a personas con discapacidad
- ✅ Escalable a cualquier evento masivo

### Categoría CSC 2025: App Inclusiva
- ♿ VoiceOver nativo completo
- 👁️ Dynamic Type y alto contraste
- 🤚 Navegación háptica direccional
- 🎤 Guías de voz multiidioma
- 🧠 Interfaz simplificada para discapacidades cognitivas

---

## 🔒 Seguridad y Privacidad

- 🔐 **Encryption**: MultipeerConnectivity con `encryptionPreference: .required`
- 🔑 **Permisos**: Explícitos y granulares (Bluetooth, Location, Health)
- 📍 **Location**: Solo compartida dentro del grupo familiar
- 🏥 **Health Data**: Solo procesada localmente, nunca almacenada

### Limitaciones de Background

| Estado | Funcionalidad |
|--------|---------------|
| Foreground | ✅ Completa |
| Background | ⚠️ 3-10 min (solo mantiene conexiones) |
| Suspended | ❌ Conexiones se pierden |

**Recomendación**: App debe estar abierta durante eventos masivos.

---

## 📊 Estructura del Proyecto

```
MeshRed/
├── MeshRed/
│   ├── MeshRedApp.swift                    # Entry point
│   ├── ContentView.swift                   # Main UI
│   ├── Info.plist                          # Permisos
│   ├── Models/
│   │   ├── Message.swift                   # UI message model
│   │   ├── FamilyGroup.swift              # Family data
│   │   ├── CustomLinkFence.swift          # Geofence model
│   │   └── ...
│   ├── Services/
│   │   ├── NetworkManager.swift           # Core P2P coordinator
│   │   ├── LinkFinderSessionManager.swift # UWB manager
│   │   ├── LinkFenceManager.swift         # Geofencing
│   │   ├── FamilyGroupManager.swift       # Family coordination
│   │   ├── MessageStore.swift             # Persistence
│   │   ├── PeerHealthMonitor.swift        # Connection quality
│   │   ├── HapticManager.swift            # Haptic feedback
│   │   └── ...
│   ├── Views/
│   │   ├── MainDashboardContainer.swift   # Main dashboard
│   │   ├── LinkFinderHubView.swift        # UWB navigation hub
│   │   ├── NetworkRadarView.swift         # Visual radar
│   │   ├── FamilyGroupView.swift          # Family management
│   │   ├── SOSView.swift                  # Emergency panel
│   │   └── ...
│   ├── Accessibility/
│   │   ├── AccessibilityModifiers.swift
│   │   ├── AccessibleThemeColors.swift
│   │   └── ...
│   ├── Settings/
│   │   └── AccessibilitySettingsView.swift
│   ├── Theme/
│   │   └── Mundial2026Theme.swift         # World Cup theme
│   ├── NetworkMessage.swift               # Network protocol
│   ├── MessageQueue.swift                 # Priority queue
│   ├── MessageCache.swift                 # Deduplication
│   ├── AckManager.swift                   # ACK tracking
│   └── ...
├── MeshRed Watch App/
│   ├── WatchEmergencyDetector.swift       # Emergency detection
│   ├── WatchSOSView.swift                 # Watch UI
│   └── ...
├── CLAUDE.md                              # Project documentation
└── README.md                              # This file
```

---

## 🧪 Testing

### Unit Tests

```bash
xcodebuild test -scheme MeshRed -destination "platform=macOS" -only-testing:MeshRedTests
```

### UI Tests

```bash
xcodebuild test -scheme MeshRed -destination "platform=iOS Simulator,name=iPhone 16 Pro" -only-testing:MeshRedUITests
```

### Manual Testing

**Requisitos**: 2+ dispositivos físicos iOS (simulador no soporta MultipeerConnectivity/UWB)

1. Instalar app en ambos dispositivos
2. Abrir app en ambos
3. Verificar descubrimiento automático
4. Crear grupo en dispositivo A
5. Unirse con código en dispositivo B
6. Probar navegación UWB (requiere iPhone 11+)

---

## 🤝 Contribuir

Este proyecto fue desarrollado para el Changemakers Social Challenge 2025. Contribuciones son bienvenidas para:

- Nuevas funcionalidades de accesibilidad
- Optimizaciones de batería
- Mejoras de UI/UX
- Corrección de bugs
- Documentación

### Pull Request Process

1. Fork el repositorio
2. Crear rama feature (`git checkout -b feature/AmazingFeature`)
3. Commit cambios (`git commit -m 'Add AmazingFeature'`)
4. Push a rama (`git push origin feature/AmazingFeature`)
5. Abrir Pull Request

---

## 📄 Licencia

Este proyecto está bajo la licencia MIT. Ver archivo `LICENSE` para más detalles.

---

## 👥 Equipo

- **Desarrollo**: Emilio Contreras
- **Evento**: Changemakers Social Challenge (CSC) 2025
- **Institución**: Facultad de Ingeniería UNAM
- **Organizador**: iOS Development Lab - División de Ingeniería Eléctrica Electrónica

---

## 📞 Contacto

- **GitHub**: [@SEBASTIANCONTRERAS35](https://github.com/SEBASTIANCONTRERAS35)
- **Repositorio**: [LinkUp](https://github.com/SEBASTIANCONTRERAS35/LinkUp)

---

## 🙏 Agradecimientos

- iOS Development Lab UNAM por organizar el CSC 2025
- Apple por los frameworks MultipeerConnectivity, NearbyInteraction, y HealthKit
- Comunidad de desarrolladores iOS

---

## 🔮 Roadmap Futuro

- [ ] Integración con Core ML para detección inteligente de emergencias
- [ ] Soporte para ARKit en navegación indoor
- [ ] Backend opcional para analytics y estadísticas
- [ ] Expansión a otros eventos masivos (conciertos, festivales)
- [ ] Integración con sistemas de seguridad del estadio
- [ ] Soporte multiidioma completo (español, inglés, francés, etc.)

---

**Desarrollado con ❤️ para el Mundial FIFA 2026 y eventos masivos inclusivos**
