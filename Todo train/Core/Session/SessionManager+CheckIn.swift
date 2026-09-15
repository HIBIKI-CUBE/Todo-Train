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

        consumePendingCheckIn(session, answer: answer, now: now)
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
                try? save()
                return
            case .none:
                break
            }

            guard !session.isPaused, session.remainingSeconds(at: now) > CheckInScheduling.overtimeGuardSeconds else {
                return
            }
            let elapsed = session.elapsedSeconds(at: now)
            guard CheckInScheduling.dueProgressOffset(
                offsets: session.checkInOffsets,
                firedCount: session.checkInFiredCount,
                elapsedSeconds: elapsed,
                remainingSeconds: session.remainingSeconds(at: now),
                hasPending: false
            ) != nil else { return }
            session.checkInFiredCount += 1
            bumpCompanionSync()
            try? save()
            reconcile(now: now)
            return
        }

        consumeIdleCabinStill(now: now)
    }

    func handleNotification(identifier: String, action: String) {
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
        guard !timetableFit(at: now).shouldSuppressAway else { return }

        let delay = CheckInScheduling.awayDelay(
            seed: session.id,
            salt: UInt64(session.checkInFiredCount) &+ 99
        )
        let fireAt = now.addingTimeInterval(delay)
        session.awayDueAt = fireAt
        try? save()
        if awayInterruptChannel == .localNotification {
            checkInNotifier.scheduleAway(
                sessionID: session.id,
                ticketTitle: session.ticket?.title ?? "切符",
                body: CheckInCopy.away,
                fireAt: fireAt
            )
        }
        armAwayFire(at: fireAt, sessionID: session.id)
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
        if changed { try? save() }
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
            checkInHapticTick += 1
            try? save()
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
            try? save()
            reconcile(now: now)
            return
        }
        if !session.isPaused {
            refreshProgressCheckInNotifications(for: session, now: now)
        }
    }
    // MARK: - Check-in

    func applyCheckInSchedule(to session: WorkSession, title: String, estimatedSeconds: Int) {
        session.checkInOffsetSeconds = CheckInScheduling.offsets(
            estimatedSeconds: estimatedSeconds,
            seed: session.id
        )
        session.checkInFiredCount = 0
        session.pendingCheckInKindRaw = nil
        session.awayDueAt = nil
        session.checkInPromptLine = CheckInCopy.fallback(title: title)
        session.checkInAnswersJSON = "[]"
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
            current.checkInPromptLine = line
            try? self.save()
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

    func consumePendingCheckIn(
        _ session: WorkSession,
        answer: CheckInAnswerKind,
        now: Date
    ) {
        guard let kind = session.pendingCheckIn else { return }
        var answers = session.checkInAnswers
        answers.append(CheckInAnswerRecord(kind: kind, answer: answer, answeredAt: now))
        session.checkInAnswers = answers
        if kind == .progress {
            session.checkInFiredCount += 1
        }
        session.pendingCheckIn = nil
    }

    func skipPendingCheckInForOvertime(_ session: WorkSession) {
        if session.pendingCheckIn == .progress {
            session.checkInFiredCount += 1
        }
        session.pendingCheckIn = nil
        session.awayDueAt = nil
        cancelAwayFireTask()
        checkInNotifier.cancel(sessionID: session.id)
        try? save()
    }

    func refreshPendingCheckIn(_ session: WorkSession, now: Date) {
        guard ownsDeviceSideEffects(session) else { return }
        guard settings.cabinAnnouncementsEnabled else {
            if session.pendingCheckIn != nil || session.awayDueAt != nil {
                session.pendingCheckIn = nil
                session.awayDueAt = nil
                cancelAwayFireTask()
                checkInNotifier.cancel(sessionID: session.id)
                try? save()
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

        let elapsed = session.elapsedSeconds(at: now)
        if CheckInScheduling.dueProgressOffset(
            offsets: session.checkInOffsets,
            firedCount: session.checkInFiredCount,
            elapsedSeconds: elapsed,
            remainingSeconds: remaining,
            hasPending: false
        ) != nil {
            session.pendingCheckIn = .progress
            session.awayDueAt = nil
            cancelAwayFireTask()
            checkInHapticTick += 1
            bumpCompanionSync()
            try? save()
            return
        }

        if let due = session.awayDueAt, due <= now {
            fireAwayInterrupt(session, now: now, presentAlert: true)
        }
    }

    func refreshProgressCheckInNotifications(for session: WorkSession, now: Date) {
        guard ownsDeviceSideEffects(session) else {
            checkInNotifier.cancel(sessionID: session.id)
            return
        }
        guard settings.cabinAnnouncementsEnabled else {
            checkInNotifier.cancel(sessionID: session.id)
            return
        }
        guard session.isOpen, !session.isPaused else {
            checkInNotifier.cancel(sessionID: session.id)
            return
        }
        if suppressProgressLocalNotifications {
            checkInNotifier.cancelProgress(sessionID: session.id)
            return
        }
        let elapsed = session.elapsedSeconds(at: now)
        let body = session.checkInPromptLine ?? CheckInCopy.fallback(title: session.ticket?.title ?? "")
        let title = session.ticket?.title ?? "切符"
        for (index, offset) in session.checkInOffsets.enumerated() {
            guard index >= session.checkInFiredCount else { continue }
            guard let fireAt = CheckInScheduling.wallFireAt(
                offset: offset,
                elapsedSeconds: elapsed,
                now: now
            ) else { continue }
            checkInNotifier.scheduleProgress(
                sessionID: session.id,
                index: index,
                ticketTitle: title,
                body: body,
                fireAt: fireAt
            )
        }
    }
}
