import Crypto
import Foundation

public struct DerivedKeys: Equatable, Sendable {
    public var enc: Data
    public var tok: Data
    public var cfm: Data

    public init(enc: Data, tok: Data, cfm: Data) {
        self.enc = enc
        self.tok = tok
        self.cfm = cfm
    }

    public var writeToken: Data { tok }

    public var tokenHash: Data {
        Data(SHA256.hash(data: tok))
    }

    public var writeTokenBearer: String { Base64URL.encode(tok) }
    public var tokenHashB64U: String { Base64URL.encode(tokenHash) }
}

public enum SyncCrypto {
    public static func randomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        var bytes = [UInt8](repeating: 0, count: count)
        for i in bytes.indices {
            bytes[i] = UInt8.random(in: 0...255, using: &generator)
        }
        return Data(bytes)
    }

    public static func generateX25519() -> (privateKey: Curve25519.KeyAgreement.PrivateKey, publicRaw: Data) {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        return (privateKey, privateKey.publicKey.rawRepresentation)
    }

    public static func sharedSecret(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        peerPublicRaw: Data
    ) throws -> Data {
        let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicRaw)
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: peer)
        return secret.withUnsafeBytes { Data($0) }
    }

    public static func deriveKeys(masterKey: Data, pairingId: UUID) throws -> DerivedKeys {
        guard masterKey.count == 32 else { throw SyncError.invalidKeyLength }
        let ikm = SymmetricKey(data: masterKey)
        let salt = pairingId.rfc4122
        return DerivedKeys(
            enc: hkdf(ikm: ikm, salt: salt, info: HKDFInfo.enc),
            tok: hkdf(ikm: ikm, salt: salt, info: HKDFInfo.tok),
            cfm: hkdf(ikm: ikm, salt: salt, info: HKDFInfo.cfm)
        )
    }

    public static func confirmHMAC(cfmKey: Data, pairingId: UUID, offerId: UUID, role: PairingRole) -> String {
        let message = "\(pairingId.canonicalLowercase)|\(offerId.canonicalLowercase)|\(role.hmacLabel)"
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(message.utf8),
            using: SymmetricKey(data: cfmKey)
        )
        return Base64URL.encode(Data(mac))
    }

    public static func seal(
        plaintext: Data,
        pairingId: UUID,
        kind: WireKind,
        rev: Int,
        encKey: Data,
        nonce: Data
    ) throws -> Envelope {
        guard encKey.count == 32 else { throw SyncError.invalidKeyLength }
        guard nonce.count == 12 else { throw SyncError.invalidNonce }
        let key = SymmetricKey(data: encKey)
        let gcmNonce = try AES.GCM.Nonce(data: nonce)
        let aad = Envelope.aad(pairingId: pairingId, kind: kind, rev: rev)
        let box = try AES.GCM.seal(plaintext, using: key, nonce: gcmNonce, authenticating: aad)
        let ct = Data(box.ciphertext) + Data(box.tag)
        return Envelope(rev: rev, kind: kind, n: Base64URL.encode(nonce), ct: Base64URL.encode(ct))
    }

    public static func open(_ envelope: Envelope, pairingId: UUID, encKey: Data) throws -> Data {
        guard encKey.count == 32 else { throw SyncError.invalidKeyLength }
        let nonce = try Base64URL.decode(envelope.n)
        let combined = try Base64URL.decode(envelope.ct)
        guard nonce.count == 12 else { throw SyncError.invalidNonce }
        guard combined.count >= 16 else { throw SyncError.invalidCiphertext }
        let ciphertext = combined.dropLast(16)
        let tag = combined.suffix(16)
        let box = try AES.GCM.SealedBox(
            nonce: try AES.GCM.Nonce(data: nonce),
            ciphertext: ciphertext,
            tag: tag
        )
        let aad = Envelope.aad(pairingId: pairingId, kind: envelope.kind, rev: envelope.rev)
        do {
            return try AES.GCM.open(box, using: SymmetricKey(data: encKey), authenticating: aad)
        } catch {
            throw SyncError.decryptFailed
        }
    }

    public static func decodeJSON<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try WireJSON.decoder().decode(T.self, from: data)
        } catch {
            throw SyncError.invalidJSON
        }
    }

    public static func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        try WireJSON.encoder().encode(value)
    }

    private static func hkdf(ikm: SymmetricKey, salt: Data, info: String) -> Data {
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm,
            salt: salt,
            info: Data(info.utf8),
            outputByteCount: 32
        )
        return key.withUnsafeBytes { Data($0) }
    }
}
