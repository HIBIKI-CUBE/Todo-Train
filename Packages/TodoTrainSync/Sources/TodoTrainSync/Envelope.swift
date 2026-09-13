import Foundation

public struct Envelope: Codable, Equatable, Sendable {
    public var rev: Int
    public var kind: WireKind
    public var n: String
    public var ct: String

    public init(rev: Int, kind: WireKind, n: String, ct: String) {
        self.rev = rev
        self.kind = kind
        self.n = n
        self.ct = ct
    }

    public static func aad(pairingId: UUID, kind: WireKind, rev: Int) -> Data {
        Data("\(pairingId.canonicalLowercase)|\(kind.rawValue)|\(rev)".utf8)
    }
}

public struct WSFrame: Codable, Equatable, Sendable {
    public var t: WireKind
    public var envelope: Envelope

    public init(t: WireKind, envelope: Envelope) {
        self.t = t
        self.envelope = envelope
    }
}
