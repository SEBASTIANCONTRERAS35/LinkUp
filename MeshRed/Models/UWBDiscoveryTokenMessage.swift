//
//  LinkFinderDiscoveryTokenMessage.swift
//  MeshRed
//
//  Created by Emilio Contreras on 29/09/25.
//

import Foundation

/// Message containing NearbyInteraction discovery token for LinkFinder ranging session establishment
/// Exchanged automatically when two peers connect via MultipeerConnectivity
struct LinkFinderDiscoveryTokenMessage: Codable {
    let senderId: String
    let tokenData: Data  // Serialized NIDiscoveryToken
    let timestamp: Date

    init(senderId: String, tokenData: Data, timestamp: Date = Date()) {
        self.senderId = senderId
        self.tokenData = tokenData
        self.timestamp = timestamp
    }
}