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
    /// Last build received from the Mac, inside a command.
    private(set) var peerBuild: WireBuildInfo?
    /// Mac contract from a command. Nil until a command arrives.
    private(set) var peerContract: ContractAnnouncement?
    /// Relay contract from hello or hint.
    private(set) var relayContract: ContractAnnouncement?

    init(
        secrets: any SecretStoring = KeychainSecretStore(),
        settings: AppSettings? = nil,
        localAuth: any LocalAuthenticating = DeviceLocalAuth(reason: SyncCopy.iphoneConfirmReason),
        defaults: UserDefaults = .standard
    ) {
        self.secrets = secrets
        self.settings = settings ?? .shared
        self.localAuth = localAuth
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: Defaults.processedCmdIDs) ?? []
        self.processedCommandIDs = Set(stored.compactMap(UUID.init(uuidString:)))
        self.peerBuild = PeerBuildStore.load(from: defaults)
        self.peerContract = PeerContractStore.load(from: defaults, key: PeerContractStore.peerKey)
        self.relayContract = PeerContractStore.load(from: defaults, key: PeerContractStore.relayKey)
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
            try? await Task.sleep(nanoseconds: SyncTiming.snapDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.syncNow(sessionManager: sessionManager)
        }
    }

    func makeFlow() throws -> PairingFlow {
        let url = try requireRelay()
        let client = SyncHTTPClient(
            baseURL: url,
            transport: URLSessionHTTPTransport(baseURL: url)
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
        peerBuild = nil
        PeerBuildStore.save(nil, to: defaults)
        peerContract = nil
        relayContract = nil
        PeerContractStore.save(nil, to: defaults, key: PeerContractStore.peerKey)
        PeerContractStore.save(nil, to: defaults, key: PeerContractStore.relayKey)
        refreshPaired()
        lastStatus = nil
    }

    func handleScenePhase(_ phase: ScenePhase, sessionManager: SessionManager) {
        switch Policy.foregroundLoop(for: phase) {
        case .start:
            guard foregroundTask == nil else { return }
            foregroundTask = Task { [weak self] in
                await self?.runForeground(sessionManager: sessionManager)
            }
        case .keep:
            break
        case .stop:
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
        guard !Task.isCancelled else { return }
        await pollHints(sessionManager: sessionManager)
    }

    private func listenWebSocket(sessionManager: SessionManager) async {
        guard let pairing = try? secrets.load(), let url = relayURL else { return }
        let connector = URLSessionWebSocketConnecting(baseURL: url)
        let socket = BearerWebSocket(
            writeToken: pairing.writeToken,
            pairingId: pairing.pairingId,
            connector: connector
        )
        let connection: any WebSocketConnection
        do {
            connection = try await socket.connect()
        } catch {
            lastStatus = userFacing(error)
            sessionManager.noteMacPresenceUnreachable()
            return
        }
        defer { Task { await connection.close() } }
        while !Task.isCancelled {
            let incoming: WSIncoming
            do {
                incoming = try await connection.receiveIncoming()
            } catch is CancellationError {
                return
            } catch SyncError.invalidJSON {
                continue
            } catch {
                if Task.isCancelled { return }
                lastStatus = userFacing(error)
                sessionManager.noteMacPresenceUnreachable()
                return
            }
            switch incoming {
            case .hello(let announcement):
                noteRelayContract(announcement)
            case .frame(let frame):
                do {
                    if frame.t == .cmd {
                        try await handleCommandEnvelope(frame.envelope, sessionManager: sessionManager)
                        try await pushSnap(sessionManager: sessionManager)
                    }
                } catch {
                    lastStatus = userFacing(error)
                }
            }
        }
    }

    private func pollHints(sessionManager: SessionManager) async {
        var previous: HintPlaintext?
        var etag: String?
        while !Task.isCancelled {
            do {
                guard let pairing = try secrets.load() else { return }
                let client = try authedClient(pairing)
                let result = try await client.getHint(pairingId: pairing.pairingId, etag: etag)
                switch HintPolling.outcome(
                    subscriber: .iphone,
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
                    if catchUp.cmd {
                        try await pullCommandsAndPushSnap(sessionManager: sessionManager)
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
                sessionManager.noteMacPresenceUnreachable()
            }
            try? await Task.sleep(nanoseconds: HintPolling.intervalNanoseconds)
        }
    }

    private func pullCommandsAndPushSnap(sessionManager: SessionManager) async throws {
        guard let pairing = try secrets.load() else { return }
        let keys = try SyncCrypto.deriveKeys(masterKey: pairing.masterKey, pairingId: pairing.pairingId)
        let client = try authedClient(pairing)
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
        let client = try authedClient(pairing)
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
        let command = try SyncCrypto.openJSON(
            CommandPlaintext.self,
            envelope: envelope,
            pairingId: pairingId,
            encKey: encKey
        )
        if let build = command.build {
            peerBuild = build
            PeerBuildStore.save(build, to: defaults)
        }
        notePeerContract(command.announcement)
        if processedCommandIDs.contains(command.id) { return }
        var ack = try CompanionCommandApplying.apply(command, sessionManager: sessionManager)
        ack.build = LocalWireBuild.current
        ack.contract = ContractVersion.contract
        ack.minReadable = ContractVersion.minReadable
        let ackEnvelope = try SyncCrypto.sealJSON(
            ack,
            pairingId: pairingId,
            kind: .ack,
            rev: envelope.rev,
            encKey: encKey
        )
        // issueAndBoard has already boarded. A debounced snap push re-pulls cmds
        // during putAck; applying twice acks sessionMismatch and the Mac drops the ride.
        if command.op == .issueAndBoard {
            processedCommandIDs.insert(command.id)
            persistProcessed()
        }
        _ = try await client.putAck(ackEnvelope)
        if command.op != .issueAndBoard {
            processedCommandIDs.insert(command.id)
            persistProcessed()
        }
    }

    private func pushSnap(sessionManager: SessionManager) async throws {
        guard let pairing = try secrets.load() else { return }
        let keys = try SyncCrypto.deriveKeys(masterKey: pairing.masterKey, pairingId: pairing.pairingId)
        let client = try authedClient(pairing)
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
        let now = Date()
        let plaintext = RideWireSnap.make(
            sessionManager: sessionManager,
            settings: settings,
            rev: snapRev,
            now: now
        )
        let envelope = try SyncCrypto.sealJSON(
            plaintext,
            pairingId: pairing.pairingId,
            kind: .snap,
            rev: snapRev,
            encKey: encKey
        )
        _ = try await client.putSnap(envelope)
    }

    private func authedClient(_ pairing: PairingSecrets) throws -> SyncHTTPClient {
        let url = try requireRelay()
        return SyncHTTPClient(
            baseURL: url,
            transport: URLSessionHTTPTransport(baseURL: url),
            writeToken: pairing.writeToken,
            pairingId: pairing.pairingId
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

    private func notePeerContract(_ announcement: ContractAnnouncement) {
        peerContract = announcement
        PeerContractStore.save(announcement, to: defaults, key: PeerContractStore.peerKey)
    }

    private func noteRelayContract(_ announcement: ContractAnnouncement) {
        relayContract = announcement
        PeerContractStore.save(announcement, to: defaults, key: PeerContractStore.relayKey)
    }

    private func userFacing(_ error: Error) -> String {
        SyncCopy.connectionStatus(error)
    }
}

extension CompanionSyncRuntime {
    /// Pairing, scene phase, and whether progress notifications stay quiet.
    enum Policy {
        enum ForegroundLoop: Equatable {
            /// `.active` starts the foreground sync loop.
            case start
            /// `.inactive` leaves the loop as it is.
            case keep
            /// `.background` stops the loop.
            case stop
        }

        /// Progress notifications stay off while a companion is paired. Scene phase does not change this.
        static func suppressProgressNotifications(isPaired: Bool) -> Bool {
            isPaired
        }

        static func foregroundLoop(for phase: ScenePhase) -> ForegroundLoop {
            switch phase {
            case .active: .start
            case .inactive: .keep
            case .background: .stop
            @unknown default: .stop
            }
        }
    }
}
