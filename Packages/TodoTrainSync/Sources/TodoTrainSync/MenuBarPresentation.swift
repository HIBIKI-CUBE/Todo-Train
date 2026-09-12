import Foundation

public enum PairingStatus: Equatable, Sendable {
    case unpaired
    case paired
}

public enum ConnectionStatus: Equatable, Sendable {
    case connected
    case disconnected
}

public enum OutgoingPauseState: Equatable, Sendable {
    case idle
    case sending(cmdId: UUID)
    case failed(WireError)
}

public struct MenuBarInput: Equatable, Sendable {
    public var pairing: PairingStatus
    public var snap: SnapPlaintext?
    public var now: Int
    public var connection: ConnectionStatus
    public var outgoingPause: OutgoingPauseState

    public init(
        pairing: PairingStatus,
        snap: SnapPlaintext?,
        now: Int,
        connection: ConnectionStatus = .connected,
        outgoingPause: OutgoingPauseState = .idle
    ) {
        self.pairing = pairing
        self.snap = snap
        self.now = now
        self.connection = connection
        self.outgoingPause = outgoingPause
    }
}

/// Menu bar / popover state from snap + now. Copy follows docs/14 proposed defaults.
public struct MenuBarPresentation: Equatable, Sendable {
    /// Nil means icon-only on the bar.
    public var barTitle: String?
    public var remainingSeconds: Int?
    public var isOvertime: Bool
    public var canPause: Bool
    public var canResume: Bool
    public var isSending: Bool
    public var popoverTitle: String
    public var popoverDetail: String
    public var failureLine: String?

    public static let titleLimit = 10

    public static func make(_ input: MenuBarInput) -> MenuBarPresentation {
        if input.pairing == .unpaired {
            return MenuBarPresentation(
                barTitle: nil,
                remainingSeconds: nil,
                isOvertime: false,
                canPause: false,
                canResume: false,
                isSending: false,
                popoverTitle: "iPhone で QR を出す",
                popoverDetail: "画面を Mac に向ける",
                failureLine: nil
            )
        }

        let sending: Bool
        if case .sending = input.outgoingPause { sending = true } else { sending = false }

        let failureLine: String?
        if case .failed(let error) = input.outgoingPause {
            failureLine = Self.failureCopy(error)
        } else {
            failureLine = nil
        }

        guard let snap = input.snap else {
            return idle(
                sending: sending,
                failureLine: failureLine,
                disconnected: input.connection == .disconnected
            )
        }

        switch snap.phase {
        case .idle, .unknown:
            return idle(
                sending: sending,
                failureLine: failureLine,
                disconnected: input.connection == .disconnected
            )
        case .paused:
            let remaining = snap.remainingSeconds(at: input.now)
            let detail: String
            if input.connection == .disconnected {
                detail = "iPhone とつながっていない"
            } else if sending {
                detail = "iPhone に送った"
            } else {
                detail = "停車中"
            }
            return MenuBarPresentation(
                barTitle: "停車中",
                remainingSeconds: remaining,
                isOvertime: (remaining ?? 1) <= 0,
                canPause: false,
                canResume: true,
                isSending: sending,
                popoverTitle: snap.title ?? "停車中",
                popoverDetail: detail,
                failureLine: failureLine
            )
        case .running, .overtime:
            let remaining = snap.remainingSeconds(at: input.now)
            let overtime = snap.phase == .overtime || (remaining ?? 1) <= 0
            let truncated = truncatedTitle(snap.title)
            let remainingLabel = remaining.map(formatRemaining) ?? ""
            let bar = [truncated, remainingLabel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            let detail: String
            if input.connection == .disconnected {
                detail = "iPhone とつながっていない"
            } else if sending {
                detail = "iPhone に送った"
            } else if overtime {
                detail = "超過 \(remainingLabel)"
            } else {
                detail = remainingLabel
            }
            return MenuBarPresentation(
                barTitle: bar.isEmpty ? truncated : bar,
                remainingSeconds: remaining,
                isOvertime: overtime,
                canPause: true,
                canResume: false,
                isSending: sending,
                popoverTitle: snap.title ?? "",
                popoverDetail: detail,
                failureLine: failureLine
            )
        }
    }

    public static func truncatedTitle(_ title: String?) -> String? {
        guard let title, !title.isEmpty else { return nil }
        if title.count <= titleLimit { return title }
        return String(title.prefix(titleLimit)) + "…"
    }

    public static func formatRemaining(_ seconds: Int) -> String {
        let sign = seconds < 0 ? "+" : ""
        let abs = abs(seconds)
        let minutes = abs / 60
        let remainder = abs % 60
        return "\(sign)\(minutes):\(String(format: "%02d", remainder))"
    }

    public static func failureCopy(_ error: WireError) -> String {
        switch error {
        case .pauseLimitReached: "停車できません（停車上限）"
        case .noActiveService: "乗務なし"
        case .sessionMismatch: "乗務が変わった"
        case .decryptFailed: "送れなかった"
        case .notPaused: "停車中ではない"
        }
    }

    private static func idle(
        sending: Bool,
        failureLine: String?,
        disconnected: Bool
    ) -> MenuBarPresentation {
        MenuBarPresentation(
            barTitle: nil,
            remainingSeconds: nil,
            isOvertime: false,
            canPause: false,
            canResume: false,
            isSending: sending,
            popoverTitle: "乗務なし",
            popoverDetail: disconnected ? "iPhone とつながっていない" : "乗務なし",
            failureLine: failureLine
        )
    }
}
