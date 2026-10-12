//
//  SessionManager+Nudge.swift
//  Todo train
//
//  iPhone owns the nudge stages. The planner is pure; this file stores and applies them.
//

import Foundation
import SwiftData
import TodoTrainSync

extension SessionManager {
    struct NudgeSnapFields {
        var nudge: WireNudge?
        var plan: [WireNudgePlanItem]?
        var reserved: WireReservedTicket?
        var pendingCabin: CabinKind?
    }

    func noteIphoneScene(_ active: Bool) {
        let changed = iphoneSceneActive != active
        iphoneSceneActive = active
        guard changed, let session = activeSession, session.isOpen, !session.isPaused else { return }
        refreshProgressCheckInNotifications(for: session, now: clock.now)
        reconcile()
    }

    func syncNudge(_ session: WorkSession, now: Date) {
        if nudgeObservedSessionID != session.id {
            nudgeObservedSessionID = session.id
            nudgeObservedElapsed = nil
            nudgeObservedStageRaw = nil
        }
        let input = nudgeInput(for: session, now: now)
        let evaluation = NudgePlanner.evaluate(input)
        placeCheckIn(on: session, input: input)
        guard !evaluation.isFrozen else { return }

        let previous = nudgeObservedElapsed
        nudgeObservedElapsed = evaluation.workingElapsed
        let freshTick = previous.map { evaluation.workingElapsed - $0 <= 2 } ?? false
        let marks = nudgeMarks(input)
        var fired = Set(session.nudgeFiredStagesRaw)
        var changed = false
        for mark in marks where mark.offset <= evaluation.workingElapsed && !fired.contains(mark.stage.rawValue) {
            session.nudgeFiredStagesRaw.append(mark.stage.rawValue)
            fired.insert(mark.stage.rawValue)
            changed = true
            if mark.stage == .checkIn {
                promoteCheckIn(session)
            } else if freshTick, let previous, mark.offset > previous {
                let ring = NudgePlanner.ring(stage: mark.stage, on: input)
                if ring.rings, ring.surface == .iphone, mark.stage != .estimate {
                    nudgeRingTick += 1
                }
            }
        }
        let visible = visibleNudgeStage(session)
        if session.nudgePendingStageRaw != visible?.rawValue {
            session.nudgePendingStageRaw = visible?.rawValue
            changed = true
        }
        let stageRaw = evaluation.current?.rawValue
        if nudgeObservedStageRaw != stageRaw {
            nudgeObservedStageRaw = stageRaw
            changed = true
        }
        guard changed else { return }
        bumpCompanionSync()
        _ = saveBestEffort()
        refreshLiveActivity(for: session, now: now)
    }

    func nudgeSnapFields(now: Date) -> NudgeSnapFields {
        let reserved = reservedNextTicket().map {
            WireReservedTicket(ticketId: $0.id, title: $0.title, estimatedSeconds: $0.estimatedSeconds)
        }
        guard let session = activeSession, session.isOpen, phase != .idle else {
            return NudgeSnapFields(nudge: nil, plan: nil, reserved: reserved, pendingCabin: nil)
        }
        let input = nudgeInput(for: session, now: now)
        let evaluation = NudgePlanner.evaluate(input)
        let stage = visibleNudgeStage(session)
        let nudge = stage.map { wireNudge(stage: $0, session: session, input: input) }
        let plan = evaluation.plan.map { item in
            WireNudgePlanItem(
                stage: NudgeStageWire(item.stage),
                fireAt: Int(item.fireAt.timeIntervalSince1970),
                surface: NudgeRingSurface(rawValue: item.surface.rawValue),
                rings: item.rings
            )
        }
        let cabin: CabinKind? = {
            guard let stage else { return nil }
            if stage == .checkIn { return .progress }
            if stage.number >= 3 { return .overrun }
            return nil
        }()
        return NudgeSnapFields(
            nudge: nudge,
            plan: plan.isEmpty ? nil : plan,
            reserved: reserved,
            pendingCabin: cabin
        )
    }

    var nudgeCurrentStage: NudgeStage? {
        guard let session = activeSession, session.isOpen, phase != .idle else { return nil }
        return NudgePlanner.evaluate(nudgeInput(for: session, now: clock.now)).current
    }

    /// Winning extension, as the instrument names it.
    var nudgeExtensionCaption: String? {
        guard let session = activeSession else { return nil }
        guard let stamp = session.checkInAnswers.last(where: {
            $0.answer == .willExtend && $0.addSeconds != nil
        }) else { return nil }
        let minutes = max(0, (stamp.addSeconds ?? 0) / 60)
        let device = stamp.answeredOn == "mac" ? "Mac" : "iPhone"
        return "延長 +\(minutes)（\(device)）"
    }

    func applyNudgeCommand(_ command: CommandPlaintext) -> AckPlaintext {
        let now = clock.now
        let openID: UUID? = {
            guard let session = activeSession, session.isOpen, phase != .idle else { return nil }
            return session.id
        }()
        let decision = NudgeCommandEvaluating.evaluate(
            command: command,
            serviceActive: activeServiceDay?.isOpen == true,
            openSessionId: openID,
            currentNudgeId: openID.flatMap { _ in activeSession.flatMap(commandNudgeID) },
            reservedTicketId: reservedNextTicket()?.id
        )
        guard decision == .accept else {
            return NudgeCommandEvaluating.ack(decision: decision, commandId: command.id)
        }
        switch command.op {
        case .presence:
            macPipVisible = command.pipVisible == true
            macAttending = command.attending == true
            reconcile(now: now)
            bumpCompanionSync()
            return AckPlaintext(cmdId: command.id, ok: true)
        case .boardReserved:
            return applyBoardReserved(command)
        case .answer:
            return applyRemoteAnswer(command, now: now)
        default:
            return NudgeCommandEvaluating.ack(decision: .unsupportedOp, commandId: command.id)
        }
    }

    func recordStandingPauseAnswer(on session: WorkSession, now: Date) {
        guard let stage = visibleNudgeStage(session) else { return }
        let nudgeID = NudgeSession.idString(sessionID: session.id, stage: stage)
        guard nudgeStamp(on: session, nudgeID: nudgeID) == nil else { return }
        appendNudgeStamp(
            on: session,
            kind: .progress,
            answer: .paused,
            at: now,
            nudgeID: nudgeID,
            addSeconds: nil,
            answeredOn: "iphone"
        )
        _ = saveBestEffort()
    }

    func fillWillExtendStamp(on session: WorkSession, addSeconds: Int) {
        var answers = session.checkInAnswers
        guard let index = answers.lastIndex(where: {
            $0.answer == .willExtend && $0.addSeconds == nil && $0.answeredOn != "mac"
        }) else { return }
        answers[index].addSeconds = addSeconds
        session.checkInAnswers = answers
    }

    func nudgeInstrument(for session: WorkSession, now: Date, remaining: TimeInterval) -> (
        prompt: String?,
        phaseRaw: String?,
        keepsTimerColor: Bool
    ) {
        let away = (!session.isPaused && session.pendingCheckIn == .away) ? CheckInCopy.away : nil
        guard !session.isPaused, remaining > 0 else {
            return (away, nil, false)
        }
        let current = NudgePlanner.evaluate(nudgeInput(for: session, now: now)).current
        let prompt: String?
        let keeps: Bool
        if session.pendingCheckIn == .progress {
            prompt = session.checkInPromptLine
            keeps = true
        } else {
            prompt = away
            keeps = false
        }
        let phaseRaw = current == .approach ? NudgeStage.approach.rawValue : nil
        return (prompt, phaseRaw, keeps)
    }

    func nudgeWorkingSeconds(for session: WorkSession, now: Date) -> TimeInterval {
        NudgePlanner.workingElapsed(nudgeInput(for: session, now: now))
    }

    func nudgeInput(for session: WorkSession, now: Date) -> NudgeRideInput {
        var foreground: [NudgeSurface] = []
        if iphoneSceneActive { foreground.append(.iphone) }
        if macPipVisible { foreground.append(.mac) }
        let passenger = fetchOpenPassengerRide()
        let passengerWhileRunning = passenger != nil && !session.isPaused
        return NudgeRideInput(
            startedAt: session.startedAt,
            pausedAccumulated: completedPauseSeconds(session),
            pausedAt: session.pausedAt,
            isPaused: session.isPaused,
            passengerAccumulated: 0,
            passengerSince: passengerWhileRunning ? passenger?.boardedAt : nil,
            isPassenger: passengerWhileRunning,
            estimatedSeconds: session.budgetSecondsAtStart,
            rideID: session.id,
            extensions: session.extensions.map {
                NudgeExtension(
                    addedSeconds: $0.addedSeconds,
                    createdAt: $0.createdAt,
                    workingSeconds: $0.workingSeconds
                )
            },
            alarmKitEndBell: isAlarmKitEndBellActive,
            foreground: foreground,
            macAttending: macAttending,
            now: now
        )
    }

    private func applyBoardReserved(_ command: CommandPlaintext) -> AckPlaintext {
        guard let ticket = reservedNextTicket(), ticket.id == command.ticketId else {
            return NudgeCommandEvaluating.ack(decision: .noReservation, commandId: command.id)
        }
        let at = Date(timeIntervalSince1970: TimeInterval(command.at))
        do {
            try board(ticket: ticket, now: at)
            return AckPlaintext(cmdId: command.id, ok: true)
        } catch let error as SessionError {
            return AckPlaintext(cmdId: command.id, ok: false, error: nudgeWireError(for: error))
        } catch {
            return AckPlaintext(cmdId: command.id, ok: false, error: .invalidPayload)
        }
    }

    private func applyRemoteAnswer(_ command: CommandPlaintext, now: Date) -> AckPlaintext {
        guard let session = activeSession, session.isOpen,
              let choice = command.choice,
              let answer = CheckInAnswerKind(choice),
              let stage = commandNudgeStage(session)
        else {
            return NudgeCommandEvaluating.ack(decision: .nudgeStale, commandId: command.id)
        }
        let nudgeID = NudgeSession.idString(sessionID: session.id, stage: stage)
        let fired = nudgeFiredDate(stage: stage, session: session, now: now)
        let commandAt = Date(timeIntervalSince1970: TimeInterval(command.at))
        switch NudgeSession.decide(
            existing: nudgeStamp(on: session, nudgeID: nudgeID),
            choice: answer,
            addSeconds: command.addSeconds,
            firedAt: fired,
            commandAt: commandAt,
            now: now
        ) {
        case .duplicate:
            return AckPlaintext(cmdId: command.id, ok: true)
        case .stale:
            return NudgeCommandEvaluating.ack(decision: .nudgeStale, commandId: command.id)
        case .apply(let at):
            do {
                try applyNudgeAnswer(
                    answer,
                    addSeconds: command.addSeconds,
                    at: at,
                    stage: stage,
                    nudgeID: nudgeID,
                    answeredOn: "mac",
                    session: session
                )
                return AckPlaintext(cmdId: command.id, ok: true)
            } catch {
                return AckPlaintext(cmdId: command.id, ok: false, error: .invalidPayload)
            }
        }
    }

    func applyNudgeAnswer(
        _ answer: CheckInAnswerKind,
        addSeconds: Int?,
        at: Date,
        stage: NudgeStage,
        nudgeID: String,
        answeredOn: String,
        session: WorkSession
    ) throws {
        switch answer {
        case .willExtend:
            let seconds = TimeInterval(addSeconds ?? 0)
            try extend(by: seconds, now: at)
            appendNudgeStamp(
                on: session,
                kind: .progress,
                answer: .willExtend,
                at: at,
                nudgeID: nudgeID,
                addSeconds: addSeconds,
                answeredOn: answeredOn
            )
            try save()
        case .alreadyDone:
            appendNudgeStamp(
                on: session,
                kind: stage == .checkIn ? .progress : .progress,
                answer: .alreadyDone,
                at: at,
                nudgeID: nudgeID,
                addSeconds: nil,
                answeredOn: answeredOn
            )
            if session.pendingCheckIn != nil {
                session.pendingCheckIn = nil
            }
            try arrive(resolution: .alreadyDone, now: at)
        case .paused:
            appendNudgeStamp(
                on: session,
                kind: .progress,
                answer: .paused,
                at: at,
                nudgeID: nudgeID,
                addSeconds: nil,
                answeredOn: answeredOn
            )
            let origin: PauseOrigin = answeredOn == "mac" ? .mac : .iphone
            try pause(now: at, heldBy: .user, pausedOn: origin)
        case .stillOnIt:
            if session.pendingCheckIn == .progress {
                consumePendingCheckIn(
                    session,
                    answer: .stillOnIt,
                    now: at,
                    nudgeID: nudgeID,
                    answeredOn: answeredOn
                )
            } else {
                appendNudgeStamp(
                    on: session,
                    kind: .progress,
                    answer: .stillOnIt,
                    at: at,
                    nudgeID: nudgeID,
                    addSeconds: nil,
                    answeredOn: answeredOn
                )
            }
            session.awayDueAt = nil
            noteCabinActivity(now: at, clearPendingIdle: true)
            bumpCompanionSync()
            try save()
            reconcile(now: at)
        }
    }

    /// False when this nudge already has an answer. The caller leaves the ride as it is.
    func uiCanAnswer(session: WorkSession) -> Bool {
        guard let stage = visibleNudgeStage(session) ?? (session.pendingCheckIn == .progress ? .checkIn : nil) else {
            return true
        }
        let nudgeID = NudgeSession.idString(sessionID: session.id, stage: stage)
        return nudgeStamp(on: session, nudgeID: nudgeID) == nil
    }

    func uiNudgeStamp(session: WorkSession) -> (String, NudgeStage)? {
        guard let stage = visibleNudgeStage(session) ?? (session.pendingCheckIn == .progress ? .checkIn : nil) else {
            return nil
        }
        return (NudgeSession.idString(sessionID: session.id, stage: stage), stage)
    }

    private func placeCheckIn(on session: WorkSession, input: NudgeRideInput) {
        guard !session.nudgeFiredStagesRaw.contains(NudgeStage.checkIn.rawValue) else { return }
        if let offset = nudgeMarks(input).first(where: { $0.stage == .checkIn })?.offset {
            session.checkInOffsetSeconds = [offset]
            let budget = TimeInterval(max(session.budgetSecondsAtStart, 1))
            session.checkInFraction = offset / budget
        } else if !session.extensions.isEmpty {
            session.checkInOffsetSeconds = []
            session.checkInFraction = nil
        }
    }

    private func promoteCheckIn(_ session: WorkSession) {
        guard settings.cabinAnnouncementsEnabled else { return }
        guard session.checkInFiredCount == 0 else { return }
        guard session.pendingCheckIn == nil else { return }
        session.pendingCheckIn = .progress
        session.awayDueAt = nil
        cancelAwayFireTask()
        presentation.noteCheckInHaptic()
    }

    private func nudgeMarks(_ input: NudgeRideInput) -> [NudgeStageMark] {
        NudgePlanner.marks(
            estimatedSeconds: input.estimatedSeconds,
            rideID: input.rideID,
            extensions: input.extensions,
            startedAt: input.startedAt,
            activeSeconds: NudgePlanner.workingElapsed(input),
            pausedAccumulated: input.pausedAccumulated,
            pausedAt: input.pausedAt,
            isPaused: input.isPaused,
            passengerAccumulated: input.passengerAccumulated,
            passengerSince: input.passengerSince,
            isPassenger: input.isPassenger
        )
    }

    private func wireNudge(stage: NudgeStage, session: WorkSession, input: NudgeRideInput) -> WireNudge {
        let ring = NudgePlanner.ring(stage: stage, on: input)
        let fired = nudgeFiredDate(stage: stage, session: session, now: input.now)
        return WireNudge(
            id: NudgeSession.id(sessionID: session.id, stage: stage),
            kind: stage == .checkIn ? .progress : .overrun,
            stage: NudgeStageWire(stage),
            ringSurface: NudgeRingSurface(rawValue: ring.surface.rawValue),
            firedAt: Int(fired.timeIntervalSince1970)
        )
    }

    private func nudgeFiredDate(stage: NudgeStage, session: WorkSession, now: Date) -> Date {
        let input = nudgeInput(for: session, now: now)
        let offset = nudgeMarks(input).first { $0.stage == stage }?.offset ?? 0
        let exclusions = session.pauses.map {
            NudgeSession.Interval(start: $0.startedAt, end: $0.endedAt ?? now)
        }
        return NudgeSession.firedAt(startedAt: session.startedAt, offset: offset, exclusions: exclusions)
    }

    func visibleNudgeStage(_ session: WorkSession) -> NudgeStage? {
        NudgeSession.visibleStage(
            fired: firedNudgeStages(session),
            answered: answeredNudgeIDs(session),
            sessionID: session.id
        )
    }

    func commandNudgeStage(_ session: WorkSession) -> NudgeStage? {
        NudgeSession.commandStage(
            fired: firedNudgeStages(session),
            answered: answeredNudgeIDs(session),
            sessionID: session.id
        )
    }

    func commandNudgeID(_ session: WorkSession) -> UUID? {
        commandNudgeStage(session).map { NudgeSession.id(sessionID: session.id, stage: $0) }
    }

    private func firedNudgeStages(_ session: WorkSession) -> [NudgeStage] {
        session.nudgeFiredStagesRaw.compactMap(NudgeStage.init(rawValue:))
    }

    private func answeredNudgeIDs(_ session: WorkSession) -> Set<String> {
        Set(session.checkInAnswers.compactMap { $0.nudgeID?.lowercased() })
    }

    private func nudgeStamp(on session: WorkSession, nudgeID: String) -> NudgeSession.Stamp? {
        let key = nudgeID.lowercased()
        guard let record = session.checkInAnswers.last(where: { $0.nudgeID?.lowercased() == key }) else {
            return nil
        }
        return NudgeSession.Stamp(answer: record.answer, addSeconds: record.addSeconds)
    }

    private func appendNudgeStamp(
        on session: WorkSession,
        kind: CheckInKind,
        answer: CheckInAnswerKind,
        at: Date,
        nudgeID: String,
        addSeconds: Int?,
        answeredOn: String
    ) {
        var answers = session.checkInAnswers
        answers.append(
            CheckInAnswerRecord(
                kind: kind,
                answer: answer,
                answeredAt: at,
                nudgeID: nudgeID,
                addSeconds: addSeconds,
                answeredOn: answeredOn
            )
        )
        session.checkInAnswers = answers
        session.nudgeAnsweredAt = at
        session.nudgeAnsweredOnRaw = answeredOn
        if visibleNudgeStage(session) == nil {
            session.nudgePendingStageRaw = nil
        }
    }

    private func completedPauseSeconds(_ session: WorkSession) -> TimeInterval {
        session.pauses.reduce(0) { total, pause in
            guard let ended = pause.endedAt else { return total }
            return total + max(0, ended.timeIntervalSince(pause.startedAt))
        }
    }

    private func nudgeWireError(for error: SessionError) -> WireError {
        switch error {
        case .noActiveService, .serviceDayNeedsEnd, .passengerAboard:
            .noActiveService
        case .pauseLimitReached:
            .pauseLimitReached
        case .alreadyBoarding:
            .sessionMismatch
        default:
            .invalidPayload
        }
    }
}
