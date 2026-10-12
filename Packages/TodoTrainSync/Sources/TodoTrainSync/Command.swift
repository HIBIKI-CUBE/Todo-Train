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
    /// Mac build. Commands are written by the Mac. Absent on older peers.
    public var build: WireBuildInfo?
    /// Mac contract. Absent means v3.
    public var contract: Int?
    public var minReadable: Int?
    /// `answer`, and optionally `boardReserved`.
    public var nudgeId: UUID?
    /// `answer` only.
    public var choice: NudgeChoice?
    /// `answer` with `willExtend` only. Preset seconds.
    public var addSeconds: Int?
    /// `answer` only. `mac` for now.
    public var answeredOn: NudgeAnsweredOn?
    /// `boardReserved` only.
    public var ticketId: UUID?
    /// `presence` only.
    public var pipVisible: Bool?
    /// `presence` only. Unlocked, and the last input is inside the presence window.
    public var attending: Bool?

    public init(
        id: UUID,
        op: WireOp = .pause,
        sessionId: UUID?,
        at: Int,
        title: String? = nil,
        estimatedSeconds: Int? = nil,
        build: WireBuildInfo? = nil,
        contract: Int? = nil,
        minReadable: Int? = nil,
        nudgeId: UUID? = nil,
        choice: NudgeChoice? = nil,
        addSeconds: Int? = nil,
        answeredOn: NudgeAnsweredOn? = nil,
        ticketId: UUID? = nil,
        pipVisible: Bool? = nil,
        attending: Bool? = nil
    ) {
        self.id = id
        self.op = op
        self.sessionId = sessionId
        self.at = at
        self.build = build
        self.contract = contract
        self.minReadable = minReadable
        self.title = nil
        self.estimatedSeconds = nil
        self.nudgeId = nil
        self.choice = nil
        self.addSeconds = nil
        self.answeredOn = nil
        self.ticketId = nil
        self.pipVisible = nil
        self.attending = nil
        switch op {
        case .issueAndBoard:
            self.title = title
            self.estimatedSeconds = estimatedSeconds
        case .answer:
            self.nudgeId = nudgeId
            self.choice = choice
            self.addSeconds = addSeconds
            self.answeredOn = answeredOn
        case .boardReserved:
            self.ticketId = ticketId
            self.nudgeId = nudgeId
        case .presence:
            self.pipVisible = pipVisible
            self.attending = attending
        case .pause, .resume, .still, .unknown:
            break
        }
    }

    public var announcement: ContractAnnouncement {
        .resolved(contract: contract, minReadable: minReadable)
    }

    enum CodingKeys: String, CodingKey {
        case id, op, sessionId, at, title, estimatedSeconds, build, contract, minReadable
        case nudgeId, choice, addSeconds, answeredOn, ticketId, pipVisible, attending
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
        title = nil
        estimatedSeconds = nil
        nudgeId = nil
        choice = nil
        addSeconds = nil
        answeredOn = nil
        ticketId = nil
        pipVisible = nil
        attending = nil
        switch op {
        case .issueAndBoard:
            title = try container.decodeIfPresent(String.self, forKey: .title)
            estimatedSeconds = try container.decodeIfPresent(Int.self, forKey: .estimatedSeconds)
        case .answer:
            nudgeId = try container.decodeLowercaseUUIDIfPresent(.nudgeId)
            choice = try container.decodeIfPresent(NudgeChoice.self, forKey: .choice)
            addSeconds = try container.decodeIfPresent(Int.self, forKey: .addSeconds)
            answeredOn = try container.decodeIfPresent(NudgeAnsweredOn.self, forKey: .answeredOn)
        case .boardReserved:
            ticketId = try container.decodeLowercaseUUIDIfPresent(.ticketId)
            nudgeId = try container.decodeLowercaseUUIDIfPresent(.nudgeId)
        case .presence:
            pipVisible = try container.decodeIfPresent(Bool.self, forKey: .pipVisible)
            attending = try container.decodeIfPresent(Bool.self, forKey: .attending)
        case .pause, .resume, .still, .unknown:
            break
        }
        build = WireBuildInfo.decodeLenient(from: container, forKey: .build)
        contract = ContractKeyDecoding.positiveInt(container, .contract)
        minReadable = ContractKeyDecoding.positiveInt(container, .minReadable)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.canonicalLowercase, forKey: .id)
        try container.encode(op, forKey: .op)
        try container.encodeLowercaseUUID(sessionId, forKey: .sessionId)
        try container.encode(at, forKey: .at)
        switch op {
        case .issueAndBoard:
            try container.encode(title ?? "", forKey: .title)
            try container.encode(estimatedSeconds ?? 0, forKey: .estimatedSeconds)
        case .answer:
            try container.encodeLowercaseUUID(nudgeId, forKey: .nudgeId)
            if let choice {
                try container.encode(choice, forKey: .choice)
            }
            try container.encodeIfPresent(addSeconds, forKey: .addSeconds)
            if let answeredOn {
                try container.encode(answeredOn, forKey: .answeredOn)
            }
        case .boardReserved:
            try container.encodeLowercaseUUID(ticketId, forKey: .ticketId)
            try container.encodeIfPresentLowercaseUUID(nudgeId, forKey: .nudgeId)
        case .presence:
            try container.encodeIfPresent(pipVisible, forKey: .pipVisible)
            try container.encodeIfPresent(attending, forKey: .attending)
        case .pause, .resume, .still, .unknown:
            break
        }
        try container.encodeIfPresent(build, forKey: .build)
        try container.encodeIfPresent(contract, forKey: .contract)
        try container.encodeIfPresent(minReadable, forKey: .minReadable)
    }
}
