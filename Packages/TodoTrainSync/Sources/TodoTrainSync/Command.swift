import Foundation

public struct CommandPlaintext: Codable, Equatable, Sendable {
    public var id: UUID
    public var op: WireOp
    public var sessionId: UUID?
    public var at: Int
    /// Present only for `issueAndBoard`. Other ops omit the key.
    public var title: String?
    /// Present only for `issueAndBoard`. Seconds, not minutes. Other ops omit the key.
    public var estimatedSeconds: Int?

    public init(
        id: UUID,
        op: WireOp = .pause,
        sessionId: UUID?,
        at: Int,
        title: String? = nil,
        estimatedSeconds: Int? = nil
    ) {
        self.id = id
        self.op = op
        self.sessionId = sessionId
        self.at = at
        if op == .issueAndBoard {
            self.title = title
            self.estimatedSeconds = estimatedSeconds
        } else {
            self.title = nil
            self.estimatedSeconds = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, op, sessionId, at, title, estimatedSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let idRaw = try container.decode(String.self, forKey: .id)
        guard let parsedID = UUID(uuidString: idRaw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid UUID")
            )
        }
        id = parsedID
        op = try container.decode(WireOp.self, forKey: .op)
        sessionId = try container.decodeLowercaseUUIDIfPresent(.sessionId)
        at = try container.decode(Int.self, forKey: .at)
        if op == .issueAndBoard {
            title = try container.decodeIfPresent(String.self, forKey: .title)
            estimatedSeconds = try container.decodeIfPresent(Int.self, forKey: .estimatedSeconds)
        } else {
            title = nil
            estimatedSeconds = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.canonicalLowercase, forKey: .id)
        try container.encode(op, forKey: .op)
        try container.encodeLowercaseUUID(sessionId, forKey: .sessionId)
        try container.encode(at, forKey: .at)
        if op == .issueAndBoard {
            try container.encode(title ?? "", forKey: .title)
            try container.encode(estimatedSeconds ?? 0, forKey: .estimatedSeconds)
        }
    }
}
