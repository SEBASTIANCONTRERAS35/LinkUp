# 🏟️ StadiumConnect Pro (MeshRed)

[![Swift Version](https://img.shields.io/badge/Swift-5.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-iOS%2018%2B%20%7C%20macOS%2014%2B%20%7C%20watchOS%2010%2B-lightgrey.svg)](https://developer.apple.com)
[![Lines of Code](https://img.shields.io/badge/LOC-51%2C272-blue.svg)]()
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![CSC 2025](https://img.shields.io/badge/CSC%202025-UNAM-purple.svg)](https://fi.unam.mx)

> **Solución integral de comunicación resiliente para eventos masivos del Mundial FIFA 2026** - Comunicación mesh P2P sin infraestructura, localización ultra-precisa con UWB, geofencing inteligente y accesibilidad universal.

**Proyecto desarrollado para el [Changemakers Social Challenge (CSC) 2025](https://fi.unam.mx)** de la Facultad de Ingeniería UNAM - iOS Development Lab.

---

## 📑 Tabla de Contenidos

- [Concepto y Problemática](#-concepto-y-problemática)
- [Arquitectura Técnica](#️-arquitectura-técnica)
- [Componentes Core](#-componentes-core)
- [Características Avanzadas](#-características-avanzadas)
- [Instalación y Configuración](#-instalación-y-configuración)
- [Casos de Uso](#-casos-de-uso-mundial-2026)
- [Estructura del Proyecto](#-estructura-del-proyecto)
- [Testing y Debugging](#-testing-y-debugging)
- [Contribuir](#-contribuir)
- [Roadmap](#-roadmap)
- [Contacto](#-contacto)

---

## 🎯 Concepto y Problemática

### Contexto del Hackathon - CSC 2025

**Evento**: Changemakers Social Challenge (CSC) 2025
**Organizador**: iOS Development Lab - División de Ingeniería Eléctrica Electrónica, UNAM
**Temática**: Apps iOS innovadoras para el Mundial FIFA 2026 en México
**Formato**: Equipos de hasta 4 personas, 12 equipos totales
**Categorías**: Perspectiva Mujeres | Inteligencia Artificial | **App Inclusiva** ✅
**Premio**: Representar a la Facultad en el nacional (noviembre 2025)

**Cronograma**:
- ✅ **Registro**: 22-26 septiembre 2025
- ✅ **Entrega de propuesta**: 29 septiembre - 3 octubre
- 📅 **Presentaciones presenciales**: 13-14 octubre en iOS Lab (Edificio P)
- 🏆 **Resultados**: 15 octubre 19:00 hrs

### Problemática Social Identificada

Durante eventos masivos como el Mundial FIFA 2026 (Estadios Azteca, BBVA, Akron con 80,000+ asistentes):

| Problema | Impacto | Solución StadiumConnect Pro |
|----------|---------|------------------------------|
| 📶 **Saturación de Redes** | Torres celulares colapsan con 80K+ usuarios simultáneos | LinkMesh P2P: Comunicación sin dependencia de infraestructura |
| 👨‍👩‍👧‍👦 **Familias Separadas** | Imposible localizar miembros en multitudes masivas | LinkFinder UWB: Precisión centimétrica con dirección 3D |
| 🚨 **Emergencias Médicas** | Respuesta lenta (8-10 min) en alta densidad | Detección multi-sensor + Personal médico intermediario |
| ♿ **Exclusión Digital** | Personas con discapacidades enfrentan barreras | Accesibilidad nativa: VoiceOver, Dynamic Type, Haptic |

### Innovación Tecnológica

**Primera aplicación en combinar**:
- ✅ MultipeerConnectivity (mesh networking) + NearbyInteraction (UWB) + CoreLocation (geofencing)
- ✅ Routing multi-hop con cola de prioridades de 5 niveles
- ✅ Sistema de emergencias con validación humana (NO 911 directo)
- ✅ Arquitectura 100% descentralizada y resiliente
- ✅ **Sistema de fallback UWB → GPS+Brújula** para medición de dirección

**Categoría**: **App Inclusiva** - Diseñada desde el inicio con accesibilidad universal, no como adición posterior.

---

## 🏗️ Arquitectura Técnica

### Stack Tecnológico

```swift
// Frameworks iOS Principales
import MultipeerConnectivity  // LinkMesh P2P networking
import NearbyInteraction      // UWB localización ultra-precisa (LinkFinder)
import CoreLocation          // GPS, geofencing (LinkFence)
import HealthKit            // Monitoreo biométrico (Apple Watch)
import AVFoundation         // Análisis de audio para emergencias
import CoreHaptics          // Feedback táctil direccional
import ActivityKit          // Live Activities en Dynamic Island
import SwiftUI              // Interfaz moderna declarativa
import Combine              // Reactive programming
import CoreMotion           // Acelerómetro para ARKit
```

### Deployment Targets

- **iOS**: 18.0+ (algunas features requieren 14.0+ para UWB, 16.0+ para camera assistance)
- **macOS**: 14.0+ (Sonoma)
- **watchOS**: 10.0+ (para emergency detection)
- **visionOS**: 2.0+ (soporte futuro)

### Estadísticas del Proyecto

| Métrica | Valor |
|---------|-------|
| **Total Lines of Code** | 51,272 |
| **Swift Files** | 127+ |
| **Services** | 35+ |
| **Views** | 45+ |
| **Models** | 25+ |
| **NetworkManager.swift** | 4,415 líneas |
| **LinkFinderSessionManager.swift** | 1,388 líneas |
| **LinkFenceManager.swift** | 728 líneas |
| **Supported Message Types** | 20+ payloads |
| **Supported Devices** | iPhone 11+ (U1/U2 chip) |

---

## 🔧 Componentes Core

### 1. 🌐 LinkMesh Networking (MultipeerConnectivity)

**NetworkManager.swift** (4,415 líneas) - Coordinador central de toda la comunicación P2P

#### Subsistemas Principales

##### 1.1 Message Queue (Priority Heap)
```swift
// MessageQueue.swift - Min-heap implementation
enum MessageType: Int {
    case emergency = 0  // Highest priority
    case alert = 1
    case meetup = 2
    case location = 3
    case chat = 4       // Lowest priority
}

// Dynamic queue size based on network mode
Standard: 100 messages
PowerSaving: 50 messages
HighAvailability (Stadium): 500 messages
```

**Características**:
- Cola de prioridad con min-heap
- Evicción automática de mensajes de baja prioridad cuando está llena
- Thread-safe con `DispatchQueue` con barriers para writes
- Ordenamiento por prioridad + timestamp (FIFO en misma prioridad)

##### 1.2 AckManager (Acknowledgment System)
```swift
// AckManager.swift - Confirmaciones con reintentos
- Base timeout: 5 segundos (conexión directa)
- Adaptive timeout: +1.5s por hop adicional
  * TTL 1 (directo): 5s
  * TTL 3 (hasta 3 hops): 8s
  * TTL 5 (hasta 5 hops): 11s
- Max reintentos: 3 intentos
- Check interval: 3 segundos
```

**Características**:
- Tracking de mensajes pendientes con `[UUID: PendingMessage]`
- Timeout adaptativo basado en TTL esperado
- Incremento automático de TTL en reintentos
- Callbacks delegate para resend/failure

##### 1.3 MessageCache (Deduplication)
```swift
// MessageCache.swift - Prevención de duplicados
- Cache window: 5 minutos
- Thread-safe dictionary [UUID: Date]
- Limpieza automática de mensajes expirados
```

Previene loops infinitos en routing multi-hop mediante cache de UUIDs.

##### 1.4 Multi-Hop Routing (AODV-like)

**Route Discovery Protocol**:
```swift
// RouteRequest (RREQ)
origin → broadcast → intermediaries → destination

// RouteReply (RREP)
destination → reverse path → origin

// Route Cache (AODV-like)
RouteCache: [destination: nextHop]
TTL: 5 hops máximo
Route path tracking: previene loops circulares
```

**Algoritmo**:
1. **Broadcast RREQ**: Origen transmite solicitud de ruta
2. **Intermediaries relay**: Peers retransmiten si no es destino
3. **Destination replies**: Destino envía RREP por camino reverso
4. **Route caching**: Cada peer aprende rutas en ambas direcciones
5. **Route error**: Si falla transmisión, envía RERR e invalida ruta

**Limitaciones**:
- TTL por defecto: 5 hops (configurable)
- `hopCount >= ttl` → mensaje descartado
- `routePath.contains(peerId)` → loop detection

##### 1.5 SessionManager (Connection Lifecycle)
```swift
// SessionManager.swift - Connection state tracking
- Connection cooldowns: Previene connection storms
- Attempt tracking: Limita reintentos fallidos
- State transitions: waiting → connecting → connected → failed
- Metrics recording: Success/failure rates
```

##### 1.6 ConnectionMutex (Race Condition Prevention)
```swift
// ConnectionMutex.swift - Connection synchronization
- Prevents simultaneous bidirectional connections
- Deterministic conflict resolution: lower peer ID wins
- Lock/unlock per peer
- Timeout handling
```

**Conflict Resolution**:
```swift
if localPeerID.displayName < remotePeerID.displayName {
    // I initiate connection
    browser.invitePeer(remotePeerID, to: session)
} else {
    // I wait for invitation
    // Remote peer will initiate
}
```

##### 1.7 PeerHealthMonitor (Connection Quality)
```swift
// PeerHealthMonitor.swift - Ping/Pong health checks
- Ping interval: 30s (standard), 15s (high availability)
- Latency tracking: Round-trip time measurement
- Connection quality: Good (<100ms), Fair (100-300ms), Poor (>300ms)
- Automatic disconnection on timeout
```

##### 1.8 ConnectionOrchestrator (Intelligent Management)
```swift
// ConnectionOrchestrator.swift (538 líneas)
- Leader election (Bully algorithm)
- Connection pool management (max 5 connections)
- Peer reputation system (0-100 score)
- Adaptive backoff (exponential + jitter)
- Predictive disconnection detection
```

**Subsistemas**:
- **LeaderElection**: Elección distribuida de líder de red
- **ConnectionPoolManager**: Gestión de slots de conexión
- **PeerReputationSystem**: Scoring basado en éxito/latencia
- **AdaptiveBackoffManager**: Cooldowns exponenciales con jitter

#### Network Payload Types

```swift
enum NetworkPayload: Codable {
    // Core messaging
    case message(NetworkMessage)
    case ack(AckMessage)
    case ping(PingMessage)
    case pong(PongMessage)

    // Routing
    case routeRequest(RouteRequest)
    case routeReply(RouteReply)
    case routeError(RouteError)
    case topology(TopologyMessage)

    // Location & Navigation
    case locationRequest(LocationRequestMessage)
    case locationResponse(LocationResponseMessage)
    case gpsLocation(GPSLocationMessage)  // For UWB fallback
    case uwbDiscoveryToken(UWBDiscoveryTokenMessage)

    // Family Groups
    case familySync(FamilySyncMessage)
    case familyJoinRequest(FamilyJoinRequestMessage)
    case familyInfo(FamilyGroupInfoMessage)

    // Geofencing
    case linkfenceEvent(LinkFenceEventMessage)
    case linkfenceShare(LinkFenceShareMessage)

    // Stadium Mode
    case stadiumBeacon(StadiumBeaconMessage)

    // Emergency
    case emergency(EmergencyMessage)
}
```

#### Network Modes

```swift
// NetworkConfig.swift
enum NetworkMode {
    case standard         // Normal operation
    case powerSaving      // Battery conservation
    case highAvailability // Stadium/concert events
}

// Configuration per mode
Standard:
    - Ping: 30s
    - Queue: 100 msgs
    - Retries: 5
    - Timeout: 30s

PowerSaving:
    - Ping: 60s
    - Queue: 50 msgs
    - Retries: 3
    - Timeout: 20s

HighAvailability (Stadium):
    - Ping: 15s
    - Queue: 500 msgs
    - Retries: 10
    - Timeout: 45s
```

#### Stadium Mode Profiles

```swift
// StadiumMode.swift - FIFA 2026 optimizations
enum StadiumProfile {
    case smallVenue      // < 10K: max 10 connections
    case mediumVenue     // 10-30K: max 7 connections
    case largeStadium    // 30-60K: max 5 connections
    case megaStadium     // 60K+: max 3 connections (FIFA 2026)
}

// MegaStadium optimizations:
- Discovery rate: 0.05s (ultra-aggressive)
- Connection timeout: 1s (fast failover)
- Lightning mesh enabled
- Predictive disconnection enabled
- UDP transport enabled
- Bluetooth LE enabled
```

---

### 2. 📍 LinkFinder (Ultra Wideband - UWB)

**LinkFinderSessionManager.swift** (1,388 líneas) - Gestión de sesiones NearbyInteraction

#### Device Capabilities

```swift
struct DeviceCapabilities {
    let deviceModel: String
    let hasUWB: Bool
    let hasU1Chip: Bool      // iPhone 11-14
    let hasU2Chip: Bool      // iPhone 15+
    let supportsDistance: Bool
    let supportsDirection: Bool
    let supportsCameraAssist: Bool  // iPhone 14+ required
    let supportsExtendedRange: Bool
    let osVersion: String
}

// Detection automática
iPhone 11-13: U1 chip, dirección nativa
iPhone 14-17: U2 chip, dirección via camera assistance (ARKit)
```

#### Camera Assistance (iOS 16+)

**Requisitos**:
1. ✅ iPhone 14+ (U2 chip)
2. ✅ iOS 16.0+
3. ✅ **Permiso de Cámara** (`NSCameraUsageDescription`)
4. ✅ **Permiso de Motion** (`NSMotionUsageDescription`) ← **CRÍTICO**

**Problema identificado**: Sin permiso de Motion, ARKit no puede funcionar → dirección SIEMPRE nil.

**Solución implementada**:
```swift
// MotionPermissionManager.swift
// Solicitud explícita de Motion & Fitness
CMMotionActivityManager().startActivityUpdates()
// Dispara permission dialog del sistema
```

#### Direction Measurement Modes

```swift
enum DirectionMode {
    case waiting              // Calibrando...
    case preciseUWB           // 🎯 Dirección Precisa (UWB + ARKit)
    case approximateCompass   // 🧭 Dirección Aproximada (GPS + Brújula)
    case unavailable          // ❌ Sin Dirección
}
```

#### Sistema de Fallback Automático

**Trigger Conditions**:
1. **Permisos denegados**: Camera OR Motion denied
2. **Timeout 10s**: Direction = nil después de 10 segundos
3. **Algorithm convergence failure**: Insufficient movement/lighting

**Fallback Flow**:
```
┌─────────────────────────────────────────────────┐
│ 1. startSession() - Request Motion permission  │
└─────────────────┬───────────────────────────────┘
                  │
         ┌────────▼────────┐
         │ Permission OK?  │
         └────────┬────────┘
                  │
        ┌─────────┴─────────┐
        │ YES              NO
        ▼                   ▼
┌───────────────┐   ┌──────────────────┐
│ Enable Camera │   │ activateFallback │
│ Assistance    │   │ (GPS + Compass)  │
└───────┬───────┘   └──────────────────┘
        │
        ▼
┌──────────────────┐
│ session.run()    │
└───────┬──────────┘
        │
        ▼
┌─────────────────────┐
│ Start 10s timer     │
│ Check direction nil │
└───────┬─────────────┘
        │
        ▼
┌──────────────────────────────┐
│ direction != nil after 10s?  │
└──────────┬───────────────────┘
           │
    ┌──────┴──────┐
    │ YES        NO
    ▼             ▼
┌────────┐  ┌──────────────────┐
│ Success│  │ activateFallback │
│ (UWB)  │  │ (GPS + Compass)  │
└────────┘  └──────────────────┘
```

**Automatic GPS Sharing**:
```swift
// When fallback activates
activateFallbackMode() {
    directionMode = .approximateCompass
    fallbackService?.startTracking()

    // AUTOMATIC: Start GPS location sharing with peer
    networkManager?.startGPSLocationSharingForLinkFinder(with: mcPeerID)
}

// Peer receives GPS location
handleGPSLocationForLinkFinder() {
    let bearing = FallbackDirectionService.calculateBearing(
        from: myGPS,
        to: peerGPS
    )
    // Haversine formula: bearing calculation
}

// Automatic switch back to precise
didUpdate(session: NISession, object: NINearbyObject) {
    if object.direction != nil && directionMode == .approximateCompass {
        directionMode = .preciseUWB
        networkManager?.stopGPSLocationSharingForLinkFinder()
    }
}
```

#### FallbackDirectionService

```swift
// FallbackDirectionService.swift
// GPS + Compass bearing calculation

// Haversine formula for bearing
func calculateBearing(from: CLLocation, to: CLLocation) -> Double {
    let lat1 = from.coordinate.latitude.toRadians()
    let lon1 = from.coordinate.longitude.toRadians()
    let lat2 = to.coordinate.latitude.toRadians()
    let lon2 = to.coordinate.longitude.toRadians()

    let dLon = lon2 - lon1
    let y = sin(dLon) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)

    return atan2(y, x).toDegrees()  // -180 to 180
}

// Compass heading adjustment
relativeBearing = bearing - compassHeading

// Accuracy: ±10-15° (vs ±1° with UWB)
```

#### Algorithm Convergence Monitoring (iOS 16+)

```swift
func session(_ session: NISession,
             didUpdateAlgorithmConvergence convergence: NIAlgorithmConvergence,
             for object: NINearbyObject?) {

    switch convergence.status {
    case .converged:
        // ✅ Direction available

    case .notConverged(let reasons):
        for reason in reasons {
            case .insufficientMovement:
                // "Move the iPhone around"
            case .insufficientHorizontalSweep:
                // "Move iPhone left-right"
            case .insufficientVerticalSweep:
                // "Move iPhone up-down"
            case .insufficientLighting:
                // "Move to better lit area"
        }
    }
}
```

#### Token Exchange Protocol

```swift
// 1. Prepare session
prepareSession(for peerID: String) {
    let session = NISession()
    let token = session.discoveryToken

    // 2. Exchange token via LinkMesh
    let message = UWBDiscoveryTokenMessage(
        senderPeerID: localPeerID,
        receiverPeerID: peerID,
        token: token
    )
    networkManager?.sendNetworkMessage(payload: .uwbDiscoveryToken(message))
}

// 3. Receive peer token
handleReceivedToken(peerToken: NIDiscoveryToken) {
    let config = NINearbyPeerConfiguration(peerToken: peerToken)

    // 4. Enable camera assistance if available
    if #available(iOS 16.0, *),
       NISession.deviceCapabilities.supportsCameraAssistance {
        config.isCameraAssistanceEnabled = true
    }

    // 5. Run session
    session.run(config)
}

// 6. Receive updates
func session(_ session: NISession, didUpdate object: NINearbyObject) {
    distance = object.distance  // Float (meters)
    direction = object.direction  // simd_float3 (x,y,z)
}
```

#### Session States

```swift
enum SessionState {
    case preparing       // Token extracted, not running
    case tokenReady      // Waiting for peer token
    case running         // session.run() called
    case ranging         // Receiving didUpdate callbacks
    case suspended       // System suspended
    case disconnected    // Session invalidated
}
```

---

### 3. 🗺️ LinkFence (Geofencing)

**LinkFenceManager.swift** (728 líneas) - Sistema de geofencing múltiple

#### Features

- ✅ **Hasta 20 geofences simultáneas** (límite iOS)
- ✅ **6 categorías predefinidas** (Entrada, Baño, Concesión, Primeros Auxilios, Punto de Encuentro, Custom)
- ✅ **Compartir con familia** vía LinkMesh
- ✅ **Event timeline** por geofence
- ✅ **Notificaciones locales** en entry/exit
- ✅ **Background monitoring** con `Always` authorization

#### Categories

```swift
enum LinkFenceCategory: String, Codable {
    case entrance        // 🚪 Entradas
    case bathroom        // 🚻 Baños
    case concession      // 🍔 Concesiones
    case firstAid        // 🏥 Primeros Auxilios
    case meetingPoint    // 📍 Punto de Encuentro
    case custom          // ⭐ Personalizado

    var icon: String
    var defaultColorHex: String
    var displayName: String
}
```

#### Geofence Model

```swift
struct CustomLinkFence: Identifiable, Codable {
    let id: UUID
    var name: String
    var center: CLLocationCoordinate2D
    var radius: CLLocationDistance  // meters
    var createdAt: Date
    var creatorPeerID: String
    var isActive: Bool
    var category: LinkFenceCategory
    var colorHex: String
    var isMonitoring: Bool

    func toCLCircularRegion() -> CLCircularRegion {
        let region = CLCircularRegion(
            center: center,
            radius: radius,
            identifier: id.uuidString
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true
        return region
    }
}
```

#### Entry/Exit Events

```swift
struct LinkFenceEventMessage: Codable {
    let linkfenceID: UUID
    let linkfenceName: String
    let peerID: String
    let eventType: EventType  // .entered, .exited
    let timestamp: Date
    let location: CLLocationCoordinate2D

    enum EventType: String, Codable {
        case entered
        case exited
    }
}
```

---

### 4. 👨‍👩‍👧‍👦 Family Groups

**FamilyGroupManager.swift** - Gestión de grupos familiares

#### Group Structure

```swift
struct FamilyGroup: Identifiable, Codable {
    let id: UUID
    var name: String
    let code: FamilyGroupCode  // 6 digits
    var members: [FamilyMember]
    let creatorPeerID: String
    var createdAt: Date
    var lastSyncedAt: Date

    var memberCount: Int { members.count }
}

struct FamilyMember: Identifiable, Codable {
    let id: UUID = UUID()
    var peerID: String
    var nickname: String?
    var relationshipTag: String?  // "Papá", "Mamá", "Hijo", etc
    var lastSeenDate: Date
    var isCurrentDevice: Bool
    var lastKnownLocation: CLLocationCoordinate2D?
}

struct FamilyGroupCode: Codable, Hashable {
    let rawCode: String  // 6 digits: "482951"

    var displayCode: String {
        // Format: "482 951"
        let index = rawCode.index(rawCode.startIndex, offsetBy: 3)
        return "\(rawCode[..<index]) \(rawCode[index...])"
    }

    static func generate() -> FamilyGroupCode {
        let code = String(format: "%06d", Int.random(in: 0...999999))
        return FamilyGroupCode(rawCode: code)
    }
}
```

---

### 5. 🎯 ProximityHapticEngine

**ProximityHapticEngine.swift** (538 líneas) - Haptic feedback direccional

#### Proximity Zones

```swift
enum ProximityZone {
    case veryFar    // > 20m - no feedback
    case far        // 10-20m - slow pulses (3s)
    case near       // 5-10m - moderate pulses (2s)
    case close      // 2-5m - fast pulses (1s)
    case veryClose  // 1-2m - very fast pulses (0.5s)
    case arriving   // < 1m - continuous (0.2s)

    var intensity: Float      // 0.2 - 1.0
    var sharpness: Float      // 0.3 - 0.9
}
```

#### Directional Hints

```swift
enum RelativeDirection {
    case ahead       // ±15°
    case slightRight // 15-45°
    case right       // 45-90°
    case sharpRight  // 90-135°
    case behind      // > 135°
    case slightLeft  // -15 to -45°
    case left        // -45 to -90°
    case sharpLeft   // -90 to -135°
}

// Haptic patterns per direction
ahead: Single centered pulse
right: Two quick pulses (ascending intensity)
left: Two quick pulses (descending intensity)
behind: Double tap pattern
```

---

### 6. 🏝️ Live Activities + Dynamic Island

**MeshActivityAttributes.swift** - ActivityKit integration

#### Data Model

```swift
@available(iOS 16.1, *)
struct MeshActivityAttributes: ActivityAttributes {
    // Static (no cambia)
    var sessionId: String
    var localDeviceName: String
    var startedAt: Date

    // Dynamic (actualiza en tiempo real)
    struct ContentState: Codable, Hashable {
        var connectedPeers: Int
        var connectionQuality: ConnectionQualityState
        var trackingUser: String?
        var distance: Double?
        var direction: CardinalDirection?
        var isUWBTracking: Bool
        var familyMemberCount: Int
        var nearbyFamilyMembers: Int
        var activeLinkFence: String?
        var linkfenceStatus: LinkFenceStatus?
        var emergencyActive: Bool
        var lastUpdated: Date
    }
}
```

#### Dynamic Island States

##### 1. Tracking Activo (UWB)
```
┌─────────────────────────┐
│ 🔷  Buscando a Papá    │
│                         │
│  23m     ↗️ NE          │
│                         │
│ 👨‍👩‍👧‍👦 3/4 familia  🗺️ Punto │
└─────────────────────────┘
```

##### 2. Red Mesh Normal
```
┌─────────────────────────┐
│ 🌐  15 conectados      │
│                         │
│  💚 Mesh activo        │
│                         │
│ 📶 Buena calidad       │
└─────────────────────────┘
```

##### 3. Emergencia
```
┌─────────────────────────┐
│ 🚨  Alerta Médica      │
│                         │
│ 👨‍⚕️ Personal notificado  │
│                         │
│ 📍 Sección 104         │
└─────────────────────────┘
```

#### Background Extension

**Beneficios**:
| Sin Live Activity | Con Live Activity |
|-------------------|-------------------|
| 3-10 minutos background | **30-60 minutos** |
| Estado invisible | ✅ Isla Dinámica |
| Baja prioridad iOS | Alta prioridad |
| Reconexión manual | Automática |

---

### 7. ♿ Accessibility System

**AccessibilitySettingsManager.swift** - WCAG 2.1 AA compliance

#### Features Implementadas

##### 7.1 VoiceOver Complete
```swift
// AccessibilityModifiers.swift
extension View {
    func accessibleButton(
        label: String,
        hint: String?,
        value: String?,
        traits: AccessibilityTraits = [],
        minTouchTarget: CGFloat = 44
    ) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityValue(value ?? "")
            .accessibilityAddTraits(.isButton)
            .frame(minWidth: 44, minHeight: 44)
    }

    func accessibleGroup(
        label: String,
        hint: String?,
        sortPriority: Double = 0
    ) -> some View {
        self
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilitySortPriority(sortPriority)
    }
}
```

##### 7.2 Dynamic Type
```swift
@ScaledMetric(relativeTo: .body) var buttonHeight: CGFloat = 44

Text("Connect")
    .font(.body)  // Scales automatically
    .minimumScaleFactor(0.5)
```

##### 7.3 High Contrast Themes
```swift
struct AccessibleThemeColors {
    // WCAG AA compliant (4.5:1 minimum)
    let background: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let error: Color

    static let standard: AccessibleThemeColors(...)
    static let highContrast: AccessibleThemeColors(...)
    static let darkMode: AccessibleThemeColors(...)
}
```

---

## 🚀 Características Avanzadas

### 1. Connection Orchestrator

**Intelligent Connection Management** con subsistemas integrados:

#### Leader Election (Bully Algorithm)
```swift
// LeaderElection.swift
- Distributed leader selection
- Network state coordination
- Failover automatic
- Priority based on peer ID hash
```

#### Connection Pool
```swift
// ConnectionPoolManager.swift
- Max 5 connections (optimal mesh density)
- Priority slots (family > friends > strangers)
- Automatic eviction of low-quality connections
- Load balancing
```

#### Peer Reputation System
```swift
// PeerReputationSystem.swift
Score: 0-100 based on:
- Message success rate (40%)
- Connection stability (30%)
- Latency average (20%)
- Time connected (10%)

Reputation tiers:
- Excellent (80-100): Auto-accept always
- Good (60-80): Accept with priority
- Fair (40-60): Accept if slots available
- Poor (20-40): Postpone connection
- Bad (0-20): Reject
```

#### Adaptive Backoff
```swift
// AdaptiveBackoffManager.swift
Exponential backoff with jitter:
Attempt 1: 1s + random(0-0.5s)
Attempt 2: 2s + random(0-1s)
Attempt 3: 4s + random(0-2s)
Attempt 4: 8s + random(0-4s)
Max: 30s

Circuit breaker pattern:
- Open: After 5 consecutive failures
- Half-open: Allow 1 test connection after cooldown
- Closed: Resume normal operations
```

### 2. Stadium Mode Optimizations

```swift
// StadiumMode.swift - FIFA 2026
MegaStadium (80,000+ users):
✅ Max 3 connections (prevents network storm)
✅ Discovery rate 0.05s (ultra-aggressive scan)
✅ Connection timeout 1s (fast failover)
✅ Lightning Mesh enabled (predictive routing)
✅ UDP transport enabled (faster than TCP)
✅ Bluetooth LE enabled (fallback transport)
✅ Predictive disconnection detection
```

### 3. Offline Maps

**OfflineMapManager.swift** - Pre-download stadium maps

```swift
// Support for MapTiler, Mapbox, OpenStreetMap
- Tile-based caching
- Auto-download popup on first launch
- Region selection (stadium boundaries)
- Zoom levels 10-18
- Progress tracking
- MBTiles format support
```

### 4. Network Topology Visualization

**TopologyMessage** - Network graph discovery

```swift
struct TopologyMessage: Codable {
    let senderPeerID: String
    let connectedPeers: [String]
    let hopCount: Int
    let timestamp: Date
}

// Periodic broadcast (every 30s)
// Build distributed network graph
// Visualize in NetworkRadarView
```

---

## 💻 Instalación y Configuración

### Requisitos del Sistema

- **Xcode**: 15.0+ (16.0+ recomendado)
- **macOS**: Sonoma 14.0+
- **Swift**: 5.9+
- **iOS Device**: iPhone 11+ (para UWB)
  - iPhone 11-13: U1 chip (dirección nativa)
  - iPhone 14+: U2 chip (camera assistance required)

### Clonar Repositorio

```bash
git clone https://github.com/SEBASTIANCONTRERAS35/LinkUp.git
cd LinkUp
```

### Configuración de Permisos (Info.plist)

El proyecto requiere los siguientes permisos:

```xml
<!-- Bluetooth para mesh networking -->
<key>NSBluetoothAlwaysUsageDescription</key>
<string>StadiumConnect Pro usa Bluetooth para descubrir dispositivos cercanos...</string>

<key>NSBluetoothPeripheralUsageDescription</key>
<string>StadiumConnect Pro necesita Bluetooth para anunciarse...</string>

<!-- Red local para MultipeerConnectivity -->
<key>NSLocalNetworkUsageDescription</key>
<string>StadiumConnect Pro necesita acceso a la red local para comunicación P2P...</string>

<key>NSBonjourServices</key>
<array>
    <string>_meshred-chat._tcp</string>
    <string>_meshred-chat._udp</string>
</array>

<!-- Ubicación para geofencing -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>StadiumConnect Pro necesita tu ubicación para ayudar a familiares...</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>StadiumConnect Pro necesita acceso a tu ubicación en segundo plano...</string>

<!-- UWB (NearbyInteraction) -->
<key>NSNearbyInteractionUsageDescription</key>
<string>StadiumConnect Pro usa Nearby Interaction (LinkFinder) para navegación precisa...</string>

<key>NSNearbyInteractionAllowOnceUsageDescription</key>
<string>StadiumConnect Pro necesita acceso a Nearby Interaction para localizar dispositivos...</string>

<!-- Camera Assistance (iPhone 14+) -->
<key>NSCameraUsageDescription</key>
<string>StadiumConnect Pro necesita acceso a la cámara para Camera Assistance (ARKit)...</string>

<!-- Motion (CRÍTICO para ARKit) -->
<key>NSMotionUsageDescription</key>
<string>StadiumConnect Pro usa sensores de movimiento para mejorar la precisión de LinkFinder...</string>

<!-- Live Activities -->
<key>NSSupportsLiveActivities</key>
<true/>
<key>NSSupportsLiveActivitiesFrequentUpdates</key>
<true/>

<!-- Background Modes -->
<key>UIBackgroundModes</key>
<array>
    <string>location</string>
    <string>network-authentication</string>
</array>
```

### Build y Ejecución

```bash
# Clean build
xcodebuild clean -scheme MeshRed

# Build para iOS Simulator
xcodebuild -scheme MeshRed \
    -destination "platform=iOS Simulator,name=iPhone 17"

# Build para dispositivo físico (requiere Apple Developer account)
xcodebuild -scheme MeshRed \
    -destination "platform=iOS,name=Any iOS Device" \
    CODE_SIGN_IDENTITY="iPhone Developer" \
    DEVELOPMENT_TEAM="QF2R75VM2Y"

# Run tests
xcodebuild test -scheme MeshRed \
    -destination "platform=macOS"
```

### Configuración de Apple Developer

1. **Capabilities** requeridas:
   - ✅ Bluetooth
   - ✅ Network Extensions
   - ✅ Background Modes (Location, Network Authentication)
   - ✅ Push Notifications (para Live Activities)

2. **Entitlements**:
   - `com.apple.security.application-groups` (para Live Activity extension)
   - `com.apple.developer.networking.multicast` (para Bonjour)

3. **App Sandbox**: DESHABILITADO (`ENABLE_APP_SANDBOX = NO`)

### Configuración de Red Importante ⚠️

**PROBLEMA CRÍTICO**: WiFi habilitado pero NO conectado causa fallos de conexión.

**Configuraciones válidas**:
1. ✅ **WiFi OFF + Bluetooth ON** (modo avión)
2. ✅ **WiFi CONECTADO + Bluetooth ON**

**Configuración NO soportada**:
❌ WiFi habilitado pero NO conectado + Bluetooth ON
→ Causa `SocketStream read error: Code=60 "Operation timed out"`

**Solución**:
- La app detecta esta configuración y muestra advertencia automática
- Banner rojo en UI sugiere conectar WiFi o deshabilitarlo completamente

---

## 🎬 Casos de Uso: Mundial 2026

### Escenario Completo: Familia González en Estadio Azteca

**Contexto**: 87,000 asistentes, red celular saturada, niño perdido

#### 1. Setup Inicial (Pre-evento)

```swift
// Papá crea grupo familiar
familyGroupManager.createGroup(
    name: "Familia González",
    creatorPeerID: "iPhone de Papá",
    creatorNickname: "Papá"
)
// Código generado: "482 951"

// Mamá, hijo, hija se unen
familyGroupManager.joinGroup(
    code: FamilyGroupCode(rawCode: "482951"),
    groupName: "Familia González",
    memberPeerID: "iPhone de Hijo",
    memberNickname: "Diego",
    relationshipTag: "Hijo"
)

// Crear LinkFence de punto de encuentro
linkfenceManager.createGeofence(
    name: "Sección 120 - Punto de Encuentro",
    center: CLLocationCoordinate2D(latitude: 19.4326, longitude: -99.1332),
    radius: 50,
    shareWithFamily: true,
    category: .meetingPoint
)
```

#### 2. Durante el Evento: Niño Perdido

**Timeline**:
```
14:30 - Hijo sale a buscar baño
14:35 - Familia nota ausencia de Diego
14:36 - Papá activa LinkFinder en app
14:36:05 - Token exchange via LinkMesh completo
14:36:10 - UWB ranging establecido
14:36:15 - Distancia: 47m | Dirección: NE ↗️
14:37 - Papá sigue flecha direccional con haptic feedback
14:38 - Zona "near": Haptic pulses cada 2s
14:39 - Zona "close": Haptic pulses cada 1s
14:39:30 - Encuentro exitoso
```

**Tecnologías usadas**:
- LinkMesh: Token exchange sin internet
- LinkFinder UWB: Precisión centimétrica
- ProximityHapticEngine: Feedback direccional
- Live Activity: Estado visible en Dynamic Island

#### 3. Emergencia Médica: Abuelo Cardíaco

**Apple Watch Detection Flow**:
```swift
// WatchEmergencyDetector.swift
1. Apple Watch detecta HR anormal: 150 bpm (umbral: 130 bpm)
2. Confirma durante 60s consecutivos
3. Audio analysis: NO grito detectado (ruling out false positive)
4. Trigger emergency alert

// iPhone app recibe alerta
5. Muestra SOS View automáticamente
6. Broadcast emergency message via LinkMesh:
   - Tipo: .emergency (prioridad 0)
   - requiresAck: true
   - TTL: 5 (multi-hop)

7. Personal médico del estadio (app instalada) recibe alerta:
   - Notificación local high-priority
   - Ubicación del usuario con mapa
   - Perfil médico (grupo sanguíneo, alergias)

8. Médico confirma recepción (ACK automático)
9. Médico navega con LinkFinder UWB hacia paciente
10. Tiempo respuesta: 2 minutos (vs 8-10 típico)
```

**NO llama 911 directamente**:
- ❌ Evita falsas alarmas que saturan emergencias
- ✅ Personal médico del estadio actúa como intermediario
- ✅ Validación humana antes de escalar a 911

#### 4. Red Saturada: 80,000+ Usuarios

**Comparación**:

| Escenario | Red Celular | StadiumConnect Pro |
|-----------|-------------|---------------------|
| **Torre celular** | Colapsada | N/A (no usa) |
| **Latencia** | 5000ms+ o timeout | 50-200ms (Bluetooth) |
| **Cobertura** | Intermitente | Mesh multi-hop estable |
| **Mensajes** | ❌ Fallan | ✅ Delivered via relay |
| **Localización** | ❌ GPS timeout | ✅ UWB centimétrica |
| **Familia** | ❌ Incomunicados | ✅ LinkMesh activo |

**StadiumConnect Pro sigue funcionando**:
- Bluetooth/WiFi Direct no dependen de torres
- Multi-hop routing: mensajes saltan entre peers
- Family group sincroniza estado vía mesh
- LinkFinder funciona independientemente de internet

---

## 📊 Estructura del Proyecto

```
MeshRed/
├── MeshRed/                                    # Main app target
│   ├── MeshRedApp.swift                        # Entry point + scene lifecycle
│   ├── ContentView.swift                       # Root view
│   ├── Info.plist                              # Permisos y configuración
│   │
│   ├── Models/                                 # 25+ data models
│   │   ├── Message.swift                       # UI message model
│   │   ├── FamilyGroup.swift                   # Family group structure
│   │   ├── FamilyMember.swift                  # Member with nickname/relationship
│   │   ├── FamilyGroupCode.swift               # 6-digit code
│   │   ├── CustomLinkFence.swift               # Geofence model
│   │   ├── LinkFenceCategory.swift             # 6 categories
│   │   ├── UserLocation.swift                  # Location wrapper
│   │   ├── MeshActivityAttributes.swift        # Live Activity data
│   │   ├── EmergencyMedicalProfile.swift       # Medical info
│   │   └── ...
│   │
│   ├── Services/                               # 35+ service managers (20,159 LOC)
│   │   ├── NetworkManager.swift                # ⭐ Core P2P coordinator (4,415 lines)
│   │   ├── NetworkManager+LiveActivity.swift   # Live Activity extension
│   │   ├── NetworkManager+Orchestrator.swift   # Orchestrator integration
│   │   ├── LinkFinderSessionManager.swift      # ⭐ UWB manager (1,388 lines)
│   │   ├── LinkFenceManager.swift              # Geofencing (728 lines)
│   │   ├── FamilyGroupManager.swift            # Family coordination
│   │   ├── MessageStore.swift                  # Persistent storage
│   │   ├── PeerHealthMonitor.swift             # Connection quality
│   │   ├── ConnectionOrchestrator.swift        # Intelligent management (538 lines)
│   │   ├── ConnectionPoolManager.swift         # Pool management
│   │   ├── LeaderElection.swift                # Distributed leader
│   │   ├── PeerReputationSystem.swift          # Peer scoring (533 lines)
│   │   ├── AdaptiveBackoffManager.swift        # Exponential backoff (497 lines)
│   │   ├── ProximityHapticEngine.swift         # Haptic feedback (538 lines)
│   │   ├── HapticManager.swift                 # General haptics (599 lines)
│   │   ├── SessionManager.swift                # Connection lifecycle (565 lines)
│   │   ├── ConnectionMutex.swift               # Race condition prevention
│   │   ├── LocationService.swift               # GPS/CoreLocation
│   │   ├── LocationRequestManager.swift        # Location sharing
│   │   ├── PeerLocationTracker.swift           # Peer location tracking
│   │   ├── NavigationCalculator.swift          # Route calculation
│   │   ├── FallbackDirectionService.swift      # GPS + Compass fallback
│   │   ├── MotionPermissionManager.swift       # Motion permission request
│   │   ├── StadiumMode.swift                   # FIFA 2026 optimizations (482 lines)
│   │   ├── StadiumModeManager.swift            # Stadium mode activation
│   │   ├── OfflineMapManager.swift             # Map tile caching
│   │   ├── OfflineMapDownloader.swift          # Map download
│   │   ├── AudioManager.swift                  # Audio guidance
│   │   └── ...
│   │
│   ├── Views/                                  # 45+ SwiftUI views
│   │   ├── MainDashboardContainer.swift        # Main dashboard
│   │   ├── LinkFinderHubView.swift             # UWB navigation hub
│   │   ├── LinkFinderNavigationView.swift      # Navigation with arrow
│   │   ├── NetworkRadarView.swift              # Visual peer radar
│   │   ├── SinglePeerRadarView.swift           # Single peer tracking
│   │   ├── FamilyGroupView.swift               # Family management
│   │   ├── CreateFamilyGroupView.swift         # Group creation
│   │   ├── JoinFamilyGroupView.swift           # Join with code
│   │   ├── LinkFenceListView.swift             # Geofence list
│   │   ├── LinkFenceCreatorView.swift          # Create geofence
│   │   ├── LinkFenceDetailView.swift           # Geofence details
│   │   ├── FamilyLinkFenceMapView.swift        # Map with geofences
│   │   ├── SOSView.swift                       # Emergency panel
│   │   ├── MessagingDashboardView.swift        # Chat interface
│   │   ├── NetworkManagementView.swift         # Connection management
│   │   ├── NetworkOrchestratorView.swift       # Orchestrator UI
│   │   └── Components/
│   │       ├── PeerConnectionCard.swift
│   │       ├── LinkFenceRow.swift
│   │       ├── LinkFenceStatCard.swift
│   │       ├── SignalQualityBar.swift
│   │       └── ...
│   │
│   ├── Accessibility/                          # WCAG 2.1 AA compliance
│   │   ├── AccessibilityModifiers.swift        # View extensions
│   │   ├── AccessibilityViewModifiers.swift    # Custom modifiers
│   │   ├── AccessibleThemeColors.swift         # High contrast themes
│   │   └── ...
│   │
│   ├── Settings/
│   │   ├── AccessibilitySettingsView.swift     # Accessibility panel
│   │   ├── AccessibilitySettingsManager.swift  # Settings persistence
│   │   ├── StadiumModeSettingsView.swift       # Stadium mode config
│   │   └── UserDisplayNameSettingsView.swift   # Name customization
│   │
│   ├── Theme/
│   │   └── Mundial2026Theme.swift              # World Cup theme
│   │
│   ├── NetworkMessage.swift                    # Network protocol definitions
│   ├── MessageQueue.swift                      # Priority queue (159 lines)
│   ├── MessageCache.swift                      # Deduplication cache
│   ├── AckManager.swift                        # ACK system (185 lines)
│   ├── RoutingTable.swift                      # Route storage
│   ├── RouteCache.swift                        # AODV-like cache
│   ├── NetworkConfig.swift                     # Network modes config
│   └── ...
│
├── MeshRedLiveActivity/                        # Widget Extension
│   ├── MeshRedLiveActivityBundle.swift         # Extension entry
│   ├── MeshActivityWidget.swift                # Main widget
│   ├── MeshRedLiveActivity.swift               # Live Activity definition
│   └── Views/
│       ├── LockScreenLiveActivityView.swift    # Lock screen
│       ├── CompactLeadingView.swift            # Dynamic Island compact left
│       ├── CompactTrailingView.swift           # Dynamic Island compact right
│       ├── MinimalView.swift                   # Minimal state
│       └── Expanded*View.swift                 # Expanded states
│
├── MeshRed Watch App/                          # watchOS target
│   ├── MeshRed_Watch_AppApp.swift              # Watch entry point
│   ├── WatchEmergencyDetector.swift            # Multi-sensor emergency
│   ├── WatchSOSView.swift                      # Watch SOS UI
│   └── ContentView.swift                       # Watch main view
│
├── MeshRedTests/                               # Unit tests
│   └── MeshRedTests.swift
│
├── MeshRedUITests/                             # UI tests
│   └── MeshRedUITests.swift
│
├── CLAUDE.md                                   # Project context for AI
├── LINKFINDER_FALLBACK_SYSTEM.md               # UWB fallback docs
└── README.md                                   # This file
```

---

## 🧪 Testing y Debugging

### Unit Tests

```bash
# Run all unit tests
xcodebuild test -scheme MeshRed \
    -destination "platform=macOS" \
    -only-testing:MeshRedTests

# Run specific test
xcodebuild test -scheme MeshRed \
    -destination "platform=macOS" \
    -only-testing:MeshRedTests/NetworkManagerTests/testMultiHopRouting
```

### UI Tests

```bash
# Run all UI tests
xcodebuild test -scheme MeshRed \
    -destination "platform=iOS Simulator,name=iPhone 17" \
    -only-testing:MeshRedUITests

# Accessibility UI tests
xcodebuild test -scheme MeshRed \
    -destination "platform=iOS Simulator,name=iPhone 17" \
    -only-testing:MeshRedUITests/AccessibilityTests
```

### Manual Testing (Dispositivos Físicos Requeridos)

**Requisitos mínimos**: 2 iPhones (11+)

#### Test 1: Basic Mesh Connectivity
1. Instalar app en ambos dispositivos
2. Abrir app en ambos
3. ✅ Verificar descubrimiento automático en 5 segundos
4. ✅ Verificar conexión establecida
5. ✅ Enviar mensaje de prueba
6. ✅ Verificar ACK recibido

#### Test 2: UWB LinkFinder (iPhone 11+ required)
1. Dispositivo A: Abrir LinkFinder Hub
2. Dispositivo A: Seleccionar peer B
3. ✅ Token exchange automático
4. ✅ Distance measurement aparece en <3 segundos
5. iPhone 14+: ✅ Direction measurement con camera assistance
6. iPhone 11-13: ✅ Direction nativa sin camera
7. ✅ Haptic feedback al acercarse

### 🔍 Sistema de Logging Automático

**NUEVO**: Sistema completo de logging con captura automática para análisis sin copiar/pegar.

#### Componentes del Sistema

1. **LoggingService.swift**: Sistema moderno usando OSLog framework
   - Categorías: network, mesh, uwb, geofence, emergency, ui
   - Niveles: debug, info, warning, error, fault
   - Performance tracking con signposts

2. **log_monitor.sh**: Script de captura en tiempo real
   - Detecta simuladores/dispositivos automáticamente
   - Filtra por subsystem de la app
   - Análisis en tiempo real con detección de errores
   - Buffer circular de 1000 líneas

3. **analyze_logs.sh**: Analizador automático
   - Genera reportes en Markdown
   - Detecta patrones problemáticos
   - Exporta JSON para análisis automático
   - Estadísticas de sesión

#### Uso Rápido

```bash
# Iniciar monitoreo automático
./log_monitor.sh --auto

# Modo interactivo con menú
./log_monitor.sh

# Monitorear simulador específico
./log_monitor.sh --simulator

# Analizar logs capturados
./analyze_logs.sh

# Análisis rápido (solo errores)
./analyze_logs.sh --quick

# Exportar para Claude Code
./analyze_logs.sh --json
```

#### Estructura de Logs

```
logs/
├── current_session.log     # Sesión actual
├── errors.log              # Errores detectados
├── stats.log               # Estadísticas
├── sessions/               # Historial de sesiones
│   └── session_*.log       # Sesiones anteriores
└── analysis/               # Reportes de análisis
    ├── report_*.md         # Reportes legibles
    └── claude_analysis.json # Para análisis automático
```

#### Análisis Automático por Claude Code

Ahora puedo analizar tus logs automáticamente:
```bash
# Tú ejecutas:
./log_monitor.sh --auto &  # Captura en background

# Yo puedo leer directamente:
cat logs/current_session.log     # Ver logs completos
cat logs/errors.log              # Ver solo errores
cat logs/analysis/claude_analysis.json  # Métricas estructuradas
```

#### Categorías de Logging

- **network**: Conexiones P2P, MultipeerConnectivity
- **mesh**: Routing, multi-hop, retransmisiones
- **uwb**: NearbyInteraction, mediciones de distancia
- **geofence**: Zonas virtuales, notificaciones por ubicación
- **emergency**: Detección de emergencias, alertas médicas
- **ui**: Eventos de interfaz, interacciones del usuario

#### Test 3: UWB Fallback System (iPhone 14+ required)
1. iPhone 14+: Denegar permiso de Motion
2. Activar LinkFinder
3. ✅ Fallback mode activa después de 10s
4. ✅ GPS location sharing iniciado automáticamente
5. ✅ Bearing aproximado calculado (GPS + Compass)
6. ✅ UI muestra "🧭 Dirección Aproximada (Brújula)"
7. Otorgar permiso de Motion
8. Reiniciar LinkFinder
9. ✅ Cambio automático a "🎯 Dirección Precisa (UWB)"

#### Test 4: Family Groups
1. Dispositivo A: Crear grupo "Test Family"
2. ✅ Código de 6 dígitos generado
3. Dispositivo B: Unirse con código
4. ✅ Sincronización automática vía LinkMesh
5. ✅ Ambos dispositivos ven mismos miembros

#### Test 5: LinkFence Geofencing
1. Crear geofence "Test Point" (50m radius)
2. Compartir con familia
3. ✅ Family members reciben geofence
4. Caminar hacia/desde geofence
5. ✅ Entry/exit events disparados
6. ✅ Notificaciones locales recibidas
7. ✅ Timeline actualizado

#### Test 6: Stadium Mode (3+ dispositivos)
1. Dispositivo A: Activar Stadium Mode (Mega Stadium)
2. ✅ Max connections limitado a 3
3. ✅ Discovery rate 0.05s (muy rápido)
4. ✅ Lightning mesh habilitado
5. Conectar 5+ peers cercanos
6. ✅ Solo 3 mejores peers conectados
7. ✅ Reputation system selecciona mejores

#### Test 7: Live Activity
1. Conectar a 2+ peers
2. ✅ Live Activity inicia automáticamente
3. ✅ Dynamic Island muestra peers count
4. Iniciar LinkFinder tracking
5. ✅ Dynamic Island muestra distancia/dirección
6. Poner app en background
7. ✅ Conexiones mantenidas 30+ minutos (vs 3-10 min sin Live Activity)

#### Test 8: Accessibility (VoiceOver)
1. Activar VoiceOver (Settings → Accessibility)
2. Abrir app
3. ✅ Todos los botones tienen labels
4. ✅ Navigation lógica (sortPriority correcto)
5. ✅ Hints informativos
6. ✅ State changes announced
7. LinkFinder: ✅ Distance/direction announced en voz

### Debug Logging

El proyecto incluye logging extenso con emojis para fácil identificación:

```swift
// Networking
📡 MultipeerConnectivity events
🌐 Mesh networking operations
🔄 Multi-hop routing
✅ Successful operations
❌ Errors
⚠️ Warnings

// UWB
🎯 LinkFinder sessions
📏 Distance measurements
🧭 Direction measurements (UWB or Compass)
🔐 Permission requests

// Family
👨‍👩‍👧‍👦 Family group operations
📍 Location sharing
🗺️ Geofencing

// Emergency
🚨 Emergency alerts
⌚ Apple Watch detection
```

**Filtrar logs**:
```bash
# Solo logs de LinkFinder
xcrun simctl spawn booted log stream --predicate 'processImagePath contains "MeshRed"' | grep "🎯"

# Solo logs de networking
xcrun simctl spawn booted log stream --predicate 'processImagePath contains "MeshRed"' | grep "📡"
```

### Troubleshooting Common Issues

#### Issue 1: Peers Not Discovering

**Symptoms**: availablePeers array vacío después de 10+ segundos

**Diagnosis**:
```bash
# Check network configuration
NetworkManager: hasNetworkConfigurationIssue = true?
```

**Solutions**:
1. ✅ WiFi: Conectar a una red OR deshabilitar completamente
2. ✅ Bluetooth: Verificar habilitado en Settings
3. ✅ Permisos: Local Network permission granted
4. ✅ Mismo service type: "meshred-chat"
5. ✅ No en modo avión (a menos que solo Bluetooth)

#### Issue 2: UWB Direction Always Nil (iPhone 14+)

**Symptoms**: `object.direction = nil` perpetuo, pero distance funciona

**Diagnosis**:
```bash
# Check permissions
Camera: authorized
Motion: ⚠️ denied ← CULPRIT
```

**Solutions**:
1. ✅ Settings → Privacy → Motion & Fitness → MeshRed → Enable
2. ✅ Reiniciar app
3. ✅ Verificar MotionPermissionManager.swift logs
4. Si persiste: ✅ Fallback automático a GPS + Compass después de 10s

#### Issue 3: ACK Timeouts

**Symptoms**: Mensajes nunca reciben ACK, reintentos infinitos

**Diagnosis**:
```bash
AckManager: Pending ACKs Count: 15+ (creciendo)
```

**Solutions**:
1. ✅ Verificar TTL adecuado (default: 5 hops)
2. ✅ Check routing path: ¿loops circulares?
3. ✅ Adaptive timeout: Incrementar para redes lentas
4. ✅ Recipient conectado y activo?

#### Issue 4: Connection Limit Reached

**Symptoms**: "Cannot connect to peer - at max connections (5)"

**Solutions**:
1. ✅ Desconectar peers de baja calidad manualmente
2. ✅ ConnectionOrchestrator evict automáticamente
3. ✅ Incrementar maxConnections (no recomendado > 8)
4. ✅ Habilitar Stadium Mode (reduce max connections)

---

## 🤝 Contribuir

Este proyecto fue desarrollado para el **Changemakers Social Challenge 2025**. Contribuciones son bienvenidas para:

### Áreas de Contribución

1. **Nuevas funcionalidades de accesibilidad**
   - Soporte para switch control
   - Voice control improvements
   - Color blindness modes

2. **Optimizaciones de batería**
   - Background execution improvements
   - Bluetooth LE scanning optimizations
   - GPS usage reduction

3. **Mejoras de UI/UX**
   - Nuevos temas
   - Animaciones mejoradas
   - Onboarding flow

4. **Corrección de bugs**
   - Reportar issues en GitHub
   - Pull requests con fixes
   - Tests adicionales

5. **Documentación**
   - Traducción a otros idiomas
   - Tutoriales en video
   - Guías de integración

### Pull Request Process

1. Fork el repositorio
2. Crear rama feature:
   ```bash
   git checkout -b feature/AmazingFeature
   ```
3. Commit cambios con mensajes descriptivos:
   ```bash
   git commit -m "Add: UWB extended range support for iPhone 15 Pro"
   ```
4. Push a rama:
   ```bash
   git push origin feature/AmazingFeature
   ```
5. Abrir Pull Request en GitHub
6. Esperar code review
7. Hacer ajustes si necesario
8. Merge! 🎉

### Code Style Guidelines

- **Swift Style Guide**: Follow [Swift.org API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- **Comments**: En español para este proyecto (UNAM context)
- **Logging**: Use emoji prefixes para categorización
- **Accessibility**: `accessibilityLabel`, `accessibilityHint`, `accessibilitySortPriority` obligatorios
- **Thread Safety**: Document all concurrent code
- **Performance**: Profile antes de optimizar

---

## 🔮 Roadmap

### Fase 1: CSC 2025 (Octubre 2025) ✅
- [x] LinkMesh P2P networking
- [x] LinkFinder UWB con fallback
- [x] LinkFence geofencing
- [x] Family groups
- [x] Live Activities
- [x] Accessibility completa

### Fase 2: Post-Hackathon (Noviembre 2025)
- [ ] Core ML integration para emergencias
- [ ] ARKit indoor navigation
- [ ] Backend opcional (analytics)
- [ ] Multi-idioma completo (español, inglés, francés)

### Fase 3: Mundial 2026 (Junio-Julio 2026)
- [ ] Integración con sistemas del estadio
- [ ] Partnership con FIFA
- [ ] Beta testing en estadios reales
- [ ] Escalabilidad 100,000+ usuarios

### Fase 4: Post-Mundial (2027+)
- [ ] Expansión a otros eventos (conciertos, festivales)
- [ ] Smart city integration
- [ ] IoT stadium devices
- [ ] Machine learning optimizations

---

## 📄 Licencia

Este proyecto está bajo la licencia MIT. Ver archivo [LICENSE](LICENSE) para más detalles.

---

## 👥 Equipo

- **Desarrollo**: Emilio Contreras
- **Institución**: Facultad de Ingeniería UNAM
- **Evento**: Changemakers Social Challenge (CSC) 2025
- **Organizador**: iOS Development Lab - División de Ingeniería Eléctrica Electrónica
- **Categoría**: App Inclusiva

---

## 📞 Contacto

- **GitHub**: [@SEBASTIANCONTRERAS35](https://github.com/SEBASTIANCONTRERAS35)
- **Repositorio**: [LinkUp](https://github.com/SEBASTIANCONTRERAS35/LinkUp)

---

## 🙏 Agradecimientos

- **iOS Development Lab UNAM** por organizar el CSC 2025
- **Apple** por los frameworks MultipeerConnectivity, NearbyInteraction, y HealthKit
- **Comunidad de desarrolladores iOS** por soporte y feedback
- **FIFA 2026** por la inspiración del caso de uso

---

## 📚 Referencias y Documentación

### Apple Frameworks
- [MultipeerConnectivity](https://developer.apple.com/documentation/multipeerconnectivity)
- [NearbyInteraction](https://developer.apple.com/documentation/nearbyinteraction)
- [CoreLocation](https://developer.apple.com/documentation/corelocation)
- [ActivityKit (Live Activities)](https://developer.apple.com/documentation/activitykit)
- [CoreHaptics](https://developer.apple.com/documentation/corehaptics)

### Accessibility
- [WCAG 2.1 Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)
- [Apple Accessibility](https://developer.apple.com/accessibility/)
- [VoiceOver Programming Guide](https://developer.apple.com/library/archive/documentation/Accessibility/Conceptual/AccessibilityMacOSX/index.html)

### Networking
- [AODV Routing Protocol](https://www.ietf.org/rfc/rfc3561.txt)
- [Mesh Networking Best Practices](https://en.wikipedia.org/wiki/Wireless_mesh_network)

### Documentation Interna
- [CLAUDE.md](CLAUDE.md) - Contexto completo del proyecto
- [LINKFINDER_FALLBACK_SYSTEM.md](LINKFINDER_FALLBACK_SYSTEM.md) - Sistema de fallback UWB

---

<p align="center">
  <strong>Desarrollado con ❤️ para el Mundial FIFA 2026 y eventos masivos inclusivos</strong>
  <br>
  <em>Changemakers Social Challenge 2025 - UNAM</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Made%20with-Swift-orange.svg" alt="Made with Swift">
  <img src="https://img.shields.io/badge/Platform-iOS%20%7C%20watchOS-lightgrey.svg" alt="Platform">
  <img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License">
</p>
