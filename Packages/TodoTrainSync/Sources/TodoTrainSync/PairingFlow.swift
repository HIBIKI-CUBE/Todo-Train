import Crypto
import Foundation

public enum PairingPhase: Equatable, Sendable {
    case idle
    case presentingQR(PairingURL)
    case peerRead
    case binding
    case awaitingLocalAuth
    case confirming
    case established
    case aborted
}

public struct PairingPeer: Equatable, Sendable {
    public var macSession: UUID
    public var iphonePublic: Data
    public var macPublic: Data
}

/// Pairing state machine: both QR shown → both optical strings ingested → bind → LA.
/// Optical input is a URL string (camera / paste / tests).
public actor PairingFlow {
    public let role: PairingRole
    public private(set) var phase: PairingPhase = .idle

    private var client: SyncHTTPClient
    private let secrets: any SecretStoring
    private let localAuth: any LocalAuthenticating

    private var privateKey: Curve25519.KeyAgreement.PrivateKey?
    private var publicRaw: Data?
    private var ownURL: PairingURL?
    private var offerId: UUID?
    private var pairingId: UUID?
    private var macSession: UUID?
    private var peerPublic: Data?
    private var masterKey: Data?

    public init(
        role: PairingRole,
        client: SyncHTTPClient,
        secrets: any SecretStoring,
        localAuth: any LocalAuthenticating = ImmediateLocalAuth()
    ) {
        self.role = role
        self.client = client
        self.secrets = secrets
        self.localAuth = localAuth
    }

    /// Present this side's QR. iPhone creates the offer; Mac only generates keys.
    @discardableResult
    public func presentQR() async throws -> PairingURL {
        let (privateKey, publicRaw) = SyncCrypto.generateX25519()
        self.privateKey = privateKey
        self.publicRaw = publicRaw

        let url: PairingURL
        switch role {
        case .iphone:
            let offer = try await client.createOffer(x: publicRaw)
            offerId = offer.offerId
            pairingId = offer.pairingId
            url = .iphone(pairingId: offer.pairingId, offerId: offer.offerId, x: publicRaw)
        case .mac:
            let session = UUID()
            macSession = session
            url = .mac(macSession: session, y: publicRaw)
        }
        ownURL = url
        phase = .presentingQR(url)
        return url
    }

    /// Inject an optically-read peer URL, then POST bind once.
    @discardableResult
    public func ingestOptical(_ urlString: String) async throws -> BindResponse {
        guard phase != .aborted else { throw SyncError.pairingAborted }
        let parsed = try PairingURL.parse(urlString)
        try applyPeer(parsed)
        phase = .peerRead
        return try await bind()
    }

    /// Idempotent re-POST of the same bind payload until `bound == true`.
    @discardableResult
    public func refreshBind() async throws -> BindResponse {
        try await bind()
    }

    /// Face ID / Touch ID, then confirm HMAC, then register tokenHash and store secrets.
    public func authenticateAndConfirm() async throws {
        guard phase == .awaitingLocalAuth || phase == .confirming else {
            throw SyncError.pairingNotBound
        }
        try await localAuth.confirmPresence()
        try await confirmUntilEstablished()
    }

    public func abort() async throws {
        if let offerId {
            try? await client.deleteOffer(id: offerId)
        }
        privateKey = nil
        masterKey = nil
        phase = .aborted
    }

    private func applyPeer(_ url: PairingURL) throws {
        switch (role, url) {
        case (.iphone, .mac(let session, let y)):
            macSession = session
            peerPublic = y
        case (.mac, .iphone(let pairing, let offer, let x)):
            pairingId = pairing
            offerId = offer
            peerPublic = x
        default:
            throw SyncError.invalidPairingURL
        }
    }

    private func bind() async throws -> BindResponse {
        guard let offerId, let macSession, let peerPublic, let privateKey, let publicRaw else {
            throw SyncError.invalidPairingURL
        }
        phase = .binding
        let request: BindRequest
        switch role {
        case .iphone:
            request = .iphone(s: macSession, y: peerPublic)
        case .mac:
            request = .mac(s: macSession, x: peerPublic)
        }
        let response = try await client.bindOffer(id: offerId, request: request)
        if response.bound {
            let shared = try SyncCrypto.sharedSecret(privateKey: privateKey, peerPublicRaw: peerPublic)
            masterKey = shared
            pairingId = response.pairingId ?? pairingId
            _ = publicRaw
            phase = .awaitingLocalAuth
        }
        return response
    }

    private func confirmUntilEstablished() async throws {
        guard let offerId, let pairingId, let masterKey else {
            throw SyncError.pairingNotBound
        }
        phase = .confirming
        let keys = try SyncCrypto.deriveKeys(masterKey: masterKey, pairingId: pairingId)
        let hmac = SyncCrypto.confirmHMAC(
            cfmKey: keys.cfm,
            pairingId: pairingId,
            offerId: offerId,
            role: role
        )
        let confirmed: ConfirmResponse
        switch role {
        case .iphone:
            confirmed = try await client.confirmIphone(id: offerId, hmac: hmac)
        case .mac:
            confirmed = try await client.confirmMac(id: offerId, hmac: hmac)
        }
        if !confirmed.confirmed {
            return
        }
        _ = try await client.putPairing(id: pairingId, tokenHash: keys.tokenHashB64U)
        let stored = PairingSecrets(
            pairingId: pairingId,
            masterKey: masterKey,
            writeToken: keys.writeToken
        )
        try secrets.save(stored)
        client.writeToken = keys.writeToken
        phase = .established
    }
}
