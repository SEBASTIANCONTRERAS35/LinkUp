//
//  DeviceCompatibilityMatrixView.swift
//  MeshRed
//
//  Device compatibility matrix showing UWB capabilities across iPhone models
//

import SwiftUI

struct DeviceCompatibilityMatrixView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var networkManager: NetworkManager
    @EnvironmentObject var accessibilitySettings: AccessibilitySettingsManager
    @Environment(\.accessibleTheme) var accessibleTheme
    @Environment(\.colorScheme) var colorScheme

    @State private var selectedCategory: DeviceCategory = .current

    enum DeviceCategory: String, CaseIterable {
        case current = "Tu Dispositivo"
        case u2Devices = "Chip U2 (Mejor)"
        case u1Devices = "Chip U1"
        case noUWB = "Sin UWB"

        var icon: String {
            switch self {
            case .current: return "iphone"
            case .u2Devices: return "antenna.radiowaves.left.and.right.circle.fill"
            case .u1Devices: return "antenna.radiowaves.left.and.right.circle"
            case .noUWB: return "antenna.radiowaves.left.and.right.slash.circle"
            }
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header with explanation
                    headerSection

                    // Category selector
                    categorySelector

                    // Device list for selected category
                    deviceListSection

                    // Compatibility matrix
                    compatibilityMatrixSection
                }
                .padding()
            }
            .background(accessibleTheme.background)
            .navigationTitle("Matriz de Compatibilidad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .font(.title2)
                    .foregroundColor(Mundial2026Colors.azul)

                Text("Compatibilidad LinkFinder")
                    .font(.headline)
                    .foregroundColor(accessibleTheme.textPrimary)
            }

            Text("LinkFinder requiere chips UWB específicos para funcionar. La dirección solo funciona cuando AMBOS dispositivos tienen UWB.")
                .font(.subheadline)
                .foregroundColor(accessibleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.1))
        )
    }

    // MARK: - Category Selector
    private var categorySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(DeviceCategory.allCases, id: \.self) { category in
                    CategoryButton(
                        category: category,
                        isSelected: selectedCategory == category,
                        action: {
                            withAnimation(.spring(response: 0.3)) {
                                selectedCategory = category
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Device List Section
    private var deviceListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: selectedCategory.icon)
                    .font(.title3)
                    .foregroundColor(colorForCategory(selectedCategory))

                Text(selectedCategory.rawValue)
                    .font(.headline)
                    .foregroundColor(accessibleTheme.textPrimary)

                Spacer()
            }

            VStack(spacing: 8) {
                ForEach(devicesForCategory(selectedCategory), id: \.self) { device in
                    DeviceRow(
                        device: device,
                        isCurrentDevice: isCurrentDevice(device)
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
        )
    }

    // MARK: - Compatibility Matrix Section
    private var compatibilityMatrixSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tabla de Compatibilidad", systemImage: "chart.bar.fill")
                .font(.headline)
                .foregroundColor(accessibleTheme.textPrimary)

            // Matrix grid
            VStack(alignment: .leading, spacing: 8) {
                // Header row
                HStack(spacing: 16) {
                    Text("Tu dispositivo")
                        .font(.caption)
                        .frame(width: 100, alignment: .leading)

                    Text("Otro")
                        .font(.caption)
                        .frame(width: 100, alignment: .leading)

                    Text("Distancia")
                        .font(.caption)
                        .frame(width: 70)

                    Text("Dirección")
                        .font(.caption)
                        .frame(width: 70)
                }
                .foregroundColor(accessibleTheme.textSecondary)

                Divider()

                // Compatibility rows
                ForEach(compatibilityScenarios, id: \.id) { scenario in
                    CompatibilityRow(scenario: scenario)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.05))
            )
        }
    }

    // MARK: - Helper Methods
    private func devicesForCategory(_ category: DeviceCategory) -> [String] {
        switch category {
        case .current:
            if #available(iOS 14.0, *),
               let uwbManager = networkManager.uwbSessionManager,
               let localCaps = uwbManager.localDeviceCapabilities {
                return [localCaps.deviceModel]
            }
            return ["Dispositivo desconocido"]

        case .u2Devices:
            return ["iPhone 17 Pro Max", "iPhone 17 Pro", "iPhone 17",
                    "iPhone 16 Pro Max", "iPhone 16 Pro", "iPhone 16",
                    "iPhone 15 Pro Max", "iPhone 15 Pro", "iPhone 15 Plus", "iPhone 15"]

        case .u1Devices:
            return ["iPhone 14 Plus", "iPhone 14",
                    "iPhone 13 Pro Max", "iPhone 13 Pro", "iPhone 13 mini", "iPhone 13",
                    "iPhone 12 Pro Max", "iPhone 12 Pro", "iPhone 12 mini", "iPhone 12",
                    "iPhone 11 Pro Max", "iPhone 11 Pro", "iPhone 11"]

        case .noUWB:
            return ["iPhone SE (3ra gen)", "iPhone SE (2da gen)",
                    "iPhone XS Max", "iPhone XS", "iPhone XR", "iPhone X",
                    "iPhone 8 Plus", "iPhone 8", "iPhone 7 y anteriores"]
        }
    }

    private func isCurrentDevice(_ device: String) -> Bool {
        if #available(iOS 14.0, *),
           let uwbManager = networkManager.uwbSessionManager,
           let localCaps = uwbManager.localDeviceCapabilities {
            return device == localCaps.deviceModel
        }
        return false
    }

    private func colorForCategory(_ category: DeviceCategory) -> Color {
        switch category {
        case .current: return Mundial2026Colors.azul
        case .u2Devices: return Mundial2026Colors.verde
        case .u1Devices: return Color.orange
        case .noUWB: return Color.red
        }
    }

    private var compatibilityScenarios: [CompatibilityScenario] {
        [
            CompatibilityScenario(device1: "U2 + U2", device2: "U2", hasDistance: true, hasDirection: true),
            CompatibilityScenario(device1: "U2 + U1", device2: "U1", hasDistance: true, hasDirection: true),
            CompatibilityScenario(device1: "U1 + U1", device2: "U1", hasDistance: true, hasDirection: true),
            CompatibilityScenario(device1: "U2/U1", device2: "Sin UWB", hasDistance: false, hasDirection: false),
            CompatibilityScenario(device1: "Sin UWB", device2: "Sin UWB", hasDistance: false, hasDirection: false)
        ]
    }
}

// MARK: - Supporting Views
struct CategoryButton: View {
    let category: DeviceCompatibilityMatrixView.DeviceCategory
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibleTheme) var accessibleTheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 14))

                Text(category.rawValue)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundColor(isSelected ? .white : accessibleTheme.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Mundial2026Colors.azul : Color.gray.opacity(0.2))
            )
        }
        .buttonStyle(.plain)
    }
}

struct DeviceRow: View {
    let device: String
    let isCurrentDevice: Bool

    @Environment(\.accessibleTheme) var accessibleTheme

    var body: some View {
        HStack {
            Image(systemName: "iphone")
                .font(.system(size: 14))
                .foregroundColor(isCurrentDevice ? Mundial2026Colors.azul : accessibleTheme.textSecondary)

            Text(device)
                .font(.subheadline)
                .foregroundColor(accessibleTheme.textPrimary)
                .fontWeight(isCurrentDevice ? .semibold : .regular)

            if isCurrentDevice {
                Spacer()
                Label("Tu dispositivo", systemImage: "person.fill")
                    .font(.caption)
                    .foregroundColor(Mundial2026Colors.azul)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrentDevice ? Color.blue.opacity(0.1) : Color.clear)
        )
    }
}

struct CompatibilityScenario: Identifiable {
    let id = UUID()
    let device1: String
    let device2: String
    let hasDistance: Bool
    let hasDirection: Bool
}

struct CompatibilityRow: View {
    let scenario: CompatibilityScenario

    @Environment(\.accessibleTheme) var accessibleTheme

    var body: some View {
        HStack(spacing: 16) {
            Text(scenario.device1)
                .font(.caption)
                .frame(width: 100, alignment: .leading)
                .foregroundColor(accessibleTheme.textPrimary)

            Text(scenario.device2)
                .font(.caption)
                .frame(width: 100, alignment: .leading)
                .foregroundColor(accessibleTheme.textSecondary)

            Image(systemName: scenario.hasDistance ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: 14))
                .foregroundColor(scenario.hasDistance ? Mundial2026Colors.verde : Color.red)
                .frame(width: 70)

            Image(systemName: scenario.hasDirection ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: 14))
                .foregroundColor(scenario.hasDirection ? Mundial2026Colors.verde : Color.red)
                .frame(width: 70)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview
#Preview {
    DeviceCompatibilityMatrixView()
        .environmentObject(NetworkManager())
        .environmentObject(AccessibilitySettingsManager())
}