import Foundation

/// Who is holding a pause. Snap `pauseHeldBy` uses every known value.
/// A Mac `pause` may send only `user` and `timetable`.
public enum PauseHeldBy: Sendable, Equatable {
    case user
    case timetable
    case alarm
    /// Wire value `switch`. Parking the open ride for another ticket.
    case rideSwitch
    case passenger
    case unknown(String)

    public static let knownRawValues = ["user", "timetable", "alarm", "switch", "passenger"]
    /// Values a Mac `pause` may carry. Anything else is `invalidPayload`.
    public static let pauseCommandRawValues = ["user", "timetable"]

    public var rawValue: String {
        switch self {
        case .user: "user"
        case .timetable: "timetable"
        case .alarm: "alarm"
        case .rideSwitch: "switch"
        case .passenger: "passenger"
        case .unknown(let value): value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "user": self = .user
        case "timetable": self = .timetable
        case "alarm": self = .alarm
        case "switch": self = .rideSwitch
        case "passenger": self = .passenger
        default: self = .unknown(rawValue)
        }
    }

    /// `user` and `timetable` only. Missing is not rejected here; the resolver infers it.
    public var isPauseCommandValue: Bool {
        switch self {
        case .user, .timetable: true
        case .alarm, .rideSwitch, .passenger, .unknown: false
        }
    }
}

extension PauseHeldBy: Codable {
    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// How a `pause` command becomes a stored reason.
///
/// A missing `heldBy` is an older Mac. It is the person's pause (`user`).
/// A timetable boundary does not change the reason. The clock does not pause.
public enum PauseReasonResolving {
    public enum Record: Equatable, Sendable {
        case explicit(PauseHeldBy)
        case inferred(PauseHeldBy)
        case invalidPayload
    }

    public static func rejectsPauseCommand(_ heldBy: PauseHeldBy?) -> Bool {
        guard let heldBy else { return false }
        return !heldBy.isPauseCommandValue
    }

    /// Missing `heldBy` is `user`. Explicit `user` and `timetable` stay as sent.
    public static func resolve(heldBy: PauseHeldBy?) -> Record {
        if let heldBy {
            if heldBy.isPauseCommandValue { return .explicit(heldBy) }
            return .invalidPayload
        }
        return .inferred(.user)
    }
}
