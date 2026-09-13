import Foundation
import TodoTrainSync

extension CompanionMacRuntime {
    func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.now = Int(Date().timeIntervalSince1970)
                self?.syncCabinNotification()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func startListening() {
        hintTask?.cancel()
        hintTask = nil
        listenTask?.cancel()
        listenTask = Task { [weak self] in
            await self?.connectOnce()
        }
    }

    func startHintPolling() {
        guard HintPolling.shouldPoll(isPaired: isPaired, connection: connection) else { return }
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            await self?.pollHints()
        }
    }

    func connectOnce() async {
        refreshPaired()
        guard isPaired, !Task.isCancelled else {
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
        connection = .connected
        lastStatus = nil
    }

    func pollHints() async {
        var previous: HintPlaintext?
        var etag: String?
        while !Task.isCancelled {
            guard HintPolling.shouldPoll(isPaired: isPaired, connection: connection) else { return }
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
                    previous = hint
                    etag = tag
                case .catchUp(let catchUp, let hint, let tag):
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
            let frame: WSFrame
            do {
                frame = try await connection.receive()
            } catch SyncError.invalidJSON {
                continue
            }
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

    func applySnap(_ envelope: Envelope, pairingId: UUID, encKey: Data) throws {
        snap = try SyncCrypto.openJSON(SnapPlaintext.self, envelope: envelope, pairingId: pairingId, encKey: encKey)
        reconcileOptimisticCabin()
        if snap?.pendingCabin != .idle {
            optimisticIdleConsumed = false
        }
        syncCabinNotification()
    }

    func applyAck(_ envelope: Envelope, pairingId: UUID, encKey: Data) throws {
        let ack = try SyncCrypto.openJSON(AckPlaintext.self, envelope: envelope, pairingId: pairingId, encKey: encKey)
        outgoingPause = OutgoingPauseApplying.applyAck(ack, current: outgoingPause)
        if case .failed = outgoingPause {
            clearOptimisticCabin()
            optimisticIdleConsumed = false
        }
    }
}
