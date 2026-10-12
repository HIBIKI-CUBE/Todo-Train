import Foundation

/// Wire `pendingCabin`. Unknown values must not crash; Mac ignores them.
public enum CabinKind: Sendable, Equatable {
    case progress
    case away
    case idle
    /// Estimate and the handoffs after it. Stage 1 stays `progress`.
    case overrun
    /// Blank after arrival.
    case gap
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .progress: "progress"
        case .away: "away"
        case .idle: "idle"
        case .overrun: "overrun"
        case .gap: "gap"
        case .unknown(let value): value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "progress": self = .progress
        case "away": self = .away
        case "idle": self = .idle
        case "overrun": self = .overrun
        case "gap": self = .gap
        default: self = .unknown(rawValue)
        }
    }
}

extension CabinKind: Codable {
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self.init(rawValue: value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Where Mac should put a cabin prompt. Notification is reserved for idle / no-ride.
public enum CabinDelivery: Equatable, Sendable {
    case pip
    case notification
    case ignore

    public static func surface(kind: CabinKind?, hasRide: Bool) -> CabinDelivery {
        switch kind {
        case .progress:
            hasRide ? .pip : .notification
        case .idle:
            .notification
        case .overrun, .gap:
            // #107 and #108 choose the surface. Until then, do not notify.
            .ignore
        case .away, .unknown, .none:
            .ignore
        }
    }
}

public enum CabinCopy {
    /// Progress interrupt on Mac PiP. Title is already on the card.
    public static let prompt = "まだ乗ってる？"
    /// Service is open but there is no ride.
    public static let idle = "運行は続いてる"
    public static let still = "続行"
}
