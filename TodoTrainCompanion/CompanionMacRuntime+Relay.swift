import Foundation
import TodoTrainSync

extension CompanionMacRuntime {
    func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                let sampled = Date()
                self?.now = WholeSecond.unix(sampled)
                self?.expireReestimateUndo()
                self?.notePauseInputClock()
                self?.confirmSnapWhileConnected()
                self?.refreshRadio()
                self?.syncCabinNotification()
                self?.maybeSendTimetablePause()
                self?.refreshMacPresence()
                let after = Date()
                if WholeSecond.unix(after) != WholeSecond.unix(sampled) { continue }
                try? await Task.sleep(nanoseconds: WholeSecond.nanosecondsUntilNextBoundary(after: after))
            }
        }
    }

    func startListening() {
        guard HintPolling.shouldListen(isPaired: isPaired, isIdle: presence.isIdle) else {
            suppressRelay()
            return
        }
        // Join the previous task so its socket is closed before this one opens.
        let previous = listenTask
        listenTask = Task { [weak self] in
            previous?.cancel()
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            await self.maintainRelay()
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
        listenTask?.cancel()
        connection = .disconnected
        relayRetryingSince = nil
        relayExhausted = false
        refreshRadio()
    }

    /// One task, one socket. After the attempt cap, hint polling is the only watcher.
    func maintainRelay() async {
        relayExhausted = false
        relayRetryingSince = nil
        refreshRadio()
        var attempt = 0
        var failedAt: Date?
        while !Task.isCancelled {
            refreshPaired()
            guard HintPolling.shouldListen(isPaired: isPaired, isIdle: presence.isIdle) else {
                connection = .disconnected
                relayRetryingSince = nil
                relayExhausted = false
                refreshRadio()
                return
            }
            let result = await openAndListen()
            if Task.isCancelled || presence.isIdle || !isPaired { return }
            switch result {
            case .cancelled:
                return
            case .unauthorized:
                connection = .disconnected
                lastStatus = userFacing(SyncError.transport(status: 401, code: "invalid"))
                relayRetryingSince = nil
                relayExhausted = false
                refreshRadio()
                return
            case .rateLimited, .dropped:
                let healthy = if case .dropped(let wasHealthy) = result { wasHealthy } else { false }
                if healthy {
                    attempt = 0
                    failedAt = nil
                    relayRetryingSince = nil
                    relayExhausted = false
                }
                connection = .disconnected
                attempt += 1
                let moment = Date()
                if failedAt == nil { failedAt = moment }
                if relayRetryingSince == nil { relayRetryingSince = failedAt }
                relayExhausted = false
                refreshRadio()
                let elapsed = moment.timeIntervalSince(failedAt ?? moment)
                if !RelayReconnect.shouldRetry(attempt: attempt, elapsedSeconds: elapsed) {
                    relayExhausted = true
                    refreshRadio()
                    _ = await pollHints(until: nil)
                    return
                }
                let delay = RelayReconnect.delaySeconds(
                    attempt: attempt,
                    unit: Double.random(in: 0..<1)
                )
                let waited = await pollHints(until: Date().addingTimeInterval(delay))
                switch waited {
                case .unauthorized:
                    connection = .disconnected
                    lastStatus = userFacing(SyncError.transport(status: 401, code: "invalid"))
                    relayRetryingSince = nil
                    refreshRadio()
                    return
                case .cancelled:
                    return
                case .elapsed:
                    break
                }
            }
        }
    }

    func openAndListen() async -> RelaySocketResult {
        do {
            try await pullSnapAndAck()
        } catch is CancellationError {
            return .cancelled
        } catch {
            if Task.isCancelled { return .cancelled }
            return finishOpen(error, healthy: false)
        }
        relayRetryingSince = nil
        relayExhausted = false
        refreshRadio()
        let listened = await listenWebSocket()
        if let error = listened.error {
            return finishOpen(error, healthy: listened.healthy)
        }
        if Task.isCancelled { return .cancelled }
        return .dropped(healthy: listened.healthy)
    }

    func finishOpen(_ error: Error, healthy: Bool) -> RelaySocketResult {
        if error is CancellationError || Task.isCancelled { return .cancelled }
        lastStatus = userFacing(error)
        if let status = RelayReconnect.transportStatus(error) {
            switch HintPolling.rateLimit(status) {
            case .stop:
                return .unauthorized
            case .wait:
                return .rateLimited
            case .again:
                break
            }
        }
        return .dropped(healthy: healthy)
    }

    func pullSnapAndAck() async throws {
        let pairing = try requireSecrets()
        let keys = try SyncCrypto.deriveKeys(masterKey: pairing.masterKey, pairingId: pairing.pairingId)
        let client = try authedClient(pairing)
        try await readIfPresent {
            let envelope = try await client.getSnap()
            try self.applySnap(envelope, pairingId: pairing.pairingId, encKey: keys.enc)
        }
        try await readIfPresent {
            let envelope = try await client.getAck()
            try self.applyAck(envelope, pairingId: pairing.pairingId, encKey: keys.enc)
        }
        guard !Task.isCancelled, !presence.isIdle else { throw CancellationError() }
        connection = .connected
        lastStatus = nil
    }

    /// 401 and 429 leave the optional read. Anything else (a missing snap) stays quiet.
    func readIfPresent(_ body: () async throws -> Void) async throws {
        do {
            try await body()
        } catch {
            if let status = RelayReconnect.transportStatus(error), HintPolling.rateLimit(status) != .again {
                throw error
            }
        }
    }

    /// `until == nil` watches until cancel or an invalid pairing. A deadline is the backoff bridge.
    func pollHints(until deadline: Date?) async -> HintWatch {
        var previous: HintPlaintext?
        var etag: String?
        var rateAttempt = 0
        while !Task.isCancelled {
            if let deadline, Date() >= deadline { return .elapsed }
            guard HintPolling.shouldPoll(
                isPaired: isPaired,
                connection: connection,
                isIdle: presence.isIdle
            ) else { return .cancelled }
            do {
                let pairing = try requireSecrets()
                let client = try authedClient(pairing)
                let result = try await client.getHint(pairingId: pairing.pairingId, etag: etag)
                rateAttempt = 0
                switch HintPolling.outcome(
                    subscriber: .mac,
                    previous: previous,
                    result: result
                ) {
                case .ignore:
                    if result.notModified { confirmSnapFromRelay() }
                case .remember(let hint, let tag):
                    noteRelayContract(hint.relayAnnouncement)
                    previous = hint
                    etag = tag
                    confirmSnapFromRelay()
                case .catchUp(let catchUp, let hint, let tag):
                    noteRelayContract(hint.relayAnnouncement)
                    previous = hint
                    etag = tag
                    let keys = try SyncCrypto.deriveKeys(
                        masterKey: pairing.masterKey,
                        pairingId: pairing.pairingId
                    )
                    if catchUp.snap {
                        try await readIfPresent {
                            let envelope = try await client.getSnap()
                            try self.applySnap(envelope, pairingId: pairing.pairingId, encKey: keys.enc)
                        }
                    }
                    if catchUp.ack {
                        try await readIfPresent {
                            let envelope = try await client.getAck()
                            try self.applyAck(envelope, pairingId: pairing.pairingId, encKey: keys.enc)
                        }
                    }
                    confirmSnapFromRelay()
                case .stop:
                    return .unauthorized
                }
            } catch SyncError.transport(let status, _) {
                lastStatus = userFacing(SyncError.transport(status: status, code: "invalid"))
                switch HintPolling.rateLimit(status) {
                case .stop:
                    return .unauthorized
                case .wait:
                    rateAttempt += 1
                    let pause = RelayReconnect.delaySeconds(
                        attempt: rateAttempt,
                        unit: Double.random(in: 0..<1)
                    )
                    let paused = await sleepHint(pause, until: deadline)
                    if !paused {
                        return Task.isCancelled ? .cancelled : .elapsed
                    }
                    continue
                case .again:
                    break
                }
            } catch is CancellationError {
                return .cancelled
            } catch {
                if Task.isCancelled { return .cancelled }
                lastStatus = userFacing(error)
            }
            let paused = await sleepHint(
                Double(HintPolling.intervalNanoseconds) / 1_000_000_000,
                until: deadline
            )
            if !paused {
                return Task.isCancelled ? .cancelled : .elapsed
            }
        }
        return .cancelled
    }

    /// False when the wait was cut short by cancellation or the deadline.
    func sleepHint(_ seconds: Double, until deadline: Date?) async -> Bool {
        let requested = max(0, seconds)
        let slice: Double
        if let deadline {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { return false }
            slice = min(requested, remaining)
        } else {
            slice = requested
        }
        let nanos = UInt64((slice * 1_000_000_000).rounded())
        if nanos > 0 {
            try? await Task.sleep(nanoseconds: nanos)
        }
        if Task.isCancelled { return false }
        if let deadline, Date() >= deadline { return false }
        return true
    }

    func listenWebSocket() async -> (healthy: Bool, error: Error?) {
        let pairing: PairingSecrets
        let url: URL
        do {
            pairing = try requireSecrets()
            url = try requireRelay()
        } catch {
            return (false, error)
        }
        let connector = URLSessionWebSocketConnecting(baseURL: url)
        let socket = BearerWebSocket(
            writeToken: pairing.writeToken,
            pairingId: pairing.pairingId,
            role: .mac,
            connector: connector
        )
        let connection: EchoingWebSocketConnection
        do {
            connection = EchoingWebSocketConnection(try await socket.connect())
        } catch {
            return (false, error)
        }
        self.connection = .connected
        lastStatus = nil
        var healthy = false
        var failure: Error?
        while !Task.isCancelled {
            let incoming: WSIncoming
            do {
                incoming = try await connection.receiveIncoming()
            } catch SyncError.invalidJSON {
                continue
            } catch {
                failure = error
                break
            }
            healthy = true
            switch incoming {
            case .hello(let announcement):
                noteRelayContract(announcement)
            case .ping, .pong, .echo:
                break
            case .frame(let frame):
                let keys: DerivedKeys
                do {
                    keys = try SyncCrypto.deriveKeys(masterKey: pairing.masterKey, pairingId: pairing.pairingId)
                } catch {
                    lastStatus = userFacing(error)
                    continue
                }
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
        if failure == nil, Task.isCancelled {
            failure = CancellationError()
        }
        await connection.close()
        return (healthy, failure)
    }

    func confirmSnapWhileConnected() {
        guard connection == .connected, snap != nil else { return }
        snapConfirmedAt = Date(timeIntervalSince1970: TimeInterval(now))
    }

    func confirmSnapFromRelay() {
        guard snap != nil else { return }
        snapConfirmedAt = Date()
        refreshRadio()
    }

    func refreshRadio() {
        let output = RelayRadio.judge(
            RelayRadio.Input(
                now: now,
                snapConfirmedAt: snapConfirmedAt.map { Int($0.timeIntervalSince1970) },
                retryingSince: relayRetryingSince.map { Int($0.timeIntervalSince1970) },
                exhausted: relayExhausted,
                acknowledged: radioAcknowledged,
                prior: radioPrior,
                recoveredUntil: radioRecoveredUntil,
                timeZone: .current
            )
        )
        radioReading = output.reading
        radioPrior = output.reading.phase
        radioRecoveredUntil = output.recoveredUntil
        if output.clearAcknowledged {
            radioAcknowledged = false
        }
        syncRadioNotice()
    }

    func acknowledgeRadio() {
        guard radioReading.phase == .reconnecting || radioReading.phase == .outOfContact else { return }
        radioAcknowledged = true
        refreshRadio()
    }

    func syncRadioNotice() {
        let riding = snap.map { RelayRadio.riding($0.phase) } ?? false
        if RelayRadio.shouldPostNotice(
            phase: radioReading.phase,
            riding: riding,
            session: snap?.sessionId,
            postedFor: radioNotifiedSession
        ), let session = snap?.sessionId {
            radioNotifiedSession = session
            cabinNotifier.postRadio(title: SyncCopy.radioNoticeTitle, body: SyncCopy.radioNoticeBody)
            return
        }
        if radioReading.phase != .outOfContact {
            cabinNotifier.withdrawRadio()
        }
    }

    func applySnap(_ envelope: Envelope, pairingId: UUID, encKey: Data) throws {
        let previousSession = snap?.sessionId
        snap = try SyncCrypto.openJSON(SnapPlaintext.self, envelope: envelope, pairingId: pairingId, encKey: encKey)
        if snap?.sessionId != previousSession {
            radioNotifiedSession = nil
        }
        snapConfirmedAt = Date()
        refreshRadio()
        if let build = snap?.build {
            notePeerBuild(build)
        }
        if let snap {
            notePeerContract(snap.announcement)
        }
        notePauseInputClock()
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
        noteIssueAck(ack)
        guard ack.cmdId == inFlight else { return }
        transportNotice = nil
        if ack.cmdId == reestimateUndoCommandID, !ack.ok {
            reestimateUndoUntil = nil
            reestimateUndoCommandID = nil
            reestimateUndoChoice = nil
        }
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
            reestimateUndoUntil = nil
            reestimateUndoCommandID = nil
            reestimateUndoChoice = nil
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
        flushPauseInputReports()
    }

    func noteRelayContract(_ announcement: ContractAnnouncement) {
        relayContract = announcement
        PeerContractStore.save(announcement, to: defaults, key: PeerContractStore.relayKey)
    }
}
