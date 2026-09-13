import Foundation

/// Public plaintext from `GET /v1/hint/:pairingId`. Revs only; no ciphertext.
public struct HintPlaintext: Codable, Equatable, Sendable {
    public var snapRev: Int
    public var ackRev: Int
    public var cmdCount: Int

    public init(snapRev: Int, ackRev: Int, cmdCount: Int) {
        self.snapRev = snapRev
        self.ackRev = ackRev
        self.cmdCount = cmdCount
    }
}

public struct HintGetResult: Equatable, Sendable {
    public var notModified: Bool
    public var hint: HintPlaintext?
    public var etag: String?

    public init(notModified: Bool, hint: HintPlaintext? = nil, etag: String? = nil) {
        self.notModified = notModified
        self.hint = hint
        self.etag = etag
    }
}

public struct HintCatchUp: Equatable, Sendable {
    public var snap: Bool
    public var ack: Bool
    public var cmd: Bool

    public var needsFetch: Bool { snap || ack || cmd }

    public init(snap: Bool, ack: Bool, cmd: Bool) {
        self.snap = snap
        self.ack = ack
        self.cmd = cmd
    }
}

public enum HintSubscriber: Equatable, Sendable {
    case mac
    case iphone
}

public enum HintPollOutcome: Equatable, Sendable {
    case ignore
    case remember(hint: HintPlaintext, etag: String)
    case catchUp(HintCatchUp, hint: HintPlaintext, etag: String)
    case stop
}

/// Disconnect-only hint watching. Not a connected-path catch-up loop.
public enum HintPolling: Sendable {
    public static let intervalNanoseconds: UInt64 = 5_000_000_000

    public static func shouldPoll(isPaired: Bool, connection: ConnectionStatus) -> Bool {
        isPaired && connection == .disconnected
    }

    public static func etag(for hint: HintPlaintext) -> String {
        "\"\(hint.snapRev)-\(hint.ackRev)-\(hint.cmdCount)\""
    }

    public static func catchUp(
        previous: HintPlaintext?,
        current: HintPlaintext,
        subscriber: HintSubscriber
    ) -> HintCatchUp {
        let snapChanged = previous.map { $0.snapRev != current.snapRev } ?? (current.snapRev > 0)
        let ackChanged = previous.map { $0.ackRev != current.ackRev } ?? (current.ackRev > 0)
        switch subscriber {
        case .mac:
            return HintCatchUp(snap: snapChanged, ack: ackChanged, cmd: false)
        case .iphone:
            return HintCatchUp(snap: false, ack: false, cmd: current.cmdCount > 0)
        }
    }

    public static func outcome(
        subscriber: HintSubscriber,
        previous: HintPlaintext?,
        result: HintGetResult
    ) -> HintPollOutcome {
        outcome(
            subscriber: subscriber,
            previous: previous,
            status: result.notModified ? 304 : 200,
            hint: result.hint,
            responseETag: result.etag
        )
    }

    public static func outcome(
        subscriber: HintSubscriber,
        previous: HintPlaintext?,
        status: Int,
        hint: HintPlaintext?,
        responseETag: String?
    ) -> HintPollOutcome {
        if status == 304 { return .ignore }
        if status == 429 || status == 401 { return .stop }
        guard status == 200, let hint else { return .ignore }
        let tag = responseETag ?? etag(for: hint)
        let next = catchUp(previous: previous, current: hint, subscriber: subscriber)
        if next.needsFetch {
            return .catchUp(next, hint: hint, etag: tag)
        }
        return .remember(hint: hint, etag: tag)
    }
}
