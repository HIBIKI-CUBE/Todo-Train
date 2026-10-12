import Foundation
import TodoTrainSync

extension CompanionMacRuntime {
    /// PiP の停車と車内放送の停車は `user`。保護境界は `timetable` を渡す。
    func sendPause(heldBy: PauseHeldBy = .user) async {
        await sendRideCommand(.pause, heldBy: heldBy)
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
        case .issueAndBoard, .answer, .boardReserved, .presence, .unknown:
            return
        }
        let sessionId: UUID?
        switch op {
        case .pause, .resume:
            guard let id = snap?.sessionId else { return }
            sessionId = id
        case .still:
            sessionId = snap?.sessionId
        case .issueAndBoard, .answer, .boardReserved, .presence, .unknown:
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
            outgoingPause = .failed(.decryptFailed)
            lastStatus = userFacing(error)
            if op == .still {
                clearOptimisticCabin()
                optimisticIdleConsumed = false
            }
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
