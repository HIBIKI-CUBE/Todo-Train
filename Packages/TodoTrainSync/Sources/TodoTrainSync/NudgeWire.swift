import Foundation

/// `nudge.kind`. Unknown values stay on the value and do not fail the snap.
public enum NudgeKind: Sendable, Equatable {
    case progress
    case overrun
    case gap
    case unknown(String)

    public static let knownRawValues = ["progress", "overrun", "gap"]

    public var rawValue: String {
        switch self {
        case .progress: "progress"
        case .overrun: "overrun"
        case .gap: "gap"
        case .unknown(let value): value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "progress": self = .progress
        case "overrun": self = .overrun
        case "gap": self = .gap
        default: self = .unknown(rawValue)
        }
    }
}

extension NudgeKind: Codable {
    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// `nudge.stage` and `nudgePlan.stage`. Ride names match `NudgeStage`. Gaps match `NudgeGap`.
public enum NudgeStageWire: Sendable, Equatable {
    case checkIn
    case approach
    case estimate
    case handoff1
    case handoff2
    case handoff3
    case gap1
    case gap2
    case unknown(String)

    public static let knownRawValues = [
        "checkIn", "approach", "estimate", "handoff1", "handoff2", "handoff3", "gap1", "gap2",
    ]

    public var rawValue: String {
        switch self {
        case .checkIn: "checkIn"
        case .approach: "approach"
        case .estimate: "estimate"
        case .handoff1: "handoff1"
        case .handoff2: "handoff2"
        case .handoff3: "handoff3"
        case .gap1: "gap1"
        case .gap2: "gap2"
        case .unknown(let value): value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "checkIn": self = .checkIn
        case "approach": self = .approach
        case "estimate": self = .estimate
        case "handoff1": self = .handoff1
        case "handoff2": self = .handoff2
        case "handoff3": self = .handoff3
        case "gap1": self = .gap1
        case "gap2": self = .gap2
        default: self = .unknown(rawValue)
        }
    }

    public init(_ stage: NudgeStage) {
        self.init(rawValue: stage.rawValue)
    }

    public init(_ gap: NudgeGap) {
        self.init(rawValue: gap.rawValue)
    }
}

extension NudgeStageWire: Codable {
    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// `nudge.ringSurface` and `nudgePlan.surface`. `watch` stays unknown until #100 names it.
public enum NudgeRingSurface: Sendable, Equatable {
    case mac
    case iphone
    case none
    case unknown(String)

    public static let knownRawValues = ["mac", "iphone", "none"]

    public var rawValue: String {
        switch self {
        case .mac: "mac"
        case .iphone: "iphone"
        case .none: "none"
        case .unknown(let value): value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "mac": self = .mac
        case "iphone": self = .iphone
        case "none": self = .none
        default: self = .unknown(rawValue)
        }
    }
}

extension NudgeRingSurface: Codable {
    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// `answer.choice`. Same words as `CheckInAnswerKind`.
public enum NudgeChoice: Sendable, Equatable {
    case stillOnIt
    case willExtend
    case alreadyDone
    case paused
    case unknown(String)

    public static let knownRawValues = ["stillOnIt", "willExtend", "alreadyDone", "paused"]

    public var rawValue: String {
        switch self {
        case .stillOnIt: "stillOnIt"
        case .willExtend: "willExtend"
        case .alreadyDone: "alreadyDone"
        case .paused: "paused"
        case .unknown(let value): value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "stillOnIt": self = .stillOnIt
        case "willExtend": self = .willExtend
        case "alreadyDone": self = .alreadyDone
        case "paused": self = .paused
        default: self = .unknown(rawValue)
        }
    }
}

extension NudgeChoice: Codable {
    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// `answer.answeredOn`. Only `mac` is valid. Unknown strings decode so #100 can add `watch`.
public enum NudgeAnsweredOn: Sendable, Equatable {
    case mac
    case unknown(String)

    public static let knownRawValues = ["mac"]

    public var rawValue: String {
        switch self {
        case .mac: "mac"
        case .unknown(let value): value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "mac": self = .mac
        default: self = .unknown(rawValue)
        }
    }
}

extension NudgeAnsweredOn: Codable {
    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct WireNudge: Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: NudgeKind
    public var stage: NudgeStageWire
    public var ringSurface: NudgeRingSurface
    public var firedAt: Int

    public init(
        id: UUID,
        kind: NudgeKind,
        stage: NudgeStageWire,
        ringSurface: NudgeRingSurface,
        firedAt: Int
    ) {
        self.id = id
        self.kind = kind
        self.stage = stage
        self.ringSurface = ringSurface
        self.firedAt = firedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, stage, ringSurface, firedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let idRaw = try container.decode(String.self, forKey: .id)
        guard let id = UUID(uuidString: idRaw) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Invalid UUID")
        }
        self.id = id
        kind = try container.decode(NudgeKind.self, forKey: .kind)
        stage = try container.decode(NudgeStageWire.self, forKey: .stage)
        ringSurface = try container.decode(NudgeRingSurface.self, forKey: .ringSurface)
        firedAt = try container.decode(Int.self, forKey: .firedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.canonicalLowercase, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(stage, forKey: .stage)
        try container.encode(ringSurface, forKey: .ringSurface)
        try container.encode(firedAt, forKey: .firedAt)
    }
}

public struct WireNudgePlanItem: Codable, Equatable, Sendable {
    public var stage: NudgeStageWire
    public var fireAt: Int
    public var surface: NudgeRingSurface
    public var rings: Bool

    public init(stage: NudgeStageWire, fireAt: Int, surface: NudgeRingSurface, rings: Bool) {
        self.stage = stage
        self.fireAt = fireAt
        self.surface = surface
        self.rings = rings
    }
}

public struct WireReservedTicket: Codable, Equatable, Sendable {
    public var ticketId: UUID
    public var title: String
    public var estimatedSeconds: Int

    public init(ticketId: UUID, title: String, estimatedSeconds: Int) {
        self.ticketId = ticketId
        self.title = title
        self.estimatedSeconds = estimatedSeconds
    }

    enum CodingKeys: String, CodingKey {
        case ticketId, title, estimatedSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .ticketId)
        guard let ticketId = UUID(uuidString: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .ticketId,
                in: container,
                debugDescription: "Invalid UUID"
            )
        }
        self.ticketId = ticketId
        title = try container.decode(String.self, forKey: .title)
        estimatedSeconds = try container.decode(Int.self, forKey: .estimatedSeconds)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ticketId.canonicalLowercase, forKey: .ticketId)
        try container.encode(title, forKey: .title)
        try container.encode(estimatedSeconds, forKey: .estimatedSeconds)
    }
}

public enum NudgeWireDecision: Equatable, Sendable {
    case accept
    case invalidPayload
    case sessionMismatch
    case noActiveService
    case nudgeStale
    case noReservation
    case reservationChanged
    case unsupportedOp

    public var wireError: WireError? {
        switch self {
        case .accept: nil
        case .invalidPayload: .invalidPayload
        case .sessionMismatch: .sessionMismatch
        case .noActiveService: .noActiveService
        case .nudgeStale: .nudgeStale
        case .noReservation: .noReservation
        case .reservationChanged: .reservationChanged
        case .unsupportedOp: .unsupportedOp
        }
    }
}

/// Shape and version gate for nudge ops. Does not apply the ride. `#106` calls this.
public enum NudgeCommandEvaluating {
    /// 5, 10, and 15 minutes.
    public static let extendPresetSeconds: Set<Int> = [300, 600, 900]

    public static func versionGate(op: WireOp, receiverContract: Int) -> NudgeWireDecision? {
        guard let introduced = op.introducedIn else { return .unsupportedOp }
        if receiverContract < introduced { return .unsupportedOp }
        return nil
    }

    public static func evaluate(
        command: CommandPlaintext,
        serviceActive: Bool = true,
        openSessionId: UUID? = nil,
        currentNudgeId: UUID? = nil,
        reservedTicketId: UUID? = nil,
        receiverContract: Int = ContractVersion.contract
    ) -> NudgeWireDecision {
        if let blocked = versionGate(op: command.op, receiverContract: receiverContract) {
            return blocked
        }
        switch command.op {
        case .answer:
            return evaluateAnswer(
                command,
                openSessionId: openSessionId,
                currentNudgeId: currentNudgeId
            )
        case .boardReserved:
            return evaluateBoardReserved(
                command,
                serviceActive: serviceActive,
                openSessionId: openSessionId,
                reservedTicketId: reservedTicketId
            )
        case .presence:
            return evaluatePresence(command)
        case .pause, .resume, .still, .issueAndBoard, .pauseInputReport, .reestimate, .undoReestimate, .unknown:
            return .accept
        }
    }

    public static func ack(decision: NudgeWireDecision, commandId: UUID) -> AckPlaintext {
        if decision == .accept {
            return AckPlaintext(cmdId: commandId, ok: true)
        }
        return AckPlaintext(cmdId: commandId, ok: false, error: decision.wireError)
    }

    private static func evaluateAnswer(
        _ command: CommandPlaintext,
        openSessionId: UUID?,
        currentNudgeId: UUID?
    ) -> NudgeWireDecision {
        switch command.choice {
        case .willExtend:
            guard let addSeconds = command.addSeconds, extendPresetSeconds.contains(addSeconds) else {
                return .invalidPayload
            }
        case .stillOnIt, .alreadyDone, .paused:
            if command.addSeconds != nil { return .invalidPayload }
        case .unknown, .none:
            return .invalidPayload
        }
        guard command.answeredOn == .mac else { return .invalidPayload }
        guard command.nudgeId != nil else { return .invalidPayload }
        guard command.sessionId == openSessionId else { return .sessionMismatch }
        guard command.nudgeId == currentNudgeId else { return .nudgeStale }
        return .accept
    }

    private static func evaluateBoardReserved(
        _ command: CommandPlaintext,
        serviceActive: Bool,
        openSessionId: UUID?,
        reservedTicketId: UUID?
    ) -> NudgeWireDecision {
        guard command.ticketId != nil, command.sessionId == nil else { return .invalidPayload }
        guard serviceActive else { return .noActiveService }
        if openSessionId != nil { return .sessionMismatch }
        guard let reservedTicketId else { return .noReservation }
        guard command.ticketId == reservedTicketId else { return .reservationChanged }
        return .accept
    }

    private static func evaluatePresence(_ command: CommandPlaintext) -> NudgeWireDecision {
        guard command.pipVisible != nil, command.attending != nil, command.sessionId == nil else {
            return .invalidPayload
        }
        return .accept
    }
}
