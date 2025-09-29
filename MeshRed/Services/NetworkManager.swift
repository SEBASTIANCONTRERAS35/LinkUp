//
//  NetworkManager.swift
//  MeshRed
//
//  Created by Emilio Contreras on 28/09/25.
//

import Foundation
import MultipeerConnectivity
import Combine

class NetworkManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var connectedPeers: [MCPeerID] = []
    @Published var availablePeers: [MCPeerID] = []
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var isAdvertising: Bool = false
    @Published var isBrowsing: Bool = false

    // MARK: - Core Components
    private let serviceType = "meshred-chat"
    private let localPeerID: MCPeerID = {
        let deviceName = ProcessInfo.processInfo.hostName
        return MCPeerID(displayName: deviceName)
    }()
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    // MARK: - Message Store
    let messageStore = MessageStore()

    // MARK: - Connection Status Enum
    enum ConnectionStatus {
        case disconnected
        case connecting
        case connected
    }

    override init() {
        self.session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .required)
        super.init()

        session.delegate = self
        startServices()

        print("🚀 NetworkManager: Initialized with peer ID: \(localPeerID.displayName)")
    }

    deinit {
        stopServices()
    }

    // MARK: - Public Methods

    func startServices() {
        startAdvertising()
        startBrowsing()
        print("🔄 NetworkManager: Started advertising and browsing services")
    }

    func stopServices() {
        stopAdvertising()
        stopBrowsing()
        session.disconnect()
        print("⏹️ NetworkManager: Stopped all services and disconnected session")
    }

    func sendMessage(_ content: String) {
        guard !connectedPeers.isEmpty else {
            print("⚠️ NetworkManager: No connected peers to send message to")
            return
        }

        let message = Message(sender: localPeerID.displayName, content: content)

        guard let messageData = message.toData() else {
            print("❌ NetworkManager: Failed to serialize message")
            return
        }

        do {
            try session.send(messageData, toPeers: connectedPeers, with: .reliable)

            // Add to local message store
            messageStore.addMessage(message)

            print("📤 NetworkManager: Sent message to \(connectedPeers.count) peers: \(content)")
        } catch {
            print("❌ NetworkManager: Failed to send message: \(error.localizedDescription)")
        }
    }

    func connectToPeer(_ peerID: MCPeerID) {
        guard let browser = browser else {
            print("❌ NetworkManager: Browser not available")
            return
        }

        print("🔗 NetworkManager: Attempting to connect to peer: \(peerID.displayName)")
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
    }

    func disconnectFromPeer(_ peerID: MCPeerID) {
        session.cancelConnectPeer(peerID)
        print("🔗 NetworkManager: Disconnected from peer: \(peerID.displayName)")
    }

    // MARK: - Private Methods

    private func startAdvertising() {
        advertiser = MCNearbyServiceAdvertiser(peer: localPeerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()

        DispatchQueue.main.async {
            self.isAdvertising = true
        }

        print("📡 NetworkManager: Started advertising with service type: \(serviceType)")
    }

    private func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil

        DispatchQueue.main.async {
            self.isAdvertising = false
        }

        print("📡 NetworkManager: Stopped advertising")
    }

    private func startBrowsing() {
        browser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()

        DispatchQueue.main.async {
            self.isBrowsing = true
        }

        print("🔍 NetworkManager: Started browsing for peers")
    }

    private func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil

        DispatchQueue.main.async {
            self.isBrowsing = false
        }

        print("🔍 NetworkManager: Stopped browsing")
    }

    private func updateConnectionStatus() {
        DispatchQueue.main.async {
            if self.connectedPeers.isEmpty {
                self.connectionStatus = .disconnected
            } else {
                self.connectionStatus = .connected
            }
        }
    }

    private func handleReceivedMessage(data: Data, from peerID: MCPeerID) {
        guard let message = Message.fromData(data) else {
            print("❌ NetworkManager: Failed to deserialize received message")
            return
        }

        DispatchQueue.main.async {
            self.messageStore.addMessage(message)
            print("📥 NetworkManager: Received message from \(peerID.displayName): \(message.content)")
        }
    }
}

// MARK: - MCSessionDelegate

extension NetworkManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                }
                self.updateConnectionStatus()
                print("✅ NetworkManager: Connected to peer: \(peerID.displayName)")

            case .connecting:
                self.connectionStatus = .connecting
                print("🔄 NetworkManager: Connecting to peer: \(peerID.displayName)")

            case .notConnected:
                self.connectedPeers.removeAll { $0 == peerID }
                self.updateConnectionStatus()
                print("❌ NetworkManager: Disconnected from peer: \(peerID.displayName)")

            @unknown default:
                print("⚠️ NetworkManager: Unknown connection state for peer: \(peerID.displayName)")
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        handleReceivedMessage(data: data, from: peerID)
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used in this implementation
        print("📡 NetworkManager: Received stream (not implemented): \(streamName) from \(peerID.displayName)")
    }

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not used in this implementation
        print("📡 NetworkManager: Started receiving resource (not implemented): \(resourceName) from \(peerID.displayName)")
    }

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Not used in this implementation
        print("📡 NetworkManager: Finished receiving resource (not implemented): \(resourceName) from \(peerID.displayName)")
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension NetworkManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("📨 NetworkManager: Received invitation from peer: \(peerID.displayName)")

        // Auto-accept all invitations for mesh network
        invitationHandler(true, session)
        print("✅ NetworkManager: Auto-accepted invitation from: \(peerID.displayName)")
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("❌ NetworkManager: Failed to start advertising: \(error.localizedDescription)")

        DispatchQueue.main.async {
            self.isAdvertising = false
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension NetworkManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        DispatchQueue.main.async {
            if !self.availablePeers.contains(peerID) && peerID != self.localPeerID {
                self.availablePeers.append(peerID)
                print("🔍 NetworkManager: Found peer: \(peerID.displayName)")

                // Auto-connect to discovered peers for mesh network
                self.connectToPeer(peerID)
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.availablePeers.removeAll { $0 == peerID }
            print("👻 NetworkManager: Lost peer: \(peerID.displayName)")
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("❌ NetworkManager: Failed to start browsing: \(error.localizedDescription)")

        DispatchQueue.main.async {
            self.isBrowsing = false
        }
    }
}

// MARK: - Helper Extensions

extension NetworkManager {
    var localDeviceName: String {
        return localPeerID.displayName
    }

    var isConnected: Bool {
        return !connectedPeers.isEmpty
    }

    var connectedPeerNames: [String] {
        return connectedPeers.map { $0.displayName }
    }

    var availablePeerNames: [String] {
        return availablePeers.map { $0.displayName }
    }
}