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
    /// Progress interrupt on an older iPhone that does not send `nudge`.
    public static let prompt = "まだ乗ってる？"
    /// Service is open but there is no ride.
    public static let idle = "運行は続いてる"
    public static let still = "続行"
    public static let extend = "延長"
    public static let arrived = "到着済み"
    public static let pause = "停車"
    /// Closes the extend presets and returns to the four answers.
    public static let back = "戻る"
    public static let extendFive = "+5"
    public static let extendTen = "+10"
    public static let extendFifteen = "+15"
    public static let iphone = "iPhone"
    public static let mac = "Mac"

    /// Dispatcher question. The same line at every stage.
    public static func question(title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "まだこれ？" }
        return "まだ『\(trimmed)』？"
    }

    public static func extendSending(minutes: Int) -> String {
        "延長 +\(minutes)（送信中）"
    }

    public static func extendRecorded(minutes: Int, on device: String) -> String {
        "延長 +\(minutes)（\(device)）"
    }

    public static func actionRecorded(_ action: String, on device: String) -> String {
        "\(action)（\(device)）"
    }

    public static let stillHint = "この乗務を続けます。"
    public static let extendHint = "延長の分数を出します。"
    public static let arrivedHint = "到着として iPhone に送ります。"
    public static let pauseHint = "この乗務を停車します。"
    public static let extendFiveHint = "5分の延長を iPhone に送ります。"
    public static let extendTenHint = "10分の延長を iPhone に送ります。"
    public static let extendFifteenHint = "15分の延長を iPhone に送ります。"
    public static let backHint = "分数の選択を閉じます。"
    public static let restoreHint = "端から乗務を出します。"
    public static let questionHint = "答えを選ぶと iPhone に送られます。"
    public static let extendPickerHint = "5分、10分、15分の延長を選べます。"
}
