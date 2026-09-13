import Foundation

public enum PairingRole: String, Sendable, Equatable {
    case iphone
    case mac

    var hmacLabel: String { rawValue }
}

public enum PairingURL: Equatable, Sendable {
    case iphone(pairingId: UUID, offerId: UUID, x: Data)
    case mac(macSession: UUID, y: Data, name: String?)

    public var role: PairingRole {
        switch self {
        case .iphone: .iphone
        case .mac: .mac
        }
    }

    public var companionName: String? {
        switch self {
        case .iphone: nil
        case .mac(_, _, let name): CompanionDisplayName.sanitize(name)
        }
    }

    /// Builder order is fixed: `p&o&x` / `s&y` / optional `&n=`. Parsers accept any query order.
    public var encoded: String {
        switch self {
        case .iphone(let pairingId, let offerId, let x):
            return "todotrain://pair?p=\(pairingId.canonicalLowercase)&o=\(offerId.canonicalLowercase)&x=\(Base64URL.encode(x))"
        case .mac(let macSession, let y, let name):
            var encoded = "todotrain://pair-mac?s=\(macSession.canonicalLowercase)&y=\(Base64URL.encode(y))"
            if let name = CompanionDisplayName.sanitize(name),
               let escaped = CompanionDisplayName.percentEncode(name) {
                encoded += "&n=\(escaped)"
            }
            return encoded
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
            let keys = Set(query.keys)
            guard keys.isSuperset(of: ["s", "y"]),
                  keys.isSubset(of: ["s", "y", "n"]),
                  let macSession = UUID.parseCanonical(query["s"] ?? ""),
                  let y = try? Base64URL.decode(query["y"] ?? ""),
                  y.count == 32,
                  (query["y"] ?? "").count == 43
            else { throw SyncError.invalidPairingURL }
            return .mac(
                macSession: macSession,
                y: y,
                name: CompanionDisplayName.sanitize(query["n"])
            )
        default:
            throw SyncError.invalidPairingURL
        }
    }
}

enum CompanionDisplayName {
    static let maxLength = 32

    static func sanitize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= maxLength { return trimmed }
        return String(trimmed.prefix(maxLength))
    }

    static func percentEncode(_ name: String) -> String? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":/?#[]@!$&'()*+,;=")
        return name.addingPercentEncoding(withAllowedCharacters: allowed)
    }
}
