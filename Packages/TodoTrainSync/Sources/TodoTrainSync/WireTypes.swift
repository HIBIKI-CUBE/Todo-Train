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

public enum WireOp: String, Codable, Sendable, Equatable {
    case pause
    case resume
}

public enum WireError: String, Codable, Sendable, Equatable {
    case pauseLimitReached
    case noActiveService
    case sessionMismatch
    case decryptFailed
    case notPaused
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
