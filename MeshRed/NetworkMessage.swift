import Foundation

enum MessageType: String, Codable, CaseIterable {
    case chat = "chat"
    case emergency = "emergency"
    case location = "location"
    case meetup = "meetup"
    case alert = "alert"
    case messageRequest = "messageRequest"  // New type for first message requests

    var displayName: String {
        switch self {
        case .chat: return "Chat"
        case .emergency: return "Emergencia"
        case .location: return "Ubicación"
        case .meetup: return "Reunión"
        case .alert: return "Alerta"
        case .messageRequest: return "Solicitud"
        }
    }

    var defaultPriority: Int {
        switch self {
        case .emergency: return 0
        case .alert: return 1
        case .meetup: return 2
        case .location: return 3
        case .messageRequest: return 3  // Same priority as location
        case .chat: return 4
        }
    }
}

struct NetworkMessage: Codable, Identifiable {
    let id: UUID
    let senderId: String
    let recipientId: String
    let content: String
    let timestamp: Date
    let messageType: MessageType
    let priority: Int
    var ttl: Int
    var hopCount: Int
    var routePath: [String]
    let requiresAck: Bool
    var ackReceived: Bool

    init(
        id: UUID = UUID(),
        senderId: String,
        recipientId: String = "broadcast",
        content: String,
        timestamp: Date = Date(),
        messageType: MessageType = .chat,
        priority: Int? = nil,
        ttl: Int = 5,
        hopCount: Int = 0,
        routePath: [String] = [],
        requiresAck: Bool = false,
        ackReceived: Bool = false
    ) {
        self.id = id
        self.senderId = senderId
        self.recipientId = recipientId
        self.content = content
        self.timestamp = timestamp
        self.messageType = messageType
        self.priority = priority ?? messageType.defaultPriority
        self.ttl = ttl
        self.hopCount = hopCount
        self.routePath = routePath
        self.requiresAck = requiresAck
        self.ackReceived = ackReceived
    }

    func isForMe(_ myPeerId: String) -> Bool {
        return recipientId == "broadcast" || recipientId == myPeerId
    }

    func hasVisited(_ peerId: String) -> Bool {
        return routePath.contains(peerId)
    }

    func canHop() -> Bool {
        return hopCount < ttl
    }

    mutating func addHop(_ peerId: String) {
        if !routePath.contains(peerId) {
            routePath.append(peerId)
        }
        hopCount += 1
    }

    mutating func markAcknowledged() {
        ackReceived = true
    }
}

struct AckMessage: Codable {
    let originalMessageId: UUID
    let ackSenderId: String
    let timestamp: Date

    init(originalMessageId: UUID, ackSenderId: String) {
        self.originalMessageId = originalMessageId
        self.ackSenderId = ackSenderId
        self.timestamp = Date()
    }
}

struct PingMessage: Codable {
    let timestamp: Date
}

struct PongMessage: Codable {
    let timestamp: Date
}

// MARK: - GPS Location Message

/// GPS Location message for fallback direction calculation
struct GPSLocationMessage: Codable {
    let senderId: String
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let altitude: Double
    let verticalAccuracy: Double
    let timestamp: Date

    init(senderId: String, latitude: Double, longitude: Double, horizontalAccuracy: Double, altitude: Double, verticalAccuracy: Double, timestamp: Date = Date()) {
        self.senderId = senderId
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.altitude = altitude
        self.verticalAccuracy = verticalAccuracy
        self.timestamp = timestamp
    }
}

// MARK: - Route Discovery Messages

/// Route Request message for discovering paths to destination peers
struct RouteRequest: Codable {
    let requestID: UUID
    let origin: String      // Origin peer ID
    let destination: String // Destination peer ID
    var hopCount: Int
    var routePath: [String] // Path taken so far
    let timestamp: Date

    init(requestID: UUID = UUID(), origin: String, destination: String, hopCount: Int = 0, routePath: [String] = [], timestamp: Date = Date()) {
        self.requestID = requestID
        self.origin = origin
        self.destination = destination
        self.hopCount = hopCount
        self.routePath = routePath
        self.timestamp = timestamp
    }
}

/// Route Reply message containing discovered path information
struct RouteReply: Codable {
    let requestID: UUID     // Original request ID
    let destination: String // Destination peer ID
    let routePath: [String] // Complete path from origin to destination
    let hopCount: Int       // Total hops
    let timestamp: Date

    init(requestID: UUID, destination: String, routePath: [String], hopCount: Int, timestamp: Date = Date()) {
        self.requestID = requestID
        self.destination = destination
        self.routePath = routePath
        self.hopCount = hopCount
        self.timestamp = timestamp
    }
}

/// Route Error message for notifying broken routes
struct RouteError: Codable {
    let destination: String // Destination that is unreachable
    let brokenNextHop: String // Next hop that failed
    let timestamp: Date

    init(destination: String, brokenNextHop: String, timestamp: Date = Date()) {
        self.destination = destination
        self.brokenNextHop = brokenNextHop
        self.timestamp = timestamp
    }
}

enum NetworkPayload: Codable {
    case message(NetworkMessage)
    case ack(AckMessage)
    case ping(PingMessage)
    case pong(PongMessage)
    case keepAlive(KeepAlivePing)
    case locationRequest(LocationRequestMessage)
    case locationResponse(LocationResponseMessage)
    case uwbDiscoveryToken(LinkFinderDiscoveryTokenMessage)
    case familySync(FamilySyncMessage)
    case familyJoinRequest(FamilyJoinRequestMessage)
    case familyGroupInfo(FamilyGroupInfoMessage)
    case topology(TopologyMessage)
    case linkfenceEvent(LinkFenceEventMessage)
    case linkfenceShare(LinkFenceShareMessage)
    case routeRequest(RouteRequest)
    case routeReply(RouteReply)
    case routeError(RouteError)
    case gpsLocation(GPSLocationMessage)

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "message":
            let message = try container.decode(NetworkMessage.self, forKey: .payload)
            self = .message(message)
        case "ack":
            let ack = try container.decode(AckMessage.self, forKey: .payload)
            self = .ack(ack)
        case "ping":
            let ping = try container.decode(PingMessage.self, forKey: .payload)
            self = .ping(ping)
        case "pong":
            let pong = try container.decode(PongMessage.self, forKey: .payload)
            self = .pong(pong)
        case "keep-alive":
            let keepAlive = try container.decode(KeepAlivePing.self, forKey: .payload)
            self = .keepAlive(keepAlive)
        case "locationRequest":
            let request = try container.decode(LocationRequestMessage.self, forKey: .payload)
            self = .locationRequest(request)
        case "locationResponse":
            let response = try container.decode(LocationResponseMessage.self, forKey: .payload)
            self = .locationResponse(response)
        case "uwbDiscoveryToken":
            let token = try container.decode(LinkFinderDiscoveryTokenMessage.self, forKey: .payload)
            self = .uwbDiscoveryToken(token)
        case "familySync":
            let familySync = try container.decode(FamilySyncMessage.self, forKey: .payload)
            self = .familySync(familySync)
        case "familyJoinRequest":
            let joinRequest = try container.decode(FamilyJoinRequestMessage.self, forKey: .payload)
            self = .familyJoinRequest(joinRequest)
        case "familyGroupInfo":
            let groupInfo = try container.decode(FamilyGroupInfoMessage.self, forKey: .payload)
            self = .familyGroupInfo(groupInfo)
        case "topology":
            let topology = try container.decode(TopologyMessage.self, forKey: .payload)
            self = .topology(topology)
        case "linkfenceEvent":
            let event = try container.decode(LinkFenceEventMessage.self, forKey: .payload)
            self = .linkfenceEvent(event)
        case "linkfenceShare":
            let share = try container.decode(LinkFenceShareMessage.self, forKey: .payload)
            self = .linkfenceShare(share)
        case "routeRequest":
            let routeRequest = try container.decode(RouteRequest.self, forKey: .payload)
            self = .routeRequest(routeRequest)
        case "routeReply":
            let routeReply = try container.decode(RouteReply.self, forKey: .payload)
            self = .routeReply(routeReply)
        case "routeError":
            let routeError = try container.decode(RouteError.self, forKey: .payload)
            self = .routeError(routeError)
        case "gpsLocation":
            let gpsLocation = try container.decode(GPSLocationMessage.self, forKey: .payload)
            self = .gpsLocation(gpsLocation)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown payload type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .message(let message):
            try container.encode("message", forKey: .type)
            try container.encode(message, forKey: .payload)
        case .ack(let ack):
            try container.encode("ack", forKey: .type)
            try container.encode(ack, forKey: .payload)
        case .ping(let ping):
            try container.encode("ping", forKey: .type)
            try container.encode(ping, forKey: .payload)
        case .pong(let pong):
            try container.encode("pong", forKey: .type)
            try container.encode(pong, forKey: .payload)
        case .keepAlive(let keepAlive):
            try container.encode("keep-alive", forKey: .type)
            try container.encode(keepAlive, forKey: .payload)
        case .locationRequest(let request):
            try container.encode("locationRequest", forKey: .type)
            try container.encode(request, forKey: .payload)
        case .locationResponse(let response):
            try container.encode("locationResponse", forKey: .type)
            try container.encode(response, forKey: .payload)
        case .uwbDiscoveryToken(let token):
            try container.encode("uwbDiscoveryToken", forKey: .type)
            try container.encode(token, forKey: .payload)
        case .familySync(let familySync):
            try container.encode("familySync", forKey: .type)
            try container.encode(familySync, forKey: .payload)
        case .familyJoinRequest(let joinRequest):
            try container.encode("familyJoinRequest", forKey: .type)
            try container.encode(joinRequest, forKey: .payload)
        case .familyGroupInfo(let groupInfo):
            try container.encode("familyGroupInfo", forKey: .type)
            try container.encode(groupInfo, forKey: .payload)
        case .topology(let topology):
            try container.encode("topology", forKey: .type)
            try container.encode(topology, forKey: .payload)
        case .linkfenceEvent(let event):
            try container.encode("linkfenceEvent", forKey: .type)
            try container.encode(event, forKey: .payload)
        case .linkfenceShare(let share):
            try container.encode("linkfenceShare", forKey: .type)
            try container.encode(share, forKey: .payload)
        case .routeRequest(let routeRequest):
            try container.encode("routeRequest", forKey: .type)
            try container.encode(routeRequest, forKey: .payload)
        case .routeReply(let routeReply):
            try container.encode("routeReply", forKey: .type)
            try container.encode(routeReply, forKey: .payload)
        case .routeError(let routeError):
            try container.encode("routeError", forKey: .type)
            try container.encode(routeError, forKey: .payload)
        case .gpsLocation(let gpsLocation):
            try container.encode("gpsLocation", forKey: .type)
            try container.encode(gpsLocation, forKey: .payload)
        }
    }
}