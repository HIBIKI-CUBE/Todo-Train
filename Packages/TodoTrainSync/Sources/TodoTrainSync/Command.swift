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
    /// `pause` only. Absent on older Macs, which is stored as `user`. `user` and `timetable` are applied; other values are `invalidPayload`. A timetable time does not choose the reason.
    public var heldBy: PauseHeldBy?
    /// `pauseInputReport` only. The open pause on the snap.
    public var pauseId: UUID?
    /// `pauseInputReport` only. Seconds the Mac was able to look. Never below `macActiveSeconds`.
    public var macSampledSeconds: Double?
    /// `pauseInputReport` only. Seconds whose 30 second bucket had input inside 60 seconds.
    public var macActiveSeconds: Double?
    /// `pauseInputReport` only. Unix seconds when the pause question was shown.
    public var promptedAt: Int?
    /// `pauseInputReport` only. Absent when the question was not shown.
    public var promptAnswer: PausePromptAnswer?
    /// `reestimate` only. Omitted when the commit did not use a progress ratio.
    public var progressAnswer: Double?
    /// `reestimate` only.
    public var committedRemainingSeconds: Int?
    /// `reestimate` only.
    public var mode: WireReestimateMode?
    /// `reestimate` only.
    public var trigger: WireReestimateTrigger?
    /// `reestimate` only.
    public var promptId: String?
    /// `reestimate` only.
    public var surface: WireReestimateSurface?
    /// `reestimate` only.
    public var input: WireReestimateInput?

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
        attending: Bool? = nil,
        heldBy: PauseHeldBy? = nil,
        pauseId: UUID? = nil,
        macSampledSeconds: Double? = nil,
        macActiveSeconds: Double? = nil,
        promptedAt: Int? = nil,
        promptAnswer: PausePromptAnswer? = nil,
        progressAnswer: Double? = nil,
        committedRemainingSeconds: Int? = nil,
        mode: WireReestimateMode? = nil,
        trigger: WireReestimateTrigger? = nil,
        promptId: String? = nil,
        surface: WireReestimateSurface? = nil,
        input: WireReestimateInput? = nil
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
        self.heldBy = nil
        self.pauseId = nil
        self.macSampledSeconds = nil
        self.macActiveSeconds = nil
        self.promptedAt = nil
        self.promptAnswer = nil
        self.progressAnswer = nil
        self.committedRemainingSeconds = nil
        self.mode = nil
        self.trigger = nil
        self.promptId = nil
        self.surface = nil
        self.input = nil
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
        case .pause:
            self.heldBy = heldBy
        case .pauseInputReport:
            self.pauseId = pauseId
            self.macSampledSeconds = macSampledSeconds
            self.macActiveSeconds = macActiveSeconds
            self.promptedAt = promptedAt
            self.promptAnswer = promptAnswer
        case .reestimate:
            self.progressAnswer = progressAnswer
            self.committedRemainingSeconds = committedRemainingSeconds
            self.mode = mode
            self.trigger = trigger
            self.promptId = promptId
            self.surface = surface
            self.input = input
        case .resume, .still, .undoReestimate, .unknown:
            break
        }
    }

    public var announcement: ContractAnnouncement {
        .resolved(contract: contract, minReadable: minReadable)
    }

    enum CodingKeys: String, CodingKey {
        case id, op, sessionId, at, title, estimatedSeconds, build, contract, minReadable
        case nudgeId, choice, addSeconds, answeredOn, ticketId, pipVisible, attending
        case heldBy
        case pauseId, macSampledSeconds, macActiveSeconds, promptedAt, promptAnswer
        case progressAnswer, committedRemainingSeconds, mode, trigger, promptId, surface, input
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
        heldBy = nil
        pauseId = nil
        macSampledSeconds = nil
        macActiveSeconds = nil
        promptedAt = nil
        promptAnswer = nil
        progressAnswer = nil
        committedRemainingSeconds = nil
        mode = nil
        trigger = nil
        promptId = nil
        surface = nil
        input = nil
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
        case .pause:
            heldBy = try container.decodeIfPresent(PauseHeldBy.self, forKey: .heldBy)
        case .pauseInputReport:
            pauseId = try container.decodeLowercaseUUIDIfPresent(.pauseId)
            macSampledSeconds = try container.decodeIfPresent(Double.self, forKey: .macSampledSeconds)
            macActiveSeconds = try container.decodeIfPresent(Double.self, forKey: .macActiveSeconds)
            promptedAt = try container.decodeIfPresent(Int.self, forKey: .promptedAt)
            promptAnswer = try container.decodeIfPresent(PausePromptAnswer.self, forKey: .promptAnswer)
        case .reestimate:
            progressAnswer = try container.decodeIfPresent(Double.self, forKey: .progressAnswer)
            committedRemainingSeconds = try container.decodeIfPresent(Int.self, forKey: .committedRemainingSeconds)
            mode = try container.decodeIfPresent(WireReestimateMode.self, forKey: .mode)
            trigger = try container.decodeIfPresent(WireReestimateTrigger.self, forKey: .trigger)
            promptId = try container.decodeIfPresent(String.self, forKey: .promptId)
            surface = try container.decodeIfPresent(WireReestimateSurface.self, forKey: .surface)
            input = try container.decodeIfPresent(WireReestimateInput.self, forKey: .input)
        case .resume, .still, .undoReestimate, .unknown:
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
        case .pause:
            try container.encodeIfPresent(heldBy, forKey: .heldBy)
        case .pauseInputReport:
            try container.encodeIfPresentLowercaseUUID(pauseId, forKey: .pauseId)
            try container.encodeIfPresent(macSampledSeconds, forKey: .macSampledSeconds)
            try container.encodeIfPresent(macActiveSeconds, forKey: .macActiveSeconds)
            try container.encodeIfPresent(promptedAt, forKey: .promptedAt)
            try container.encodeIfPresent(promptAnswer, forKey: .promptAnswer)
        case .reestimate:
            try container.encodeIfPresent(progressAnswer, forKey: .progressAnswer)
            try container.encodeIfPresent(committedRemainingSeconds, forKey: .committedRemainingSeconds)
            try container.encodeIfPresent(mode, forKey: .mode)
            try container.encodeIfPresent(trigger, forKey: .trigger)
            try container.encodeIfPresent(promptId, forKey: .promptId)
            try container.encodeIfPresent(surface, forKey: .surface)
            try container.encodeIfPresent(input, forKey: .input)
        case .resume, .still, .undoReestimate, .unknown:
            break
        }
        try container.encodeIfPresent(build, forKey: .build)
        try container.encodeIfPresent(contract, forKey: .contract)
        try container.encodeIfPresent(minReadable, forKey: .minReadable)
    }
}
