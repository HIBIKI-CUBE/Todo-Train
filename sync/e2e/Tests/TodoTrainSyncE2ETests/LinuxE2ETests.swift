import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import TodoTrainSync

@Suite("Linux E2E against local Worker", .serialized)
struct LinuxE2ETests {
    let baseURL = E2EConfig.baseURL

    init() async throws {
        try await waitForWorker(url: baseURL)
    }

    @Test func encryptedClientRoundTripsSnapPauseAck() async throws {
        let recording = RecordingHTTPTransport(AbsoluteURLHTTPTransport(baseURL: baseURL))
        let iphoneStore = InMemorySecretStore()
        let macStore = InMemorySecretStore()
        let iphoneFlow = PairingFlow(
            role: .iphone,
            client: SyncHTTPClient(baseURL: baseURL, transport: recording),
            secrets: iphoneStore,
            localAuth: ImmediateLocalAuth()
        )
        let macFlow = PairingFlow(
            role: .mac,
            client: SyncHTTPClient(baseURL: baseURL, transport: recording),
            secrets: macStore,
            localAuth: ImmediateLocalAuth()
        )

        let iphoneQR = try await iphoneFlow.presentQR()
        let macQR = try await macFlow.presentQR()
        _ = try await iphoneFlow.ingestOptical(macQR.encoded)
        _ = try await macFlow.ingestOptical(iphoneQR.encoded)
        try await bindUntilBound(iphoneFlow)
        try await bindUntilBound(macFlow)
        #expect(await iphoneFlow.phase == .awaitingLocalAuth)
        #expect(await macFlow.phase == .awaitingLocalAuth)

        try await confirmUntilEstablished(iphoneFlow)
        try await confirmUntilEstablished(macFlow)
        #expect(await iphoneFlow.phase == .established)
        #expect(await macFlow.phase == .established)

        guard let iphoneSecrets = try iphoneStore.load() else {
            throw E2EError.timeout("iphone secrets")
        }
        guard let macSecrets = try macStore.load() else {
            throw E2EError.timeout("mac secrets")
        }
        #expect(iphoneSecrets.pairingId == macSecrets.pairingId)
        #expect(iphoneSecrets.masterKey == macSecrets.masterKey)
        #expect(iphoneSecrets.writeToken == macSecrets.writeToken)

        let pairingId = iphoneSecrets.pairingId
        let keys = try SyncCrypto.deriveKeys(masterKey: iphoneSecrets.masterKey, pairingId: pairingId)
        let iphone = SyncHTTPClient(baseURL: baseURL, transport: recording, writeToken: iphoneSecrets.writeToken)
        let mac = SyncHTTPClient(baseURL: baseURL, transport: recording, writeToken: macSecrets.writeToken)

        let ws = BearerWebSocket(
            writeToken: macSecrets.writeToken,
            connector: RawWebSocketConnecting(baseURL: baseURL)
        )
        let connection = try await ws.connect()

        let snap = E2EConfig.runningSnap()
        let snapEnvelope = try seal(snap, pairingId: pairingId, kind: .snap, rev: snap.rev, encKey: keys.enc)
        let put = try await iphone.putSnap(snapEnvelope)
        #expect(put.rev == snap.rev)

        let wsFrame = try await connection.receive()
        #expect(wsFrame.t == .snap)
        #expect(wsFrame.envelope.rev == snap.rev)
        let fromWS = try openJSON(SnapPlaintext.self, envelope: wsFrame.envelope, pairingId: pairingId, encKey: keys.enc)
        #expect(fromWS.title == E2EConfig.plaintextTitle)
        #expect(fromWS.remainingSeconds(at: E2EConfig.snapNow) == E2EConfig.remainingAtSnapNow)

        let got = try await mac.getSnap()
        #expect(got.kind == .snap)
        let fromGET = try openJSON(SnapPlaintext.self, envelope: got, pairingId: pairingId, encKey: keys.enc)
        #expect(fromGET == fromWS)
        #expect(fromGET.title == E2EConfig.plaintextTitle)
        #expect(fromGET.sessionId == E2EConfig.sessionId)

        let presentation = MenuBarPresentation.make(
            MenuBarInput(pairing: .paired, snap: fromGET, now: E2EConfig.snapNow)
        )
        #expect(presentation.popoverTitle == E2EConfig.plaintextTitle)
        #expect(presentation.remainingSeconds == E2EConfig.remainingAtSnapNow)
        #expect(presentation.canPause)

        let command = CommandPlaintext(
            id: E2EConfig.commandId,
            op: .pause,
            sessionId: E2EConfig.sessionId,
            at: E2EConfig.snapNow
        )
        let decision = RemotePauseEvaluating.evaluate(
            openSessionId: fromGET.sessionId,
            pausedCount: 0,
            pauseLimit: 2,
            command: command
        )
        #expect(decision == .apply)
        let ack = RemotePauseEvaluating.ack(decision: decision, commandId: command.id)
        #expect(ack.ok)
        #expect(ack.error == nil)

        let cmdEnvelope = try seal(command, pairingId: pairingId, kind: .cmd, rev: 1, encKey: keys.enc)
        let queued = try await mac.postCmd(cmdEnvelope)
        #expect(queued.queued)
        let cmdFrame = try await connection.receive()
        #expect(cmdFrame.t == .cmd)
        #expect(cmdFrame.envelope.rev == 1)

        let pending = try await iphone.getCmd()
        #expect(pending.items.count == 1)
        let receivedCmd = try openJSON(CommandPlaintext.self, envelope: pending.items[0], pairingId: pairingId, encKey: keys.enc)
        #expect(receivedCmd == command)
        #expect(
            RemotePauseEvaluating.evaluate(
                openSessionId: fromGET.sessionId,
                pausedCount: 0,
                pauseLimit: 2,
                command: receivedCmd
            ) == .apply
        )

        let ackEnvelope = try seal(ack, pairingId: pairingId, kind: .ack, rev: 1, encKey: keys.enc)
        let stored = try await iphone.putAck(ackEnvelope)
        #expect(stored.stored)

        let ackFrame = try await connection.receive()
        #expect(ackFrame.t == .ack)
        let fromAckWS = try openJSON(AckPlaintext.self, envelope: ackFrame.envelope, pairingId: pairingId, encKey: keys.enc)
        #expect(fromAckWS == ack)

        let gotAck = try await mac.getAck()
        let fromAckGET = try openJSON(AckPlaintext.self, envelope: gotAck, pairingId: pairingId, encKey: keys.enc)
        #expect(fromAckGET.ok)
        #expect(fromAckGET.cmdId == command.id)
        #expect(fromAckGET.error == nil)

        let drained = try await iphone.getCmd()
        #expect(drained.items.isEmpty)

        await connection.close()

        let exchanges = await recording.exchanges
        let snapGets = exchanges.filter { $0.0.method == "GET" && $0.0.path == "/v1/snap" }
        let snapGet = try #require(snapGets.last)
        try assertOpaqueEnvelopeJSON(snapGet.1.body, expectedKind: .snap)
        try assertNoPlaintextTitle(in: exchanges, title: E2EConfig.plaintextTitle)
    }

    @Test func oneSidedOpticalDoesNotEstablishPairing() async throws {
        let transport = AbsoluteURLHTTPTransport(baseURL: baseURL)

        let iphoneOnly = PairingFlow(
            role: .iphone,
            client: SyncHTTPClient(baseURL: baseURL, transport: transport),
            secrets: InMemorySecretStore(),
            localAuth: ImmediateLocalAuth()
        )
        let macUnread = PairingFlow(
            role: .mac,
            client: SyncHTTPClient(baseURL: baseURL, transport: transport),
            secrets: InMemorySecretStore(),
            localAuth: ImmediateLocalAuth()
        )
        _ = try await iphoneOnly.presentQR()
        let macQR = try await macUnread.presentQR()
        let iphoneBind = try await iphoneOnly.ingestOptical(macQR.encoded)
        #expect(!iphoneBind.bound)
        #expect(await iphoneOnly.phase == .binding)
        await #expect(throws: SyncError.pairingNotBound) {
            try await iphoneOnly.authenticateAndConfirm()
        }

        let iphoneUnreadStore = InMemorySecretStore()
        let macOnlyStore = InMemorySecretStore()
        let iphoneUnread = PairingFlow(
            role: .iphone,
            client: SyncHTTPClient(baseURL: baseURL, transport: transport),
            secrets: iphoneUnreadStore,
            localAuth: ImmediateLocalAuth()
        )
        let macOnly = PairingFlow(
            role: .mac,
            client: SyncHTTPClient(baseURL: baseURL, transport: transport),
            secrets: macOnlyStore,
            localAuth: ImmediateLocalAuth()
        )
        let iphoneQR = try await iphoneUnread.presentQR()
        _ = try await macOnly.presentQR()
        let macBind = try await macOnly.ingestOptical(iphoneQR.encoded)
        #expect(!macBind.bound)
        #expect(await macOnly.phase == .binding)
        await #expect(throws: SyncError.pairingNotBound) {
            try await macOnly.authenticateAndConfirm()
        }
        #expect(try iphoneUnreadStore.load() == nil)
        #expect(try macOnlyStore.load() == nil)
    }

    @Test func oneSidedConfirmDoesNotEstablishPairing() async throws {
        let transport = AbsoluteURLHTTPTransport(baseURL: baseURL)
        let iphoneStore = InMemorySecretStore()
        let macStore = InMemorySecretStore()
        let iphone = PairingFlow(
            role: .iphone,
            client: SyncHTTPClient(baseURL: baseURL, transport: transport),
            secrets: iphoneStore,
            localAuth: ImmediateLocalAuth()
        )
        let mac = PairingFlow(
            role: .mac,
            client: SyncHTTPClient(baseURL: baseURL, transport: transport),
            secrets: macStore,
            localAuth: ImmediateLocalAuth()
        )
        let iphoneQR = try await iphone.presentQR()
        let macQR = try await mac.presentQR()
        _ = try await iphone.ingestOptical(macQR.encoded)
        _ = try await mac.ingestOptical(iphoneQR.encoded)
        try await bindUntilBound(iphone)
        try await bindUntilBound(mac)

        try await iphone.authenticateAndConfirm()
        #expect(await iphone.phase == .confirming)
        #expect(await mac.phase == .awaitingLocalAuth)
        #expect(try iphoneStore.load() == nil)
        #expect(try macStore.load() == nil)

        let unauthorized = SyncHTTPClient(
            baseURL: baseURL,
            transport: transport,
            writeToken: Data(repeating: 9, count: 32)
        )
        await #expect(throws: SyncError.transport(status: 401, code: "unauthorized")) {
            _ = try await unauthorized.getSnap()
        }
    }
}
