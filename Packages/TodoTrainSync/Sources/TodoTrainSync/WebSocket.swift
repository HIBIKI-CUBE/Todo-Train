import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class URLSessionWebSocketConnecting: WebSocketConnecting, @unchecked Sendable {
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func connect(path: String, headers: [String: String]) async throws -> any WebSocketConnection {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        components?.path = (baseURL.path as NSString).appendingPathComponent(trimmed)
        if baseURL.scheme == "https" {
            components?.scheme = "wss"
        } else if baseURL.scheme == "http" {
            components?.scheme = "ws"
        }
        guard let url = components?.url else { throw SyncError.invalidPairingURL }
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let task = session.webSocketTask(with: request)
        task.resume()
        return URLSessionWebSocketConnection(task: task)
    }
}

final class URLSessionWebSocketConnection: WebSocketConnection, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
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
        return try WireJSON.decoder().decode(WSFrame.self, from: data)
    }

    func close() async {
        task.cancel(with: .goingAway, reason: nil)
    }
}

public struct BearerWebSocket {
    public var writeToken: Data
    public var connector: any WebSocketConnecting

    public init(writeToken: Data, connector: any WebSocketConnecting) {
        self.writeToken = writeToken
        self.connector = connector
    }

    public func connect() async throws -> any WebSocketConnection {
        try await connector.connect(
            path: "/v1/ws",
            headers: ["Authorization": "Bearer \(Base64URL.encode(writeToken))"]
        )
    }
}
