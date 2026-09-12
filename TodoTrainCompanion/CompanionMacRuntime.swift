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
    }

    private let secrets: any SecretStoring
    private let localAuth: any LocalAuthenticating
    private let defaults: UserDefaults
    private let registersLoginItem: Bool
    private var listenTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    private(set) var isPaired = false
    private(set) var snap: SnapPlaintext?
    private(set) var connection: ConnectionStatus = .disconnected
    private(set) var outgoingPause: OutgoingPauseState = .idle
    private(set) var now = Int(Date().timeIntervalSince1970)
    private(set) var lastStatus: String?
    var relayURLString: String {
        didSet { defaults.set(relayURLString, forKey: Defaults.relayURL) }
    }

    var loginAtStartup: Bool {
        didSet {
            defaults.set(!loginAtStartup, forKey: Defaults.loginItemOptOut)
            applyLoginItem()
        }
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
        self.relayURLString = defaults.string(forKey: Defaults.relayURL) ?? RelayEndpoint.defaultURLString
        self.loginAtStartup = defaults.object(forKey: Defaults.loginItemOptOut) as? Bool != true
        refreshPaired()
        applyLoginItem()
        startTicking()
        startListening()
    }

    var relayURL: URL? { URL(string: relayURLString) }

    var presentation: MenuBarPresentation {
        MenuBarPresentation.make(
            MenuBarInput(
                pairing: isPaired ? .paired : .unpaired,
                snap: snap,
                now: now,
                connection: connection,
                outgoingPause: outgoingPause
            )
        )
    }

    func refreshPaired() {
        isPaired = (try? secrets.load()) != nil
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

    func sendPause() async {
        guard presentation.canPause else { return }
        guard let snap, let sessionId = snap.sessionId else { return }
        let cmdId = UUID()
        guard let next = OutgoingPauseApplying.beginSending(cmdId: cmdId, current: outgoingPause) else {
            return
        }
        outgoingPause = next
        do {
            let pairing = try requireSecrets()
            let keys = try SyncCrypto.deriveKeys(masterKey: pairing.masterKey, pairingId: pairing.pairingId)
            let client = try authedClient(writeToken: pairing.writeToken)
            let command = CommandPlaintext(
                id: cmdId,
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
        listenTask?.cancel()
        listenTask = Task { [weak self] in
            await self?.runListenLoop()
        }
    }

    private func runListenLoop() async {
        while !Task.isCancelled {
            refreshPaired()
            guard isPaired else {
                connection = .disconnected
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                continue
            }
            do {
                try await pullSnapAndAck()
                await listenWebSocket()
            } catch {
                if Task.isCancelled { return }
                connection = .disconnected
                lastStatus = userFacing(error)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func pullSnapAndAck() async throws {
        let pairing = try requireSecrets()
        let keys = try SyncCrypto.deriveKeys(masterKey: pairing.masterKey, pairingId: pairing.pairingId)
        let client = try authedClient(writeToken: pairing.writeToken)
        if let envelope = try? await client.getSnap() {
            try applySnap(envelope, pairingId: pairing.pairingId, encKey: keys.enc)
        }
        if let envelope = try? await client.getAck() {
            try applyAck(envelope, pairingId: pairing.pairingId, encKey: keys.enc)
        }
        connection = .connected
        lastStatus = nil
    }

    private func listenWebSocket() async {
        guard let pairing = try? secrets.load(), let url = relayURL else { return }
        let connector = URLSessionWebSocketConnecting(baseURL: url)
        let socket = BearerWebSocket(writeToken: pairing.writeToken, connector: connector)
        let connection: any WebSocketConnection
        do {
            connection = try await socket.connect()
            self.connection = .connected
        } catch {
            lastStatus = userFacing(error)
            return
        }
        defer { Task { await connection.close() } }
        while !Task.isCancelled {
            do {
                let frame = try await connection.receive()
                let keys = try SyncCrypto.deriveKeys(masterKey: pairing.masterKey, pairingId: pairing.pairingId)
                switch frame.t {
                case .snap:
                    try applySnap(frame.envelope, pairingId: pairing.pairingId, encKey: keys.enc)
                case .ack:
                    try applyAck(frame.envelope, pairingId: pairing.pairingId, encKey: keys.enc)
                case .cmd:
                    break
                }
            } catch {
                if Task.isCancelled { return }
                self.connection = .disconnected
                lastStatus = userFacing(error)
                return
            }
        }
    }

    private func applySnap(_ envelope: Envelope, pairingId: UUID, encKey: Data) throws {
        snap = try CompanionEnvelope.open(SnapPlaintext.self, envelope: envelope, pairingId: pairingId, encKey: encKey)
        connection = .connected
    }

    private func applyAck(_ envelope: Envelope, pairingId: UUID, encKey: Data) throws {
        let ack = try CompanionEnvelope.open(AckPlaintext.self, envelope: envelope, pairingId: pairingId, encKey: encKey)
        outgoingPause = OutgoingPauseApplying.applyAck(ack, current: outgoingPause)
    }

    private func authedClient(writeToken: Data) throws -> SyncHTTPClient {
        let url = try requireRelay()
        return SyncHTTPClient(
            baseURL: url,
            transport: CompanionHTTPTransport(baseURL: url),
            writeToken: writeToken
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
            default: "iPhone とつながっていない"
            }
        } else {
            "iPhone とつながっていない"
        }
    }
}
