//
//  FamilyGroupCode.swift
//  MeshRed
//
//  Created by Claude for StadiumConnect Pro
//

import Foundation

/// Generates and validates unique family group codes
/// Format: FAM-XXXXX (where X is alphanumeric)
struct FamilyGroupCode: Codable, Equatable, Hashable {
    let rawCode: String

    private static let prefix = "FAM"
    private static let codeLength = 5
    private static let allowedCharacters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // Removed ambiguous: 0,O,1,I

    init?(rawCode: String) {
        let normalized = rawCode.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate format: FAM-XXXXX
        guard normalized.hasPrefix(Self.prefix + "-") else {
            return nil
        }

        let code = String(normalized.dropFirst(Self.prefix.count + 1))

        guard code.count == Self.codeLength else {
            return nil
        }

        // Validate characters
        guard code.allSatisfy({ Self.allowedCharacters.contains($0) }) else {
            return nil
        }

        self.rawCode = normalized
    }

    /// Generate a new random family group code
    static func generate() -> FamilyGroupCode {
        let code = (0..<codeLength)
            .map { _ in allowedCharacters.randomElement()! }
            .map(String.init)
            .joined()

        let fullCode = "\(prefix)-\(code)"
        return FamilyGroupCode(rawCode: fullCode)!
    }

    /// User-friendly display format
    var displayCode: String {
        return rawCode
    }

    /// Format for QR code (full identifier)
    var qrCodeData: String {
        return "STADIUMCONNECT://family/\(rawCode)"
    }

    /// Parse from QR code data
    static func fromQRCode(_ qrData: String) -> FamilyGroupCode? {
        // Support both direct code and QR format
        if qrData.hasPrefix("STADIUMCONNECT://family/") {
            let code = String(qrData.dropFirst("STADIUMCONNECT://family/".count))
            return FamilyGroupCode(rawCode: code)
        } else {
            return FamilyGroupCode(rawCode: qrData)
        }
    }
}
