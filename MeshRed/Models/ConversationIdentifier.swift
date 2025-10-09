import Foundation

struct ConversationIdentifier: RawRepresentable, Codable, Hashable, Equatable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    // MARK: - Static Factories

    /// Public broadcast conversation (all connected peers)
    static let `public` = ConversationIdentifier(rawValue: "conversation.public")

    /// Private conversation with a family group member
    static func family(peerId: String) -> ConversationIdentifier {
        return ConversationIdentifier(rawValue: "conversation.family.\(peerId)")
    }

    /// Direct private conversation with a non-family peer
    static func direct(peerId: String) -> ConversationIdentifier {
        return ConversationIdentifier(rawValue: "conversation.direct.\(peerId)")
    }

    // MARK: - Type Detection

    /// True if this is the public broadcast conversation
    var isPublic: Bool {
        return rawValue == "conversation.public"
    }

    /// True if this is a family member conversation
    var isFamily: Bool {
        return rawValue.hasPrefix("conversation.family.")
    }

    /// True if this is a direct (non-family) conversation
    var isDirect: Bool {
        return rawValue.hasPrefix("conversation.direct.")
    }

    /// True if this is any private conversation (family or direct)
    var isPrivate: Bool {
        return isFamily || isDirect
    }

    // MARK: - Peer ID Extraction

    /// Extract peer ID from family conversation, nil otherwise
    var familyPeerId: String? {
        guard isFamily else { return nil }
        return rawValue.components(separatedBy: "conversation.family.").last
    }

    /// Extract peer ID from direct conversation, nil otherwise
    var directPeerId: String? {
        guard isDirect else { return nil }
        return rawValue.components(separatedBy: "conversation.direct.").last
    }

    /// Extract peer ID from any private conversation (family or direct), nil for public
    var privatePeerId: String? {
        return familyPeerId ?? directPeerId
    }

    // MARK: - Display Type

    /// Human-readable conversation type
    var displayType: String {
        if isPublic { return "Público" }
        if isFamily { return "Familia" }
        if isDirect { return "Directo" }
        return "Desconocido"
    }
}
