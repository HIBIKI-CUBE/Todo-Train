import Foundation
import Observation
import ServiceManagement
import TodoTrainSync

@Observable
@MainActor
final class CompanionMacRuntime {
    enum Defaults {
        static let relayURL = "companion.relayURL"
        static let cmdRev = "companion.cmdRev"
        static let loginItemOptOut = "companion.loginItemOptOut"
        static let cabinEnabled = "companion.cabinAnnouncementsEnabled"
        static let cabinOptimisticSession = "companion.cabinOptimisticSession"
        static let cabinOptimisticFired = "companion.cabinOptimisticFired"
    }

    let secrets: any SecretStoring
    let localAuth: any LocalAuthenticating
    let defaults: UserDefaults
    let registersLoginItem: Bool
    var listenTask: Task<Void, Never>?
    var hintTask: Task<Void, Never>?
    var tickTask: Task<Void, Never>?
    var presence = RelayPresence()
    let cabinNotifier = CompanionCabinNotifier()
    var optimisticIdleConsumed = false
    var pairingFlow: PairingFlow?
    var pairingBindTask: Task<Void, Never>?
    var pairingConfirmTask: Task<Void, Never>?
    var pairingUIVisible = false
    var pairingEpoch = 0

    var isPaired = false
    var companionName: String?
    var pairingShortID: String?
    var snap: SnapPlaintext?
    var connection: ConnectionStatus = .disconnected
    var outgoingPause: OutgoingPauseState = .idle
    var now = Int(Date().timeIntervalSince1970)
    var lastStatus: String?
    var sentTimetablePauseAt: Int?
    var pairingPhase: PairingPhase = .idle
    var pairingQR: PairingURL?
    var pairingCue: PairingCue = .scanning
    var pairingScanGeneration = 0
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
        localAuth: any LocalAuthenticating = DeviceLocalAuth(reason: SyncCopy.macConfirmReason),
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
        cabinNotifier.configure()
        cabinNotifier.onStill = { [weak self] in
            Task { await self?.sendStill() }
        }
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
            optimisticFiredCount: optimisticFiredCount,
            optimisticIdleConsumed: optimisticIdleConsumed
        )
    }

    var presentation: MenuBarPresentation {
        MenuBarPresentation.make(menuBarInput)
    }

    var overlayPresentation: RideOverlayPresentation {
        RideOverlayPresentation.make(menuBarInput)
    }

    var cabinInterrupt: CabinInterrupt {
        CabinInterruptWatch.evaluate(
            snap: snap,
            now: now,
            localEnabled: cabinAnnouncementsEnabled,
            optimisticFiredCount: optimisticFiredCount,
            optimisticIdleConsumed: optimisticIdleConsumed
        )
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


    func authedClient(_ pairing: PairingSecrets) throws -> SyncHTTPClient {
        let url = try requireRelay()
        return SyncHTTPClient(
            baseURL: url,
            transport: URLSessionHTTPTransport(baseURL: url),
            writeToken: pairing.writeToken,
            pairingId: pairing.pairingId
        )
    }

    func requireRelay() throws -> URL {
        guard let url = relayURL else { throw SyncError.invalidPairingURL }
        return url
    }

    func requireSecrets() throws -> PairingSecrets {
        guard let pairing = try secrets.load() else { throw SyncError.notPaired }
        return pairing
    }

    func applyLoginItem() {
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

    func userFacing(_ error: Error) -> String {
        SyncCopy.connectionStatus(error)
    }
}
