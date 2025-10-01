import Foundation

struct ConversationIdentifier: RawRepresentable, Codable, Hashable, Equatable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let `public` = ConversationIdentifier(rawValue: "conversation.public")

    static func family(peerId: String) -> ConversationIdentifier {
        return ConversationIdentifier(rawValue: "conversation.family.\(peerId)")
    }

    var isFamily: Bool {
        return rawValue.hasPrefix("conversation.family.")
    }

    var familyPeerId: String? {
        guard isFamily else { return nil }
        return rawValue.components(separatedBy: "conversation.family.").last
    }
}
