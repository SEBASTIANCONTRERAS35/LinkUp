//
//  LinkFinderDiscoveryTokenMessage.swift
//  MeshRed
//
//  Created by Emilio Contreras on 29/09/25.
//

import Foundation

/// Device capabilities for UWB/LinkFinder (subset for exchange)
struct UWBDeviceCapabilities: Codable {
    let deviceModel: String
    let hasUWB: Bool
    let hasU1Chip: Bool
    let hasU2Chip: Bool
    let supportsDistance: Bool
    let supportsDirection: Bool
    let supportsCameraAssist: Bool
    let supportsExtendedRange: Bool
    let osVersion: String
}

/// Message containing NearbyInteraction discovery token for LinkFinder ranging session establishment
/// Exchanged automatically when two peers connect via MultipeerConnectivity
struct LinkFinderDiscoveryTokenMessage: Codable {
    let senderId: String
    let tokenData: Data  // Serialized NIDiscoveryToken
    let timestamp: Date
    let deviceCapabilities: UWBDeviceCapabilities?  // Device UWB capabilities (optional for backward compatibility)

    init(senderId: String, tokenData: Data, timestamp: Date = Date(), deviceCapabilities: UWBDeviceCapabilities? = nil) {
        self.senderId = senderId
        self.tokenData = tokenData
        self.timestamp = timestamp
        self.deviceCapabilities = deviceCapabilities
    }
}