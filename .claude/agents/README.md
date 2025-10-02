# StadiumConnect Pro - Claude Code Agents

Agentes especializados para el desarrollo de StadiumConnect Pro (CSC 2025).

## Agentes Disponibles

### 🎨 frontend
**Especialidad**: SwiftUI, UI/UX, diseño inclusivo

```swift
Task({
  subagent_type: "frontend",
  description: "Design dashboard UI",
  prompt: "Create the main stadium dashboard with geofencing visualization, peer list, and emergency button. Must support VoiceOver and Dynamic Type."
})
```

**Usa este agente para**:
- Diseñar e implementar vistas SwiftUI
- Crear componentes reutilizables
- Gestión de estado y navegación
- Integración de accesibilidad en UI
- Optimización de rendimiento visual

---

### 🌐 networking
**Especialidad**: Mesh P2P, UWB, geofencing

```swift
Task({
  subagent_type: "networking",
  description: "Implement UWB location",
  prompt: "Integrate NearbyInteraction for UWB peer localization. Exchange discovery tokens via mesh network and track distance/direction in real-time."
})
```

**Usa este agente para**:
- MultipeerConnectivity (mesh networking)
- NearbyInteraction (UWB localización)
- CoreLocation (geofencing)
- Message routing y priorización
- Optimización de red y batería

---

### ♿️ accessibility
**Especialidad**: VoiceOver, tecnologías asistivas, diseño universal

```swift
Task({
  subagent_type: "accessibility",
  description: "Audit SOS view accessibility",
  prompt: "Review SOSView for full VoiceOver support. Ensure emergency button is accessible via voice, touch, and haptics. Test with Accessibility Inspector."
})
```

**Usa este agente para**:
- Auditorías de accesibilidad
- Implementación de VoiceOver
- Dynamic Type y high contrast
- Haptic feedback y audio cues
- Testing con Accessibility Inspector

---

## Ejemplos de Uso

### Múltiples agentes en paralelo
```swift
// Investigar arquitectura completa
Task({ subagent_type: "frontend", prompt: "Analyze current view architecture" })
Task({ subagent_type: "networking", prompt: "Review mesh routing implementation" })
Task({ subagent_type: "accessibility", prompt: "Audit all views for VoiceOver" })
```

### Flujo de desarrollo típico

1. **Diseño**: `frontend` agente diseña la UI
2. **Networking**: `networking` agente implementa lógica de red
3. **Accesibilidad**: `accessibility` agente audita y mejora
4. **Iteración**: Repetir hasta cumplir estándares CSC 2025

---

## Contexto del Proyecto

**StadiumConnect Pro** evoluciona MeshRed hacia una solución integral para el Mundial FIFA 2026:

- **Mesh P2P**: Comunicación sin infraestructura
- **UWB**: Localización centimétrica indoor
- **Geofencing**: Zonas virtuales del estadio
- **Emergencias**: Sistema inteligente con validación humana
- **Inclusión**: Accesibilidad completa (categoría CSC 2025)

---

## Comandos Útiles

### Listar agentes disponibles
```bash
ls -la .claude/agents/
```

### Ver configuración de un agente
```bash
cat .claude/agents/frontend.json | jq .
```

### Testing con agentes
```swift
// Frontend: Crear test de UI
Task({
  subagent_type: "frontend",
  prompt: "Create SwiftUI preview for StadiumDashboardView with mock data"
})

// Networking: Test de mensaje routing
Task({
  subagent_type: "networking",
  prompt: "Write unit test for multi-hop message routing with 3 peers"
})
```

---

## Notas Importantes

- **Agentes son autónomos**: Reciben una tarea y la ejecutan completamente
- **Usa agentes para tareas complejas**: Multi-paso, investigación, refactoring
- **NO uses agentes para tareas simples**: Lectura de un archivo conocido (usa Read)
- **Paraleliza cuando sea posible**: Múltiples agentes en un solo mensaje

---

## CSC 2025 - Categoría Inclusiva

Los agentes están optimizados para la **categoría "App Inclusiva"** del hackathon:

- ✅ Accesibilidad nativa desde el diseño
- ✅ VoiceOver, Dynamic Type, high contrast
- ✅ Múltiples modalidades de interacción
- ✅ Testing con tecnologías asistivas
- ✅ Impacto social medible

**Objetivo**: App que genuinamente mejora la experiencia de personas con discapacidades en eventos masivos.
