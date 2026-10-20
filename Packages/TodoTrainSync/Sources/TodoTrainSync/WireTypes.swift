import Foundation

/// Wire constants from `sync/contract/constants.json`. Do not invent new values.
public enum SyncConstants: Sendable {
    public static let offerTtlSeconds = 120
    public static let confirmOverlapWindowSeconds = 15
    public static let cmdFifoMax = 8
}

/// HKDF info strings from `sync/contract/envelope.md`. Nothing else is added.
public enum HKDFInfo: Sendable {
    public static let enc = "todotrain/v1/enc"
    public static let tok = "todotrain/v1/tok"
    public static let cfm = "todotrain/v1/cfm"
}

public enum WireKind: String, Codable, Sendable, Equatable {
    case snap
    case cmd
    case ack
}

/// `op` on the wire. Unknown values must not throw; the host acks `unsupportedOp` and does not run them.
public enum WireOp: Sendable, Equatable {
    case pause
    case resume
    case still
    /// Issue a ticket and board it in one beat. Not arrive/extend.
    case issueAndBoard
    /// Reply to the nudge on the snap. Not arrive/extend.
    case answer
    /// Board the ticket in `snap.reserved`. `sessionId` is null.
    case boardReserved
    /// Mac `pipVisible` and `attending`. Sent only when either changes.
    case presence
    /// Mac samples of input during one pause. Stored seconds only rise.
    case pauseInputReport
    /// Commit a reestimate. The iPhone records it through the existing entry.
    case reestimate
    /// Undo the latest reestimate that is still in effect.
    case undoReestimate
    case unknown(String)

    /// Contract that introduced this op. Unknown ops have no version.
    public var introducedIn: Int? {
        switch self {
        case .pause, .resume, .still, .issueAndBoard: 3
        case .answer, .boardReserved, .presence: 5
        case .pauseInputReport: 12
        case .reestimate, .undoReestimate: 15
        case .unknown: nil
        }
    }

    public var rawValue: String {
        switch self {
        case .pause: "pause"
        case .resume: "resume"
        case .still: "still"
        case .issueAndBoard: "issueAndBoard"
        case .answer: "answer"
        case .boardReserved: "boardReserved"
        case .presence: "presence"
        case .pauseInputReport: "pauseInputReport"
        case .reestimate: "reestimate"
        case .undoReestimate: "undoReestimate"
        case .unknown(let value): value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "pause": self = .pause
        case "resume": self = .resume
        case "still": self = .still
        case "issueAndBoard": self = .issueAndBoard
        case "answer": self = .answer
        case "boardReserved": self = .boardReserved
        case "presence": self = .presence
        case "pauseInputReport": self = .pauseInputReport
        case "reestimate": self = .reestimate
        case "undoReestimate": self = .undoReestimate
        default: self = .unknown(rawValue)
        }
    }
}

extension WireOp: Codable {
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self.init(rawValue: value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum WireError: String, Codable, Sendable, Equatable {
    case pauseLimitReached
    case noActiveService
    case sessionMismatch
    case decryptFailed
    case notPaused
    /// Empty title, estimatedSeconds outside 60...3600, `addSeconds` outside the extend presets, or `pause.heldBy` other than `user` or `timetable`.
    case invalidPayload
    /// The receiver does not implement this `op`, or its contract predates the op.
    case unsupportedOp
    /// `nudgeId` is not the nudge on the current snap.
    case nudgeStale
    /// `boardReserved` arrived with no `reserved` ticket.
    case noReservation
    /// `ticketId` is not `reserved.ticketId`.
    case reservationChanged
}

/// `phase` on the wire. Unknown values must not crash; display conservatively.
public enum WirePhase: Sendable, Equatable {
    case idle
    case running
    case paused
    case overtime
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .idle: "idle"
        case .running: "running"
        case .paused: "paused"
        case .overtime: "overtime"
        case .unknown(let value): value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "idle": self = .idle
        case "running": self = .running
        case "paused": self = .paused
        case "overtime": self = .overtime
        default: self = .unknown(rawValue)
        }
    }

    public var isKnownRunningLike: Bool {
        switch self {
        case .running, .overtime: true
        default: false
        }
    }
}

extension WirePhase: Codable {
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self.init(rawValue: value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum WireJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

extension UUID {
    var canonicalLowercase: String { uuidString.lowercased() }

    var rfc4122: Data {
        withUnsafeBytes(of: uuid) { Data($0) }
    }

    static func parseCanonical(_ string: String) -> UUID? {
        UUID(uuidString: string)
    }
}
