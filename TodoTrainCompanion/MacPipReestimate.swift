import Foundation
import TodoTrainSync

/// PiP の位置確認。一段は声掛け、二段は割合、三段は回復運転と運転調整。
enum PipReestimateBand: Equatable, Sendable {
    case answers
    case progress
    case declare
}

enum PipReestimateDeclaration: Equatable, Sendable {
    case recovery
    case adjust
}

enum MacPipReestimateChoice: Equatable, Sendable {
    case recovery(progress: Double, committedRemainingSeconds: Int)
    case adjust(progress: Double)
}

enum PipBandCopy {
    static let positionCheck = "位置確認"
    static let share30 = "3割"
    static let share50 = "5割"
    static let share80 = "8割"
    static let recovery = "回復運転"
    static let adjust = "運転調整"
    static let undo = "取り消す"
    static let positionHeading = "位置確認"
    static let positionCheckHint = "進捗の割合を選びます。"
    static let shareHint = "その割合で次の選択へ進みます。"
    static let declareHint = "回復運転か運転調整を選びます。"
    static let undoHint = "直前の位置確認を取り消します。"
}

enum PipPositionWording {
    private static let arrivalFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func clock(_ date: Date) -> String {
        arrivalFormatter.string(from: date)
    }

    static func recoveryCaption(arrival: Date) -> String {
        "\(clock(arrival))着を目指す"
    }

    static func adjustCaption(arrival: Date) -> String {
        "\(clock(arrival))着にする"
    }
}

struct PipPositionDeclareLabels: Equatable, Sendable {
    var showsRecovery: Bool
    var recoveryCaption: String?
    var adjustCaption: String
}

/// `reestimate` / `undoReestimate` の平文を組み立てる。送信そのものはしない。
enum MacPipReestimate {
    static let progressAnswers = [0.3, 0.5, 0.8]
    static let undoSeconds = 5
    static let positionPromptID = "reestimate.position.v2"

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

    static func declareLabels(
        progress: Double,
        activeSeconds: TimeInterval,
        plannedBudgetSeconds: Int,
        remainingSeconds: Int,
        now: Date
    ) -> PipPositionDeclareLabels? {
        guard progressAnswers.contains(progress), activeSeconds >= 1, remainingSeconds >= 0 else { return nil }
        guard let projectedArrival = PositionReport.projectedArrival(
            now: now,
            activeSeconds: activeSeconds,
            progress: progress
        ) else {
            return nil
        }
        let showsRecovery = PositionReport.showsRecoveryDeclaration(
            activeSeconds: activeSeconds,
            plannedBudgetSeconds: plannedBudgetSeconds
        )
        let originalArrival = now.addingTimeInterval(TimeInterval(remainingSeconds))
        return PipPositionDeclareLabels(
            showsRecovery: showsRecovery,
            recoveryCaption: showsRecovery ? PipPositionWording.recoveryCaption(arrival: originalArrival) : nil,
            adjustCaption: PipPositionWording.adjustCaption(arrival: projectedArrival)
        )
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
        let progress: Double
        let committed: Int
        switch choice {
        case .recovery(let ratio, let remaining):
            guard progressAnswers.contains(ratio), remaining > 0 else { return nil }
            progress = ratio
            committed = remaining
        case .adjust(let ratio):
            guard progressAnswers.contains(ratio) else { return nil }
            guard let remaining = PositionReport.committedRemainingSeconds(
                activeSeconds: activeSeconds,
                progress: ratio
            ), remaining > 0 else { return nil }
            progress = ratio
            committed = remaining
        }
        return CommandPlaintext(
            id: id,
            op: .reestimate,
            sessionId: sessionId,
            at: at,
            build: build,
            contract: contract,
            minReadable: minReadable,
            progressAnswer: progress,
            committedRemainingSeconds: committed,
            mode: .positionReport,
            trigger: trigger(for: nudgeStage),
            promptId: positionPromptID,
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