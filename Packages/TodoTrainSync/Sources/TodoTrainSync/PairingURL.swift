import Foundation

public enum PairingRole: String, Sendable, Equatable {
    case iphone
    case mac

    var hmacLabel: String { rawValue }
}

public enum PairingURL: Equatable, Sendable {
    case iphone(pairingId: UUID, offerId: UUID, x: Data)
    case mac(macSession: UUID, y: Data)

    public var role: PairingRole {
        switch self {
        case .iphone: .iphone
        case .mac: .mac
        }
    }

    /// Builder order is fixed: `p&o&x` / `s&y`. Parsers accept any query order.
    public var encoded: String {
        switch self {
        case .iphone(let pairingId, let offerId, let x):
            "todotrain://pair?p=\(pairingId.canonicalLowercase)&o=\(offerId.canonicalLowercase)&x=\(Base64URL.encode(x))"
        case .mac(let macSession, let y):
            "todotrain://pair-mac?s=\(macSession.canonicalLowercase)&y=\(Base64URL.encode(y))"
        }
    }

    public static func parse(_ string: String) throws -> PairingURL {
        guard let url = URL(string: string), url.scheme == "todotrain" else {
            throw SyncError.invalidPairingURL
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })
        let host = url.host
            ?? url.path.split(separator: "/").map(String.init).first
            ?? ""

        switch host {
        case "pair":
            guard Set(query.keys) == ["p", "o", "x"],
                  let pairingId = UUID.parseCanonical(query["p"] ?? ""),
                  let offerId = UUID.parseCanonical(query["o"] ?? ""),
                  let x = try? Base64URL.decode(query["x"] ?? ""),
                  x.count == 32,
                  (query["x"] ?? "").count == 43
            else { throw SyncError.invalidPairingURL }
            return .iphone(pairingId: pairingId, offerId: offerId, x: x)
        case "pair-mac":
            guard Set(query.keys) == ["s", "y"],
                  let macSession = UUID.parseCanonical(query["s"] ?? ""),
                  let y = try? Base64URL.decode(query["y"] ?? ""),
                  y.count == 32,
                  (query["y"] ?? "").count == 43
            else { throw SyncError.invalidPairingURL }
            return .mac(macSession: macSession, y: y)
        default:
            throw SyncError.invalidPairingURL
        }
    }
}
