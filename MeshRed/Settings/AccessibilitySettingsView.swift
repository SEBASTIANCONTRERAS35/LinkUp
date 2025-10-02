//
//  AccessibilitySettingsView.swift
//  MeshRed - StadiumConnect Pro
//
//  Complete Accessibility Settings Screen for CSC 2025
//  Ultra-accessible fullscreen settings with presets and testing
//

import SwiftUI

struct AccessibilitySettingsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var settings = AccessibilitySettingsManager.shared

    @State private var showingResetAlert = false
    @State private var showingPresetPicker = false
    @State private var selectedPreset: AccessibilitySettingsManager.AccessibilityPreset?
    @State private var showTestingPanel = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Accessibility Score Card
                    accessibilityScoreCard

                    // Quick Presets
                    quickPresetsSection

                    // Settings Sections
                    voiceOverSection
                    visualSection
                    hapticSection
                    motionSection
                    emergencySection
                    networkSection
                    connectionSection
                    locationSection
                    themeSection
                    privacySection
                    performanceSection

                    // Testing Panel
                    testingPanelSection

                    // Reset Button
                    resetButton

                    // Bottom spacing
                    Color.clear.frame(height: 40)
                }
                .padding(.top, 20)
            }
            .background(ThemeColors.background.ignoresSafeArea())
            .navigationTitle("Accesibilidad")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Listo") {
                        dismiss()
                    }
                    .accessibilityLabel("Cerrar configuración")
                }
            }
            .alert("Restablecer Configuración", isPresented: $showingResetAlert) {
                Button("Cancelar", role: .cancel) { }
                Button("Restablecer", role: .destructive) {
                    settings.resetToDefaults()
                    announceChange("Configuración restablecida a valores recomendados")
                }
            } message: {
                Text("¿Estás seguro de que quieres restablecer toda la configuración de accesibilidad a los valores recomendados?")
            }
        }
    }

    // MARK: - Accessibility Score Card

    private var accessibilityScoreCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                // Score Circle
                ZStack {
                    Circle()
                        .stroke(ThemeColors.textTertiary.opacity(0.3), lineWidth: 8)

                    Circle()
                        .trim(from: 0, to: CGFloat(settings.accessibilityScore) / 100)
                        .stroke(scoreColor, lineWidth: 8)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 4) {
                        Text("\(settings.accessibilityScore)")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(scoreColor)

                        Text("%")
                            .font(.caption)
                            .foregroundColor(ThemeColors.textSecondary)
                    }
                }
                .frame(width: 100, height: 100)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Puntuación de accesibilidad: \(settings.accessibilityScore) por ciento")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Tu Configuración")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(ThemeColors.textPrimary)

                    Text(scoreMessage)
                        .font(.subheadline)
                        .foregroundColor(ThemeColors.textSecondary)

                    if let suggestion = scoreSuggestion {
                        HStack(spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption)
                                .foregroundColor(ThemeColors.warning)

                            Text(suggestion)
                                .font(.caption)
                                .foregroundColor(ThemeColors.warning)
                        }
                    }
                }

                Spacer()
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(ThemeColors.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(scoreColor.opacity(0.3), lineWidth: 2)
            )
        }
        .padding(.horizontal, 20)
    }

    private var scoreColor: Color {
        let score = settings.accessibilityScore
        if score >= 80 { return ThemeColors.success }
        if score >= 50 { return ThemeColors.warning }
        return ThemeColors.error
    }

    private var scoreMessage: String {
        let score = settings.accessibilityScore
        if score >= 80 { return "¡Excelente configuración!" }
        if score >= 50 { return "Buena configuración" }
        return "Considera activar más funciones"
    }

    private var scoreSuggestion: String? {
        if !settings.hapticsEnabled {
            return "💡 Activa Haptic Feedback para mejor experiencia táctil"
        }
        if !settings.announceNetworkChanges {
            return "💡 Activa anuncios de red para mayor información"
        }
        if settings.buttonSizeMultiplier < 1.2 {
            return "💡 Aumenta el tamaño de botones para facilitar el toque"
        }
        return nil
    }

    // MARK: - Quick Presets

    private var quickPresetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configuraciones Rápidas")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(ThemeColors.textPrimary)
                .padding(.horizontal, 20)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    PresetCard(
                        icon: "person.crop.circle",
                        title: "Adulto Mayor",
                        description: "Texto grande + VoiceOver",
                        color: ThemeColors.primaryBlue
                    ) {
                        applyPreset(.adultoMayor)
                    }

                    PresetCard(
                        icon: "eye.slash",
                        title: "Discapacidad Visual",
                        description: "VoiceOver máximo",
                        color: ThemeColors.primaryGreen
                    ) {
                        applyPreset(.discapacidadVisual)
                    }

                    PresetCard(
                        icon: "ear.badge.waveform",
                        title: "Discapacidad Auditiva",
                        description: "Haptics + Visual",
                        color: ThemeColors.warning
                    ) {
                        applyPreset(.discapacidadAuditiva)
                    }

                    PresetCard(
                        icon: "brain.head.profile",
                        title: "Discapacidad Cognitiva",
                        description: "Simple + Sin movimiento",
                        color: ThemeColors.info
                    ) {
                        applyPreset(.discapacidadCognitiva)
                    }

                    PresetCard(
                        icon: "bolt.fill",
                        title: "Rendimiento",
                        description: "Batería optimizada",
                        color: ThemeColors.error
                    ) {
                        applyPreset(.maximoRendimiento)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - VoiceOver Section

    private var voiceOverSection: some View {
        SettingsSection(
            icon: "speaker.wave.3",
            title: "VoiceOver y Audio",
            description: "Configuración de voz y sonidos",
            iconColor: ThemeColors.primaryBlue
        ) {
            AccessibleSettingToggle(
                title: "Mostrar hints de VoiceOver",
                description: "Información adicional al usar VoiceOver",
                icon: "info.circle",
                isOn: $settings.enableVoiceOverHints
            )

            AccessibleSettingSlider(
                title: "Velocidad de lectura",
                description: "Velocidad de VoiceOver",
                icon: "speedometer",
                value: $settings.voiceOverSpeakingRate,
                range: 0.5...2.0,
                step: 0.1,
                valueFormatter: { "\(Int($0 * 100))%" }
            )

            AccessibleSettingToggle(
                title: "Anunciar cambios de red",
                description: "VoiceOver anuncia conexiones/desconexiones",
                icon: "antenna.radiowaves.left.and.right",
                isOn: $settings.announceNetworkChanges
            )

            AccessibleSettingToggle(
                title: "Anunciar zonas geográficas",
                description: "Aviso al entrar/salir de zonas",
                icon: "location.circle",
                isOn: $settings.announceGeofenceTransitions
            )

            AccessibleSettingSlider(
                title: "Volumen de efectos de sonido",
                description: "Volumen de sonidos de la app",
                icon: "speaker.fill",
                value: $settings.soundEffectsVolume,
                range: 0.0...1.0,
                step: 0.1,
                valueFormatter: { "\(Int($0 * 100))%" }
            )
        }
    }

    // MARK: - Visual Section

    private var visualSection: some View {
        SettingsSection(
            icon: "textformat.size",
            title: "Visual y Texto",
            description: "Configuración de tamaño y contraste",
            iconColor: ThemeColors.primaryGreen
        ) {
            AccessibleSettingSlider(
                title: "Multiplicador de botones",
                description: "Tamaño de todos los botones",
                icon: "circle.fill",
                value: $settings.buttonSizeMultiplier,
                range: 0.8...1.5,
                step: 0.1,
                valueFormatter: { "\(Int($0 * 100))%" }
            )

            AccessibleSettingToggle(
                title: "Alto contraste",
                description: "Aumenta el contraste de colores",
                icon: "circle.lefthalf.filled",
                isOn: $settings.enableHighContrast
            )

            AccessibleSettingToggle(
                title: "Texto en negrita",
                description: "Hace el texto más grueso y legible",
                icon: "bold",
                isOn: $settings.preferBoldText
            )

            AccessibleSettingToggle(
                title: "Reducir transparencia",
                description: "Elimina efectos de transparencia",
                icon: "square.on.square",
                isOn: $settings.reduceTransparency
            )

            AccessibleSettingToggle(
                title: "Mostrar etiquetas en botones",
                description: "Texto adicional en iconos",
                icon: "tag",
                isOn: $settings.showButtonLabels
            )
        }
    }

    // MARK: - Haptic Section

    private var hapticSection: some View {
        SettingsSection(
            icon: "hand.point.up.braille",
            title: "Retroalimentación Háptica",
            description: "Vibraciones táctiles",
            iconColor: ThemeColors.warning
        ) {
            AccessibleSettingToggle(
                title: "Activar haptics",
                description: "Vibraciones al interactuar con la app",
                icon: "iphone.radiowaves.left.and.right",
                isOn: $settings.hapticsEnabled
            )

            if settings.hapticsEnabled {
                AccessibleSettingPicker(
                    title: "Intensidad de vibración",
                    description: nil,
                    icon: "waveform",
                    selection: $settings.hapticIntensity,
                    options: ["light", "medium", "strong"],
                    displayNames: ["light": "Suave", "medium": "Media", "strong": "Fuerte"]
                )

                AccessibleSettingToggle(
                    title: "Vibrar en cambios de conexión",
                    description: "Al conectar/desconectar peers",
                    icon: "person.2",
                    isOn: $settings.hapticOnConnectionChanges
                )

                AccessibleSettingToggle(
                    title: "Vibrar en interacciones",
                    description: "Al tocar botones y controles",
                    icon: "hand.tap",
                    isOn: $settings.hapticOnUIInteractions
                )

                AccessibleSettingToggle(
                    title: "Vibrar en transiciones de zona",
                    description: "Al entrar/salir de zonas geográficas",
                    icon: "mappin.circle",
                    isOn: $settings.hapticOnGeofenceTransitions
                )
            }
        }
    }

    // MARK: - Motion Section

    private var motionSection: some View {
        SettingsSection(
            icon: "figure.walk.motion",
            title: "Movimiento y Animaciones",
            description: "Control de efectos de movimiento",
            iconColor: ThemeColors.info
        ) {
            AccessibleSettingPicker(
                title: "Reducir movimiento",
                description: "Nivel de reducción de animaciones",
                icon: "motion.pause",
                selection: $settings.reduceMotionLevel,
                options: ["none", "some", "all"],
                displayNames: ["none": "Ninguno", "some": "Algunas", "all": "Todas"]
            )

            AccessibleSettingSlider(
                title: "Velocidad de animaciones",
                description: "Multiplicador de velocidad",
                icon: "timer",
                value: $settings.animationSpeedMultiplier,
                range: 0.5...2.0,
                step: 0.1,
                valueFormatter: { "\(Int($0 * 100))%" }
            )

            AccessibleSettingToggle(
                title: "Solo transiciones cruzadas",
                description: "Usa solo fade in/out",
                icon: "arrow.left.arrow.right",
                isOn: $settings.crossfadeOnlyTransitions
            )

            AccessibleSettingToggle(
                title: "Desactivar pulsaciones",
                description: "Elimina animaciones pulsantes",
                icon: "circle.dashed",
                isOn: $settings.disablePulsingAnimations
            )
        }
    }

    // MARK: - Emergency Section

    private var emergencySection: some View {
        SettingsSection(
            icon: "exclamationmark.triangle.fill",
            title: "Configuración de Emergencias",
            description: "Opciones de SOS",
            iconColor: ThemeColors.emergency
        ) {
            AccessibleSettingToggle(
                title: "Requerir confirmación",
                description: "Confirmación antes de enviar SOS",
                icon: "checkmark.shield",
                isOn: $settings.requireSOSConfirmation
            )

            AccessibleSettingPicker(
                title: "Duración de cuenta regresiva",
                description: "Segundos antes de enviar SOS",
                icon: "timer",
                selection: Binding(
                    get: { String(settings.sosCountdownDuration) },
                    set: { settings.sosCountdownDuration = Int($0) ?? 5 }
                ),
                options: ["3", "5", "10"],
                displayNames: ["3": "3 seg", "5": "5 seg", "10": "10 seg"]
            )

            AccessibleSettingToggle(
                title: "Notificar a familia automáticamente",
                description: "Envía SOS a grupo familiar",
                icon: "person.3",
                isOn: $settings.autoNotifyFamilyOnSOS
            )

            AccessibleSettingToggle(
                title: "Vibrar durante cuenta regresiva",
                description: "Feedback táctil antes de enviar",
                icon: "iphone.radiowaves.left.and.right",
                isOn: $settings.vibrateDuringSOSCountdown
            )
        }
    }

    // MARK: - Network Section

    private var networkSection: some View {
        SettingsSection(
            icon: "network",
            title: "Anuncios de Red",
            description: "Notificaciones de conexión",
            iconColor: ThemeColors.connected
        ) {
            AccessibleSettingToggle(
                title: "Anunciar conexiones",
                description: "Aviso al conectar/desconectar peers",
                icon: "link",
                isOn: $settings.announceConnectionChanges
            )

            AccessibleSettingToggle(
                title: "Efectos de sonido de conexión",
                description: "Sonido al conectar peers",
                icon: "speaker.wave.2",
                isOn: $settings.peerConnectionSoundEffects
            )

            AccessibleSettingPicker(
                title: "Nivel de detalle",
                description: "Cantidad de información en anuncios",
                icon: "list.bullet",
                selection: $settings.networkStatusDetailLevel,
                options: ["brief", "medium", "detailed"],
                displayNames: ["brief": "Breve", "medium": "Medio", "detailed": "Detallado"]
            )
        }
    }

    // MARK: - Connection Section

    private var connectionSection: some View {
        SettingsSection(
            icon: "antenna.radiowaves.left.and.right",
            title: "Gestión de Conexiones",
            description: "Administrar conexiones mesh",
            iconColor: ThemeColors.primaryBlue
        ) {
            // Connection stats
            ConnectionStatsRow()

            // Clear all connections button
            Button {
                clearAllConnections()
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                        .foregroundColor(.white)
                    Text("Limpiar Todas las Conexiones")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding()
                .background(ThemeColors.error)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .accessibilityLabel("Limpiar todas las conexiones")
            .accessibilityHint("Desconecta de todos los peers y reinicia el sistema de red")

            // Restart network services button
            Button {
                restartNetworkServices()
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(ThemeColors.primaryBlue)
                    Text("Reiniciar Servicios de Red")
                        .fontWeight(.medium)
                    Spacer()
                }
                .padding()
                .background(ThemeColors.cardBackground)
                .foregroundColor(ThemeColors.textPrimary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(ThemeColors.primaryBlue, lineWidth: 2)
                )
            }
            .accessibilityLabel("Reiniciar servicios de red")
            .accessibilityHint("Reinicia advertiser y browser sin desconectar peers")
        }
    }

    // MARK: - Location Section

    private var locationSection: some View {
        SettingsSection(
            icon: "location.fill",
            title: "Ubicación y Navegación",
            description: "Configuración de GPS y zonas",
            iconColor: ThemeColors.primaryGreen
        ) {
            AccessibleSettingToggle(
                title: "Anunciar cambios de zona",
                description: "Aviso al entrar/salir de zonas",
                icon: "mappin.and.ellipse",
                isOn: $settings.announceZoneTransitions
            )

            AccessibleSettingPicker(
                title: "Unidad de distancia",
                description: "Metros o pies",
                icon: "ruler",
                selection: $settings.distanceUnit,
                options: ["meters", "feet"],
                displayNames: ["meters": "Metros", "feet": "Pies"]
            )

            AccessibleSettingToggle(
                title: "Guía de voz para navegación",
                description: "Instrucciones habladas",
                icon: "figure.walk",
                isOn: $settings.enableNavigationVoiceGuidance
            )

            AccessibleSettingToggle(
                title: "Alertas de proximidad",
                description: "Aviso al acercarse a objetivos",
                icon: "bell.badge",
                isOn: $settings.enableProximityAlerts
            )
        }
    }

    // MARK: - Theme Section

    private var themeSection: some View {
        SettingsSection(
            icon: "paintbrush.fill",
            title: "Tema y Apariencia",
            description: "Colores e iconos",
            iconColor: ThemeColors.primaryRed
        ) {
            AccessibleSettingPicker(
                title: "Esquema de color",
                description: "Tema claro u oscuro",
                icon: "moon.fill",
                selection: $settings.preferredColorScheme,
                options: ["system", "light", "dark"],
                displayNames: ["system": "Sistema", "light": "Claro", "dark": "Oscuro"]
            )

            AccessibleSettingPicker(
                title: "Color principal",
                description: "Tema de color de la app",
                icon: "paintpalette",
                selection: $settings.primaryColorTheme,
                options: ["mexico", "usa", "canada"],
                displayNames: ["mexico": "México 🇲🇽", "usa": "USA 🇺🇸", "canada": "Canadá 🇨🇦"]
            )

            AccessibleSettingToggle(
                title: "Activar degradados",
                description: "Fondos con gradiente de color",
                icon: "gradient",
                isOn: $settings.enableGradients
            )
        }
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        SettingsSection(
            icon: "lock.shield",
            title: "Privacidad",
            description: "Control de datos personales",
            iconColor: ThemeColors.textSecondary
        ) {
            AccessibleSettingToggle(
                title: "Compartir ubicación con peers",
                description: "Otros usuarios pueden ver tu ubicación",
                icon: "location.fill.viewfinder",
                isOn: $settings.shareLocationWithPeers
            )

            AccessibleSettingToggle(
                title: "Modo anónimo",
                description: "Oculta tu nombre de dispositivo",
                icon: "theatermasks",
                isOn: $settings.anonymousMode
            )
        }
    }

    // MARK: - Performance Section

    private var performanceSection: some View {
        SettingsSection(
            icon: "bolt.fill",
            title: "Rendimiento",
            description: "Optimización de batería",
            iconColor: ThemeColors.warning
        ) {
            AccessibleSettingToggle(
                title: "Modo ahorro de batería",
                description: "Reduce consumo de energía",
                icon: "battery.25",
                isOn: $settings.batterySaverMode
            )

            AccessibleSettingToggle(
                title: "Reducir actividad en segundo plano",
                description: "Menos actualizaciones automáticas",
                icon: "moon.zzz",
                isOn: $settings.reduceBackgroundActivity
            )

            AccessibleSettingPicker(
                title: "Tamaño de caché de mensajes",
                description: "Cantidad de mensajes guardados",
                icon: "tray.full",
                selection: Binding(
                    get: { String(settings.messageCacheSize) },
                    set: { settings.messageCacheSize = Int($0) ?? 100 }
                ),
                options: ["50", "100", "200"],
                displayNames: ["50": "50 msg", "100": "100 msg", "200": "200 msg"]
            )
        }
    }

    // MARK: - Testing Panel

    private var testingPanelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Panel de Pruebas")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(ThemeColors.textPrimary)
                .padding(.horizontal, 20)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 12) {
                Button {
                    testVoiceOver()
                } label: {
                    HStack {
                        Image(systemName: "speaker.wave.3")
                        Text("Probar VoiceOver")
                        Spacer()
                        Image(systemName: "play.fill")
                    }
                    .padding()
                    .background(ThemeColors.cardBackground)
                    .cornerRadius(12)
                }
                .accessibilityLabel("Probar VoiceOver")
                .accessibilityHint("Reproduce un mensaje de prueba con tu configuración actual")

                Button {
                    testHaptics()
                } label: {
                    HStack {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                        Text("Probar Vibración")
                        Spacer()
                        Image(systemName: "hand.tap")
                    }
                    .padding()
                    .background(ThemeColors.cardBackground)
                    .cornerRadius(12)
                }
                .accessibilityLabel("Probar vibración")
                .accessibilityHint("Siente la vibración con tu configuración actual")

                Button {
                    testTextSize()
                } label: {
                    HStack {
                        Image(systemName: "textformat.size")
                        Text("Probar Tamaño de Texto")
                        Spacer()
                        Image(systemName: "eye")
                    }
                    .padding()
                    .background(ThemeColors.cardBackground)
                    .cornerRadius(12)
                }
                .accessibilityLabel("Probar tamaño de texto")
                .accessibilityHint("Ver muestra de texto con tu configuración actual")
            }
            .buttonStyle(.plain)
            .foregroundColor(ThemeColors.textPrimary)
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Reset Button

    private var resetButton: some View {
        Button {
            showingResetAlert = true
        } label: {
            HStack {
                Image(systemName: "arrow.counterclockwise")
                Text("Restablecer a Valores Recomendados")
            }
            .font(.body)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(ThemeColors.error)
            .cornerRadius(12)
        }
        .padding(.horizontal, 20)
        .accessibilityLabel("Restablecer configuración")
        .accessibilityHint("Vuelve a los valores recomendados de accesibilidad")
    }

    // MARK: - Helper Methods

    private func applyPreset(_ preset: AccessibilitySettingsManager.AccessibilityPreset) {
        settings.applyPreset(preset)

        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif

        let presetName = presetDisplayName(preset)
        announceChange("Preset \(presetName) aplicado")
    }

    private func presetDisplayName(_ preset: AccessibilitySettingsManager.AccessibilityPreset) -> String {
        switch preset {
        case .adultoMayor: return "Adulto Mayor"
        case .discapacidadVisual: return "Discapacidad Visual"
        case .discapacidadAuditiva: return "Discapacidad Auditiva"
        case .discapacidadCognitiva: return "Discapacidad Cognitiva"
        case .maximoRendimiento: return "Máximo Rendimiento"
        case .recomendado: return "Recomendado"
        }
    }

    private func testVoiceOver() {
        let message = "Esta es una prueba de VoiceOver. Tu velocidad de lectura está configurada al \(Int(settings.voiceOverSpeakingRate * 100)) por ciento."
        announceChange(message)
    }

    private func testHaptics() {
        #if os(iOS)
        switch settings.hapticIntensity {
        case "light":
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        case "strong":
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
        default:
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
        #endif

        announceChange("Vibración de intensidad \(settings.hapticIntensity)")
    }

    private func testTextSize() {
        announceChange("Tu multiplicador de botones está en \(Int(settings.buttonSizeMultiplier * 100)) por ciento")
    }

    private func announceChange(_ message: String) {
        #if os(iOS)
        UIAccessibility.post(notification: .announcement, argument: message)
        #endif
    }

    private func clearAllConnections() {
        // Get NetworkManager from environment
        // We'll need to access it through a proper way
        announceChange("Limpiando todas las conexiones")

        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        #endif

        // This will be handled by NetworkManager
        NotificationCenter.default.post(name: NSNotification.Name("ClearAllConnections"), object: nil)
    }

    private func restartNetworkServices() {
        announceChange("Reiniciando servicios de red")

        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif

        // This will be handled by NetworkManager
        NotificationCenter.default.post(name: NSNotification.Name("RestartNetworkServices"), object: nil)
    }
}

// MARK: - Connection Stats Row Component

struct ConnectionStatsRow: View {
    @EnvironmentObject var networkManager: NetworkManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 20) {
                // Connected peers
                StatItem(
                    icon: "person.2.fill",
                    label: "Conectados",
                    value: "\(networkManager.connectedPeers.count)",
                    color: ThemeColors.connected
                )

                Divider()
                    .frame(height: 40)

                // Available peers
                StatItem(
                    icon: "antenna.radiowaves.left.and.right",
                    label: "Disponibles",
                    value: "\(networkManager.availablePeers.count)",
                    color: ThemeColors.info
                )

                Divider()
                    .frame(height: 40)

                // Pending messages
                StatItem(
                    icon: "envelope.fill",
                    label: "Pendientes",
                    value: "\(networkManager.pendingAcksCount)",
                    color: ThemeColors.warning
                )
            }
            .padding()
            .background(ThemeColors.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(ThemeColors.textSecondary.opacity(0.2), lineWidth: 1)
            )
        }
    }
}

struct StatItem: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(ThemeColors.textPrimary)

            Text(label)
                .font(.caption)
                .foregroundColor(ThemeColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preset Card Component

struct PresetCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: {
            #if os(iOS)
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            #endif
            action()
        }) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(color)
                    .frame(height: 40)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(ThemeColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text(description)
                    .font(.caption)
                    .foregroundColor(ThemeColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(width: 140, height: 140)
            .padding()
            .background(ThemeColors.cardBackground)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(color.opacity(0.3), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(description)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Preview

#Preview {
    AccessibilitySettingsView()
}
