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
    /// When the relay last confirmed `snap`. A dropped relay leaves this behind.
    var snapConfirmedAt: Date?
    var connection: ConnectionStatus = .disconnected
    var outgoingPause: OutgoingPauseState = .idle
    var issueBoardTrack: IssueBoardTrack = .idle
    /// Hide the ride PiP while いまやる is in flight, so it appears under the dispensed ticket.
    var suppressRideOverlay = false
    var now = Int(Date().timeIntervalSince1970)
    var lastStatus: String?
    /// Last build received from the iPhone, inside a snap or ack.
    var peerBuild: WireBuildInfo?
    /// iPhone contract from a snap or ack. Nil until one arrives.
    var peerContract: ContractAnnouncement?
    /// Relay contract from hello or hint.
    var relayContract: ContractAnnouncement?
    var sentTimetablePauseAt: Int?
    /// Extend answer in flight, in minutes. Nil for the other three answers.
    var pendingExtendMinutes: Int?
    var answerEstimateBefore: Int?
    var answerNudgeID: UUID?
    var staleWinner = false
    var nudgeWinnerLine: String?
    var transportNotice: String?
    var screenLocked = false
    var pauseInput = PauseInputEngine()
    var pausePromptLine: String?
    var pendingPauseReports: [UUID: PauseInputReport] = [:]
    var lastPresence: MacPresenceSample?
    var presenceInFlight = false
    var presenceObservers: [NSObjectProtocol] = []
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

    var imaYaruShortcut: ImaYaruShortcut? {
        didSet {
            ImaYaruShortcutStore.write(imaYaruShortcut, to: defaults)
            imaYaruShortcutRejected = !ImaYaruHotKeyCenter.shared.register(imaYaruShortcut)
        }
    }

    var imaYaruShortcutRejected = false

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
        self.imaYaruShortcut = ImaYaruShortcutStore.read(defaults)
        self.peerBuild = PeerBuildStore.load(from: defaults)
        self.peerContract = PeerContractStore.load(from: defaults, key: PeerContractStore.peerKey)
        self.relayContract = PeerContractStore.load(from: defaults, key: PeerContractStore.relayKey)
        refreshPaired()
        applyLoginItem()
        cabinNotifier.configure()
        cabinNotifier.onStill = { [weak self] in
            Task { await self?.sendStill() }
        }
        startTicking()
        startScreenLockObservation()
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
            optimisticIdleConsumed: optimisticIdleConsumed,
            sendingExtendMinutes: pendingExtendMinutes,
            nudgeWinnerLine: nudgeWinnerLine,
            transportNotice: transportNotice,
            pausePromptLine: pausePromptLine
        )
    }

    var presentation: MenuBarPresentation {
        MenuBarPresentation.make(menuBarInput)
    }

    var canOfferImaYaru: Bool {
        ImaYaruOffer.isAvailable(isPaired: isPaired, serviceActive: snap?.serviceActive)
    }

    func openImaYaru() {
        ImaYaruOpener.present?()
    }

    func activateImaYaruShortcut() {
        imaYaruShortcutRejected = !ImaYaruHotKeyCenter.shared.register(imaYaruShortcut)
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
