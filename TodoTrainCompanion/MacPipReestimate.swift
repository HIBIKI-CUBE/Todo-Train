import Foundation
import TodoTrainSync

/// PiP の見積もり直し。一段は声掛け、二段は割合、三段は残りの分。
enum PipReestimateBand: Equatable, Sendable {
    case answers
    case progress
    case minutes
}

enum MacPipReestimateChoice: Equatable, Sendable {
    case progress(Double)
    case minutes(Int)
}

enum PipBandCopy {
    static let reestimate = "見積もり直す"
    static let share30 = "3割"
    static let share50 = "5割"
    static let share80 = "8割"
    static let byMinutes = "分で決める"
    static let undo = "取り消し"
    static let progressHeading = "進捗は何割？"
    static let minutesHeading = "残りは何分？"
    static let reestimateHint = "進捗の割合を選びます。"
    static let shareHint = "その割合で見積もり直します。"
    static let byMinutesHint = "残りの分数を選びます。"
    static let minutesHint = "その分数を残りにして見積もり直します。"
    static let undoHint = "直前の見積もり直しを取り消します。"

    static func minutes(_ value: Int) -> String {
        "\(value)分"
    }
}

/// `reestimate` / `undoReestimate` の平文を組み立てる。送信そのものはしない。
enum MacPipReestimate {
    /// 四等分の帯に収まる残り分。発券ゲージの停止位置から短い・中・長を取る。
    static let minuteAnswers = [5, 15, 30, 60]
    static let progressAnswers = [0.3, 0.5, 0.8]
    static let undoSeconds = 5
    static let progressPromptID = "reestimate.progress.v1"
    static let minutesPromptID = "reestimate.remaining.v1"

    static func trigger(for stage: NudgeStageWire?) -> WireReestimateTrigger {
        switch stage {
        case .checkIn:
            return .checkIn
        case .estimate, .handoff1, .handoff2, .handoff3:
            return .planEnd
        case .approach, .gap1, .gap2, .unknown, .none:
            return .manual
        }
    }

    static func command(
        id: UUID,
        sessionId: UUID,
        at: Int,
        activeSeconds: TimeInterval,
        nudgeStage: NudgeStageWire?,
        choice: MacPipReestimateChoice,
        build: WireBuildInfo?,
        contract: Int,
        minReadable: Int
    ) -> CommandPlaintext? {
        let mode: WireReestimateMode
        let progressAnswer: Double?
        let remaining: Int
        let promptId: String
        switch choice {
        case .progress(let ratio):
            guard progressAnswers.contains(ratio) else { return nil }
            guard let committed = PositionReport.committedRemainingSeconds(
                activeSeconds: activeSeconds,
                progress: ratio
            ) else { return nil }
            mode = .progress
            progressAnswer = ratio
            remaining = committed
            promptId = progressPromptID
        case .minutes(let minutes):
            guard minuteAnswers.contains(minutes), minutes > 0 else { return nil }
            mode = .minutesOnly
            progressAnswer = nil
            remaining = minutes * 60
            promptId = minutesPromptID
        }
        return CommandPlaintext(
            id: id,
            op: .reestimate,
            sessionId: sessionId,
            at: at,
            build: build,
            contract: contract,
            minReadable: minReadable,
            progressAnswer: progressAnswer,
            committedRemainingSeconds: remaining,
            mode: mode,
            trigger: trigger(for: nudgeStage),
            promptId: promptId,
            surface: .macPip,
            input: .click
        )
    }

    static func undoCommand(
        id: UUID,
        sessionId: UUID,
        at: Int,
        build: WireBuildInfo?,
        contract: Int,
        minReadable: Int
    ) -> CommandPlaintext {
        CommandPlaintext(
            id: id,
            op: .undoReestimate,
            sessionId: sessionId,
            at: at,
            build: build,
            contract: contract,
            minReadable: minReadable
        )
    }
}
