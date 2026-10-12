import Foundation

/// Numbers from `sync/contract/version.json`. Do not invent a second source.
public enum ContractVersion {
    public static let contract = 4
    public static let minReadable = 3
    /// A peer that omits `contract` / `minReadable`.
    public static let legacy = 3
}
