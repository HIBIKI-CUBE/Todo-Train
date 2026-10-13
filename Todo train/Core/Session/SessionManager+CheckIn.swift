//
//  SessionManager+CheckIn.swift
//  Todo train
//

import Foundation
import Observation
import SwiftData
import TodoTrainSync
#if canImport(UIKit)
import UIKit
#endif

extension SessionManager {
    /// 車内放送 4 択. `willExtend` only acknowledges; Focus shows the extend panel.
    func answerCheckIn(_ answer: CheckInAnswerKind, now: Date? = nil) throws {
        let now = now ?? clock.now
        guard let session = activeSession, session.isOpen else {
            throw SessionError.noActiveSession
        }
        guard session.pendingCheckIn != nil else { return }
        guard uiCanAnswer(session: session) else {
            releaseAnsweredCheckInPrompt(session, now: now)
            return
        }

        let stamp = uiNudgeStamp(session: session)
        consumePendingCheckIn(
            session,
            answer: answer,
            now: now,
            nudgeID: stamp?.0,
            answeredOn: stamp == nil ? nil : "iphone",
            answeredStage: stamp?.1.rawValue,
            recordKind: stamp.map { CheckInKind.recorded(for: $0.1) }
        )
        session.awayDueAt = nil
        noteCabinActivity(now: now, clearPendingIdle: true)
        bumpCompanionSync()
        try save()

        switch answer {
        case .stillOnIt, .willExtend:
            reconcile(now: now)
            refreshProgressCheckInNotifications(for: session, now: now)
        case .paused:
            try pause(now: now)
        case .alreadyDone:
            try arrive(resolution: .alreadyDone, now: now)
        case .board:
            break
        }
    }

    /// Mac `still` cmd. Consumes progress or service-idle (even if iPhone has not promoted pending yet).
    func acknowledgeCabinStill(now: Date? = nil) {
        let now = now ?? clock.now
        if let session = activeSession, session.isOpen {
            switch session.pendingCheckIn {
            case .progress:
                try? answerCheckIn(.stillOnIt, now: now)
                return
            case .away:
                cancelAwayWatch(now: now)
                bumpCompanionSync()
                return
            case .idle:
                session.pendingCheckIn = nil
                bumpCompanionSync()
                _ = saveBestEffort()
                return
            case .overrun, .gap, .none:
                break
            }

            guard !session.isPaused, session.remainingSeconds(at: now) > CheckInScheduling.overtimeGuardSeconds else {
                return
            }
            let elapsed = nudgeWorkingSeconds(for: session, now: now)
            guard CheckInScheduling.dueProgressOffset(
                offsets: session.checkInOffsets,
                firedCount: session.checkInFiredCount,
                elapsedSeconds: elapsed,
                remainingSeconds: session.remainingSeconds(at: now),
                hasPending: false
            ) != nil else { return }
            session.checkInFiredCount += 1
            bumpCompanionSync()
            _ = saveBestEffort()
            reconcile(now: now)
            return
        }

        if dismissArrivalGapIfShowing(now: now) { return }
        consumeIdleCabinStill(now: now)
    }

    func handleNotification(identifier: String, action: String) {
        if PassengerNotification.isPassenger(identifier)
            || (TimetableNotification.isTimetable(identifier) && action == PassengerNotification.boardAction) {
            boardPassenger()
            return
        }
        if TimetableNotification.isTimetable(identifier) {
            handleTimetableNotification(identifier: identifier, action: action)
            return
        }
        handleCheckInNotification(identifier: identifier, action: action)
    }

    /// Unlocked background only. Locked / end-bell LA / cabin-off: no away watch.
    func beginAwayWatch(now: Date? = nil) {
        if deviceLock.isLocked {
            cancelAwayWatch(now: now)
            return
        }
        let now = now ?? clock.now
        guard settings.cabinAnnouncementsEnabled else { return }
        guard awayInterruptChannel != .none else { return }
        guard let session = activeSession, session.isOpen, !session.isPaused else { return }
        guard ownsDeviceSideEffects(session) else { return }
        guard session.remainingSeconds(at: now) > 0 else { return }
        guard session.pendingCheckIn == nil else { return }
        guard session.awayDueAt == nil else { return }
        guard fetchOpenPassengerRide() == nil else { return }
        guard !timetableFit(at: now).shouldSuppressAway else { return }

        let delay = CheckInScheduling.awayDelay(
            seed: session.id,
            salt: UInt64(session.checkInFiredCount) &+ 99
        )
        let fireAt = now.addingTimeInterval(delay)
        session.awayDueAt = fireAt
        guard saveBestEffort() else {
            session.awayDueAt = nil
            return
        }
        if awayInterruptChannel == .localNotification, iphonePosts(.away, turn: 0, now: now) {
            checkInNotifier.scheduleAway(
                sessionID: session.id,
                ticketTitle: session.ticket?.title ?? "切符",
                body: CheckInCopy.away,
                fireAt: fireAt
            )
        }
        armAwayFire(at: fireAt, sessionID: session.id)
        publishOffscreenAssignment(now: now)
    }

    /// Lock screen: drop the watch. Do not promote a pending `.away` panel.
    func cancelAwayWatch(now: Date? = nil) {
        let now = now ?? clock.now
        cancelAwayFireTask()
        guard let session = activeSession, session.isOpen else { return }
        var changed = false
        if session.awayDueAt != nil {
            session.awayDueAt = nil
            changed = true
        }
        if session.pendingCheckIn == .away {
            session.pendingCheckIn = nil
            changed = true
        }
        if changed { _ = saveBestEffort() }
        checkInNotifier.cancel(sessionID: session.id)
        if !session.isPaused, session.remainingSeconds(at: now) > 0, ownsDeviceSideEffects(session) {
            refreshProgressCheckInNotifications(for: session, now: now)
            refreshLiveActivity(for: session, now: now)
        }
    }

    /// Foreground: clear the watch without turning away into a Focus 4-choice.
    func endAwayWatch(now: Date? = nil) {
        let now = now ?? clock.now
        cancelAwayWatch(now: now)
        reconcile(now: now)
    }

    func handleCheckInNotification(identifier: String, action: String) {
        guard CheckInNotification.isCheckIn(identifier) else { return }
        if CheckInNotification.isIdle(identifier) {
            if action == CheckInNotification.stillOnItAction {
                acknowledgeCabinStill()
            } else {
                refreshIdleCabin(now: clock.now)
            }
            return
        }
        reconcile()
        guard ownsActiveRide else { return }
        guard let session = activeSession, session.isOpen, !session.isPaused else { return }
        guard session.remainingSeconds(at: clock.now) > CheckInScheduling.overtimeGuardSeconds else { return }

        let isAway = CheckInNotification.isAway(identifier)
        if isAway {
            if action == CheckInNotification.pauseAction {
                try? pause()
            }
            return
        }

        if session.pendingCheckIn == nil {
            session.pendingCheckIn = .progress
            if session.awayDueAt != nil {
                session.awayDueAt = nil
                cancelAwayFireTask()
            }
            presentation.noteCheckInHaptic()
            _ = saveBestEffort()
        }

        switch action {
        case CheckInNotification.pauseAction:
            try? answerCheckIn(.paused)
        case CheckInNotification.stillOnItAction:
            guard session.pendingCheckIn == .progress else { return }
            try? answerCheckIn(.stillOnIt)
        default:
            break
        }
    }

    func pauseRide(sessionID: UUID) {
        guard activeSession?.id == sessionID else { return }
        try? pause()
    }

    func continueRide(sessionID: UUID) {
        guard activeSession?.id == sessionID else { return }
        acknowledgeCabinStill()
    }

    /// Settings toggle for 車内放送 — apply immediately to the active ride.
    func syncCabinAnnouncementsWithSettings(now: Date? = nil) {
        let now = now ?? clock.now
        bumpCompanionSync()
        guard let session = activeSession, session.isOpen else {
            if !settings.cabinAnnouncementsEnabled {
                clearIdleCabin(touch: false, now: now)
            }
            refreshIdleCabin(now: now)
            return
        }
        guard ownsDeviceSideEffects(session) else {
            checkInNotifier.cancelAll()
            return
        }
        if !settings.cabinAnnouncementsEnabled {
            session.pendingCheckIn = nil
            session.awayDueAt = nil
            cancelAwayFireTask()
            checkInNotifier.cancel(sessionID: session.id)
            _ = saveBestEffort()
            reconcile(now: now)
            return
        }
        if !session.isPaused {
            refreshProgressCheckInNotifications(for: session, now: now)
        }
    }
    // MARK: - Check-in

    func applyCheckInSchedule(to session: WorkSession, title: String, estimatedSeconds: Int) {
        if let offset = NudgePlanner.checkInOffset(estimatedSeconds: estimatedSeconds, rideID: session.id) {
            session.checkInOffsetSeconds = [offset]
            session.checkInFraction = offset / TimeInterval(max(estimatedSeconds, 1))
        } else {
            session.checkInOffsetSeconds = []
            session.checkInFraction = nil
        }
        session.checkInFiredCount = 0
        session.pendingCheckInKindRaw = nil
        session.awayDueAt = nil
        session.checkInPromptLine = CheckInCopy.fallback(title: title)
        session.checkInAnswersJSON = "[]"
        session.nudgeFiredStagesRaw = []
        session.nudgePendingStageRaw = nil
        session.nudgeAnsweredAt = nil
        session.nudgeAnsweredOnRaw = nil
        session.nudgeEventsJSON = "[]"
    }

    func requestCheckInPrompt(for session: WorkSession, title: String, estimatedMinutes: Int) {
        guard settings.cabinAnnouncementsEnabled else { return }
        guard ownsDeviceSideEffects(session) else { return }
        let sessionID = session.id
        Task { @MainActor [weak self] in
            guard let self else { return }
            let lines = await self.coachingEngine.checkInLines(
                title: title,
                estimatedMinutes: estimatedMinutes
            )
            guard let line = lines.first.map(Self.sanitizeCheckInLine), !line.isEmpty else { return }
            guard let current = self.activeSession, current.id == sessionID, current.isOpen else { return }
            let previousLine = current.checkInPromptLine
            current.checkInPromptLine = line
            guard self.saveBestEffort() else {
                current.checkInPromptLine = previousLine
                return
            }
            self.refreshProgressCheckInNotifications(for: current, now: self.clock.now)
        }
    }

    private static func sanitizeCheckInLine(_ raw: String) -> String {
        let collapsed = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return "" }
        if collapsed.count <= 40 { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: 40)
        return String(collapsed[..<end])
    }

    /// 答えの出た問いかけが画面に残っているとき、表示だけ閉じる。新しい答えは足さない。
    func releaseAnsweredCheckInPrompt(_ session: WorkSession, now: Date) {
        guard session.pendingCheckIn != nil else { return }
        guard !uiCanAnswer(session: session) else { return }
        if session.pendingCheckIn == .progress, session.checkInFiredCount == 0 {
            session.checkInFiredCount = 1
        }
        session.pendingCheckIn = nil
        session.awayDueAt = nil
        cancelAwayFireTask()
        bumpCompanionSync()
        _ = saveBestEffort()
        reconcile(now: now)
        guard session.isOpen else { return }
        refreshRideSideEffects(for: session, now: now)
    }

    func consumePendingCheckIn(
        _ session: WorkSession,
        answer: CheckInAnswerKind,
        now: Date,
        nudgeID: String? = nil,
        addSeconds: Int? = nil,
        answeredOn: String? = nil,
        answeredStage: String? = nil,
        recordKind: CheckInKind? = nil
    ) {
        guard let pending = session.pendingCheckIn else { return }
        let kind = recordKind ?? pending
        var answers = session.checkInAnswers
        answers.append(
            CheckInAnswerRecord(
                kind: kind,
                answer: answer,
                answeredAt: now,
                nudgeID: nudgeID,
                addSeconds: addSeconds,
                answeredOn: answeredOn,
                answeredStage: answeredStage
            )
        )
        session.checkInAnswers = answers
        if nudgeID != nil {
            session.nudgeAnsweredAt = now
            session.nudgeAnsweredOnRaw = answeredOn
        }
        if pending == .progress {
            session.checkInFiredCount += 1
        }
        session.pendingCheckIn = nil
        if nudgeID != nil, visibleNudgeStage(session) == nil {
            session.nudgePendingStageRaw = nil
        }
    }

    func skipPendingCheckInForOvertime(_ session: WorkSession) {
        if session.pendingCheckIn == .progress {
            session.checkInFiredCount += 1
        }
        session.pendingCheckIn = nil
        session.awayDueAt = nil
        cancelAwayFireTask()
        checkInNotifier.cancel(sessionID: session.id)
        _ = saveBestEffort()
    }

    func refreshPendingCheckIn(_ session: WorkSession, now: Date) {
        guard ownsDeviceSideEffects(session) else { return }
        if fetchOpenPassengerRide() != nil {
            if session.pendingCheckIn != nil || session.awayDueAt != nil {
                session.pendingCheckIn = nil
                session.awayDueAt = nil
                cancelAwayFireTask()
                checkInNotifier.cancel(sessionID: session.id)
                _ = saveBestEffort()
            }
            return
        }
        guard settings.cabinAnnouncementsEnabled else {
            if session.pendingCheckIn != nil || session.awayDueAt != nil {
                session.pendingCheckIn = nil
                session.awayDueAt = nil
                cancelAwayFireTask()
                checkInNotifier.cancel(sessionID: session.id)
                _ = saveBestEffort()
            }
            return
        }

        let remaining = session.remainingSeconds(at: now)
        if remaining <= CheckInScheduling.overtimeGuardSeconds {
            return
        }

        if session.pendingCheckIn != nil {
            return
        }

        if let due = session.awayDueAt, due <= now {
            fireAwayInterrupt(session, now: now, presentAlert: true)
        }
    }

    func refreshProgressCheckInNotifications(for session: WorkSession, now: Date) {
        _ = now
        checkInNotifier.cancelProgress(sessionID: session.id)
    }
}
