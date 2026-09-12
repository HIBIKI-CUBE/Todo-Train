import Foundation
import Observation
import SwiftUI
import TodoTrainSync

@Observable
@MainActor
final class CompanionSyncRuntime {
    private enum Defaults {
        static let snapRev = "companion.snapRev"
        static let processedCmdIDs = "companion.processedCmdIDs"
    }

    private let secrets: any SecretStoring
    private let settings: AppSettings
    private let localAuth: any LocalAuthenticating
    private let defaults: UserDefaults
    private var foregroundTask: Task<Void, Never>?
    private var pushTask: Task<Void, Never>?
    private var processedCommandIDs: Set<UUID>

    private(set) var isPaired = false
    private(set) var companionName: String?
    private(set) var pairingShortID: String?
    private(set) var lastStatus: String?

    init(
        secrets: any SecretStoring = KeychainSecretStore(),
        settings: AppSettings = .shared,
        localAuth: any LocalAuthenticating = DeviceLocalAuth(),
        defaults: UserDefaults = .standard
    ) {
        self.secrets = secrets
        self.settings = settings
        self.localAuth = localAuth
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: Defaults.processedCmdIDs) ?? []
        self.processedCommandIDs = Set(stored.compactMap(UUID.init(uuidString:)))
        refreshPaired()
    }

    var relayURL: URL? { settings.companionRelayURL }

    func refreshPaired() {
        let pairing = try? secrets.load()
        isPaired = pairing != nil
        companionName = pairing?.companionName
        pairingShortID = pairing?.shortPairingID
    }

    func noteSessionChanged(sessionManager: SessionManager) {
        guard isPaired else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            await self?.syncNow(sessionManager: sessionManager)
        }
    }

    func makeFlow() throws -> PairingFlow {
        let url = try requireRelay()
        let client = SyncHTTPClient(
            baseURL: url,
            transport: CompanionHTTPTransport(baseURL: url)
        )
        return PairingFlow(
            role: .iphone,
            client: client,
            secrets: secrets,
            localAuth: localAuth
        )
    }

    func unpair() throws {
        try secrets.delete()
        snapRev = 0
        processedCommandIDs = []
        persistProcessed()
        refreshPaired()
        lastStatus = nil
    }

    func handleScenePhase(_ phase: ScenePhase, sessionManager: SessionManager) {
        switch phase {
        case .active:
            foregroundTask?.cancel()
            foregroundTask = Task { [weak self] in
                await self?.runForeground(sessionManager: sessionManager)
            }
        default:
            foregroundTask?.cancel()
            foregroundTask = nil
        }
    }

    func syncNow(sessionManager: SessionManager) async {
        do {
            try await pullCommandsAndPushSnap(sessionManager: sessionManager)
            lastStatus = nil
        } catch {
            lastStatus = userFacing(error)
        }
    }

    private func runForeground(sessionManager: SessionManager) async {
        refreshPaired()
        guard isPaired else { return }
        await syncNow(sessionManager: sessionManager)
        guard !Task.isCancelled else { return }
        await listenWebSocket(sessionManager: sessionManager)
    }

    private func listenWebSocket(sessionManager: SessionManager) async {
        guard let pairing = try? secrets.load(), let url = relayURL else { return }
        let connector = URLSessionWebSocketConnecting(baseURL: url)
        let socket = BearerWebSocket(writeToken: pairing.writeToken, connector: connector)
        let connection: any WebSocketConnection
        do {
            connection = try await socket.connect()
        } catch {
            lastStatus = userFacing(error)
            return
        }
        defer { Task { await connection.close() } }
        while !Task.isCancelled {
            do {
                let frame = try await connection.receive()
                if frame.t == .cmd {
                    try await handleCommandEnvelope(frame.envelope, sessionManager: sessionManager)
                    try await pushSnap(sessionManager: sessionManager)
                }
            } catch {
                if Task.isCancelled { return }
                lastStatus = userFacing(error)
                return
            }
        }
    }

    private func pullCommandsAndPushSnap(sessionManager: SessionManager) async throws {
        guard let pairing = try secrets.load() else { return }
        let keys = try SyncCrypto.deriveKeys(masterKey: pairing.masterKey, pairingId: pairing.pairingId)
        let client = try authedClient(writeToken: pairing.writeToken)
        let listed = try await client.getCmd()
        for envelope in listed.items {
            try await applyCommand(
                envelope: envelope,
                pairingId: pairing.pairingId,
                encKey: keys.enc,
                client: client,
                sessionManager: sessionManager
            )
        }
        try await pushSnap(
            sessionManager: sessionManager,
            pairing: pairing,
            encKey: keys.enc,
            client: client
        )
    }

    private func handleCommandEnvelope(
        _ envelope: Envelope,
        sessionManager: SessionManager
    ) async throws {
        guard let pairing = try secrets.load() else { return }
        let keys = try SyncCrypto.deriveKeys(masterKey: pairing.masterKey, pairingId: pairing.pairingId)
        let client = try authedClient(writeToken: pairing.writeToken)
        try await applyCommand(
            envelope: envelope,
            pairingId: pairing.pairingId,
            encKey: keys.enc,
            client: client,
            sessionManager: sessionManager
        )
    }

    private func applyCommand(
        envelope: Envelope,
        pairingId: UUID,
        encKey: Data,
        client: SyncHTTPClient,
        sessionManager: SessionManager
    ) async throws {
        let command = try CompanionEnvelope.open(
            CommandPlaintext.self,
            envelope: envelope,
            pairingId: pairingId,
            encKey: encKey
        )
        if processedCommandIDs.contains(command.id) { return }
        let decision = RemotePauseEvaluating.evaluate(
            openSessionId: sessionManager.activeSession?.id,
            pausedCount: sessionManager.pausedTicketCount,
            pauseLimit: sessionManager.pauseLimit,
            command: command
        )
        if CompanionCommandApplying.shouldCallPause(decision) {
            try sessionManager.pause()
        }
        let ack = RemotePauseEvaluating.ack(decision: decision, commandId: command.id)
        let ackEnvelope = try CompanionEnvelope.seal(
            ack,
            pairingId: pairingId,
            kind: .ack,
            rev: envelope.rev,
            encKey: encKey
        )
        _ = try await client.putAck(ackEnvelope)
        processedCommandIDs.insert(command.id)
        persistProcessed()
    }

    private func pushSnap(sessionManager: SessionManager) async throws {
        guard let pairing = try secrets.load() else { return }
        let keys = try SyncCrypto.deriveKeys(masterKey: pairing.masterKey, pairingId: pairing.pairingId)
        let client = try authedClient(writeToken: pairing.writeToken)
        try await pushSnap(
            sessionManager: sessionManager,
            pairing: pairing,
            encKey: keys.enc,
            client: client
        )
    }

    private func pushSnap(
        sessionManager: SessionManager,
        pairing: PairingSecrets,
        encKey: Data,
        client: SyncHTTPClient
    ) async throws {
        snapRev += 1
        let plaintext = CompanionSnapBuilding.snap(
            rev: snapRev,
            phase: sessionManager.phase,
            session: sessionManager.activeSession,
            now: Date()
        )
        let envelope = try CompanionEnvelope.seal(
            plaintext,
            pairingId: pairing.pairingId,
            kind: .snap,
            rev: snapRev,
            encKey: encKey
        )
        _ = try await client.putSnap(envelope)
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
        guard let url = settings.companionRelayURL else {
            throw SyncError.invalidPairingURL
        }
        return url
    }

    private var snapRev: Int {
        get { defaults.integer(forKey: Defaults.snapRev) }
        set { defaults.set(newValue, forKey: Defaults.snapRev) }
    }

    private func persistProcessed() {
        let kept = processedCommandIDs.prefix(32).map(\.uuidString)
        defaults.set(Array(kept), forKey: Defaults.processedCmdIDs)
    }

    private func userFacing(_ error: Error) -> String {
        if let sync = error as? SyncError {
            switch sync {
            case .notPaired, .pairingAborted, .pairingNotBound:
                return "つながっていません"
            case .confirmTimedOut:
                return "確定の時間切れ。もう一度画面を向けてください"
            case .transport(_, let code) where code == "pauseLimitReached":
                return "停車できません（停車上限）"
            default:
                return "iPhone とつながっていない"
            }
        }
        return "iPhone とつながっていない"
    }
}
