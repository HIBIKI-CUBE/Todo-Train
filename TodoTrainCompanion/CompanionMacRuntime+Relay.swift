import Foundation
import TodoTrainSync

extension CompanionMacRuntime {
    func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.now = Int(Date().timeIntervalSince1970)
                self?.syncCabinNotification()
                self?.maybeSendTimetablePause()
                self?.refreshMacPresence()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func startListening() {
        hintTask?.cancel()
        hintTask = nil
        listenTask?.cancel()
        listenTask = nil
        guard HintPolling.shouldListen(isPaired: isPaired, isIdle: presence.isIdle) else { return }
        listenTask = Task { [weak self] in
            await self?.connectOnce()
        }
    }

    func startHintPolling() {
        guard HintPolling.shouldPoll(
            isPaired: isPaired,
            connection: connection,
            isIdle: presence.isIdle
        ) else { return }
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            await self?.pollHints()
        }
    }

    func noteSystemSleep() {
        applyPresence { $0.systemAsleep = true }
    }

    func noteSystemWake() {
        applyPresence { $0.systemAsleep = false }
    }

    func noteScreensSleep() {
        applyPresence { $0.screensAsleep = true }
    }

    func noteScreensWake() {
        applyPresence { $0.screensAsleep = false }
    }

    func noteScreensaverDidStart() {
        applyPresence { $0.screensaver = true }
    }

    func noteScreensaverDidStop() {
        applyPresence { $0.screensaver = false }
    }

    func applyPresence(_ mutate: (inout RelayPresence) -> Void) {
        let wasIdle = presence.isIdle
        mutate(&presence)
        if RelayPresence.shouldSuppress(wasIdle: wasIdle, isIdle: presence.isIdle) {
            suppressRelay()
        } else if RelayPresence.shouldResume(wasIdle: wasIdle, isIdle: presence.isIdle) {
            startListening()
        }
        refreshMacPresence()
    }

    func suppressRelay() {
        hintTask?.cancel()
        hintTask = nil
        listenTask?.cancel()
        listenTask = nil
        connection = .disconnected
    }

    func connectOnce() async {
        refreshPaired()
        guard HintPolling.shouldListen(isPaired: isPaired, isIdle: presence.isIdle), !Task.isCancelled else {
            connection = .disconnected
            return
        }
        do {
            try await pullSnapAndAck()
            try await listenWebSocket()
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            connection = .disconnected
            lastStatus = userFacing(error)
            startHintPolling()
        }
    }

    func pullSnapAndAck() async throws {
        let pairing = try requireSecrets()
        let keys = try SyncCrypto.deriveKeys(masterKey: pairing.masterKey, pairingId: pairing.pairingId)
        let client = try authedClient(pairing)
        if let envelope = try? await client.getSnap() {
            try applySnap(envelope, pairingId: pairing.pairingId, encKey: keys.enc)
        }
        if let envelope = try? await client.getAck() {
            try applyAck(envelope, pairingId: pairing.pairingId, encKey: keys.enc)
        }
        guard !Task.isCancelled, !presence.isIdle else { throw CancellationError() }
        connection = .connected
        lastStatus = nil
    }

    func pollHints() async {
        var previous: HintPlaintext?
        var etag: String?
        while !Task.isCancelled {
            guard HintPolling.shouldPoll(
                isPaired: isPaired,
                connection: connection,
                isIdle: presence.isIdle
            ) else { return }
            do {
                let pairing = try requireSecrets()
                let client = try authedClient(pairing)
                let result = try await client.getHint(pairingId: pairing.pairingId, etag: etag)
                switch HintPolling.outcome(
                    subscriber: .mac,
                    previous: previous,
                    result: result
                ) {
                case .ignore:
                    break
                case .remember(let hint, let tag):
                    noteRelayContract(hint.relayAnnouncement)
                    previous = hint
                    etag = tag
                case .catchUp(let catchUp, let hint, let tag):
                    noteRelayContract(hint.relayAnnouncement)
                    previous = hint
                    etag = tag
                    let keys = try SyncCrypto.deriveKeys(
                        masterKey: pairing.masterKey,
                        pairingId: pairing.pairingId
                    )
                    if catchUp.snap, let envelope = try? await client.getSnap() {
                        try applySnap(envelope, pairingId: pairing.pairingId, encKey: keys.enc)
                    }
                    if catchUp.ack, let envelope = try? await client.getAck() {
                        try applyAck(envelope, pairingId: pairing.pairingId, encKey: keys.enc)
                    }
                case .stop:
                    return
                }
            } catch SyncError.transport(let status, _) where status == 429 || status == 401 {
                lastStatus = userFacing(SyncError.transport(status: status, code: "invalid"))
                return
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                lastStatus = userFacing(error)
            }
            try? await Task.sleep(nanoseconds: HintPolling.intervalNanoseconds)
        }
    }

    func listenWebSocket() async throws {
        let pairing = try requireSecrets()
        let url = try requireRelay()
        let connector = URLSessionWebSocketConnecting(baseURL: url)
        let socket = BearerWebSocket(
            writeToken: pairing.writeToken,
            pairingId: pairing.pairingId,
            connector: connector
        )
        let connection = try await socket.connect()
        self.connection = .connected
        lastStatus = nil
        defer { Task { await connection.close() } }
        while !Task.isCancelled {
            let incoming: WSIncoming
            do {
                incoming = try await connection.receiveIncoming()
            } catch SyncError.invalidJSON {
                continue
            }
            switch incoming {
            case .hello(let announcement):
                noteRelayContract(announcement)
            case .frame(let frame):
                let keys = try SyncCrypto.deriveKeys(masterKey: pairing.masterKey, pairingId: pairing.pairingId)
                do {
                    switch frame.t {
                    case .snap:
                        try applySnap(frame.envelope, pairingId: pairing.pairingId, encKey: keys.enc)
                    case .ack:
                        try applyAck(frame.envelope, pairingId: pairing.pairingId, encKey: keys.enc)
                    case .cmd:
                        break
                    }
                } catch {
                    lastStatus = userFacing(error)
                }
            }
        }
    }

    func applySnap(_ envelope: Envelope, pairingId: UUID, encKey: Data) throws {
        snap = try SyncCrypto.openJSON(SnapPlaintext.self, envelope: envelope, pairingId: pairingId, encKey: encKey)
        if let build = snap?.build {
            notePeerBuild(build)
        }
        if let snap {
            notePeerContract(snap.announcement)
        }
        reconcileOptimisticCabin()
        if snap?.pendingCabin != .idle {
            optimisticIdleConsumed = false
        }
        if staleWinner, let current = snap?.nudge?.id, current != answerNudgeID {
            staleWinner = false
            nudgeWinnerLine = nil
        }
        refreshStaleWinner()
        syncCabinNotification()
    }

    func applyAck(_ envelope: Envelope, pairingId: UUID, encKey: Data) throws {
        let ack = try SyncCrypto.openJSON(AckPlaintext.self, envelope: envelope, pairingId: pairingId, encKey: encKey)
        if let build = ack.build {
            notePeerBuild(build)
        }
        notePeerContract(ack.announcement)
        let inFlight: UUID?
        if case .sending(let id) = outgoingPause { inFlight = id } else { inFlight = nil }
        outgoingPause = OutgoingPauseApplying.applyAck(ack, current: outgoingPause)
        issueBoardTrack = IssueBoardTracking.applyAck(ack, current: issueBoardTrack)
        guard ack.cmdId == inFlight else { return }
        transportNotice = nil
        pendingExtendMinutes = nil
        if ack.ok {
            staleWinner = false
            nudgeWinnerLine = nil
        } else if ack.error == .nudgeStale {
            staleWinner = true
            clearOptimisticCabin()
            optimisticIdleConsumed = false
            refreshStaleWinner()
        } else {
            clearOptimisticCabin()
            optimisticIdleConsumed = false
        }
    }

    func refreshStaleWinner() {
        guard staleWinner, let snap else { return }
        nudgeWinnerLine = MacNudgeReceipt.winnerLine(snap: snap, estimateBefore: answerEstimateBefore)
    }

    func noteCommandTransportFailure(_ error: Error) {
        if let sync = error as? SyncError, case .transport(_, let code) = sync, code == "fifoFull" {
            outgoingPause = .idle
            pendingExtendMinutes = nil
            transportNotice = SyncCopy.fifoFull
            lastStatus = SyncCopy.fifoFull
            return
        }
        outgoingPause = .failed(.decryptFailed)
        lastStatus = userFacing(error)
    }

    func notePeerBuild(_ build: WireBuildInfo) {
        peerBuild = build
        PeerBuildStore.save(build, to: defaults)
    }

    func notePeerContract(_ announcement: ContractAnnouncement) {
        peerContract = announcement
        PeerContractStore.save(announcement, to: defaults, key: PeerContractStore.peerKey)
    }

    func noteRelayContract(_ announcement: ContractAnnouncement) {
        relayContract = announcement
        PeerContractStore.save(announcement, to: defaults, key: PeerContractStore.relayKey)
    }
}
