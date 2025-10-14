# 🎨 Guía de Migración de Colores - Ejemplos Prácticos

Esta guía contiene ejemplos concretos de cómo migrar colores en diferentes componentes de la aplicación.

---

## 📋 Tabla de Contenidos

1. [Botones](#botones)
2. [Fondos](#fondos)
3. [Tarjetas y Cards](#tarjetas-y-cards)
4. [Iconos](#iconos)
5. [Badges y Estados](#badges-y-estados)
6. [Gradientes](#gradientes)
7. [Shadows](#shadows)
8. [Borders](#borders)

---

## 1. Botones

### Botón Principal

```swift
// ❌ ANTES
Button("Acción") {
    // acción
}
.padding()
.background(Mundial2026Colors.azul)
.foregroundColor(.white)
.cornerRadius(12)

// ✅ DESPUÉS
Button("Acción") {
    // acción
}
.padding()
.background(Color.appPrimary)  // Violeta moderno
.foregroundColor(.white)
.cornerRadius(12)
```

### Botón Secundario

```swift
// ❌ ANTES
Button("Cancelar") {
    // acción
}
.padding()
.background(Color.blue.opacity(0.2))
.foregroundColor(Color.blue)
.cornerRadius(12)

// ✅ DESPUÉS
Button("Cancelar") {
    // acción
}
.padding()
.background(Color.appSecondary.opacity(0.2))  // Cyan moderno
.foregroundColor(Color.appSecondary)
.cornerRadius(12)
```

### Botón de Acción Rápida

```swift
// ❌ ANTES
AccessibleQuickActionCard(
    title: "Mensajes",
    icon: "message.fill",
    iconColor: Mundial2026Colors.verde,
    backgroundColor: Color(.secondarySystemBackground),
    action: { }
)

// ✅ DESPUÉS
AccessibleQuickActionCard(
    title: "Mensajes",
    icon: "message.fill",
    iconColor: Color.appAccent,  // Teal moderno
    backgroundColor: Color.appBackgroundSecondary,  // Fondo oscuro
    action: { }
)
```

---

## 2. Fondos

### Fondo Principal de Pantalla

```swift
// ❌ ANTES
ZStack {
    Color(.systemBackground)
        .ignoresSafeArea()

    // contenido
}

// ✅ DESPUÉS
ZStack {
    Color.appBackgroundDark
        .ignoresSafeArea()

    // contenido
}
```

### Fondo de ScrollView

```swift
// ❌ ANTES
ScrollView {
    // contenido
}
.background(Color(.systemBackground))

// ✅ DESPUÉS
ScrollView {
    // contenido
}
.background(Color.appBackgroundDark)
```

### Fondo de Navegación

```swift
// ❌ ANTES
NavigationView {
    // contenido
}
.background(Color.white)

// ✅ DESPUÉS
NavigationView {
    // contenido
}
.background(Color.appBackgroundDark)
```

---

## 3. Tarjetas y Cards

### Card Básica

```swift
// ❌ ANTES
VStack {
    Text("Título")
    Text("Contenido")
}
.padding()
.background(Color(.secondarySystemBackground))
.cornerRadius(16)

// ✅ DESPUÉS
VStack {
    Text("Título")
    Text("Contenido")
}
.padding()
.background(Color.appBackgroundSecondary)
.cornerRadius(16)
```

### Card con Borde

```swift
// ❌ ANTES
VStack {
    // contenido
}
.padding()
.background(Color.white)
.overlay(
    RoundedRectangle(cornerRadius: 16)
        .stroke(Color.blue, lineWidth: 2)
)

// ✅ DESPUÉS
VStack {
    // contenido
}
.padding()
.background(Color.appBackgroundSecondary)
.overlay(
    RoundedRectangle(cornerRadius: 16)
        .stroke(Color.appPrimary, lineWidth: 2)
)
```

### Card de Estado

```swift
// ❌ ANTES
HStack {
    Image(systemName: "checkmark.circle.fill")
        .foregroundColor(Color.green)
    Text("Conectado")
}
.padding()
.background(Color.green.opacity(0.1))
.cornerRadius(12)

// ✅ DESPUÉS
HStack {
    Image(systemName: "checkmark.circle.fill")
        .foregroundColor(Color.appAccent)
    Text("Conectado")
}
.padding()
.background(Color.appAccent.opacity(0.1))
.cornerRadius(12)
```

---

## 4. Iconos

### Icono Principal

```swift
// ❌ ANTES
Image(systemName: "house.fill")
    .font(.largeTitle)
    .foregroundColor(Mundial2026Colors.azul)

// ✅ DESPUÉS
Image(systemName: "house.fill")
    .font(.largeTitle)
    .foregroundColor(Color.appPrimary)
```

### Icono con Fondo

```swift
// ❌ ANTES
Image(systemName: "message.fill")
    .padding()
    .background(Color.blue.opacity(0.2))
    .foregroundColor(Color.blue)
    .clipShape(Circle())

// ✅ DESPUÉS
Image(systemName: "message.fill")
    .padding()
    .background(Color.appSecondary.opacity(0.2))
    .foregroundColor(Color.appSecondary)
    .clipShape(Circle())
```

### Icono de Estado

```swift
// ❌ ANTES
Image(systemName: "checkmark.circle.fill")
    .foregroundColor(Color.green)

// ✅ DESPUÉS
Image(systemName: "checkmark.circle.fill")
    .foregroundColor(Color.appAccent)
```

---

## 5. Badges y Estados

### Badge de Notificación

```swift
// ❌ ANTES
Text("3")
    .font(.caption2)
    .fontWeight(.bold)
    .foregroundColor(.white)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(Color.red)
    .clipShape(Capsule())

// ✅ DESPUÉS
Text("3")
    .font(.caption2)
    .fontWeight(.bold)
    .foregroundColor(.white)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(Mundial2026Colors.rojo)  // Mantener rojo para alertas
    .clipShape(Capsule())
```

### Badge de Estado Activo

```swift
// ❌ ANTES
Circle()
    .fill(Color.green)
    .frame(width: 12, height: 12)

// ✅ DESPUÉS
Circle()
    .fill(Color.appAccent)
    .frame(width: 12, height: 12)
```

### Badge de Estado Conectado

```swift
// ❌ ANTES
HStack {
    Circle()
        .fill(Color.green)
        .frame(width: 8, height: 8)
    Text("Conectado")
        .font(.caption)
        .foregroundColor(Color.green)
}

// ✅ DESPUÉS
HStack {
    Circle()
        .fill(Color.appAccent)
        .frame(width: 8, height: 8)
    Text("Conectado")
        .font(.caption)
        .foregroundColor(Color.appAccent)
}
```

---

## 6. Gradientes

### Gradiente de Fondo

```swift
// ❌ ANTES
LinearGradient(
    colors: [
        Mundial2026Colors.azul,
        Mundial2026Colors.verde
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

// ✅ DESPUÉS
LinearGradient(
    colors: [
        Color.appPrimary,
        Color.appSecondary
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)
```

### Gradiente de Overlay

```swift
// ❌ ANTES
.overlay(
    LinearGradient(
        colors: [
            Color.blue.opacity(0.8),
            Color.blue.opacity(0.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
)

// ✅ DESPUÉS
.overlay(
    LinearGradient(
        colors: [
            Color.appPrimary.opacity(0.8),
            Color.appPrimary.opacity(0.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
)
```

### Gradiente Radial

```swift
// ❌ ANTES
RadialGradient(
    colors: [
        Color.green.opacity(0.8),
        Color.green.opacity(0.3),
        Color.green.opacity(0.0)
    ],
    center: .center,
    startRadius: 0,
    endRadius: 50
)

// ✅ DESPUÉS
RadialGradient(
    colors: [
        Color.appAccent.opacity(0.8),
        Color.appAccent.opacity(0.3),
        Color.appAccent.opacity(0.0)
    ],
    center: .center,
    startRadius: 0,
    endRadius: 50
)
```

---

## 7. Shadows

### Shadow Básico

```swift
// ❌ ANTES
.shadow(
    color: Color.black.opacity(0.2),
    radius: 8,
    x: 0,
    y: 4
)

// ✅ DESPUÉS - Mantener igual o usar color de acento
.shadow(
    color: Color.appPrimary.opacity(0.2),
    radius: 8,
    x: 0,
    y: 4
)
```

### Shadow con Color de Marca

```swift
// ❌ ANTES
.shadow(
    color: Mundial2026Colors.verde.opacity(0.3),
    radius: 12,
    x: 0,
    y: 8
)

// ✅ DESPUÉS
.shadow(
    color: Color.appAccent.opacity(0.3),
    radius: 12,
    x: 0,
    y: 8
)
```

---

## 8. Borders

### Border Simple

```swift
// ❌ ANTES
.overlay(
    RoundedRectangle(cornerRadius: 12)
        .stroke(Color.blue, lineWidth: 2)
)

// ✅ DESPUÉS
.overlay(
    RoundedRectangle(cornerRadius: 12)
        .stroke(Color.appPrimary, lineWidth: 2)
)
```

### Border con Estado

```swift
// ❌ ANTES
.overlay(
    RoundedRectangle(cornerRadius: 12)
        .stroke(isActive ? Color.green : Color.gray, lineWidth: 2)
)

// ✅ DESPUÉS
.overlay(
    RoundedRectangle(cornerRadius: 12)
        .stroke(isActive ? Color.appAccent : Color.gray, lineWidth: 2)
)
```

---

## 🔄 Componentes Completos - Antes y Después

### NetworkStatusCard

```swift
// ❌ ANTES
struct NetworkStatusCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi")
                .font(.largeTitle)
                .foregroundColor(Mundial2026Colors.azul)

            Text("Conectado")
                .font(.headline)
                .foregroundColor(.primary)

            Text("12 dispositivos")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: Mundial2026Colors.azul.opacity(0.2), radius: 8)
    }
}

// ✅ DESPUÉS
struct NetworkStatusCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi")
                .font(.largeTitle)
                .foregroundColor(Color.appPrimary)  // Violeta moderno

            Text("Conectado")
                .font(.headline)
                .foregroundColor(.white)

            Text("12 dispositivos")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding()
        .background(Color.appBackgroundSecondary)  // Fondo oscuro
        .cornerRadius(16)
        .shadow(color: Color.appPrimary.opacity(0.2), radius: 8)
    }
}
```

### QuickActionButton

```swift
// ❌ ANTES
struct QuickActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundColor(Mundial2026Colors.verde)

                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .frame(width: 80, height: 80)
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(12)
        }
    }
}

// ✅ DESPUÉS
struct QuickActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundColor(Color.appAccent)  // Teal moderno

                Text(title)
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .frame(width: 80, height: 80)
            .background(Color.appBackgroundSecondary)  // Fondo oscuro
            .cornerRadius(12)
        }
    }
}
```

### StatusBadge

```swift
// ❌ ANTES
struct StatusBadge: View {
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(isConnected ? "Conectado" : "Desconectado")
                .font(.caption)
                .foregroundColor(isConnected ? Color.green : Color.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            (isConnected ? Color.green : Color.red).opacity(0.15)
        )
        .cornerRadius(12)
    }
}

// ✅ DESPUÉS
struct StatusBadge: View {
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isConnected ? Color.appAccent : Mundial2026Colors.rojo)
                .frame(width: 8, height: 8)

            Text(isConnected ? "Conectado" : "Desconectado")
                .font(.caption)
                .foregroundColor(isConnected ? Color.appAccent : Mundial2026Colors.rojo)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            (isConnected ? Color.appAccent : Mundial2026Colors.rojo).opacity(0.15)
        )
        .cornerRadius(12)
    }
}
```

---

## 🎯 Casos Especiales

### Colores de Emergencia (NO cambiar)

```swift
// ✅ MANTENER ROJO ORIGINAL para emergencias
Button("SOS") {
    // emergencia
}
.background(Mundial2026Colors.rojo)  // NO cambiar

// ✅ MANTENER para alertas críticas
.foregroundColor(Mundial2026Colors.rojo)  // NO cambiar
```

### Colores de Sistema Específicos

```swift
// ⚠️ Evaluar caso por caso

// Colores de estado del sistema (pueden mantenerse)
.foregroundColor(.red)    // Errores críticos
.foregroundColor(.orange) // Advertencias

// Pero considera usar:
.foregroundColor(Mundial2026Colors.rojo)   // Para errores de la app
.foregroundColor(Color.appSecondary)       // Para advertencias generales
```

### MapKit Colors (Especial)

```swift
// ❌ ANTES
renderer.fillColor = UIColor.systemBlue.withAlphaComponent(0.15)
renderer.strokeColor = UIColor.systemBlue

// ✅ DESPUÉS
renderer.fillColor = UIColor.appPrimary.withAlphaComponent(0.15)
renderer.strokeColor = UIColor.appPrimary
```

---

## 📝 Checklist por Archivo

### Para cada archivo que migres:

- [ ] Buscar `Mundial2026Colors`
- [ ] Buscar `Color.blue`, `Color.green`, etc.
- [ ] Buscar `Color(.systemBackground)`
- [ ] Buscar `UIColor.system*`
- [ ] Reemplazar con nuevos colores
- [ ] Probar en simulador
- [ ] Verificar contraste
- [ ] Commit cambios

---

## 🚀 Script de Migración Automática (Ejemplo)

```bash
#!/bin/bash

# Script para ayudar con la migración (usar con cuidado)
# Reemplaza Mundial2026Colors.azul con Color.appPrimary

FILE="$1"

# Backup
cp "$FILE" "${FILE}.backup"

# Reemplazos
sed -i '' 's/Mundial2026Colors\.azul/Color.appPrimary/g' "$FILE"
sed -i '' 's/Mundial2026Colors\.verde/Color.appAccent/g' "$FILE"
sed -i '' 's/Color(\.systemBackground)/Color.appBackgroundDark/g' "$FILE"
sed -i '' 's/Color(\.secondarySystemBackground)/Color.appBackgroundSecondary/g' "$FILE"

echo "✅ Migración completada para $FILE"
echo "⚠️  Revisa los cambios manualmente antes de commit"
```

---

## 🎉 Resultado Final

Después de migrar todos los componentes, tendrás:

1. ✅ **Diseño consistente** en toda la app
2. ✅ **Colores modernos** y vibrantes
3. ✅ **Fácil mantenimiento**
4. ✅ **Mejor accesibilidad**
5. ✅ **Dark Mode** optimizado
6. ✅ **Código más limpio** y organizado

---

**¡Feliz migración! 🎨✨**

Si tienes dudas, consulta `COLOR_SYSTEM_COMPLETE.md` para más detalles.
