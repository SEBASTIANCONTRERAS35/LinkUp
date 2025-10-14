//
//  EmergencyMedicalProfile.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Emergency Medical Profile for ICE (In Case of Emergency)
//  COMPARTIDO: iOS + watchOS
//

import Foundation
import Combine
import os

/// Perfil médico de emergencia del usuario
/// Almacena información vital que debe compartirse en caso de emergencia
struct EmergencyMedicalProfile: Codable, Equatable {
    var isEnabled: Bool = false

    // Información básica
    var fullName: String?
    var dateOfBirth: Date?
    var bloodType: BloodType?

    // Condiciones médicas
    var medicalConditions: [String] = []  // ["Diabetes", "Asma", "Epilepsia"]
    var allergies: [String] = []          // ["Penicilina", "Maní", "Polen"]
    var currentMedications: [String] = [] // ["Insulina", "Ventolin"]

    // Contactos de emergencia
    var emergencyContacts: [EmergencyContact] = []

    // Información adicional
    var additionalNotes: String?

    // Metadata
    var lastUpdated: Date = Date()

    init() {
        self.isEnabled = false
    }

    /// Crear perfil completo
    init(
        fullName: String,
        dateOfBirth: Date?,
        bloodType: BloodType?,
        medicalConditions: [String] = [],
        allergies: [String] = [],
        currentMedications: [String] = [],
        emergencyContacts: [EmergencyContact] = [],
        additionalNotes: String? = nil
    ) {
        self.isEnabled = true
        self.fullName = fullName
        self.dateOfBirth = dateOfBirth
        self.bloodType = bloodType
        self.medicalConditions = medicalConditions
        self.allergies = allergies
        self.currentMedications = currentMedications
        self.emergencyContacts = emergencyContacts
        self.additionalNotes = additionalNotes
        self.lastUpdated = Date()
    }

    /// Edad calculada desde fecha de nacimiento
    var age: Int? {
        guard let dob = dateOfBirth else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year], from: dob, to: Date())
        return components.year
    }

    /// Información resumida para mostrar en emergencias
    var summaryText: String {
        var summary: [String] = []

        if let name = fullName {
            summary.append("Nombre: \(name)")
        }

        if let age = age {
            summary.append("Edad: \(age) años")
        }

        if let blood = bloodType {
            summary.append("Tipo de sangre: \(blood.displayName)")
        }

        if !medicalConditions.isEmpty {
            summary.append("Condiciones: \(medicalConditions.joined(separator: ", "))")
        }

        if !allergies.isEmpty {
            summary.append("⚠️ Alergias: \(allergies.joined(separator: ", "))")
        }

        if !currentMedications.isEmpty {
            summary.append("Medicamentos: \(currentMedications.joined(separator: ", "))")
        }

        return summary.joined(separator: "\n")
    }

    /// Validar si el perfil tiene información suficiente
    var isComplete: Bool {
        return fullName != nil && !fullName!.isEmpty
    }

    /// Información crítica para primeros respondedores
    var criticalInfo: [String] {
        var info: [String] = []

        if let blood = bloodType {
            info.append("Sangre: \(blood.displayName)")
        }

        if !allergies.isEmpty {
            info.append("ALERGIAS: \(allergies.joined(separator: ", "))")
        }

        if !medicalConditions.isEmpty {
            info.append("Condiciones: \(medicalConditions.joined(separator: ", "))")
        }

        return info
    }
}

// MARK: - Blood Type

enum BloodType: String, Codable, CaseIterable, Identifiable {
    case aPositive = "A+"
    case aNegative = "A-"
    case bPositive = "B+"
    case bNegative = "B-"
    case abPositive = "AB+"
    case abNegative = "AB-"
    case oPositive = "O+"
    case oNegative = "O-"
    case unknown = "Desconocido"

    var id: String { rawValue }

    var displayName: String {
        return rawValue
    }

    var emoji: String {
        switch self {
        case .oNegative: return "🅾️-"  // Donador universal
        case .abPositive: return "🆎+"  // Receptor universal
        default: return "🩸"
        }
    }
}

// MARK: - Emergency Contact

struct EmergencyContact: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var relationship: String  // "Madre", "Padre", "Cónyuge", "Amigo"
    var phoneNumber: String
    var isPrimary: Bool       // Contacto principal

    init(
        id: UUID = UUID(),
        name: String,
        relationship: String,
        phoneNumber: String,
        isPrimary: Bool = false
    ) {
        self.id = id
        self.name = name
        self.relationship = relationship
        self.phoneNumber = phoneNumber
        self.isPrimary = isPrimary
    }

    var displayName: String {
        return "\(name) (\(relationship))"
    }
}

// MARK: - Persistence Manager

class EmergencyMedicalProfileManager: ObservableObject {
    static let shared = EmergencyMedicalProfileManager()

    @Published var profile: EmergencyMedicalProfile

    private let userDefaultsKey = "StadiumConnect.EmergencyMedicalProfile"

    init() {
        // Load from UserDefaults
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode(EmergencyMedicalProfile.self, from: data) {
            self.profile = decoded
            LoggingService.network.info("✅ EmergencyMedicalProfile: Loaded from storage")
        } else {
            self.profile = EmergencyMedicalProfile()
            LoggingService.network.info("ℹ️ EmergencyMedicalProfile: No saved profile, using default")
        }
    }

    /// Guardar perfil
    func save() {
        profile.lastUpdated = Date()

        if let encoded = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            LoggingService.network.info("💾 EmergencyMedicalProfile: Saved successfully")
        } else {
            LoggingService.network.info("❌ EmergencyMedicalProfile: Failed to save")
        }
    }

    /// Actualizar perfil completo
    func updateProfile(_ newProfile: EmergencyMedicalProfile) {
        self.profile = newProfile
        save()
    }

    /// Habilitar/deshabilitar perfil
    func setEnabled(_ enabled: Bool) {
        profile.isEnabled = enabled
        save()
    }

    /// Agregar contacto de emergencia
    func addEmergencyContact(_ contact: EmergencyContact) {
        profile.emergencyContacts.append(contact)
        save()
    }

    /// Remover contacto de emergencia
    func removeEmergencyContact(at index: Int) {
        guard index < profile.emergencyContacts.count else { return }
        profile.emergencyContacts.remove(at: index)
        save()
    }

    /// Limpiar perfil
    func clearProfile() {
        profile = EmergencyMedicalProfile()
        save()
    }
}
