import Foundation
import Observation
import ServiceManagement
import TodoTrainSync

@Observable
@MainActor
final class CompanionMacRuntime {
    private enum Defaults {
        static let relayURL = "companion.relayURL"
        static let cmdRev = "companion.cmdRev"
        static let loginItemOptOut = "companion.loginItemOptOut"
        static let cabinEnabled = "companion.cabinAnnouncementsEnabled"
        static let cabinOptimisticSession = "companion.cabinOptimisticSession"
        static let cabinOptimisticFired = "companion.cabinOptimisticFired"
    }

    private let secrets: any SecretStoring
    private let localAuth: any LocalAuthenticating
    private let defaults: UserDefaults
    private let registersLoginItem: Bool
    private var listenTask: Task<Void, Never>?
    private var hintTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var pairingFlow: PairingFlow?
    private var pairingBindTask: Task<Void, Never>?
    private var pairingConfirmTask: Task<Void, Never>?
    private var pairingUIVisible = false
    private var pairingEpoch = 0

    private(set) var isPaired = false
    private(set) var companionName: String?
    private(set) var pairingShortID: String?
    private(set) var snap: SnapPlaintext?
    private(set) var connection: ConnectionStatus = .disconnected
    private(set) var outgoingPause: OutgoingPauseState = .idle
    private(set) var now = Int(Date().timeIntervalSince1970)
    private(set) var lastStatus: String?
    private(set) var pairingPhase: PairingPhase = .idle
    private(set) var pairingQR: PairingURL?
    private(set) var pairingCue: PairingCue = .scanning
    private(set) var pairingScanGeneration = 0
    var relayURLString: String {
        didSet { defaults.set(relayURLString, forKey: Defaults.relayURL) }
    }

    var loginAtStartup: Bool {
        didSet {
            defaults.set(!loginAtStartup, forKey: Defaults.loginItemOptOut)
            applyLoginItem()
        }
    }

    var cabinAnnouncementsEnabled: Bool {
        didSet { defaults.set(cabinAnnouncementsEnabled, forKey: Defaults.cabinEnabled) }
    }

    init(
        secrets: any SecretStoring = KeychainSecretStore(),
        localAuth: any LocalAuthenticating = DeviceLocalAuth(),
        defaults: UserDefaults = .standard,
        registersLoginItem: Bool = true
    ) {
        self.secrets = secrets
        self.localAuth = localAuth
        self.defaults = defaults
        self.registersLoginItem = registersLoginItem
        let url = RelayEndpoint.coalesceStored(defaults.string(forKey: Defaults.relayURL))
        self.relayURLString = url
        if defaults.string(forKey: Defaults.relayURL) != url {
            defaults.set(url, forKey: Defaults.relayURL)
        }
        self.loginAtStartup = defaults.object(forKey: Defaults.loginItemOptOut) as? Bool != true
        if defaults.object(forKey: Defaults.cabinEnabled) == nil {
            self.cabinAnnouncementsEnabled = true
        } else {
            self.cabinAnnouncementsEnabled = defaults.bool(forKey: Defaults.cabinEnabled)
        }
        refreshPaired()
        applyLoginItem()
        startTicking()
        if isPaired {
            startListening()
        }
    }

    var relayURL: URL? { URL(string: relayURLString) }

    var menuBarInput: MenuBarInput {
        MenuBarInput(
            pairing: isPaired ? .paired : .unpaired,
            snap: snap,
            now: now,
            connection: connection,
            outgoingPause: outgoingPause,
            cabinEnabledLocal: cabinAnnouncementsEnabled,
            optimisticFiredCount: optimisticFiredCount
        )
    }

    var presentation: MenuBarPresentation {
        MenuBarPresentation.make(menuBarInput)
    }

    var overlayPresentation: RideOverlayPresentation {
        RideOverlayPresentation.make(menuBarInput)
    }

    func refreshPaired() {
        guard var pairing = try? secrets.load() else {
            isPaired = false
            companionName = nil
            pairingShortID = nil
            return
        }
        isPaired = true
        if pairing.companionName == nil {
            pairing.companionName = MacComputerName.current()
            try? secrets.save(pairing)
        }
        companionName = pairing.companionName
        pairingShortID = pairing.shortPairingID
    }

    func makeFlow() throws -> PairingFlow {
        let url = try requireRelay()
        let client = SyncHTTPClient(
            baseURL: url,
            transport: CompanionHTTPTransport(baseURL: url)
        )
        return PairingFlow(
            role: .mac,
            client: client,
            secrets: secrets,
            localAuth: OnceLocalAuth(localAuth)
        )
    }

    func pairingDidEstablish() {
        refreshPaired()
        lastStatus = nil
        startListening()
    }

    func reconnect() {
        guard isPaired else { return }
        startListening()
    }

    func unpair() {
        pairingBindTask?.cancel()
        pairingConfirmTask?.cancel()
        pairingBindTask = nil
        pairingConfirmTask = nil
        pairingFlow = nil
        pairingPhase = .idle
        pairingQR = nil
        pairingCue = .scanning
        listenTask?.cancel()
        listenTask = nil
        hintTask?.cancel()
        hintTask = nil
        try? secrets.delete()
        snap = nil
        outgoingPause = .idle
        lastStatus = nil
        connection = .disconnected
        clearOptimisticCabin()
        refreshPaired()
    }

    var pairingCameraActive: Bool {
        guard pairingUIVisible, !isPaired else { return false }
        switch pairingPhase {
        case .presentingQR, .peerRead, .binding, .idle:
            switch pairingCue {
            case .authenticating, .established:
                return false
            default:
                return true
            }
        default:
            return false
        }
    }

    func pairingUIDidAppear() {
        pairingUIVisible = true
        if isPaired { return }
        switch pairingPhase {
        case .idle, .aborted:
            startPairing()
        default:
            if pairingCue.isFailed { startPairing() }
        }
    }

    func pairingUIDidDisappear() {
        pairingUIVisible = false
        switch pairingPhase {
        case .idle, .presentingQR, .aborted:
            abandonPairing(keepFailure: false)
        default:
            break
        }
    }

    func ingestOptical(_ urlString: String) {
        switch pairingPhase {
        case .presentingQR, .idle:
            break
        default:
            return
        }
        Task { await ingest(urlString) }
    }

    private func startPairing() {
        abandonPairing(keepFailure: false)
        let epoch = pairingEpoch
        pairingScanGeneration += 1
        pairingCue = .scanning
        Task { await presentPairingQR(epoch: epoch) }
    }

    private func abandonPairing(keepFailure: Bool) {
        pairingEpoch += 1
        pairingBindTask?.cancel()
        pairingConfirmTask?.cancel()
        let flow = pairingFlow
        pairingFlow = nil
        pairingQR = nil
        pairingPhase = keepFailure ? pairingPhase : .idle
        if !keepFailure { pairingCue = .scanning }
        Task { try? await flow?.abort() }
    }

    private func presentPairingQR(epoch: Int) async {
        do {
            let pairing = try makeFlow()
            guard pairingEpoch == epoch else {
                try? await pairing.abort()
                return
            }
            pairingFlow = pairing
            pairingQR = try await pairing.presentQR(displayName: MacComputerName.current())
            guard pairingEpoch == epoch else {
                try? await pairing.abort()
                return
            }
            pairingPhase = await pairing.phase
            pairingCue = .scanning
        } catch {
            guard pairingEpoch == epoch else { return }
            pairingCue = .failed("リレー URL を設定に書いてから、もう一度。")
        }
    }

    private func ingest(_ urlString: String) async {
        guard let flow = pairingFlow else { return }
        do {
            let response = try await flow.ingestOptical(urlString)
            pairingPhase = await flow.phase
            pairingCue = .captured
            if response.bound {
                pairingCue = .authenticating
                beginConfirm(flow)
            } else {
                pairingCue = .waitingPeer
                pairingBindTask?.cancel()
                pairingBindTask = Task { await pollBind(flow) }
            }
        } catch {
            pairingScanGeneration += 1
            pairingCue = .failed("その QR ではつながらない")
        }
    }

    private func pollBind(_ flow: PairingFlow) async {
        let deadline = Date().addingTimeInterval(TimeInterval(SyncConstants.offerTtlSeconds))
        while Date() < deadline {
            if Task.isCancelled { return }
            do {
                let response = try await flow.refreshBind()
                pairingPhase = await flow.phase
                if response.bound {
                    pairingCue = .authenticating
                    beginConfirm(flow)
                    return
                }
            } catch {
                pairingCue = .failed("つなぎ直しが必要")
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        pairingCue = .failed("つなぎ直しが必要")
    }

    private func beginConfirm(_ flow: PairingFlow) {
        pairingConfirmTask?.cancel()
        pairingConfirmTask = Task { await confirm(flow) }
    }

    private func confirm(_ flow: PairingFlow) async {
        pairingCue = .authenticating
        do {
            try await flow.authenticateAndConfirm()
            pairingPhase = await flow.phase
            if pairingPhase == .established {
                pairingCue = .established
                try? await Task.sleep(nanoseconds: 900_000_000)
                if Task.isCancelled { return }
                pairingDidEstablish()
                return
            }
            pairingCue = .failed("確定できなかった。自分に戻してからもう一度。")
        } catch is CancellationError {
            return
        } catch SyncError.confirmTimedOut {
            pairingCue = .failed("確定の時間切れ。自分に戻してもう一度。")
        } catch SyncError.pairingAborted {
            pairingCue = .failed("確定できなかった。自分に戻してからもう一度。")
        } catch {
            pairingCue = .failed(pairingCopy(error))
        }
    }

    private func pairingCopy(_ error: Error) -> String {
        if let sync = error as? SyncError {
            switch sync {
            case .invalidPairingURL: "その QR ではつながらない"
            case .confirmTimedOut: "確定の時間切れ。自分に戻してもう一度。"
            case .pairingAborted: "確定できなかった。自分に戻してからもう一度。"
            case .transport(_, let code) where code == "confirmWindow":
                "確定の時間切れ。自分に戻してもう一度。"
            default: "つなぎ直しが必要"
            }
        } else {
            "つなぎ直しが必要"
        }
    }

    func sendPause() async {
        await sendRideCommand(.pause)
    }

    func sendResume() async {
        await sendRideCommand(.resume)
    }

    func sendStill() async {
        guard overlayPresentation.cabinPrompt != nil, !presentation.isSending else { return }
        if let sessionId = snap?.sessionId {
            markOptimisticCabin(sessionId: sessionId, firedCount: (snap?.checkInFiredCount ?? 0) + 1)
        }
        await sendRideCommand(.still)
    }

    private func sendRideCommand(_ op: WireOp) async {
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
            let envelope = try CompanionEnvelope.seal(
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
            if op == .still { clearOptimisticCabin() }
        }
    }

    private var cmdRev: Int {
        get { defaults.integer(forKey: Defaults.cmdRev) }
        set { defaults.set(newValue, forKey: Defaults.cmdRev) }
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.now = Int(Date().timeIntervalSince1970)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func startListening() {
        hintTask?.cancel()
        hintTask = nil
        listenTask?.cancel()
        listenTask = Task { [weak self] in
            await self?.connectOnce()
        }
    }

    private func startHintPolling() {
        guard HintPolling.shouldPoll(isPaired: isPaired, connection: connection) else { return }
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            await self?.pollHints()
        }
    }

    private func connectOnce() async {
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

    private func pullSnapAndAck() async throws {
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

    private func pollHints() async {
        var previous: HintPlaintext?
        var etag: String?
        while !Task.isCancelled {
            guard HintPolling.shouldPoll(isPaired: isPaired, connection: connection) else { return }
            do {
                let pairing = try requireSecrets()
                let client = try authedClient(pairing)
                let result = try await client.getHint(pairingId: pairing.pairingId, etag: etag)
                let status = result.notModified ? 304 : 200
                switch HintPolling.outcome(
                    subscriber: .mac,
                    previous: previous,
                    status: status,
                    hint: result.hint,
                    responseETag: result.etag
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

    private func listenWebSocket() async throws {
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

    private func applySnap(_ envelope: Envelope, pairingId: UUID, encKey: Data) throws {
        snap = try CompanionEnvelope.open(SnapPlaintext.self, envelope: envelope, pairingId: pairingId, encKey: encKey)
        reconcileOptimisticCabin()
    }

    private func applyAck(_ envelope: Envelope, pairingId: UUID, encKey: Data) throws {
        let ack = try CompanionEnvelope.open(AckPlaintext.self, envelope: envelope, pairingId: pairingId, encKey: encKey)
        outgoingPause = OutgoingPauseApplying.applyAck(ack, current: outgoingPause)
        if case .failed = outgoingPause {
            clearOptimisticCabin()
        }
    }

    private var optimisticFiredCount: Int {
        guard let sessionId = snap?.sessionId,
              defaults.string(forKey: Defaults.cabinOptimisticSession) == sessionId.uuidString.lowercased() else {
            return 0
        }
        return defaults.integer(forKey: Defaults.cabinOptimisticFired)
    }

    private func markOptimisticCabin(sessionId: UUID, firedCount: Int) {
        defaults.set(sessionId.uuidString.lowercased(), forKey: Defaults.cabinOptimisticSession)
        defaults.set(firedCount, forKey: Defaults.cabinOptimisticFired)
    }

    private func clearOptimisticCabin() {
        defaults.removeObject(forKey: Defaults.cabinOptimisticSession)
        defaults.removeObject(forKey: Defaults.cabinOptimisticFired)
    }

    private func reconcileOptimisticCabin() {
        guard let snap else {
            clearOptimisticCabin()
            return
        }
        let stored = defaults.string(forKey: Defaults.cabinOptimisticSession)
        if stored != snap.sessionId?.uuidString.lowercased() {
            clearOptimisticCabin()
            return
        }
        if snap.checkInFiredCount >= defaults.integer(forKey: Defaults.cabinOptimisticFired) {
            clearOptimisticCabin()
        }
    }

    private func authedClient(_ pairing: PairingSecrets) throws -> SyncHTTPClient {
        let url = try requireRelay()
        return SyncHTTPClient(
            baseURL: url,
            transport: CompanionHTTPTransport(baseURL: url),
            writeToken: pairing.writeToken,
            pairingId: pairing.pairingId
        )
    }

    private func requireRelay() throws -> URL {
        guard let url = relayURL else { throw SyncError.invalidPairingURL }
        return url
    }

    private func requireSecrets() throws -> PairingSecrets {
        guard let pairing = try secrets.load() else { throw SyncError.notPaired }
        return pairing
    }

    private func applyLoginItem() {
        guard registersLoginItem else { return }
        do {
            if loginAtStartup {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // already registered / not registered は無視
        }
    }

    private func userFacing(_ error: Error) -> String {
        if let sync = error as? SyncError {
            switch sync {
            case .notPaired: "つながっていない"
            case .pairingAborted: "確定できなかった"
            default: "リレーが切れた"
            }
        } else {
            "リレーが切れた"
        }
    }
}
