import Foundation

/// Numbers from `sync/contract/version.json`. Do not invent a second source.
public enum ContractVersion {
    public static let contract = 14
    public static let minReadable = 3
    /// A peer that omits `contract` / `minReadable`.
    public static let legacy = 3
}

public struct ContractAnnouncement: Codable, Equatable, Sendable {
    public static let headerName = "X-TT-Contract"

    public var contract: Int
    public var minReadable: Int

    public init(contract: Int, minReadable: Int) {
        self.contract = contract
        self.minReadable = minReadable
    }

    public static var current: ContractAnnouncement {
        ContractAnnouncement(contract: ContractVersion.contract, minReadable: ContractVersion.minReadable)
    }

    public static var legacyPeer: ContractAnnouncement {
        ContractAnnouncement(contract: ContractVersion.legacy, minReadable: ContractVersion.legacy)
    }

    public var headerValue: String { "\(contract);min=\(minReadable)" }

    /// Absent header is the legacy peer. A present but unreadable header is nil.
    public static func parseHeader(_ value: String?) -> ContractAnnouncement? {
        guard let value else { return .legacyPeer }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ";", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[1].hasPrefix("min=") else { return nil }
        guard let contract = Int(parts[0]), let minReadable = Int(parts[1].dropFirst(4)) else { return nil }
        guard contract > 0, minReadable > 0 else { return nil }
        return ContractAnnouncement(contract: contract, minReadable: minReadable)
    }

    /// Missing or unreadable keys are the legacy peer. One key without the other is legacy too.
    public static func resolved(contract: Int?, minReadable: Int?) -> ContractAnnouncement {
        guard let contract, let minReadable, contract > 0, minReadable > 0 else {
            return .legacyPeer
        }
        return ContractAnnouncement(contract: contract, minReadable: minReadable)
    }
}

public enum ContractSide: Sendable {
    case iphone
    case mac
}

public enum ContractCompat: Equatable, Sendable {
    case compatible
    /// The peer's contract is newer. Keep the parts this side already understands.
    case peerNewer
    /// The peer is below our minReadable. Keep reading snaps. Do not send operations.
    case peerTooOld
    /// Our contract is below the peer's minReadable.
    case selfTooOld

    public var maySendOperations: Bool {
        switch self {
        case .compatible, .peerNewer: true
        case .peerTooOld, .selfTooOld: false
        }
    }

    public static func evaluate(
        local: ContractAnnouncement = .current,
        peer: ContractAnnouncement
    ) -> ContractCompat {
        if peer.contract < local.minReadable { return .peerTooOld }
        if local.contract < peer.minReadable { return .selfTooOld }
        if peer.contract > local.contract { return .peerNewer }
        return .compatible
    }

    /// nil when operations may be sent. The string is the notice for this side.
    public static func commandBlock(
        local: ContractAnnouncement = .current,
        peer: ContractAnnouncement?,
        relay: ContractAnnouncement?,
        side: ContractSide
    ) -> String? {
        if let relay {
            switch evaluate(local: local, peer: relay) {
            case .peerTooOld:
                return ContractCopy.relayOlder
            case .selfTooOld:
                return side == .iphone ? ContractCopy.iphoneOlder : ContractCopy.macOlder
            case .compatible, .peerNewer:
                break
            }
        }
        if let peer {
            switch evaluate(local: local, peer: peer) {
            case .peerTooOld:
                return side == .iphone ? ContractCopy.macOlder : ContractCopy.iphoneOlder
            case .selfTooOld:
                return side == .iphone ? ContractCopy.iphoneOlder : ContractCopy.macOlder
            case .compatible, .peerNewer:
                break
            }
        }
        return nil
    }
}

enum ContractKeyDecoding {
    static func positiveInt<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>,
        _ key: K
    ) -> Int? {
        guard container.contains(key) else { return nil }
        if (try? container.decodeNil(forKey: key)) == true { return nil }
        guard let value = try? container.decode(Int.self, forKey: key), value > 0 else { return nil }
        return value
    }
}

public enum ContractHello {
    public static func text(_ announcement: ContractAnnouncement = .current) -> String {
        "{\"t\":\"hello\",\"contract\":\(announcement.contract),\"minReadable\":\(announcement.minReadable)}"
    }
}

public enum WSIncoming: Equatable, Sendable {
    case frame(WSFrame)
    case hello(ContractAnnouncement)

    public static func decode(_ data: Data) throws -> WSIncoming {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SyncError.invalidJSON
        }
        if object["t"] as? String == "hello" {
            let contract = object["contract"] as? Int
            let minReadable = object["minReadable"] as? Int
            return .hello(.resolved(contract: contract, minReadable: minReadable))
        }
        return .frame(try WireJSON.decoder().decode(WSFrame.self, from: data))
    }
}

public enum PeerContractStore {
    public static let peerKey = "companion.peerContract"
    public static let relayKey = "companion.relayContract"

    public static func load(from defaults: UserDefaults, key: String) -> ContractAnnouncement? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ContractAnnouncement.self, from: data)
    }

    public static func save(_ value: ContractAnnouncement?, to defaults: UserDefaults, key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}
