import Foundation

/// `reestimate.mode`. Unknown strings decode and are `invalidPayload`.
public enum WireReestimateMode: Sendable, Equatable {
    case progress
    case minutesOnly
    case positionReport
    case unknown(String)

    public static let knownRawValues = ["progress", "minutesOnly", "positionReport"]

    public var rawValue: String {
        switch self {
        case .progress: "progress"
        case .minutesOnly: "minutesOnly"
        case .positionReport: "positionReport"
        case .unknown(let value): value
        }
    }

    public var isKnown: Bool {
        if case .unknown = self { return false }
        return true
    }

    public init(rawValue: String) {
        switch rawValue {
        case "progress": self = .progress
        case "minutesOnly": self = .minutesOnly
        case "positionReport": self = .positionReport
        default: self = .unknown(rawValue)
        }
    }
}

extension WireReestimateMode: Codable {
    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// `reestimate.trigger`. Unknown strings decode and are `invalidPayload`.
public enum WireReestimateTrigger: Sendable, Equatable {
    case checkIn
    case planEnd
    case manual
    case unknown(String)

    public static let knownRawValues = ["checkIn", "planEnd", "manual"]

    public var rawValue: String {
        switch self {
        case .checkIn: "checkIn"
        case .planEnd: "planEnd"
        case .manual: "manual"
        case .unknown(let value): value
        }
    }

    public var isKnown: Bool {
        if case .unknown = self { return false }
        return true
    }

    public init(rawValue: String) {
        switch rawValue {
        case "checkIn": self = .checkIn
        case "planEnd": self = .planEnd
        case "manual": self = .manual
        default: self = .unknown(rawValue)
        }
    }
}

extension WireReestimateTrigger: Codable {
    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// `reestimate.surface`. Unknown strings decode and are `invalidPayload`.
public enum WireReestimateSurface: Sendable, Equatable {
    case iphonePortrait
    case iphoneLandscape
    case macPip
    case unknown(String)

    public static let knownRawValues = ["iphonePortrait", "iphoneLandscape", "macPip"]

    public var rawValue: String {
        switch self {
        case .iphonePortrait: "iphonePortrait"
        case .iphoneLandscape: "iphoneLandscape"
        case .macPip: "macPip"
        case .unknown(let value): value
        }
    }

    public var isKnown: Bool {
        if case .unknown = self { return false }
        return true
    }

    public init(rawValue: String) {
        switch rawValue {
        case "iphonePortrait": self = .iphonePortrait
        case "iphoneLandscape": self = .iphoneLandscape
        case "macPip": self = .macPip
        default: self = .unknown(rawValue)
        }
    }
}

extension WireReestimateSurface: Codable {
    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// `reestimate.input`. Unknown strings decode and are `invalidPayload`.
public enum WireReestimateInput: Sendable, Equatable {
    case touch
    case click
    case keyboard
    case trackpadScroll
    case unknown(String)

    public static let knownRawValues = ["touch", "click", "keyboard", "trackpadScroll"]

    public var rawValue: String {
        switch self {
        case .touch: "touch"
        case .click: "click"
        case .keyboard: "keyboard"
        case .trackpadScroll: "trackpadScroll"
        case .unknown(let value): value
        }
    }

    public var isKnown: Bool {
        if case .unknown = self { return false }
        return true
    }

    public init(rawValue: String) {
        switch rawValue {
        case "touch": self = .touch
        case "click": self = .click
        case "keyboard": self = .keyboard
        case "trackpadScroll": self = .trackpadScroll
        default: self = .unknown(rawValue)
        }
    }
}

extension WireReestimateInput: Codable {
    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// `home.signal`. Matches `PunctualityJudgment.HomeSignalState`. Unknown strings stay.
public enum WireHomeSignal: Sendable, Equatable {
    case green
    case yellow
    case off
    case unknown(String)

    public static let knownRawValues = ["green", "yellow", "off"]

    public var rawValue: String {
        switch self {
        case .green: "green"
        case .yellow: "yellow"
        case .off: "off"
        case .unknown(let value): value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "green": self = .green
        case "yellow": self = .yellow
        case "off": self = .off
        default: self = .unknown(rawValue)
        }
    }

    public init(_ state: PunctualityJudgment.HomeSignalState) {
        switch state {
        case .green: self = .green
        case .yellow: self = .yellow
        case .off: self = .off
        }
    }
}

extension WireHomeSignal: Codable {
    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// `home.judgedEstimate.kind`. Unknown strings stay and do not fail the snap.
public enum WireJudgedEstimateKind: Sendable, Equatable {
    case original
    case reestimate
    case unknown(String)

    public static let knownRawValues = ["original", "reestimate"]

    public var rawValue: String {
        switch self {
        case .original: "original"
        case .reestimate: "reestimate"
        case .unknown(let value): value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "original": self = .original
        case "reestimate": self = .reestimate
        default: self = .unknown(rawValue)
        }
    }
}

extension WireJudgedEstimateKind: Codable {
    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Which committed estimate the home band uses. `activeSeconds` is the running
/// seconds of that reestimate. Original estimates omit both optional keys.
public struct WireJudgedEstimate: Equatable, Sendable {
    public var kind: WireJudgedEstimateKind
    public var reestimateIndex: Int?
    public var activeSeconds: Double?

    public init(
        kind: WireJudgedEstimateKind,
        reestimateIndex: Int? = nil,
        activeSeconds: Double? = nil
    ) {
        self.kind = kind
        if kind == .reestimate {
            self.reestimateIndex = reestimateIndex
            self.activeSeconds = activeSeconds
        } else {
            self.reestimateIndex = nil
            self.activeSeconds = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case reestimateIndex
        case activeSeconds
    }
}

extension WireJudgedEstimate: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(WireJudgedEstimateKind.self, forKey: .kind)
        if kind == .reestimate {
            reestimateIndex = try container.decodeIfPresent(Int.self, forKey: .reestimateIndex)
            activeSeconds = try container.decodeIfPresent(Double.self, forKey: .activeSeconds)
        } else {
            reestimateIndex = nil
            activeSeconds = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        if kind == .reestimate {
            try container.encodeIfPresent(reestimateIndex, forKey: .reestimateIndex)
            try container.encodeIfPresent(activeSeconds, forKey: .activeSeconds)
        }
    }
}

/// Home band, signal, judged estimate, and seal sample. Omitted when not riding.
public struct WireHome: Codable, Equatable, Sendable {
    public var startSeconds: Double
    public var endSeconds: Double
    public var signal: WireHomeSignal
    public var judgedEstimate: WireJudgedEstimate
    /// Riding seal sample. Absent once the signal is off.
    public var sealLuxury: Double?

    public init(
        startSeconds: Double,
        endSeconds: Double,
        signal: WireHomeSignal,
        judgedEstimate: WireJudgedEstimate,
        sealLuxury: Double? = nil
    ) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.signal = signal
        self.judgedEstimate = judgedEstimate
        self.sealLuxury = sealLuxury
    }
}
