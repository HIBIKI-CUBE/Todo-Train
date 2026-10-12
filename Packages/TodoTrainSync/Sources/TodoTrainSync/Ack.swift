import Foundation

public struct AckPlaintext: Codable, Equatable, Sendable {
    public var cmdId: UUID
    public var ok: Bool
    /// Present only when `ok` is false. Omitted on success.
    public var error: WireError?
    /// iPhone build. Ack is written by the iPhone. Absent on older peers.
    public var build: WireBuildInfo?

    public init(cmdId: UUID, ok: Bool, error: WireError? = nil, build: WireBuildInfo? = nil) {
        self.cmdId = cmdId
        self.ok = ok
        self.error = ok ? nil : error
        self.build = build
    }

    enum CodingKeys: String, CodingKey {
        case cmdId, ok, error, build
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .cmdId)
        guard let parsed = UUID(uuidString: raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid UUID")
            )
        }
        cmdId = parsed
        ok = try container.decode(Bool.self, forKey: .ok)
        error = try container.decodeIfPresent(WireError.self, forKey: .error)
        build = try container.decodeIfPresent(WireBuildInfo.self, forKey: .build)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cmdId.canonicalLowercase, forKey: .cmdId)
        try container.encode(ok, forKey: .ok)
        try container.encodeIfPresent(error, forKey: .error)
        try container.encodeIfPresent(build, forKey: .build)
    }
}
