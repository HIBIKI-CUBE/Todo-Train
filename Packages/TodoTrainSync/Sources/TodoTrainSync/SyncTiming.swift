import Foundation

public enum SyncTiming {
    public static let bindPollNanoseconds: UInt64 = 250_000_000
    public static let pairingEstablishedPauseNanoseconds: UInt64 = 900_000_000
    public static let pairingDismissPauseNanoseconds: UInt64 = 800_000_000
    public static let snapDebounceNanoseconds: UInt64 = 150_000_000
}
