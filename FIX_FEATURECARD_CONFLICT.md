# Corrección de Conflicto de Nombres - ContentView
## HomeFeatureCard vs FeatureCard

### 📅 Fecha
15 de octubre de 2025

---

## 🐛 Error Detectado

### Redeclaración Inválida de 'FeatureCard'

**Errores del Compilador:**
```
/Users/alexgrim/GitHub/LinkUp/MeshRed/ContentView.swift:804:16 
Invalid redeclaration of 'FeatureCard'

/Users/alexgrim/GitHub/LinkUp/MeshRed/ContentView.swift:689:32 
Extra arguments at positions #2, #5 in call

/Users/alexgrim/GitHub/LinkUp/MeshRed/ContentView.swift:691:99 
Missing argument for parameter 'iconColor' in call

/Users/alexgrim/GitHub/LinkUp/MeshRed/ContentView.swift:693:35 
Cannot convert value of type 'Bool' to expected argument type 'Color'
```

---

## 🔍 Análisis del Problema

### Componente Original (StadiumDashboardView.swift)
```swift
struct FeatureCard: View {
    let title: String
    let icon: String
    let iconColor: Color         // ← Requerido
    let backgroundColor: Color   // ← Requerido
    var isEmpty: Bool = false
    let action: () -> Void
}
```

**Ubicación:** `MeshRed/Views/StadiumDashboardView.swift:424`  
**Scope:** Público (sin `private`)  
**Uso:** Stadium Mode dashboard

### Componente en Conflicto (ContentView.swift)
```swift
// ❌ ANTES - Conflicto
private struct FeatureCard: View {
    let title: String
    let subtitle: String         // ← Nuevo parámetro
    let icon: String
    let isActive: Bool           // ← Nuevo parámetro
    let activeColor: Color       // ← Nuevo parámetro
    let action: () -> Void
}
```

**Ubicación:** `MeshRed/ContentView.swift:804`  
**Scope:** Privado  
**Uso:** Home dashboard

**Problema:**
- Mismo nombre, firmas diferentes
- Swift intenta usar la primera definición encontrada
- Los parámetros no coinciden → Errores de compilación

---

## ✅ Solución Aplicada

### Renombrar a HomeFeatureCard

```swift
// ✅ DESPUÉS - Sin conflicto
private struct HomeFeatureCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let isActive: Bool
    let activeColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            action()
        }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(isActive ? activeColor.opacity(0.15) : Color.gray.opacity(0.1))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: icon)
                            .font(.title3)
                            .foregroundColor(isActive ? activeColor : .secondary)
                    }
                    
                    Spacer()
                    
                    if isActive {
                        Circle()
                            .fill(activeColor)
                            .frame(width: 8, height: 8)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colorScheme == .dark ? Color.appBackgroundSecondary : Color(.systemBackground))
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 2)
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.2)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}
```

---

## 🔄 Referencias Actualizadas

### 1. Grupo Familiar
```swift
// ANTES: FeatureCard(...)
// DESPUÉS:
HomeFeatureCard(
    title: hasFamilyGroup ? "Tu Grupo" : "Grupo Familiar",
    subtitle: hasFamilyGroup ? "\(familyMemberCount) miembros" : "Crear grupo",
    icon: "person.3.fill",
    isActive: hasFamilyGroup,
    activeColor: .appAccent,
    action: onOpenFamilyGroup
)
```

### 2. LinkFence
```swift
HomeFeatureCard(
    title: "LinkFence",
    subtitle: hasActiveGeofence ? "Activo" : "Configurar",
    icon: "map.circle.fill",
    isActive: hasActiveGeofence,
    activeColor: .appPrimary,
    action: onOpenGeofenceMap
)
```

### 3. Ubicación
```swift
HomeFeatureCard(
    title: "Ubicación",
    subtitle: locationStatusText,
    icon: "location.circle.fill",
    isActive: locationStatusText == "Activa",
    activeColor: locationStatusColor,
    action: onRequestPermissions ?? {}
)
.disabled(onRequestPermissions == nil)
.opacity(onRequestPermissions == nil ? 0.6 : 1.0)
```

### 4. LinkMesh
```swift
HomeFeatureCard(
    title: "LinkMesh",
    subtitle: connectedPeers > 0 ? "En línea" : "Desconectado",
    icon: "network",
    isActive: connectedPeers > 0,
    activeColor: .green,
    action: {}
)
.disabled(true)
.opacity(0.6)
```

---

## 📊 Comparación de Componentes

| Característica | StadiumDashboardView.FeatureCard | ContentView.HomeFeatureCard |
|----------------|----------------------------------|------------------------------|
| Nombre | `FeatureCard` | `HomeFeatureCard` |
| Scope | Público | Privado |
| Título | ✅ | ✅ |
| Subtítulo | ❌ | ✅ |
| Icono | ✅ | ✅ |
| Color de icono | ✅ (requerido) | ❌ (calculado) |
| Color de fondo | ✅ (requerido) | ❌ (adaptativo) |
| Estado activo | ❌ | ✅ |
| Color activo | ❌ | ✅ |
| isEmpty flag | ✅ | ❌ |
| Animación press | ❌ | ✅ |
| Haptic feedback | ❌ | ✅ |
| Indicador activo | ❌ | ✅ (punto) |

---

## ✅ Resultado Final

### Cambios Realizados
1. ✅ Renombrado: `FeatureCard` → `HomeFeatureCard` (línea 804)
2. ✅ Actualizada referencia 1: Grupo Familiar (línea 689)
3. ✅ Actualizada referencia 2: LinkFence (línea 697)
4. ✅ Actualizada referencia 3: Ubicación (línea 709)
5. ✅ Actualizada referencia 4: LinkMesh (línea 721)

### Estado de Compilación
```
✅ 0 Errores
✅ 0 Warnings
✅ Build exitoso
```

### Archivos Modificados
- `MeshRed/ContentView.swift`
  - Líneas: 689, 697, 709, 721, 804

### Archivos Sin Modificar
- `MeshRed/Views/StadiumDashboardView.swift`
  - `FeatureCard` original intacto

---

## 📝 Lecciones Aprendidas

### Convención de Nombres
- **Componentes globales/reutilizables:** Nombres genéricos
- **Componentes específicos de vista:** Prefijo con nombre de vista
  - ✅ `HomeFeatureCard` - Para ContentView
  - ✅ `StadiumFeatureCard` - Para StadiumDashboardView (futuro)
  - ✅ `MessagingFeatureCard` - Para MessagingView (futuro)

### Scope Apropiado
- **`public` o sin modificador:** Solo si se usa en múltiples archivos
- **`private`:** Componentes internos de una sola vista
- **`fileprivate`:** Compartido solo dentro del mismo archivo

### Evitar Conflictos
1. Verificar nombres existentes antes de crear componentes
2. Usar nombres descriptivos y específicos
3. Preferir scope privado cuando sea posible

---

**Completado:** 15 de octubre de 2025  
**Errores Resueltos:** 4  
**Referencias Actualizadas:** 4  
**Componentes Renombrados:** 1  
**Build Status:** ✅ Exitoso
