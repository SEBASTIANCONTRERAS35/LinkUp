//
//  SimulationControlPanelView.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Control panel for managing simulated family groups
//

import SwiftUI

struct SimulationControlPanelView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var mockManager = MockFamilyGroupsManager.shared
    @EnvironmentObject var networkManager: NetworkManager

    @State private var selectedScenario: ScenarioType = .familiaEnPartido
    @State private var showEventLog = false
    @State private var showMemberDetails = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Status Card
                    statusCard

                    // Scenario Selector (only when not active)
                    if !mockManager.isSimulationActive {
                        scenarioSelector
                    }

                    // Active Group Info (only when active)
                    if mockManager.isSimulationActive {
                        activeGroupInfo
                    }

                    // Controls
                    controlsSection

                    // Settings
                    if mockManager.isSimulationActive {
                        settingsSection
                    }

                    // Statistics
                    if mockManager.isSimulationActive {
                        statisticsSection
                    }

                    // Event Log Toggle
                    if mockManager.isSimulationActive && !mockManager.recentEvents.isEmpty {
                        eventLogSection
                    }
                }
                .padding(20)
            }
            .background(Color.appBackgroundDark.ignoresSafeArea())
            .navigationTitle("Grupos de Prueba")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        VStack(spacing: 16) {
            // Status indicator
            HStack {
                Circle()
                    .fill(mockManager.isSimulationActive ? Color.appAccent : Color.gray)
                    .frame(width: 12, height: 12)

                Text(mockManager.isSimulationActive ? "Grupo Activo" : "Sin Grupo Activo")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()
            }

            // Quick stats (only when active)
            if mockManager.isSimulationActive {
                Divider()

                HStack(spacing: 20) {
                    StatBadge(
                        icon: "person.3.fill",
                        value: "\(mockManager.currentMembersCount)",
                        label: "Miembros",
                        color: .blue
                    )

                    StatBadge(
                        icon: "antenna.radiowaves.left.and.right",
                        value: "\(mockManager.onlineMembersCount)",
                        label: "En línea",
                        color: .green
                    )

                    if !mockManager.membersNeedingHelp.isEmpty {
                        StatBadge(
                            icon: "exclamationmark.triangle.fill",
                            value: "\(mockManager.membersNeedingHelp.count)",
                            label: "Alertas",
                            color: .red
                        )
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }

    // MARK: - Scenario Selector

    private var scenarioSelector: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Seleccionar Grupo")
                .font(.headline)
                .foregroundColor(.primary)

            ForEach(ScenarioType.allCases) { scenario in
                ScenarioCard(
                    scenario: scenario,
                    isSelected: selectedScenario == scenario,
                    onSelect: {
                        selectedScenario = scenario
                    }
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }

    // MARK: - Active Group Info

    private var activeGroupInfo: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(mockManager.currentGroupName)
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Text(mockManager.currentScenario.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.appPrimary.opacity(0.1))
                    )
            }

            // Members list
            if let groupData = mockManager.activeGroupData {
                Divider()

                ForEach(groupData.members) { member in
                    MemberRow(member: member)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
        VStack(spacing: 12) {
            if !mockManager.isSimulationActive {
                // Start button
                Button(action: {
                    mockManager.startSimulation(scenario: selectedScenario, familyGroupManager: networkManager.familyGroupManager)
                }) {
                    HStack {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                        Text("Cargar Grupo")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.appAccent, Color.appAccent.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                }
                .buttonStyle(.plain)
            } else {
                // Active controls
                HStack(spacing: 12) {
                    // Reset button
                    Button(action: {
                        mockManager.resetSimulation(familyGroupManager: networkManager.familyGroupManager)
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Reset")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.appPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.appPrimary, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)

                    // Stop button
                    Button(action: {
                        mockManager.stopSimulation(familyGroupManager: networkManager.familyGroupManager)
                    }) {
                        HStack {
                            Image(systemName: "stop.circle.fill")
                            Text("Detener")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.red)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configuración")
                .font(.headline)
                .foregroundColor(.primary)

            // Speed selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Velocidad de Actividad")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("Velocidad", selection: Binding(
                    get: { mockManager.simulationSpeed },
                    set: { mockManager.changeSpeed($0) }
                )) {
                    ForEach(SimulationSpeed.allCases) { speed in
                        Text(speed.rawValue).tag(speed)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider()

            // Auto-generation toggle
            Toggle(isOn: Binding(
                get: { mockManager.autoGenerateActivity },
                set: { _ in mockManager.toggleAutoGeneration() }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Generación Automática")
                        .font(.subheadline)
                        .foregroundColor(.primary)

                    Text("Crear mensajes y movimientos automáticamente")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .tint(.green)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }

    // MARK: - Statistics Section

    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Estadísticas")
                .font(.headline)
                .foregroundColor(.primary)

            HStack(spacing: 16) {
                StatisticItem(
                    icon: "message.fill",
                    value: mockManager.totalMessagesGenerated,
                    label: "Mensajes",
                    color: .blue
                )

                StatisticItem(
                    icon: "location.fill",
                    value: mockManager.totalMovementsGenerated,
                    label: "Movimientos",
                    color: .green
                )

                StatisticItem(
                    icon: "network",
                    value: mockManager.totalGeofenceEvents,
                    label: "Eventos",
                    color: .purple
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }

    // MARK: - Event Log Section

    private var eventLogSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Registro de Eventos")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: { showEventLog.toggle() }) {
                    Text(showEventLog ? "Ocultar" : "Ver todo")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            if showEventLog {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(mockManager.recentEvents.prefix(20)) { event in
                        EventRow(event: event)
                    }
                }
            } else {
                // Show only last 3 events
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(mockManager.recentEvents.prefix(3)) { event in
                        EventRow(event: event)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Supporting Views

struct ScenarioCard: View {
    let scenario: ScenarioType
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: scenario.icon)
                    .font(.system(size: 32))
                    .foregroundColor(isSelected ? .white : .appPrimary)
                    .frame(width: 56, height: 56)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.appPrimary : Color.appPrimary.opacity(0.1))
                    )

                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(scenario.rawValue)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text(scenario.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.appPrimary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.appPrimary : Color.gray.opacity(0.2), lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? Color.appPrimary.opacity(0.05) : Color.white)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct MemberRow: View {
    let member: MockGroupMember

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                // Additional info
                HStack(spacing: 8) {
                    if let distance = member.uwbDistance {
                        Text("\(String(format: "%.1f", distance))m")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(member.connectionStatus.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Alerts
            if member.needsAttention {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
            }

            // Battery
            HStack(spacing: 4) {
                Image(systemName: "battery.\(batteryIcon(member.batteryLevel))")
                    .foregroundColor(batteryColor(member.batteryLevel))
                    .font(.caption)

                Text("\(member.batteryLevel)%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private var statusColor: Color {
        switch member.connectionStatus {
        case .online: return .green
        case .away: return .orange
        case .indirect: return .yellow
        case .offline: return .gray
        }
    }

    private func batteryIcon(_ level: Int) -> String {
        if level > 75 { return "100" }
        else if level > 50 { return "75" }
        else if level > 25 { return "50" }
        else { return "25" }
    }

    private func batteryColor(_ level: Int) -> Color {
        if level < 20 { return .red }
        else if level < 50 { return .orange }
        else { return .green }
    }
}

struct EventRow: View {
    let event: SimulationEvent

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: event.icon)
                .font(.caption)
                .foregroundColor(eventColor)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(eventColor.opacity(0.1))
                )

            // Description
            Text(event.description)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(2)

            Spacer()

            // Timestamp
            Text(timeAgo(event.timestamp))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var eventColor: Color {
        switch event.color {
        case "green": return .green
        case "red": return .red
        case "blue": return .blue
        case "orange": return .orange
        case "purple": return .purple
        case "cyan": return .cyan
        default: return .gray
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))

        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            return "\(seconds / 60)m"
        } else {
            return "\(seconds / 3600)h"
        }
    }
}

struct StatBadge: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)

            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct StatisticItem: View {
    let icon: String
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text("\(value)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Preview

#Preview {
    SimulationControlPanelView()
        .environmentObject(NetworkManager())
}
