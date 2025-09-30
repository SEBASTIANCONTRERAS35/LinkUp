# CLAUDE.md - StadiumConnect Pro

Este archivo proporciona contexto completo del proyecto StadiumConnect Pro desarrollado para el Changemakers Social Challenge (CSC) 2025 de la Facultad de Ingeniería UNAM.

## Contexto del Hackathon - CSC 2025

### Información del Evento
- **Evento**: Changemakers Social Challenge (CSC) 2025 - Facultad de Ingeniería UNAM
- **Organizador**: iOS Development Lab - División de Ingeniería Eléctrica Electrónica
- **Temática**: Desarrollar apps iOS innovadoras que resuelvan necesidades sociales relacionadas con la Copa Mundial FIFA 2026 en México
- **Formato**: Equipos de 4 personas máximo, hasta 12 equipos total (4 por categoría)
- **Tecnología Obligatoria**: Swift, Xcode, frameworks iOS
- **Premio**: Ganadores representan a la Facultad en el nacional (noviembre 2025)

### Cronograma
- **Registro**: 22-26 septiembre 2025
- **Entrega de propuesta**: 29 septiembre - 3 octubre
- **Presentaciones presenciales**: 13-14 octubre en iOS Lab (Edificio P)
- **Resultados**: 15 octubre 19:00 hrs

### Categorías Disponibles
1. **Perspectiva Mujeres**: Equipos solo de mujeres, apps de empoderamiento femenino
2. **Inteligencia Artificial**: Apps que usen IA/ML para resolver problemas sociales
3. **App Inclusiva**: Apps accesibles para personas con discapacidad

## Proyecto Base - MeshRed

### Tecnología Existente
MeshRed es una aplicación de chat P2P mesh networking desarrollada con:
- **Tecnología**: SwiftUI + MultipeerConnectivity
- **Plataformas**: iOS, macOS, visionOS 26.0+
- **Arquitectura**: NetworkManager, MessageQueue, AckManager, PeerHealthMonitor
- **Comunicación**: Sin infraestructura, completamente descentralizada

### Funcionalidades Técnicas Avanzadas
- **Routing Multi-hop**: Mensajes pueden ser retransmitidos a través de peers intermedios
- **Cola de Prioridades**: 5 tipos de mensajes (Emergency > Alert > Meetup > Location > Chat)
- **Sistema de ACK**: Confirmaciones automáticas con reintentos
- **Monitoreo de Conexiones**: Tracking de salud y latencia de peers
- **Prevención de Loops**: TTL y cache para evitar duplicados

## StadiumConnect Pro - Propuesta para CSC 2025

### Concepto Central
Evolución de MeshRed hacia una solución integral para estadios durante el Mundial 2026, combinando comunicación mesh, localización precisa y detección de emergencias.

### Problemática Social Identificada
Durante eventos masivos como el Mundial FIFA 2026:
- **Saturación de Redes**: Torres celulares colapsan con 80,000+ usuarios simultáneos
- **Familias Separadas**: Difícil localizar miembros en multitudes masivas
- **Emergencias Médicas**: Respuesta lenta en eventos de alta densidad
- **Exclusión Digital**: Personas con discapacidades enfrentan barreras adicionales

### Solución Tecnológica

#### 1. Red Mesh Bluetooth
- Comunicación P2P sin dependencia de infraestructura
- Routing inteligente entre dispositivos cercanos
- Alcance extendido mediante retransmisión de mensajes

#### 2. Ultra Wideband (UWB) - Localización Precisa
- Precisión centimétrica para encontrar familiares
- Integración con NearbyInteraction framework
- Navegación indoor en estadios complejos

#### 3. Geofencing Inteligente
- Zonas virtuales del estadio (entradas, baños, concesiones)
- Alertas automáticas de entrada/salida de zonas
- Notificaciones contextuales por ubicación

#### 4. Sistema de Emergencias Inteligente
- Detección multi-sensor: heart rate + análisis de audio
- NO llama directamente al 911
- Contacta personal médico registrado del estadio como intermediarios
- Reducción de falsas alarmas mediante validación humana

### Arquitectura Técnica

#### Frameworks iOS Utilizados
```swift
import MultipeerConnectivity  // Red mesh P2P
import NearbyInteraction      // UWB localización precisa
import CoreLocation          // GPS y geofencing
import HealthKit            // Monitoreo biométrico
import AVFoundation         // Análisis de audio
import SwiftUI              // Interfaz de usuario
import Accessibility        // Soporte para discapacidades
```

#### Componentes Principales
- **MeshNetworkManager**: Coordinador de comunicación P2P
- **UWBLocationService**: Servicio de localización UWB
- **GeofenceManager**: Gestión de zonas virtuales
- **EmergencyDetector**: Sistema multi-sensor de emergencias
- **AccessibilityManager**: Adaptaciones para inclusión

### Diferenciación e Innovación

#### Combinación Tecnológica Única
- Primera app que combina MultipeerConnectivity + NearbyInteraction + CoreLocation
- Sistema de emergencias que usa personal del estadio como intermediarios
- Arquitectura completamente descentralizada y resiliente

#### Enfoque de Inclusión Desde el Diseño
- VoiceOver completo para usuarios con discapacidad visual
- Dynamic Type para diferentes capacidades visuales
- Alto contraste y navegación por gestos simplificados
- Interfaz adaptativa para usuarios con discapacidades motoras

### Impacto Social Esperado

#### Beneficios Directos
- **Familias**: Localización precisa en multitudes de 80,000+ personas
- **Personas con Discapacidades**: Navegación asistida y comunicación mejorada
- **Emergencias Médicas**: Respuesta 3-5 minutos más rápida
- **Resiliencia**: Funciona cuando infraestructura tradicional falla

#### Escalabilidad Post-Mundial
- Aplicable a cualquier evento masivo (conciertos, festivales)
- Transferible a otros estadios y venues
- Base para smart cities y IoT urbano

### Categoría Objetivo: App Inclusiva

#### Justificación
- **Accesibilidad Nativa**: VoiceOver, Dynamic Type, alto contraste implementados desde el diseño
- **Inclusión Real**: No solo cumple con guidelines, sino que mejora la experiencia para personas con discapacidades
- **Impacto Medible**: Reduce barreras tecnológicas en eventos masivos

#### Elementos Diferenciadores
- Navegación haptic para usuarios con discapacidad visual
- Reconocimiento de voz multiidioma (español/inglés/otros)
- Interfaz simplificada para usuarios con discapacidades cognitivas
- Sistema de emergencias accesible via múltiples canales

### Plan de Desarrollo (2 Semanas)

#### Equipo Frontend/UI-UX (2 personas)
- Semana 1: Interfaces principales + sistema de accesibilidad
- Semana 2: Geofencing UI + testing con usuarios

#### Equipo Backend/Lógica (2 personas)
- Semana 1: Integración UWB + sistema de emergencias
- Semana 2: Optimización mesh + testing de rendimiento

### Estrategia de Presentación (10 minutos)

#### Estructura del Pitch
1. **Hook** (1 min): Problema real - saturación de red en estadios
2. **Solución** (3 min): Demo live de localización UWB + mesh
3. **Diferenciación** (2 min): Único combo tecnológico + inclusión
4. **Impacto** (2 min): Casos de uso reales del Mundial 2026
5. **Viabilidad** (1 min): Arquitectura basada en MeshRed existente
6. **Cierre** (1 min): Call to action - imaginar implementación real

#### Demo Técnico Preparado
- Localización UWB en tiempo real entre 2 iPhones
- Comunicación mesh sin WiFi/cellular
- Sistema de emergencias con validación humana
- Navegación completa con VoiceOver activado

### Criterios de Evaluación Cubiertos

#### Innovación Técnica
✅ Combinación única de tecnologías iOS
✅ Arquitectura descentralizada resiliente
✅ Sistema de emergencias con validación humana

#### Impacto Social
✅ Resuelve problema real del Mundial 2026
✅ Beneficia múltiples grupos vulnerables
✅ Escalable a otros contextos

#### Viabilidad de Implementación
✅ Base en MeshRed ya desarrollado
✅ Usa frameworks nativos iOS
✅ Plan de desarrollo realista

#### Excelencia en Categoría (App Inclusiva)
✅ Accesibilidad nativa, no retrofitted
✅ Mejora real de experiencia para personas con discapacidades
✅ Múltiples canales de interacción

---

## Documentación Técnica - MeshRed (Base)

### Arquitectura Core Components

**NetworkManager** ([MeshRed/Services/NetworkManager.swift](MeshRed/Services/NetworkManager.swift))
- Central coordinator for all peer-to-peer networking operations
- Manages MultipeerConnectivity session, advertiser, and browser
- Implements sophisticated connection management with mutex locks and conflict resolution
- Handles message routing, relaying, and acknowledgments
- Integrates all specialized networking components (queue, cache, health monitor, etc.)

**Message System**
- `Message` ([MeshRed/Models/Message.swift](MeshRed/Models/Message.swift)): Simple UI-level message model
- `NetworkMessage` ([MeshRed/NetworkMessage.swift](MeshRed/NetworkMessage.swift)): Advanced network-level message with routing, TTL, priority, and ACK support
- `MessageStore` ([MeshRed/Services/MessageStore.swift](MeshRed/Services/MessageStore.swift)): Persistent message storage with UserDefaults
- `MessageQueue` ([MeshRed/MessageQueue.swift](MeshRed/MessageQueue.swift)): Priority-based heap queue for outgoing messages

**Advanced Networking Components**
- `AckManager` ([MeshRed/AckManager.swift](MeshRed/AckManager.swift)): Tracks messages requiring acknowledgment, handles retries and timeouts
- `MessageCache` ([MeshRed/MessageCache.swift](MeshRed/MessageCache.swift)): Prevents message duplicates during multi-hop routing
- `PeerHealthMonitor` ([MeshRed/Services/PeerHealthMonitor.swift](MeshRed/Services/PeerHealthMonitor.swift)): Monitors connection quality via ping/pong and latency tracking
- `SessionManager` ([MeshRed/Services/SessionManager.swift](MeshRed/Services/SessionManager.swift)): Tracks connection attempts, cooldowns, and prevents connection storms
- `ConnectionMutex` ([MeshRed/Services/ConnectionMutex.swift](MeshRed/Services/ConnectionMutex.swift)): Prevents race conditions during peer connection/invitation handling

### Key Design Patterns

**Multi-Hop Message Routing**
- Messages can be relayed through intermediate peers to reach disconnected devices
- TTL (time-to-live) and hop count prevent infinite routing loops
- Route path tracking prevents circular message propagation
- Broadcast and directed messaging modes supported

**Priority-Based Message Queue**
- Min-heap implementation prioritizes urgent messages (Emergency > Alert > Meetup > Location > Chat)
- Queue automatically evicts lowest-priority messages when full
- Supports five message types with configurable priorities

**Connection Conflict Resolution**
- Deterministic peer ID comparison prevents simultaneous bidirectional connections
- ConnectionMutex ensures only one connection operation per peer at a time
- SessionManager enforces cooldown periods after failed connections

**Acknowledgment System**
- Optional message-level acknowledgments with automatic retry
- Configurable retry count and timeout intervals
- Tracks pending ACKs and notifies on success/failure

### Project Structure

```
MeshRed/
├── MeshRed/
│   ├── MeshRedApp.swift              # App entry point, initializes NetworkManager
│   ├── ContentView.swift            # Main SwiftUI interface
│   ├── Info.plist                   # Required: Bluetooth and Bonjour permissions
│   ├── Models/
│   │   └── Message.swift            # Simple message model for UI
│   ├── Services/
│   │   ├── NetworkManager.swift     # Core networking coordinator
│   │   ├── MessageStore.swift       # Persistent message storage
│   │   ├── SessionManager.swift     # Connection lifecycle management
│   │   ├── PeerHealthMonitor.swift  # Connection quality monitoring
│   │   └── ConnectionMutex.swift    # Connection synchronization
│   ├── NetworkMessage.swift         # Network-level message protocol
│   ├── MessageQueue.swift           # Priority queue implementation
│   ├── MessageCache.swift           # Deduplication cache
│   ├── AckManager.swift             # Acknowledgment tracking
│   ├── NetworkConfig.swift          # Configuration modes and settings
│   └── TestingConfig.swift          # Testing utilities (optional)
├── MeshRedTests/
└── MeshRedUITests/
```

### Key Configurations

- **Bundle Identifier**: `EmilioContreras.MeshRed`
- **Service Type**: `meshred-chat` (for MultipeerConnectivity)
- **Bonjour Services**: `_meshred-chat._tcp`, `_meshred-chat._udp`
- **Swift Version**: 5.0
- **Deployment Targets**: iOS 26.0, macOS 26.0, visionOS 26.0
- **Development Team**: QF2R75VM2Y
- **App Sandbox**: Disabled (ENABLE_APP_SANDBOX = NO) to allow network access
- **Hardened Runtime**: Enabled

### Required Permissions (Info.plist)

The app requires these permission keys:
- `NSBluetoothAlwaysUsageDescription`: For peer discovery via Bluetooth
- `NSBluetoothPeripheralUsageDescription`: For advertising availability
- `NSLocalNetworkUsageDescription`: For local network communication
- `NSBonjourServices`: Service discovery configuration

### Message Types and Priorities

| Type | Priority | Use Case |
|------|----------|----------|
| Emergency | 0 | Critical alerts requiring immediate attention |
| Alert | 1 | Important warnings |
| Meetup | 2 | Coordination and scheduling |
| Location | 3 | Position sharing |
| Chat | 4 | Regular conversation |

Lower priority numbers are processed first.

### Connection Lifecycle

1. **Discovery**: Browser finds peers via Bonjour/Bluetooth
2. **Conflict Resolution**: Lower peer ID initiates connection
3. **Mutex Lock**: Prevent duplicate connection attempts
4. **Session Validation**: Check connection cooldowns via SessionManager
5. **Invitation**: Browser invites or Advertiser accepts
6. **Connected**: Peer added to active connections, health monitoring begins
7. **Monitoring**: PeerHealthMonitor tracks latency and quality
8. **Disconnection**: Clean up locks, record in SessionManager, enforce cooldown

### Important Implementation Notes

- **Thread Safety**: All networking operations use dedicated DispatchQueues with barriers for writes
- **Event Deduplication**: 10-second window prevents duplicate peer found/lost events
- **Connection Throttling**: 1-second minimum interval between service restarts
- **Message TTL**: Default 5 hops maximum to prevent network flooding
- **Queue Size**: Maximum 100 messages in priority queue
- **ACK Timeout**: 5 seconds with 3 retry attempts
- **Cache Expiration**: 5-minute message cache to prevent memory growth

### Background Execution Limitations

**⚠️ IMPORTANTE**: MultipeerConnectivity tiene limitaciones severas en segundo plano:
- **App Activa (Foreground)**: ✅ Todas las funciones operan normalmente
- **App en Background**: ⚠️ Muy limitado (~3-10 minutos, solo mantiene conexiones existentes)
- **App Suspendida**: ❌ Todas las conexiones se pierden

**Recomendaciones**:
- La app debe estar abierta para funcionalidad completa
- Considerar notificaciones locales para eventos importantes
- UIBackgroundModes puede extender tiempo brevemente pero no es confiable

---

## Comandos de Desarrollo

### Building & Testing
```bash
# Build para iOS Simulator
xcodebuild -scheme MeshRed -destination "platform=iOS Simulator,name=iPhone 17"

# Build para dispositivo físico
xcodebuild -scheme MeshRed -destination "platform=iOS,name=Any iOS Device"

# Clean build
xcodebuild clean -scheme MeshRed

# Run unit tests
xcodebuild test -scheme MeshRed -destination "platform=macOS"

# Run UI tests
xcodebuild test -scheme MeshRed -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:MeshRedUITests

# Run single test
xcodebuild test -scheme MeshRed -destination "platform=macOS" -only-testing:MeshRedTests/TestClassName/testMethodName
```

### Type Checking Swift Files
```bash
# Type check specific file
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc -typecheck MeshRed/ContentView.swift -I MeshRed/Models -I MeshRed/Services -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.0.sdk
```

### Testing Framework
Uses Swift Testing framework (`import Testing`) with `@Test` attribute instead of XCTest.

---

## Troubleshooting

### Peer Not Connecting
- Check conflict resolution: only lower peer ID should initiate
- Verify SessionManager cooldown hasn't blocked the peer
- Check ConnectionMutex for active lock
- Ensure Bluetooth and local network permissions granted

### Messages Not Relaying
- Verify TTL hasn't reached 0 (hopCount >= ttl)
- Check MessageCache for duplicate detection
- Confirm peer in routePath to prevent loops

### Memory or Performance Issues
- Monitor MessageQueue size (max 100)
- Check MessageCache expiration (5 minutes)
- Review PeerHealthMonitor stats for poor connections
- Use NetworkConfig modes: powerSaving mode reduces ping frequency

---

## Notas para Claude Code

Este proyecto extiende MeshRed hacia StadiumConnect Pro para el CSC 2025. La propuesta combina tecnología P2P existente con nuevas capacidades de localización UWB y detección de emergencias, todo enfocado en inclusión y accesibilidad para el Mundial FIFA 2026.

**Enfoque clave**: No es solo una app técnicamente impresionante, sino una solución que genuinamente mejora la experiencia de personas con discapacidades en eventos masivos.