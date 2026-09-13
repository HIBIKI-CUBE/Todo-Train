import Foundation

public struct OfferCreated: Codable, Equatable, Sendable {
    public var offerId: UUID
    public var pairingId: UUID
    public var expiresAt: Int
}

public struct BindRequest: Codable, Equatable, Sendable {
    public var role: String
    public var s: String
    public var x: String?
    public var y: String?

    public static func iphone(s: UUID, y: Data) -> BindRequest {
        BindRequest(role: "iphone", s: s.canonicalLowercase, x: nil, y: Base64URL.encode(y))
    }

    public static func mac(s: UUID, x: Data) -> BindRequest {
        BindRequest(role: "mac", s: s.canonicalLowercase, x: Base64URL.encode(x), y: nil)
    }
}

public struct BindResponse: Codable, Equatable, Sendable {
    public var bound: Bool
    public var pairingId: UUID?
    public var s: UUID?
    public var x: String?
    public var y: String?
}

public struct ConfirmResponse: Codable, Equatable, Sendable {
    public var confirmed: Bool
    public var pairingId: UUID?
}

public struct PairingRegistered: Codable, Equatable, Sendable {
    public var pairingId: UUID
}

public struct SnapPutResponse: Codable, Equatable, Sendable {
    public var rev: Int
}

public struct CmdQueued: Codable, Equatable, Sendable {
    public var queued: Bool
}

public struct CmdList: Codable, Equatable, Sendable {
    public var items: [Envelope]
}

public struct AckStored: Codable, Equatable, Sendable {
    public var stored: Bool
}

struct ErrorBody: Codable {
    var error: String
}
