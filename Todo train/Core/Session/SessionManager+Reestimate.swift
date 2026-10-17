//
//  SessionManager+Reestimate.swift
//  Todo train
//

import Foundation
import SwiftData
import SwiftUI
import TodoTrainSync

extension SessionManager {
    struct ReestimateRequest: Equatable {
        var trigger: ReestimateTrigger
        var surface: ReestimateSurface
        var input: ReestimateInput
        var remoteWillExtendReceived: Bool
    }

    enum FocusUndoKind: Equatable {
        case reestimate
        case pause
    }

    struct FocusUndoOffer: Equatable {
        var kind: FocusUndoKind
        var message: String
        var eventID: UUID
        var expiresAt: Date
    }

    func presentReestimate(
        trigger: ReestimateTrigger,
        surface: ReestimateSurface,
        input: ReestimateInput = .touch,
        remoteWillExtendReceived: Bool = false
    ) {
        reestimateRequest = ReestimateRequest(
            trigger: trigger,
            surface: surface,
            input: input,
            remoteWillExtendReceived: remoteWillExtendReceived
        )
    }

    func dismissReestimate() {
        reestimateRequest = nil
    }

    func commitReestimate(
        mode: ReestimateMode,
        progressAnswer: Double?,
        committedRemainingSeconds: Int,
        shownBandLowSeconds: Int?,
        shownBandHighSeconds: Int?,
        detailsOpened: Bool,
        promptId: String,
        now: Date? = nil
    ) throws {
        let now = now ?? clock.now
        try refusePassengerDriving()
        guard let session = activeSession, session.isOpen else {
            throw SessionError.noActiveSession
        }
        guard !session.isPaused else {
            throw SessionError.notRunning
        }
        guard let request = reestimateRequest else { return }

        let active = session.elapsedSeconds(at: now)
        let overrun = max(0, active - TimeInterval(session.activeBudgetSeconds))
        let index = (session.reestimateEvents.filter { $0.undoneAt == nil }.count) + 1

        if let last = session.reestimateEvents.last,
           last.undoneAt == nil,
           now.timeIntervalSince(last.committedAt) < 60,
           last.committedRemainingSeconds == committedRemainingSeconds,
           last.mode == mode,
           last.progressAnswer == progressAnswer {
            dismissReestimate()
            return
        }

        let record = ReestimateEventRecord(
            reestimateIndex: index,
            trigger: request.trigger,
            surface: request.surface,
            input: request.input,
            promptId: promptId,
            mode: mode,
            committedAt: now,
            activeSeconds: active,
            overrunSeconds: overrun,
            progressAnswer: progressAnswer,
            committedRemainingSeconds: committedRemainingSeconds,
            shownBandLowSeconds: shownBandLowSeconds,
            shownBandHighSeconds: shownBandHighSeconds,
            detailsOpened: detailsOpened,
            remoteWillExtendReceived: request.remoteWillExtendReceived
        )
        var events = session.reestimateEvents
        events.append(record)
        session.reestimateEvents = events

        session.currentBudgetSeconds = Int(active.rounded()) + committedRemainingSeconds
        noteCabinActivity(now: now, clearPendingIdle: true)
        suppressedEndBellSessionIDs.remove(session.id)
        dismissReestimate()
        try save()
        reconcile(now: now)
        refreshRideSideEffects(for: session, now: now)

        focusUndoOffer = FocusUndoOffer(
            kind: .reestimate,
            message: "見積もり直しを取り消す",
            eventID: record.id,
            expiresAt: now.addingTimeInterval(5)
        )
        scheduleFocusUndoExpiry(at: focusUndoOffer!.expiresAt)
    }

    func undoReestimate(eventID: UUID, now: Date? = nil) throws {
        let now = now ?? clock.now
        guard let session = activeSession else { return }
        guard let index = session.reestimateEvents.firstIndex(where: { $0.id == eventID }) else { return }
        guard session.reestimateEvents[index].undoneAt == nil else { return }

        let priorBudget = budgetBeforeReestimate(session: session, excludingEventID: eventID)
        session.currentBudgetSeconds = priorBudget

        var all = session.reestimateEvents
        all[index].undoneAt = now
        session.reestimateEvents = all
        focusUndoOffer = nil
        try save()
        reconcile(now: now)
        if let session = activeSession {
            refreshRideSideEffects(for: session, now: now)
        }
    }

    func undoPauseFromFocus(pauseID: UUID, now: Date? = nil) throws {
        let now = now ?? clock.now
        guard phase == .paused, let session = activeSession, session.isPaused else { return }
        if let pause = session.pauses.first(where: { $0.id == pauseID }) {
            pause.undoneAt = now
        }
        reopenPausedSession(session, now: now)
        try save()
        reconcile(now: now)
        refreshRideSideEffects(for: session, now: now, endBell: .skip)
    }

    private func budgetBeforeReestimate(session: WorkSession, excludingEventID: UUID) -> Int {
        let activeEvents = session.reestimateEvents.filter { $0.undoneAt == nil && $0.id != excludingEventID }
        if let last = activeEvents.last {
            return Int(last.activeSeconds.rounded()) + last.committedRemainingSeconds
        }
        return session.budgetSecondsAtStart
    }

    func scheduleFocusUndoExpiry(at date: Date) {
        focusUndoTask?.cancel()
        let delay = max(0, date.timeIntervalSince(clock.now))
        focusUndoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            if focusUndoOffer?.expiresAt == date {
                focusUndoOffer = nil
            }
        }
    }

    func reestimateSurface(isLandscape: Bool) -> ReestimateSurface {
        isLandscape ? .iphoneLandscape : .iphonePortrait
    }
}
