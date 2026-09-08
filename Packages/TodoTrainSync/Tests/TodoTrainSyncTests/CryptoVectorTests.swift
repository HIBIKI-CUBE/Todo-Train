import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Crypto vectors")
struct CryptoVectorTests {
    @Test func hkdfAesGcmAndConfirmHMACMatchGoldenVector() throws {
        let data = try ContractFixtures.data("vectors/aes-gcm-snap.json")
        let vector = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let pairingId = UUID(uuidString: vector["pairingId"] as! String)!
        let offerId = UUID(uuidString: vector["offerId"] as! String)!
        let masterKey = try Base64URL.decode(vector["masterKey"] as! String)

        #expect(pairingId.rfc4122.map { String(format: "%02x", $0) }.joined() == "a1a2a3a4b1b24c3c8d4de5e6e7e8e9ea")

        let keys = try SyncCrypto.deriveKeys(masterKey: masterKey, pairingId: pairingId)
        let hkdf = vector["hkdf"] as! [String: Any]
        #expect(Base64URL.encode(keys.enc) == (hkdf["enc"] as? String))
        #expect(Base64URL.encode(keys.tok) == (hkdf["tok"] as? String))
        #expect(Base64URL.encode(keys.cfm) == (hkdf["cfm"] as? String))
        #expect(keys.tokenHashB64U == (vector["tokenHash"] as? String))

        let plaintextUtf8 = vector["plaintextUtf8"] as! String
        let nonce = try Base64URL.decode(vector["n"] as! String)
        let envelope = try SyncCrypto.seal(
            plaintext: Data(plaintextUtf8.utf8),
            pairingId: pairingId,
            kind: .snap,
            rev: vector["rev"] as! Int,
            encKey: keys.enc,
            nonce: nonce
        )
        #expect(envelope.n == (vector["n"] as? String))
        #expect(envelope.ct == (vector["ct"] as? String))
        #expect(envelope.kind == .snap)
        #expect(envelope.rev == 42)

        let opened = try SyncCrypto.open(envelope, pairingId: pairingId, encKey: keys.enc)
        #expect(String(data: opened, encoding: .utf8) == plaintextUtf8)
        let snap = try SyncCrypto.decodeJSON(SnapPlaintext.self, from: opened)
        #expect(snap.title == "週次レポート")
        #expect(snap.phase == .running)

        let confirm = vector["confirm"] as! [String: String]
        #expect(
            SyncCrypto.confirmHMAC(cfmKey: keys.cfm, pairingId: pairingId, offerId: offerId, role: .iphone)
                == confirm["hmacIphone"]
        )
        #expect(
            SyncCrypto.confirmHMAC(cfmKey: keys.cfm, pairingId: pairingId, offerId: offerId, role: .mac)
                == confirm["hmacMac"]
        )

        let aad = Envelope.aad(pairingId: pairingId, kind: .snap, rev: 42)
        #expect(String(data: aad, encoding: .utf8) == (vector["aadUtf8"] as? String))
    }

    @Test func wrongAADFailsOpen() throws {
        let data = try ContractFixtures.data("vectors/aes-gcm-snap.json")
        let vector = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let pairingId = UUID(uuidString: vector["pairingId"] as! String)!
        let masterKey = try Base64URL.decode(vector["masterKey"] as! String)
        let keys = try SyncCrypto.deriveKeys(masterKey: masterKey, pairingId: pairingId)
        let envelope = Envelope(
            rev: 42,
            kind: .snap,
            n: vector["n"] as! String,
            ct: vector["ct"] as! String
        )
        let otherPairing = UUID(uuidString: "00000000-0000-4000-8000-000000000000")!
        #expect(throws: SyncError.decryptFailed) {
            _ = try SyncCrypto.open(envelope, pairingId: otherPairing, encKey: keys.enc)
        }
    }

    @Test func x25519SharedSecretIsSymmetric() throws {
        let (aPriv, aPub) = SyncCrypto.generateX25519()
        let (bPriv, bPub) = SyncCrypto.generateX25519()
        let ab = try SyncCrypto.sharedSecret(privateKey: aPriv, peerPublicRaw: bPub)
        let ba = try SyncCrypto.sharedSecret(privateKey: bPriv, peerPublicRaw: aPub)
        #expect(ab == ba)
        #expect(ab.count == 32)
        #expect(aPub.count == 32)
    }
}
