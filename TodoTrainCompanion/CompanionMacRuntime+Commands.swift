import Foundation
import TodoTrainSync

extension CompanionMacRuntime {
    func sendPause() async {
        await sendRideCommand(.pause)
    }

    func sendResume() async {
        await sendRideCommand(.resume)
    }

    func sendStill() async {
        let interrupt = cabinInterrupt
        let pip = overlayPresentation.cabinPrompt != nil
        let idle = interrupt.showsNotification && interrupt.kind == .idle
        guard pip || idle, !presentation.isSending else { return }
        if pip, let sessionId = snap?.sessionId {
            markOptimisticCabin(sessionId: sessionId, firedCount: (snap?.checkInFiredCount ?? 0) + 1)
        }
        if idle {
            optimisticIdleConsumed = true
            cabinNotifier.remove()
        }
        await sendRideCommand(.still)
    }

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
        Task { await sendPause() }
    }

    func sendRideCommand(_ op: WireOp) async {
        switch op {
        case .pause:
            guard presentation.canPause, !presentation.isSending else { return }
        case .resume:
            guard presentation.canResume, !presentation.isSending else { return }
        case .still:
            guard !presentation.isSending else { return }
        case .issueAndBoard:
            return
        }
        let sessionId: UUID?
        switch op {
        case .pause, .resume:
            guard let id = snap?.sessionId else { return }
            sessionId = id
        case .still:
            sessionId = snap?.sessionId
        case .issueAndBoard:
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
                at: now
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
            outgoingPause = .failed(.decryptFailed)
            lastStatus = userFacing(error)
            if op == .still {
                clearOptimisticCabin()
                optimisticIdleConsumed = false
            }
        }
    }

    func sendIssueAndBoard(title: String, estimatedSeconds: Int) async {
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
                estimatedSeconds: estimatedSeconds
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
