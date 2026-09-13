import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class URLSessionWebSocketConnecting: WebSocketConnecting, @unchecked Sendable {
    public let baseURL: URL
    private let injectedSession: URLSession?

    public static func webSocketURL(baseURL: URL, path: String) throws -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let relative = path.hasPrefix("/") ? path : "/" + path
        let basePath = (components?.path ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if basePath.isEmpty {
            components?.path = relative
        } else {
            components?.path = "/" + basePath + relative
        }
        if baseURL.scheme == "https" {
            components?.scheme = "wss"
        } else if baseURL.scheme == "http" {
            components?.scheme = "ws"
        }
        guard let url = components?.url else { throw SyncError.invalidPairingURL }
        return url
    }

    public init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.injectedSession = session
    }

    public func connect(path: String, headers: [String: String]) async throws -> any WebSocketConnection {
        let url = try Self.webSocketURL(baseURL: baseURL, path: path)
        let session: URLSession
        if let injectedSession {
            session = injectedSession
        } else {
            // URLSessionWebSocketTask often drops URLRequest headers. Put Bearer on the
            // session and keep that session on the connection for the socket's lifetime.
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 60 * 60 * 24 * 7
            config.timeoutIntervalForResource = 60 * 60 * 24 * 7
            config.httpCookieAcceptPolicy = .never
            config.httpShouldSetCookies = false
            config.httpAdditionalHeaders = headers
            session = URLSession(configuration: config)
        }
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let task = session.webSocketTask(with: request)
        task.resume()
        return URLSessionWebSocketConnection(
            task: task,
            session: session,
            ownsSession: injectedSession == nil
        )
    }
}

final class URLSessionWebSocketConnection: WebSocketConnection, @unchecked Sendable {
    static let pingIntervalNanoseconds: UInt64 = 25_000_000_000

    private let task: URLSessionWebSocketTask
    /// Keep the session for as long as the task. Deallocating it cancels the socket.
    let retainedSession: URLSession
    private let ownsSession: Bool
    private var pingTask: Task<Void, Never>?

    init(task: URLSessionWebSocketTask, session: URLSession, ownsSession: Bool) {
        self.task = task
        self.retainedSession = session
        self.ownsSession = ownsSession
        pingTask = Task { [weak self] in
            self?.sendKeepalivePing()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.pingIntervalNanoseconds)
                guard !Task.isCancelled else { return }
                self?.sendKeepalivePing()
            }
        }
    }

    func receive() async throws -> WSFrame {
        let message = try await task.receive()
        let data: Data
        switch message {
        case .string(let text):
            data = Data(text.utf8)
        case .data(let payload):
            data = payload
        @unknown default:
            throw SyncError.invalidJSON
        }
        do {
            return try WireJSON.decoder().decode(WSFrame.self, from: data)
        } catch {
            throw SyncError.invalidJSON
        }
    }

    func close() async {
        pingTask?.cancel()
        pingTask = nil
        task.cancel(with: .goingAway, reason: nil)
        if ownsSession {
            retainedSession.finishTasksAndInvalidate()
        }
    }

    private func sendKeepalivePing() {
        #if canImport(Darwin)
        task.sendPing { _ in }
        #endif
    }
}

public struct BearerWebSocket {
    public var writeToken: Data
    public var pairingId: UUID?
    public var connector: any WebSocketConnecting

    public init(writeToken: Data, pairingId: UUID? = nil, connector: any WebSocketConnecting) {
        self.writeToken = writeToken
        self.pairingId = pairingId
        self.connector = connector
    }

    public func connect() async throws -> any WebSocketConnection {
        var headers = ["Authorization": "Bearer \(Base64URL.encode(writeToken))"]
        if let pairingId {
            headers[SyncHTTPClient.pairingIdHeaderName] = pairingId.canonicalLowercase
        }
        return try await connector.connect(
            path: "/v1/ws",
            headers: headers
        )
    }
}
