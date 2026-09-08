import Foundation

public struct SnapPlaintext: Codable, Equatable, Sendable {
    public var rev: Int
    public var sessionId: UUID?
    public var ticketId: UUID?
    public var title: String?
    public var phase: WirePhase
    public var startedAt: Int?
    public var estimatedSeconds: Int?
    public var pausedAccumulated: Int?
    public var pausedAt: Int?
    public var boardedDeviceID: String?

    public init(
        rev: Int,
        sessionId: UUID?,
        ticketId: UUID?,
        title: String?,
        phase: WirePhase,
        startedAt: Int?,
        estimatedSeconds: Int?,
        pausedAccumulated: Int?,
        pausedAt: Int?,
        boardedDeviceID: String?
    ) {
        self.rev = rev
        self.sessionId = sessionId
        self.ticketId = ticketId
        self.title = title
        self.phase = phase
        self.startedAt = startedAt
        self.estimatedSeconds = estimatedSeconds
        self.pausedAccumulated = pausedAccumulated
        self.pausedAt = pausedAt
        self.boardedDeviceID = boardedDeviceID
    }

    enum CodingKeys: String, CodingKey {
        case rev, sessionId, ticketId, title, phase
        case startedAt, estimatedSeconds, pausedAccumulated, pausedAt, boardedDeviceID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rev = try container.decode(Int.self, forKey: .rev)
        sessionId = try container.decodeLowercaseUUIDIfPresent(.sessionId)
        ticketId = try container.decodeLowercaseUUIDIfPresent(.ticketId)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        phase = try container.decode(WirePhase.self, forKey: .phase)
        startedAt = try container.decodeIfPresent(Int.self, forKey: .startedAt)
        estimatedSeconds = try container.decodeIfPresent(Int.self, forKey: .estimatedSeconds)
        pausedAccumulated = try container.decodeIfPresent(Int.self, forKey: .pausedAccumulated)
        pausedAt = try container.decodeIfPresent(Int.self, forKey: .pausedAt)
        boardedDeviceID = try container.decodeIfPresent(String.self, forKey: .boardedDeviceID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rev, forKey: .rev)
        try container.encodeLowercaseUUID(sessionId, forKey: .sessionId)
        try container.encodeLowercaseUUID(ticketId, forKey: .ticketId)
        try container.encode(title, forKey: .title)
        try container.encode(phase, forKey: .phase)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(estimatedSeconds, forKey: .estimatedSeconds)
        try container.encode(pausedAccumulated, forKey: .pausedAccumulated)
        try container.encode(pausedAt, forKey: .pausedAt)
        try container.encode(boardedDeviceID, forKey: .boardedDeviceID)
    }

    /// Remaining seconds using the contract formula. Idle / missing fields → nil.
    public func remainingSeconds(at now: Int) -> Int? {
        guard let startedAt, let estimatedSeconds else { return nil }
        let pausedTotal =
            (pausedAccumulated ?? 0)
            + (pausedAt.map { now - $0 } ?? 0)
        let elapsedActive = now - startedAt - pausedTotal
        return estimatedSeconds - elapsedActive
    }
}

extension KeyedEncodingContainer where K: CodingKey {
    mutating func encodeLowercaseUUID(_ value: UUID?, forKey key: K) throws {
        if let value {
            try encode(value.canonicalLowercase, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}

extension KeyedDecodingContainer where K: CodingKey {
    func decodeLowercaseUUIDIfPresent(_ key: K) throws -> UUID? {
        if try decodeNil(forKey: key) { return nil }
        let raw = try decode(String.self, forKey: key)
        guard let uuid = UUID(uuidString: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Invalid UUID"
            )
        }
        return uuid
    }
}
