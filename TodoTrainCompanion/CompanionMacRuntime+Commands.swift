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

    func sendRideCommand(_ op: WireOp) async {
        switch op {
        case .pause:
            guard presentation.canPause, !presentation.isSending else { return }
        case .resume:
            guard presentation.canResume, !presentation.isSending else { return }
        case .still:
            guard !presentation.isSending else { return }
        }
        let sessionId: UUID?
        switch op {
        case .pause, .resume:
            guard let id = snap?.sessionId else { return }
            sessionId = id
        case .still:
            sessionId = snap?.sessionId
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

    var cmdRev: Int {
        get { defaults.integer(forKey: Defaults.cmdRev) }
        set { defaults.set(newValue, forKey: Defaults.cmdRev) }
    }
}
