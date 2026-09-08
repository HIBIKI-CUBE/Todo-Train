import Foundation

public struct CommandPlaintext: Codable, Equatable, Sendable {
    public var id: UUID
    public var op: WireOp
    public var sessionId: UUID
    public var at: Int

    public init(id: UUID, op: WireOp = .pause, sessionId: UUID, at: Int) {
        self.id = id
        self.op = op
        self.sessionId = sessionId
        self.at = at
    }

    enum CodingKeys: String, CodingKey {
        case id, op, sessionId, at
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let idRaw = try container.decode(String.self, forKey: .id)
        let sessionRaw = try container.decode(String.self, forKey: .sessionId)
        guard let parsedID = UUID(uuidString: idRaw),
              let parsedSession = UUID(uuidString: sessionRaw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid UUID")
            )
        }
        id = parsedID
        op = try container.decode(WireOp.self, forKey: .op)
        sessionId = parsedSession
        at = try container.decode(Int.self, forKey: .at)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.canonicalLowercase, forKey: .id)
        try container.encode(op, forKey: .op)
        try container.encode(sessionId.canonicalLowercase, forKey: .sessionId)
        try container.encode(at, forKey: .at)
    }
}
