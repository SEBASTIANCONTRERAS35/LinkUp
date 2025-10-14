//
//  MockFamilyGroupsManager.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Central manager for simulated family groups and activity
//

import Foundation
import SwiftUI
import Combine
import os

// MARK: - Mock Family Groups Manager

/// Central manager for all simulated groups and their activity
class MockFamilyGroupsManager: ObservableObject {
    static let shared = MockFamilyGroupsManager()

    // MARK: - Published Properties

    @Published var isSimulationActive: Bool = false
    @Published var currentScenario: ScenarioType = .familiaEnPartido
    @Published var activeGroupData: MockFamilyGroupData?
    @Published var simulationSpeed: SimulationSpeed = .normal
    @Published var autoGenerateActivity: Bool = true

    // Activity tracking
    @Published var recentEvents: [SimulationEvent] = []
    @Published var totalMessagesGenerated: Int = 0
    @Published var totalMovementsGenerated: Int = 0
    @Published var totalGeofenceEvents: Int = 0

    // MARK: - Private Properties

    private var activityTimer: Timer?
    private var movementTimer: Timer?
    private let maxRecentEvents = 50

    private let userDefaultsKey = "MockFamilyGroups.IsActive"

    // MARK: - Initialization

    private init() {
        loadSettings()
    }

    // MARK: - Public Methods

    /// Start simulation with selected scenario
    func startSimulation(scenario: ScenarioType, familyGroupManager: FamilyGroupManager? = nil) {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🎬 STARTING SIMULATION")
        print("   Scenario: \(scenario.rawValue)")
        print("   Speed: \(simulationSpeed.rawValue)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        currentScenario = scenario
        activeGroupData = MockGroupScenarios.scenario(scenario)
        isSimulationActive = true

        // Load the simulated group into the real FamilyGroupManager
        if let familyGroupManager = familyGroupManager, let groupData = activeGroupData {
            let realGroup = groupData.toFamilyGroup()
            loadSimulatedGroupIntoManager(realGroup, manager: familyGroupManager)
        }

        // IMPORTANTE: Limpiar cualquier mensaje antiguo y marcarlo como leído
        if let groupData = activeGroupData {
            let conversationId = ConversationIdentifier.familyGroup(groupId: groupData.id).rawValue
            // Marcar TODOS los mensajes existentes como leídos antes de generar nuevos
            MessageStore.shared.markConversationAsRead(conversationId: conversationId)
            print("🧹 Cleaned any old unread messages for group: \(groupData.name)")
        }

        // DESHABILITADO: No generar mensajes simulados
        // generateInitialActivity()

        // DESHABILITADO: No generar actividad automática
        // if autoGenerateActivity {
        //     startActivityGeneration()
        // }

        saveSettings()
        logEvent(.simulationStarted(scenario: scenario.rawValue))
    }

    /// Load simulated group into the real FamilyGroupManager
    private func loadSimulatedGroupIntoManager(_ group: FamilyGroup, manager: FamilyGroupManager) {
        DispatchQueue.main.async {
            manager.currentGroup = group
            manager.hasActiveGroup = true

            print("✅ Loaded simulated group '\(group.name)' into FamilyGroupManager")
            print("   Members: \(group.memberCount)")
            print("   Code: \(group.code.displayCode)")
        }
    }

    /// Stop simulation
    func stopSimulation(familyGroupManager: FamilyGroupManager? = nil) {
        print("⏹️ STOPPING SIMULATION")

        isSimulationActive = false
        activeGroupData = nil
        stopActivityGeneration()

        // Clear the simulated group from the real FamilyGroupManager
        if let familyGroupManager = familyGroupManager {
            DispatchQueue.main.async {
                familyGroupManager.currentGroup = nil
                familyGroupManager.hasActiveGroup = false
                print("🗑️ Cleared simulated group from FamilyGroupManager")
            }
        }

        saveSettings()
        logEvent(.simulationStopped)
    }

    /// Reset simulation to initial state
    func resetSimulation(familyGroupManager: FamilyGroupManager? = nil) {
        guard let scenario = activeGroupData?.scenario else { return }

        print("🔄 RESETTING SIMULATION")

        stopActivityGeneration()
        activeGroupData = MockGroupScenarios.scenario(scenario)
        recentEvents.removeAll()
        totalMessagesGenerated = 0
        totalMovementsGenerated = 0
        totalGeofenceEvents = 0

        // Reload the group into the real FamilyGroupManager
        if let familyGroupManager = familyGroupManager, let groupData = activeGroupData {
            let realGroup = groupData.toFamilyGroup()
            loadSimulatedGroupIntoManager(realGroup, manager: familyGroupManager)
        }

        if autoGenerateActivity {
            startActivityGeneration()
        }

        // Marcar INMEDIATAMENTE todos los mensajes como leídos después del reset
        if let groupData = activeGroupData {
            let conversationId = ConversationIdentifier.familyGroup(groupId: groupData.id).rawValue
            MessageStore.shared.markConversationAsRead(conversationId: conversationId)
            print("✅ Marked all messages as read after reset for group: \(groupData.name)")
        }

        logEvent(.simulationReset)
    }

    /// Change simulation speed
    func changeSpeed(_ speed: SimulationSpeed) {
        simulationSpeed = speed

        // Restart timers with new speed
        if isSimulationActive && autoGenerateActivity {
            stopActivityGeneration()
            startActivityGeneration()
        }

        logEvent(.speedChanged(speed: speed.rawValue))
    }

    /// Toggle auto-generation of activity
    func toggleAutoGeneration() {
        autoGenerateActivity.toggle()

        if autoGenerateActivity && isSimulationActive {
            startActivityGeneration()
        } else {
            stopActivityGeneration()
        }
    }

    /// DESHABILITADO: No generar mensajes simulados
    func generateMessage(fromMember memberPeerID: String, message: String) {
        // ELIMINADO: Ya no generamos mensajes simulados
        return
        guard var groupData = activeGroupData,
              let memberIndex = groupData.members.firstIndex(where: { $0.peerID == memberPeerID }) else {
            return
        }

        // SIMPLIFICADO: Ya no necesitamos SimulatedMessage ni recentMessages
        // Todo se maneja directamente a través del MessageStore

        // Opcionalmente: mantener recentMessages para compatibilidad temporal
        let newMessage = SimulatedMessage(
            content: message,
            timestamp: Date(),
            senderId: memberPeerID,
            isRead: false
        )

        groupData.members[memberIndex].recentMessages.insert(newMessage, at: 0)
        if groupData.members[memberIndex].recentMessages.count > 5 {
            groupData.members[memberIndex].recentMessages.removeLast()
        }

        activeGroupData = groupData

        // Crear un Message regular directamente para el MessageStore
        let realMessage = Message(
            sender: groupData.members[memberIndex].nickname,
            content: message,
            recipientId: nil, // Mensaje grupal
            conversationId: ConversationIdentifier.familyGroup(groupId: groupData.id).rawValue,
            conversationName: groupData.name
        )

        // Crear el descriptor de la conversación del grupo familiar
        let conversationContext = MessageStore.ConversationDescriptor(
            id: ConversationIdentifier.familyGroup(groupId: groupData.id).rawValue,
            title: groupData.name,
            isFamily: true,
            isDirect: false,
            participantId: nil,
            defaultRecipientId: "family-group-\(groupData.id.uuidString)"
        )

        // Añadir al MessageStore para persistencia y manejo real de lectura
        MessageStore.shared.addMessage(
            realMessage,
            context: conversationContext,
            autoSwitch: false, // No cambiar automáticamente a esta conversación
            localDeviceName: ProcessInfo.processInfo.hostName
        )

        // IMPORTANTE: Marcar INMEDIATAMENTE los mensajes simulados como leídos
        // Sin delay para evitar race conditions con la UI
        MessageStore.shared.markAsRead(messageId: realMessage.id)

        totalMessagesGenerated += 1

        logEvent(.messageGenerated(
            member: groupData.members[memberIndex].nickname,
            message: message
        ))
    }

    /// Manually move a member to a new location
    func moveMember(peerID: String, to newLocation: UserLocation) {
        guard var groupData = activeGroupData,
              let memberIndex = groupData.members.firstIndex(where: { $0.peerID == peerID }) else {
            return
        }

        groupData.members[memberIndex].location = newLocation
        groupData.members[memberIndex].lastSeenMinutesAgo = 0

        activeGroupData = groupData
        totalMovementsGenerated += 1

        logEvent(.memberMoved(
            member: groupData.members[memberIndex].nickname,
            location: "(\(String(format: "%.6f", newLocation.latitude)), \(String(format: "%.6f", newLocation.longitude)))"
        ))
    }

    /// Update member connection status
    func updateMemberStatus(peerID: String, status: MockConnectionStatus) {
        guard var groupData = activeGroupData,
              let memberIndex = groupData.members.firstIndex(where: { $0.peerID == peerID }) else {
            return
        }

        let oldStatus = groupData.members[memberIndex].connectionStatus
        groupData.members[memberIndex].connectionStatus = status

        activeGroupData = groupData

        logEvent(.statusChanged(
            member: groupData.members[memberIndex].nickname,
            from: oldStatus.rawValue,
            to: status.rawValue
        ))
    }

    /// Trigger emergency for a member
    func triggerEmergency(forMember peerID: String, type: HealthAlert) {
        guard var groupData = activeGroupData,
              let memberIndex = groupData.members.firstIndex(where: { $0.peerID == peerID }) else {
            return
        }

        groupData.members[memberIndex].hasActiveEmergency = true
        groupData.members[memberIndex].healthAlert = type

        activeGroupData = groupData

        logEvent(.emergencyTriggered(
            member: groupData.members[memberIndex].nickname,
            type: type.rawValue
        ))
    }

    /// Clear emergency for a member
    func clearEmergency(forMember peerID: String) {
        guard var groupData = activeGroupData,
              let memberIndex = groupData.members.firstIndex(where: { $0.peerID == peerID }) else {
            return
        }

        groupData.members[memberIndex].hasActiveEmergency = false
        groupData.members[memberIndex].healthAlert = .none

        activeGroupData = groupData

        logEvent(.emergencyCleared(
            member: groupData.members[memberIndex].nickname
        ))
    }

    /// Mark member as lost
    func markMemberAsLost(peerID: String, isLost: Bool) {
        guard var groupData = activeGroupData,
              let memberIndex = groupData.members.firstIndex(where: { $0.peerID == peerID }) else {
            return
        }

        groupData.members[memberIndex].isLost = isLost

        activeGroupData = groupData

        if isLost {
            logEvent(.memberLost(member: groupData.members[memberIndex].nickname))
        } else {
            logEvent(.memberFound(member: groupData.members[memberIndex].nickname))
        }
    }

    /// Get current active group as FamilyGroup
    func getCurrentFamilyGroup() -> FamilyGroup? {
        return activeGroupData?.toFamilyGroup()
    }

    /// Get all available scenarios
    func getAllScenarios() -> [MockFamilyGroupData] {
        return MockGroupScenarios.allScenarios
    }

    // MARK: - Private Methods - Activity Generation

    private func generateInitialActivity() {
        // DESHABILITADO: No generar mensajes iniciales
        return
        guard let groupData = activeGroupData else { return }

        print("🎭 Generating initial activity for: \(groupData.name)")

        // Generate 3-5 initial messages from different members
        let messagesToGenerate = Int.random(in: 3...5)
        let onlineMembers = groupData.members.filter { $0.connectionStatus == .online && !$0.isCurrentDevice }

        for _ in 0..<min(messagesToGenerate, onlineMembers.count) {
            if let randomMember = onlineMembers.randomElement() {
                let contextualMessage = generateContextualMessage(for: randomMember, scenario: groupData.scenario)
                generateMessage(fromMember: randomMember.peerID, message: contextualMessage)
            }
        }

        // IMPORTANTE: Marcar INMEDIATAMENTE todos los mensajes del grupo como leídos
        // Sin delay para evitar que la UI muestre badges
        let conversationId = ConversationIdentifier.familyGroup(groupId: groupData.id).rawValue
        MessageStore.shared.markConversationAsRead(conversationId: conversationId)
        print("✅ Marked all initial messages as read for group: \(groupData.name)")
    }

    private func startActivityGeneration() {
        let messageInterval = simulationSpeed.messageInterval
        let movementInterval = simulationSpeed.movementInterval

        print("⏱️ Starting activity generation")
        print("   Message interval: \(messageInterval)s")
        print("   Movement interval: \(movementInterval)s")

        // Message generation timer
        activityTimer = Timer.scheduledTimer(withTimeInterval: messageInterval, repeats: true) { [weak self] _ in
            self?.generateRandomActivity()
        }

        // Movement timer (slower than messages)
        movementTimer = Timer.scheduledTimer(withTimeInterval: movementInterval, repeats: true) { [weak self] _ in
            self?.generateRandomMovement()
        }
    }

    private func stopActivityGeneration() {
        activityTimer?.invalidate()
        activityTimer = nil

        movementTimer?.invalidate()
        movementTimer = nil

        print("⏹️ Stopped activity generation")
    }

    private func generateRandomActivity() {
        // DESHABILITADO: No generar actividad aleatoria
        return
        guard let groupData = activeGroupData else { return }

        // 60% chance to generate a message
        if Double.random(in: 0...1) < 0.6 {
            // Pick a random online member (not current device)
            let eligibleMembers = groupData.members.filter {
                ($0.connectionStatus == .online || $0.connectionStatus == .away) &&
                !$0.isCurrentDevice
            }

            if let randomMember = eligibleMembers.randomElement() {
                let message = generateContextualMessage(for: randomMember, scenario: groupData.scenario)
                generateMessage(fromMember: randomMember.peerID, message: message)
            }
        }

        // 30% chance to update a member's status
        if Double.random(in: 0...1) < 0.3 {
            if let randomMember = groupData.members.filter({ !$0.isCurrentDevice }).randomElement() {
                let newStatus: MockConnectionStatus = [.online, .away, .indirect].randomElement() ?? .online
                updateMemberStatus(peerID: randomMember.peerID, status: newStatus)
            }
        }
    }

    private func generateRandomMovement() {
        guard var groupData = activeGroupData else { return }

        // Move 1-2 random members slightly
        let membersToMove = Int.random(in: 1...2)

        for _ in 0..<membersToMove {
            if let randomMember = groupData.members.filter({ !$0.isCurrentDevice }).randomElement(),
               let memberIndex = groupData.members.firstIndex(where: { $0.peerID == randomMember.peerID }) {

                // Move slightly (5-15 meters in random direction)
                let currentLat = groupData.members[memberIndex].location.latitude
                let currentLon = groupData.members[memberIndex].location.longitude

                let distanceMeters = Double.random(in: 5...15)
                let latOffset = (distanceMeters / 111000.0) * Double.random(in: -1...1)
                let lonOffset = (distanceMeters / 85000.0) * Double.random(in: -1...1)

                let newLocation = UserLocation(
                    latitude: currentLat + latOffset,
                    longitude: currentLon + lonOffset,
                    accuracy: 10.0,
                    timestamp: Date()
                )

                moveMember(peerID: randomMember.peerID, to: newLocation)
            }
        }

        totalMovementsGenerated += membersToMove
    }

    private func generateContextualMessage(for member: MockGroupMember, scenario: ScenarioType) -> String {
        // Return existing messages if available
        if !member.recentMessages.isEmpty {
            return member.recentMessages.randomElement()?.content ?? "👋"
        }

        // Generate contextual messages based on scenario and member state
        if member.isLost {
            return [
                "No sé dónde estoy 😰",
                "Ayuda, me perdí",
                "¿Dónde están todos?",
                "Hay mucha gente aquí"
            ].randomElement()!
        }

        if member.hasActiveEmergency {
            return [
                "Necesito ayuda",
                "No me siento bien",
                "¿Dónde está el médico?",
                "Urge asistencia"
            ].randomElement()!
        }

        if member.batteryLevel < 20 {
            return [
                "Mi batería está muy baja 🔋",
                "Se me va a apagar el celular",
                "¿Alguien trae cargador?",
                "Batería al \(member.batteryLevel)%"
            ].randomElement()!
        }

        // Default contextual messages based on scenario
        switch scenario {
        case .familiaEnPartido:
            return [
                "¡Qué buen partido! 🇲🇽",
                "¿Alguien quiere algo de comer?",
                "¿A qué hora es el medio tiempo?",
                "¡GOOOL! ⚽️",
                "Hace mucho calor aquí",
                "¿Ya vieron ese pase?",
                "Voy al baño, ya regreso",
                "La fila está larguísima 😩"
            ].randomElement()!

        case .estudiantesUNAM:
            return [
                "¡Vamos México! 🇲🇽",
                "¿Alguien vio a los profes?",
                "Esto es épico 🔥",
                "¿Dónde están los demás?",
                "Qué bien se ve el estadio",
                "¿Pedimos pizza después?",
                "Mañana hay clase temprano 😴",
                "Esto va para Instagram 📸"
            ].randomElement()!

        case .emergenciaMedica:
            return [
                "¿Cómo está papá?",
                "¿Ya llegó el médico?",
                "Manténganse tranquilos",
                "Vienen en camino",
                "Todo va a estar bien",
                "¿Necesitan algo?",
                "Estoy aquí con ustedes"
            ].randomElement()!

        case .mundial2026:
            return [
                "¡MUNDIAL! 🏆",
                "Esto es histórico 🇲🇽",
                "¿Vieron esa jugada?",
                "Messi vs México 😱",
                "Qué emoción estar aquí",
                "Los niños están felices 😊",
                "¡Argentina está fuerte!",
                "¡Vamos México! 🇲🇽⚽️"
            ].randomElement()!
        }
    }

    // MARK: - Event Logging

    private func logEvent(_ event: SimulationEvent) {
        recentEvents.insert(event, at: 0)

        // Keep only recent events
        if recentEvents.count > maxRecentEvents {
            recentEvents.removeLast()
        }

        print("📝 Event: \(event.description)")
    }

    // MARK: - Persistence

    private func saveSettings() {
        UserDefaults.standard.set(isSimulationActive, forKey: userDefaultsKey)
        UserDefaults.standard.set(currentScenario.rawValue, forKey: "MockFamilyGroups.CurrentScenario")
        UserDefaults.standard.set(simulationSpeed.rawValue, forKey: "MockFamilyGroups.SimulationSpeed")
    }

    private func loadSettings() {
        isSimulationActive = UserDefaults.standard.bool(forKey: userDefaultsKey)

        if let scenarioRaw = UserDefaults.standard.string(forKey: "MockFamilyGroups.CurrentScenario"),
           let scenario = ScenarioType(rawValue: scenarioRaw) {
            currentScenario = scenario
        }

        if let speedRaw = UserDefaults.standard.string(forKey: "MockFamilyGroups.SimulationSpeed"),
           let speed = SimulationSpeed(rawValue: speedRaw) {
            simulationSpeed = speed
        }

        // Restore active scenario if simulation was active
        if isSimulationActive {
            activeGroupData = MockGroupScenarios.scenario(currentScenario)
        }
    }

    // MARK: - Computed Properties

    var isGroupActive: Bool {
        return activeGroupData != nil
    }

    var currentGroupName: String {
        return activeGroupData?.name ?? "Sin grupo activo"
    }

    var currentMembersCount: Int {
        return activeGroupData?.members.count ?? 0
    }

    var onlineMembersCount: Int {
        return activeGroupData?.onlineMembersCount ?? 0
    }

    var membersNeedingHelp: [MockGroupMember] {
        return activeGroupData?.membersNeedingHelp ?? []
    }
}

// MARK: - Supporting Types

/// Simulation speeds
enum SimulationSpeed: String, CaseIterable, Identifiable {
    case slow = "Lento (2x)"
    case normal = "Normal (1x)"
    case fast = "Rápido (0.5x)"
    case veryFast = "Muy Rápido (0.25x)"

    var id: String { rawValue }

    /// Message generation interval in seconds
    var messageInterval: TimeInterval {
        switch self {
        case .slow: return 120.0      // 2 minutes
        case .normal: return 60.0     // 1 minute
        case .fast: return 30.0       // 30 seconds
        case .veryFast: return 15.0   // 15 seconds
        }
    }

    /// Movement interval in seconds
    var movementInterval: TimeInterval {
        switch self {
        case .slow: return 180.0      // 3 minutes
        case .normal: return 90.0     // 1.5 minutes
        case .fast: return 45.0       // 45 seconds
        case .veryFast: return 20.0   // 20 seconds
        }
    }
}

/// Simulation events for logging
enum SimulationEvent: Identifiable {
    case simulationStarted(scenario: String)
    case simulationStopped
    case simulationReset
    case speedChanged(speed: String)
    case messageGenerated(member: String, message: String)
    case memberMoved(member: String, location: String)
    case statusChanged(member: String, from: String, to: String)
    case emergencyTriggered(member: String, type: String)
    case emergencyCleared(member: String)
    case memberLost(member: String)
    case memberFound(member: String)

    var id: UUID { UUID() }

    var timestamp: Date { Date() }

    var description: String {
        switch self {
        case .simulationStarted(let scenario):
            return "▶️ Simulación iniciada: \(scenario)"
        case .simulationStopped:
            return "⏹️ Simulación detenida"
        case .simulationReset:
            return "🔄 Simulación reiniciada"
        case .speedChanged(let speed):
            return "⏱️ Velocidad cambiada a: \(speed)"
        case .messageGenerated(let member, let message):
            return "💬 \(member): \(message)"
        case .memberMoved(let member, let location):
            return "📍 \(member) se movió a \(location)"
        case .statusChanged(let member, let from, let to):
            return "🔄 \(member): \(from) → \(to)"
        case .emergencyTriggered(let member, let type):
            return "🚨 Emergencia: \(member) - \(type)"
        case .emergencyCleared(let member):
            return "✅ Emergencia resuelta: \(member)"
        case .memberLost(let member):
            return "😰 \(member) está perdido"
        case .memberFound(let member):
            return "😊 \(member) fue encontrado"
        }
    }

    var icon: String {
        switch self {
        case .simulationStarted: return "play.circle.fill"
        case .simulationStopped: return "stop.circle.fill"
        case .simulationReset: return "arrow.clockwise.circle.fill"
        case .speedChanged: return "gauge"
        case .messageGenerated: return "message.fill"
        case .memberMoved: return "location.fill"
        case .statusChanged: return "arrow.left.arrow.right.circle.fill"
        case .emergencyTriggered: return "exclamationmark.triangle.fill"
        case .emergencyCleared: return "checkmark.circle.fill"
        case .memberLost: return "person.fill.questionmark"
        case .memberFound: return "person.fill.checkmark"
        }
    }

    var color: String {
        switch self {
        case .simulationStarted: return "green"
        case .simulationStopped: return "red"
        case .simulationReset: return "blue"
        case .speedChanged: return "purple"
        case .messageGenerated: return "blue"
        case .memberMoved: return "cyan"
        case .statusChanged: return "orange"
        case .emergencyTriggered: return "red"
        case .emergencyCleared: return "green"
        case .memberLost: return "red"
        case .memberFound: return "green"
        }
    }
}
