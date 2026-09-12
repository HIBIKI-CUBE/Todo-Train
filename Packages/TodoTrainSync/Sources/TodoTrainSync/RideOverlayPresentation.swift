import Foundation

/// Budget-ratio urgency. Same thresholds as `FocusTimerPhase` on iOS (not a fixed 1-minute rule).
public enum RideOverlayTimerPhase: String, Equatable, Sendable {
    case cruise
    case approach
    case final
    case overtime
}

/// Mac ride PiP from the same snap input as the menu bar. Hidden when unpaired or idle.
public struct RideOverlayPresentation: Equatable, Sendable {
    public var isVisible: Bool
    public var title: String
    public var remainingLabel: String
    public var progress: Double
    public var timerPhase: RideOverlayTimerPhase
    public var isOvertime: Bool
    public var isPaused: Bool
    public var canPause: Bool
    public var canResume: Bool
    public var isSending: Bool
    public var failureLine: String?
    public var statusLine: String?
    public var peekTitle: String
    /// Progress 車内放送 on the PiP. Nil when idle.
    public var cabinPrompt: String?

    public static let peekTitleLimit = 6

    public static let hidden = RideOverlayPresentation(
        isVisible: false,
        title: "",
        remainingLabel: "",
        progress: 0,
        timerPhase: .cruise,
        isOvertime: false,
        isPaused: false,
        canPause: false,
        canResume: false,
        isSending: false,
        failureLine: nil,
        statusLine: nil,
        peekTitle: "",
        cabinPrompt: nil
    )

    public static func make(_ input: MenuBarInput) -> RideOverlayPresentation {
        let bar = MenuBarPresentation.make(input)
        guard input.pairing == .paired, let snap = input.snap else {
            return .hidden
        }
        switch snap.phase {
        case .idle, .unknown:
            return .hidden
        case .paused, .running, .overtime:
            break
        }

        let remaining = snap.remainingSeconds(at: input.now)
        let progress = Self.progress(
            remaining: remaining,
            estimated: snap.estimatedSeconds,
            overtime: bar.isOvertime
        )
        let title: String
        if let snapTitle = snap.title, !snapTitle.isEmpty {
            title = snapTitle
        } else if snap.phase == .paused {
            title = "停車中"
        } else {
            title = ""
        }
        let remainingLabel = remaining.map(MenuBarPresentation.formatRemaining) ?? ""
        let statusLine: String?
        if input.connection == .disconnected {
            statusLine = "リレーが切れた"
        } else if bar.isSending {
            statusLine = "iPhone に送った"
        } else {
            statusLine = nil
        }

        let cabin = CabinInterruptWatch.evaluate(
            snap: input.snap,
            now: input.now,
            localEnabled: input.cabinEnabledLocal,
            optimisticFiredCount: input.optimisticFiredCount
        )
        let cabinPrompt = (cabin.showsPip && !bar.isSending) ? cabin.prompt : nil

        return RideOverlayPresentation(
            isVisible: true,
            title: title,
            remainingLabel: remainingLabel,
            progress: progress,
            timerPhase: timerPhase(
                remaining: remaining,
                estimated: snap.estimatedSeconds,
                overtime: bar.isOvertime
            ),
            isOvertime: bar.isOvertime,
            isPaused: snap.phase == .paused,
            canPause: bar.canPause,
            canResume: bar.canResume,
            isSending: bar.isSending,
            failureLine: bar.failureLine,
            statusLine: statusLine,
            peekTitle: truncatedPeekTitle(title),
            cabinPrompt: cabinPrompt
        )
    }

    public static func progress(
        remaining: Int?,
        estimated: Int?,
        overtime: Bool
    ) -> Double {
        if overtime { return 1 }
        guard let remaining, let estimated, estimated > 0 else { return 0 }
        let elapsed = Double(estimated - remaining)
        return min(1, max(0, elapsed / Double(estimated)))
    }

    /// Same cutoffs as iOS `FocusTimerPhase.phase(remaining:budgetSeconds:)`.
    public static func timerPhase(
        remaining: Int?,
        estimated: Int?,
        overtime: Bool
    ) -> RideOverlayTimerPhase {
        if overtime { return .overtime }
        guard let remaining else { return .cruise }
        let remainingTime = TimeInterval(remaining)
        if remainingTime < 0 { return .overtime }
        let budget = TimeInterval(max(estimated ?? 1, 1))
        let finalThreshold = max(budget * 0.10, 30)
        let approachThreshold = max(budget * 0.25, 90)
        if remainingTime <= finalThreshold { return .final }
        if remainingTime <= approachThreshold { return .approach }
        return .cruise
    }

    public static func truncatedPeekTitle(_ title: String) -> String {
        if title.isEmpty { return "乗務" }
        if title.count <= peekTitleLimit { return title }
        return String(title.prefix(peekTitleLimit))
    }
}
