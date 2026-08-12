//
//  FocusTimerPhase.swift
//  Shared by app + TodoTrainWidget (Focus + Live Activity).
//

import SwiftUI

/// Countdown urgency relative to the session budget (not a fixed 1-minute rule).
enum FocusTimerPhase: Equatable {
    case cruise
    case approach
    case final
    case overtime

    init(remaining: TimeInterval, budgetSeconds: TimeInterval) {
        self = Self.phase(remaining: remaining, budgetSeconds: budgetSeconds)
    }

    static func phase(remaining: TimeInterval, budgetSeconds: TimeInterval) -> FocusTimerPhase {
        if remaining < 0 { return .overtime }
        let budget = max(budgetSeconds, 1)
        let finalThreshold = max(budget * 0.10, 30)
        let approachThreshold = max(budget * 0.25, 90)
        if remaining <= finalThreshold { return .final }
        if remaining <= approachThreshold { return .approach }
        return .cruise
    }

    var accentColor: Color {
        switch self {
        case .cruise:
            CockpitColors.ink
        case .approach:
            CockpitColors.approach
        case .final:
            CockpitColors.amber
        case .overtime:
            CockpitColors.red
        }
    }

    /// Glanceable state word; nil during comfortable cruise.
    var stateLabel: String? {
        switch self {
        case .cruise: nil
        case .approach: "終盤"
        case .final: "まもなく"
        case .overtime: "超過"
        }
    }

    var panelBorder: Color {
        switch self {
        case .cruise: CockpitColors.hairline
        case .approach: accentColor.opacity(0.45)
        case .final: CockpitColors.amber.opacity(0.55)
        case .overtime: CockpitColors.red.opacity(0.65)
        }
    }
}

/// Focus dashboard palette — usable in Widget extension without TrainTheme.
enum CockpitColors {
    static let ink = Color.white
    static let muted = Color.white.opacity(0.55)
    static let hairline = Color.white.opacity(0.14)
    static let track = Color.white.opacity(0.08)
    static let fill = Color.white.opacity(0.04)
    static let fillRaised = Color.white.opacity(0.07)
    static let approach = Color(red: 1.0, green: 0.82, blue: 0.42)
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.28)
    static let red = Color(red: 1.0, green: 0.42, blue: 0.40)
    static let green = Color(red: 0.35, green: 0.78, blue: 0.52)
}

/// How the primary clock should render (system-driven when counting down).
enum CockpitClockStyle: Equatable {
    case countdown(end: Date)
    case paused(remaining: TimeInterval)
    case alert
    case overtime
    case stale
}

enum CockpitPresentation {
    static func deadlineLabel(from snapshot: CockpitInstrumentSnapshot) -> String {
        if snapshot.headerState == "更新待ち" {
            return "予定の確認中"
        }
        return CockpitFormat.deadlineLabel(remaining: snapshot.remaining, deadline: snapshot.deadline)
    }
}

enum CockpitTimerInterval {
    /// `Text(timerInterval:)` / `ProgressView(timerInterval:)` crash if lowerBound > upperBound.
    static func countdown(to end: Date, from start: Date = .now) -> ClosedRange<Date> {
        if end >= start { return start...end }
        return start...start
    }

    static func progress(end: Date, budgetSeconds: Int) -> ClosedRange<Date> {
        let budget = TimeInterval(max(budgetSeconds, 1))
        let start = end.addingTimeInterval(-budget)
        if end >= start { return start...end }
        return end...end
    }
}

enum CockpitFormat {
    static func timerLabel(remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded())
        if total < 0 {
            let absTotal = abs(total)
            return String(format: "%d:%02d", absTotal / 60, absTotal % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Compact / width-limited Dynamic Island — drop seconds below 10 minutes when needed.
    static func shortTimerLabel(remaining: TimeInterval, limitedWidth: Bool) -> String {
        let total = max(0, Int(remaining.rounded()))
        let minutes = total / 60
        let seconds = total % 60
        if limitedWidth, minutes >= 10 {
            return "\(minutes)分"
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func deadlineLabel(remaining: TimeInterval, deadline: Date?) -> String {
        if remaining <= 0 { return "予定を超過" }
        guard let deadline else { return "予定 —" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "予定 HH:mm"
        return formatter.string(from: deadline)
    }

    static func progress(elapsed: TimeInterval, budget: TimeInterval) -> Double {
        let denom = max(budget, 1)
        return min(max(elapsed / denom, 0), 1)
    }

    static func accessibilityTimerValue(remaining: TimeInterval, isStale: Bool, isOvertime: Bool) -> String {
        if isStale { return "表示の更新を待っています" }
        if isOvertime || remaining < 0 { return "予定を超過" }
        let total = max(0, Int(remaining.rounded()))
        return "残り\(total / 60)分\(total % 60)秒"
    }
}

/// Shared glanceable model for Session LA and Alarm LA.
struct CockpitDisplayModel: Equatable {
    var title: String
    var clock: CockpitClockStyle
    var phase: FocusTimerPhase
    var headerState: String?
    var deadlineLabel: String
    var budgetSeconds: Int
    var pausedProgress: Double?
    var isStale: Bool
    var accessibilityTimer: String

    static func session(
        title: String,
        deadline: Date,
        budgetSeconds: Int,
        isOvertime: Bool,
        isStale: Bool,
        now: Date = .now
    ) -> CockpitDisplayModel {
        let snapshot = CockpitInstrumentSnapshot.session(
            deadline: deadline,
            budgetSeconds: budgetSeconds,
            isOvertime: isOvertime,
            isStale: isStale,
            now: now
        )
        let clock: CockpitClockStyle
        if isStale, !isOvertime {
            clock = .stale
        } else if isOvertime || snapshot.remaining <= 0 {
            clock = .overtime
        } else {
            clock = .countdown(end: deadline)
        }
        return CockpitDisplayModel(
            title: title,
            clock: clock,
            phase: snapshot.phase,
            headerState: snapshot.headerState,
            deadlineLabel: CockpitPresentation.deadlineLabel(from: snapshot),
            budgetSeconds: budgetSeconds,
            pausedProgress: nil,
            isStale: isStale,
            accessibilityTimer: CockpitFormat.accessibilityTimerValue(
                remaining: snapshot.remaining,
                isStale: isStale,
                isOvertime: isOvertime || snapshot.remaining <= 0
            )
        )
    }
}

struct CockpitInstrumentSnapshot: Equatable {
    let remaining: TimeInterval
    let progress: Double
    let phase: FocusTimerPhase
    let deadline: Date?
    let headerState: String?

    static func session(
        deadline: Date,
        budgetSeconds: Int,
        isOvertime: Bool,
        isStale: Bool = false,
        now: Date
    ) -> CockpitInstrumentSnapshot {
        let budget = TimeInterval(max(budgetSeconds, 1))
        let remaining = deadline.timeIntervalSince(now)
        let phase: FocusTimerPhase
        let header: String?
        if isStale, !isOvertime {
            phase = FocusTimerPhase(remaining: max(remaining, 0), budgetSeconds: budget)
            header = "更新待ち"
        } else if isOvertime {
            phase = .overtime
            header = FocusTimerPhase.overtime.stateLabel
        } else {
            phase = FocusTimerPhase(remaining: remaining, budgetSeconds: budget)
            header = phase.stateLabel
        }
        let elapsed = budget - remaining
        return CockpitInstrumentSnapshot(
            remaining: remaining,
            progress: CockpitFormat.progress(elapsed: elapsed, budget: budget),
            phase: phase,
            deadline: deadline,
            headerState: header
        )
    }
}

#if canImport(AlarmKit)
import AlarmKit

extension CockpitInstrumentSnapshot {
    static func alarm(
        mode: AlarmPresentationState.Mode,
        budgetSeconds: Int,
        now: Date
    ) -> CockpitInstrumentSnapshot {
        let budget = TimeInterval(max(budgetSeconds, 1))
        switch mode {
        case .countdown(let countdown):
            let remaining = countdown.fireDate.timeIntervalSince(now)
            let phase = FocusTimerPhase(remaining: remaining, budgetSeconds: budget)
            let elapsed = budget - remaining
            return CockpitInstrumentSnapshot(
                remaining: remaining,
                progress: CockpitFormat.progress(elapsed: elapsed, budget: budget),
                phase: phase,
                deadline: countdown.fireDate,
                headerState: phase.stateLabel
            )
        case .paused(let paused):
            let remaining = max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration)
            let phase = FocusTimerPhase(remaining: remaining, budgetSeconds: budget)
            return CockpitInstrumentSnapshot(
                remaining: remaining,
                progress: CockpitFormat.progress(
                    elapsed: paused.previouslyElapsedDuration,
                    budget: budget
                ),
                phase: phase,
                deadline: now.addingTimeInterval(remaining),
                headerState: "停車中"
            )
        case .alert:
            return CockpitInstrumentSnapshot(
                remaining: -1,
                progress: 1,
                phase: .overtime,
                deadline: nil,
                headerState: "超過"
            )
        @unknown default:
            return CockpitInstrumentSnapshot(
                remaining: 0,
                progress: 0,
                phase: .cruise,
                deadline: nil,
                headerState: nil
            )
        }
    }
}
#endif
