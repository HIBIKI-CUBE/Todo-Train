import Foundation

public enum SyncError: Error, Equatable, Sendable {
    case invalidBase64URL
    case invalidKeyLength
    case invalidNonce
    case invalidCiphertext
    case decryptFailed
    case invalidPairingURL
    case invalidJSON
    case unexpectedKind
    case transport(status: Int, code: String)
    case notPaired
    case pairingNotBound
    case pairingAborted
    case confirmTimedOut
}
