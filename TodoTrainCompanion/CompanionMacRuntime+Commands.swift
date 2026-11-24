import Foundation
import TodoTrainSync

extension CompanionMacRuntime {
    /// PiP の停車と車内放送の停車は `user`。ダイヤの時刻では送らない。
    func sendPause(heldBy: PauseHeldBy = .user) async {
        await sendRideCommand(.pause, heldBy: heldBy)
    }

    func sendResume() async {
        await sendRideCommand(.resume)
    }

    /// メニューと PiP の停車・再乗車。今送れる方を一つ送る。
    func sendPauseOrResume() async {
        if presentation.canResume {
            await sendResume()
        } else if presentation.canPause {
            await sendPause()
        }
    }

    func expireReestimateUndo() {
        guard let until = reestimateUndoUntil, now >= until else { return }
        reestimateUndoUntil = nil
        reestimateUndoCommandID = nil
    }

    /// 見積もり直しを送る。届いたあと 5 秒だけ取り消しを出す。
    @discardableResult
    func sendReestimate(_ choice: MacPipReestimateChoice) async -> Bool {
        guard let sessionId = snap?.sessionId else { return false }
        if let blocked = ContractCompat.commandBlock(peer: peerContract, relay: relayContract, side: .mac) {
            lastStatus = blocked
            return false
        }
        let active = TimeInterval(snap?.elapsedActiveSeconds(at: now) ?? 0)
        let cmdId = UUID()
        guard let command = MacPipReestimate.command(
            id: cmdId,
            sessionId: sessionId,
            at: now,
            activeSeconds: active,
            nudgeStage: snap?.nudge?.stage,
            choice: choice,
            build: LocalWireBuild.current,
            contract: ContractVersion.contract,
            minReadable: ContractVersion.minReadable
        ) else { return false }
        guard let next = OutgoingPauseApplying.beginSending(cmdId: cmdId, current: outgoingPause) else {
            return false
        }
        outgoingPause = next
        transportNotice = nil
        do {
            try await post(command)
            reestimateUndoCommandID = cmdId
            reestimateUndoUntil = now + MacPipReestimate.undoSeconds
            return true
        } catch {
            noteCommandTransportFailure(error)
            return false
        }
    }

    /// 直前の見積もり直しを取り消す。送信中の見積もり直しは、このコマンドに差し替える。
    @discardableResult
    func sendUndoReestimate() async -> Bool {
        guard let sessionId = snap?.sessionId else { return false }
        if let blocked = ContractCompat.commandBlock(peer: peerContract, relay: relayContract, side: .mac) {
            lastStatus = blocked
            return false
        }
        if case .sending(let id) = outgoingPause, id != reestimateUndoCommandID {
            return false
        }
        let keptUntil = reestimateUndoUntil
        let keptID = reestimateUndoCommandID
        let cmdId = UUID()
        let command = MacPipReestimate.undoCommand(
            id: cmdId,
            sessionId: sessionId,
            at: now,
            build: LocalWireBuild.current,
            contract: ContractVersion.contract,
            minReadable: ContractVersion.minReadable
        )
        outgoingPause = .sending(cmdId: cmdId)
        reestimateUndoUntil = nil
        reestimateUndoCommandID = nil
        transportNotice = nil
        do {
            try await post(command)
            return true
        } catch {
            noteCommandTransportFailure(error)
            if reestimateUndoUntil == nil {
                reestimateUndoUntil = keptUntil
                reestimateUndoCommandID = keptID
            }
            return false
        }
    }

    func sendStill() async {
        let interrupt = cabinInterrupt
        let pip = overlayPresentation.cabinPrompt != nil
        let idle = interrupt.showsNotification && interrupt.kind == .idle
        let gap = overlayPresentation.showsArrivalGap
        guard pip || idle || gap, !presentation.isSending else { return }
        if gap {
            await sendRideCommand(.still)
            return
        }
        if pip, let sessionId = snap?.sessionId {
            markOptimisticCabin(sessionId: sessionId, firedCount: (snap?.checkInFiredCount ?? 0) + 1)
        }
        if idle {
            optimisticIdleConsumed = true
            cabinNotifier.remove()
        }
        await sendRideCommand(.still)
    }

    /// Older snaps may still carry `timetablePauseAt`. That time does not send pause.
    func maybeSendTimetablePause() {
        let view = overlayPresentation
        let pauseAt = snap?.timetablePauseAt
        guard TimetablePauseDispatching.shouldSend(
            now: now,
            pauseAt: pauseAt,
            alreadySent: sentTimetablePauseAt,
            canPause: view.canPause,
            isSending: view.isSending
        ) else {
            if pauseAt == nil || snap?.phase == .paused || snap?.phase == .idle {
                sentTimetablePauseAt = nil
            }
            return
        }
        sentTimetablePauseAt = pauseAt
        Task { await sendPause(heldBy: .timetable) }
    }

    func sendRideCommand(_ op: WireOp, heldBy: PauseHeldBy? = nil) async {
        if let blocked = ContractCompat.commandBlock(peer: peerContract, relay: relayContract, side: .mac) {
            lastStatus = blocked
            return
        }
        switch op {
        case .pause:
            guard presentation.canPause, !presentation.isSending else { return }
        case .resume:
            guard presentation.canResume, !presentation.isSending else { return }
        case .still:
            guard !presentation.isSending else { return }
        case .issueAndBoard, .answer, .boardReserved, .presence, .pauseInputReport, .reestimate, .undoReestimate, .unknown:
            return
        }
        let sessionId: UUID?
        switch op {
        case .pause, .resume:
            guard let id = snap?.sessionId else { return }
            sessionId = id
        case .still:
            sessionId = snap?.sessionId
        case .issueAndBoard, .answer, .boardReserved, .presence, .pauseInputReport, .reestimate, .undoReestimate, .unknown:
            return
        }
        let cmdId = UUID()
        guard let next = OutgoingPauseApplying.beginSending(cmdId: cmdId, current: outgoingPause) else {
            return
        }
        outgoingPause = next
        do {
            let pairing = try requireSecrets()
            let keys = try SyncCrypto.deriveKeys(masterKey: pairing.masterKey, pairingId: pairing.pairingId)
            let client = try authedClient(pairing)
            let command = CommandPlaintext(
                id: cmdId,
                op: op,
                sessionId: sessionId,
                at: now,
                build: LocalWireBuild.current,
                contract: ContractVersion.contract,
                minReadable: ContractVersion.minReadable,
                heldBy: op == .pause ? (heldBy ?? .user) : nil
            )
            let rev = OutgoingPauseApplying.nextCommandRev(current: cmdRev)
            cmdRev = rev
            let envelope = try SyncCrypto.sealJSON(
                command,
                pairingId: pairing.pairingId,
                kind: .cmd,
                rev: rev,
                encKey: keys.enc
            )
            _ = try await client.postCmd(envelope)
        } catch {
            noteCommandTransportFailure(error)
            if op == .still {
                clearOptimisticCabin()
                optimisticIdleConsumed = false
            }
        }
    }

    func sendNudgeAnswer(_ choice: NudgeChoice) async {
        guard choice == .stillOnIt || choice == .alreadyDone || choice == .paused else { return }
        guard snap?.nudge != nil else { return }
        guard let sessionId = snap?.sessionId, let nudgeId = snap?.nudge?.id else { return }
        if let blocked = ContractCompat.commandBlock(peer: peerContract, relay: relayContract, side: .mac) {
            lastStatus = blocked
            return
        }
        let cmdId = UUID()
        guard let next = OutgoingPauseApplying.beginSending(cmdId: cmdId, current: outgoingPause) else {
            return
        }
        outgoingPause = next
        transportNotice = nil
        staleWinner = false
        nudgeWinnerLine = nil
        answerEstimateBefore = snap?.estimatedSeconds
        answerNudgeID = nudgeId
        do {
            let command = CommandPlaintext(
                id: cmdId,
                op: .answer,
                sessionId: sessionId,
                at: now,
                build: LocalWireBuild.current,
                contract: ContractVersion.contract,
                minReadable: ContractVersion.minReadable,
                nudgeId: nudgeId,
                choice: choice,
                answeredOn: .mac
            )
            try await post(command)
        } catch {
            noteCommandTransportFailure(error)
        }
    }

    func post(_ command: CommandPlaintext) async throws {
        let pairing = try requireSecrets()
        let keys = try SyncCrypto.deriveKeys(masterKey: pairing.masterKey, pairingId: pairing.pairingId)
        let client = try authedClient(pairing)
        let rev = OutgoingPauseApplying.nextCommandRev(current: cmdRev)
        cmdRev = rev
        let envelope = try SyncCrypto.sealJSON(
            command,
            pairingId: pairing.pairingId,
            kind: .cmd,
            rev: rev,
            encKey: keys.enc
        )
        _ = try await client.postCmd(envelope)
    }

    func sendBoardReserved() async {
        guard overlayPresentation.canBoardReserved, let ticketId = snap?.reserved?.ticketId else { return }
        if let blocked = ContractCompat.commandBlock(peer: peerContract, relay: relayContract, side: .mac) {
            lastStatus = blocked
            return
        }
        let cmdId = UUID()
        guard let next = OutgoingPauseApplying.beginSending(cmdId: cmdId, current: outgoingPause) else {
            return
        }
        outgoingPause = next
        transportNotice = nil
        do {
            let command = CommandPlaintext(
                id: cmdId,
                op: .boardReserved,
                sessionId: nil,
                at: now,
                build: LocalWireBuild.current,
                contract: ContractVersion.contract,
                minReadable: ContractVersion.minReadable,
                nudgeId: snap?.nudge?.id,
                ticketId: ticketId
            )
            try await post(command)
        } catch {
            noteCommandTransportFailure(error)
        }
    }

    func sendIssueAndBoard(title: String, estimatedSeconds: Int) async {
        if let blocked = ContractCompat.commandBlock(peer: peerContract, relay: relayContract, side: .mac) {
            lastStatus = blocked
            return
        }
        let trimmed = IssueAndBoardEvaluating.trimmedTitle(title)
        guard IssueAndBoardEvaluating.isValid(title: trimmed, estimatedSeconds: estimatedSeconds) else {
            issueBoardTrack = .failed(.invalidPayload)
            return
        }
        guard ImaYaruOffer.isAvailable(isPaired: isPaired, serviceActive: snap?.serviceActive) else {
            issueBoardTrack = .failed(.noActiveService)
            return
        }
        let prior = ImaYaruOffer.ridingSessionID(snap)
        let cmdId = UUID()
        guard let next = IssueBoardTracking.begin(
            cmdId: cmdId,
            title: trimmed,
            priorSessionId: prior,
            current: issueBoardTrack
        ) else { return }
        issueBoardTrack = next
        do {
            let pairing = try requireSecrets()
            let keys = try SyncCrypto.deriveKeys(masterKey: pairing.masterKey, pairingId: pairing.pairingId)
            let client = try authedClient(pairing)
            let command = CommandPlaintext(
                id: cmdId,
                op: .issueAndBoard,
                sessionId: prior,
                at: now,
                title: trimmed,
                estimatedSeconds: estimatedSeconds,
                build: LocalWireBuild.current,
                contract: ContractVersion.contract,
                minReadable: ContractVersion.minReadable
            )
            let rev = OutgoingPauseApplying.nextCommandRev(current: cmdRev)
            cmdRev = rev
            let envelope = try SyncCrypto.sealJSON(
                command,
                pairingId: pairing.pairingId,
                kind: .cmd,
                rev: rev,
                encKey: keys.enc
            )
            _ = try await client.postCmd(envelope)
        } catch {
            issueBoardTrack = IssueBoardTracking.failTransport(issueBoardTrack)
            lastStatus = userFacing(error)
        }
    }

    var cmdRev: Int {
        get { defaults.integer(forKey: Defaults.cmdRev) }
        set { defaults.set(newValue, forKey: Defaults.cmdRev) }
    }
}
