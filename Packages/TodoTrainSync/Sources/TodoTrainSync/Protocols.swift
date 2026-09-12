import Foundation

public struct PairingSecrets: Codable, Equatable, Sendable {
    public var pairingId: UUID
    public var masterKey: Data
    public var writeToken: Data
    /// Mac computer name captured at pairing. Missing on older Keychain blobs.
    public var companionName: String?

    public init(
        pairingId: UUID,
        masterKey: Data,
        writeToken: Data,
        companionName: String? = nil
    ) {
        self.pairingId = pairingId
        self.masterKey = masterKey
        self.writeToken = writeToken
        self.companionName = CompanionDisplayName.sanitize(companionName)
    }

    public var shortPairingID: String {
        String(pairingId.uuidString.lowercased().prefix(8))
    }
}

public protocol SecretStoring: Sendable {
    func load() throws -> PairingSecrets?
    func save(_ secrets: PairingSecrets) throws
    func delete() throws
}

public protocol LocalAuthenticating: Sendable {
    func confirmPresence() async throws
}

/// Camera / paste. Tests inject the optically-read URL string.
public protocol OpticalProviding: Sendable {
    func waitForURL() async throws -> String
}

public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    public var path: String
    public var headers: [String: String]
    public var body: Data?

    public init(method: String, path: String, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Equatable, Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data = Data()) {
        self.status = status
        self.body = body
    }
}

public protocol HTTPTransport: Sendable {
    func perform(_ request: HTTPRequest) async throws -> HTTPResponse
}

public protocol WebSocketConnection: Sendable {
    func receive() async throws -> WSFrame
    func close() async
}

public protocol WebSocketConnecting: Sendable {
    func connect(path: String, headers: [String: String]) async throws -> any WebSocketConnection
}
