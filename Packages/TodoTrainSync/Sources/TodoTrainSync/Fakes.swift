import Foundation

public final class InMemorySecretStore: SecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var secrets: PairingSecrets?

    public init(secrets: PairingSecrets? = nil) {
        self.secrets = secrets
    }

    public func load() throws -> PairingSecrets? {
        lock.lock()
        defer { lock.unlock() }
        return secrets
    }

    public func save(_ secrets: PairingSecrets) throws {
        lock.lock()
        defer { lock.unlock() }
        self.secrets = secrets
    }

    public func delete() throws {
        lock.lock()
        defer { lock.unlock() }
        secrets = nil
    }
}

public struct ImmediateLocalAuth: LocalAuthenticating {
    public init() {}

    public func confirmPresence() async throws {}
}

public actor CountingLocalAuth: LocalAuthenticating {
    public private(set) var count = 0

    public init() {}

    public func confirmPresence() async throws {
        count += 1
    }
}

public actor ScriptedOptical: OpticalProviding {
    private var urls: [String]

    public init(_ urls: [String]) {
        self.urls = urls
    }

    public func waitForURL() async throws -> String {
        guard !urls.isEmpty else { throw SyncError.invalidPairingURL }
        return urls.removeFirst()
    }
}

public actor ScriptedHTTPTransport: HTTPTransport {
    public struct Step: Sendable {
        public var status: Int
        public var json: String?

        public init(status: Int, json: String? = nil) {
            self.status = status
            self.json = json
        }
    }

    private var steps: [Step]
    public private(set) var requests: [HTTPRequest] = []

    public init(_ steps: [Step]) {
        self.steps = steps
    }

    public func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !steps.isEmpty else {
            throw SyncError.transport(status: 500, code: "invalid")
        }
        let step = steps.removeFirst()
        return HTTPResponse(status: step.status, body: Data((step.json ?? "").utf8))
    }
}

public actor ScriptedWebSocket: WebSocketConnecting, WebSocketConnection {
    private var frames: [WSFrame]

    public init(frames: [WSFrame] = []) {
        self.frames = frames
    }

    public func connect(path: String, headers: [String: String]) async throws -> any WebSocketConnection {
        self
    }

    public func receive() async throws -> WSFrame {
        guard !frames.isEmpty else { throw SyncError.notPaired }
        return frames.removeFirst()
    }

    public func close() async {}
}
