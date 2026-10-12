//
//  SessionSmallFace.swift
//  Shared by the app and TodoTrainWidget.
//
//  Watch Smart Stack presentation for the session Live Activity (ActivityFamily.small).
//  The instrument color is FocusTimerPhase — the same tokens as the Focus timer.
//  The hold lamp is a separate channel so a later call-out stage can change it
//  without rewriting the view. This type does not decide those stages.
//

import Foundation

/// Right-edge hold lamp. Unlit still occupies the slot; lit uses `phase.accentColor`.
nonisolated struct SessionSmallHoldLamp: Equatable {
    var isLit: Bool
    var phase: FocusTimerPhase
}

/// What the large instrument draws. Countdown is the only case that uses `Text(timerInterval:)`.
nonisolated enum SessionSmallReadout: Equatable {
    case countdown(end: Date)
    case paused(remaining: TimeInterval)
    case overtime
    case ended
    case stale

    var countsWithTimerInterval: Bool {
        if case .countdown = self { return true }
        return false
    }
}

/// Glanceable Smart Stack face. Built from the activity state the phone already pushes.
nonisolated struct SessionSmallFace: Equatable {
    var title: String
    var clock: CockpitClockStyle
    var phase: FocusTimerPhase
    var holdLamp: SessionSmallHoldLamp
    /// Set only while paused. The resume question stays on the Mac picture-in-picture.
    var pausedLabel: String?

    var readout: SessionSmallReadout {
        switch clock {
        case .countdown(let end):
            .countdown(end: end)
        case .paused(let remaining):
            .paused(remaining: remaining)
        case .overtime:
            .overtime
        case .alert:
            .ended
        case .stale:
            .stale
        }
    }

    static func make(
        title: String,
        deadline: Date,
        budgetSeconds: Int,
        isOvertime: Bool,
        isStale: Bool,
        isPaused: Bool = false,
        checkInPrompt: String? = nil,
        now: Date = .now
    ) -> SessionSmallFace {
        // Drop the prompt before the shared model so it cannot recolor the instrument.
        // Focus keeps the time-based phase; the lamp is the only prompt signal here.
        let model = CockpitDisplayModel.session(
            title: title,
            deadline: deadline,
            budgetSeconds: budgetSeconds,
            isOvertime: isOvertime,
            isStale: isStale,
            isPaused: isPaused,
            checkInPrompt: nil,
            now: now
        )
        let trimmed = checkInPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let holding = !trimmed.isEmpty && !isPaused && !isOvertime && !isStale
        return SessionSmallFace(
            title: model.title,
            clock: model.clock,
            phase: model.phase,
            holdLamp: SessionSmallHoldLamp(isLit: holding, phase: model.phase),
            pausedLabel: isPaused ? "停車中" : nil
        )
    }
}

/// Always On dims the small face. The countdown readout stays a timer interval.
nonisolated struct SessionSmallLuminance: Equatable {
    var title: Double
    var instrument: Double
    var lamp: Double

    static func resolve(reduced: Bool) -> SessionSmallLuminance {
        if reduced {
            return SessionSmallLuminance(title: 0.40, instrument: 0.62, lamp: 0.40)
        }
        return SessionSmallLuminance(title: 1, instrument: 1, lamp: 1)
    }
}
