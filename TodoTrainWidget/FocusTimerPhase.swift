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

enum CockpitFormat {
    static func timerLabel(remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded())
        if total < 0 {
            let absTotal = abs(total)
            return String(format: "%d:%02d", absTotal / 60, absTotal % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
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
        now: Date
    ) -> CockpitInstrumentSnapshot {
        let budget = TimeInterval(max(budgetSeconds, 1))
        let remaining = deadline.timeIntervalSince(now)
        let phase: FocusTimerPhase = isOvertime
            ? .overtime
            : FocusTimerPhase(remaining: remaining, budgetSeconds: budget)
        let elapsed = budget - remaining
        return CockpitInstrumentSnapshot(
            remaining: remaining,
            progress: CockpitFormat.progress(elapsed: elapsed, budget: budget),
            phase: phase,
            deadline: deadline,
            headerState: phase.stateLabel
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
