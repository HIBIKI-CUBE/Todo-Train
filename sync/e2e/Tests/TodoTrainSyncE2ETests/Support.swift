import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#endif
#if canImport(Glibc)
import Glibc
#endif
#if canImport(Musl)
import Musl
#endif
import TodoTrainSync

enum E2EError: Error, CustomStringConvertible {
    case workerUnreachable(String)
    case timeout(String)
    case plaintextLeaked(String)
    case unexpectedJSON(String)
    case websocket(String)

    var description: String {
        switch self {
        case .workerUnreachable(let detail): "worker unreachable: \(detail)"
        case .timeout(let what): "timed out waiting for \(what)"
        case .plaintextLeaked(let where_): "plaintext title leaked in \(where_)"
        case .unexpectedJSON(let detail): "unexpected JSON: \(detail)"
        case .websocket(let detail): "websocket: \(detail)"
        }
    }
}

enum E2EConfig {
    static let plaintextTitle = "週次レポート"
    static let sessionId = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    static let ticketId = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    static let commandId = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    static let snapNow = 1_768_000_060
    static let snapStartedAt = 1_768_000_000
    static let estimatedSeconds = 1500
    static let remainingAtSnapNow = 1440

    static var baseURL: URL {
        let raw = ProcessInfo.processInfo.environment["TODOTRAIN_SYNC_E2E_URL"] ?? "http://127.0.0.1:8787"
        guard let url = URL(string: raw) else {
            fatalError("TODOTRAIN_SYNC_E2E_URL is not a URL: \(raw)")
        }
        return url
    }

    static func runningSnap(rev: Int = 42) -> SnapPlaintext {
        SnapPlaintext(
            rev: rev,
            sessionId: sessionId,
            ticketId: ticketId,
            title: plaintextTitle,
            phase: .running,
            startedAt: snapStartedAt,
            estimatedSeconds: estimatedSeconds,
            pausedAccumulated: 0,
            pausedAt: nil,
            boardedDeviceID: "phone-a"
        )
    }
}

final class AbsoluteURLHTTPTransport: HTTPTransport, @unchecked Sendable {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 30
            config.httpCookieAcceptPolicy = .never
            config.httpShouldSetCookies = false
            self.session = URLSession(configuration: config)
        }
    }

    func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        let url = try Self.url(baseURL: baseURL, path: request.path)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await session.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return HTTPResponse(status: status, body: data)
    }

    static func url(baseURL: URL, path: String) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw E2EError.workerUnreachable(baseURL.absoluteString)
        }
        components.path = path.hasPrefix("/") ? path : "/" + path
        components.query = nil
        components.fragment = nil
        guard let url = components.url else {
            throw E2EError.workerUnreachable("\(baseURL.absoluteString) + \(path)")
        }
        return url
    }
}

actor RecordingHTTPTransport: HTTPTransport {
    private let inner: any HTTPTransport
    private(set) var exchanges: [(HTTPRequest, HTTPResponse)] = []

    init(_ inner: any HTTPTransport) {
        self.inner = inner
    }

    func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        let response = try await inner.perform(request)
        exchanges.append((request, response))
        return response
    }
}

/// RFC 6455 client. URLSession WebSocket on Linux is unreliable against wrangler.
final class RawWebSocketConnecting: WebSocketConnecting, @unchecked Sendable {
    let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func connect(path: String, headers: [String: String]) async throws -> any WebSocketConnection {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let connection = try RawWebSocketConnection.connect(
                        baseURL: self.baseURL,
                        path: path,
                        headers: headers
                    )
                    continuation.resume(returning: connection)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

final class RawWebSocketConnection: WebSocketConnection, @unchecked Sendable {
    private let fd: Int32
    private let lock = NSLock()
    private var buffer = Data()
    private var closed = false

    init(fd: Int32) {
        self.fd = fd
    }

    deinit {
        lock.lock()
        let already = closed
        closed = true
        lock.unlock()
        if !already {
            _ = DarwinOrGlibc.close(fd)
        }
    }

    static func connect(baseURL: URL, path: String, headers: [String: String]) throws -> RawWebSocketConnection {
        let host = baseURL.host ?? "127.0.0.1"
        let port = baseURL.port ?? (baseURL.scheme == "https" ? 443 : 80)
        let fd = try posixConnect(host: host, port: port)
        let key = Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        var headerLines = [
            "GET \(path.hasPrefix("/") ? path : "/" + path) HTTP/1.1",
            "Host: \(host):\(port)",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Version: 13",
            "Sec-WebSocket-Key: \(key)",
        ]
        for (name, value) in headers {
            headerLines.append("\(name): \(value)")
        }
        headerLines.append("")
        headerLines.append("")
        let handshake = headerLines.joined(separator: "\r\n")
        try writeAll(fd: fd, Data(handshake.utf8))

        var collected = Data()
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let chunk = try readSome(fd: fd, max: 4096)
            if chunk.isEmpty { break }
            collected.append(chunk)
            if let range = collected.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(data: collected.subdata(in: collected.startIndex..<range.lowerBound), encoding: .utf8) ?? ""
                guard head.contains("101") else {
                    _ = DarwinOrGlibc.close(fd)
                    throw E2EError.websocket("upgrade failed: \(head.prefix(200))")
                }
                let leftover = collected.subdata(in: range.upperBound..<collected.endIndex)
                let connection = RawWebSocketConnection(fd: fd)
                connection.buffer = leftover
                return connection
            }
        }
        _ = DarwinOrGlibc.close(fd)
        throw E2EError.websocket("upgrade timed out")
    }

    func receive() async throws -> WSFrame {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let payload = try self.readTextFrame()
                    let frame = try SyncCrypto.decodeJSON(WSFrame.self, from: payload)
                    continuation.resume(returning: frame)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func close() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                self.shutdown()
                continuation.resume()
            }
        }
    }

    private func shutdown() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        var frame: [UInt8] = [0x88, 0x80]
        frame.append(contentsOf: [0, 0, 0, 0])
        _ = frame.withUnsafeBytes { raw in
            DarwinOrGlibc.write(fd, raw.baseAddress, frame.count)
        }
        _ = DarwinOrGlibc.close(fd)
    }

    private func readTextFrame() throws -> Data {
        while true {
            let header = try readExact(2)
            let opcode = header[0] & 0x0F
            let masked = (header[1] & 0x80) != 0
            var len = Int(header[1] & 0x7F)
            if len == 126 {
                let ext = try readExact(2)
                len = Int(ext[0]) << 8 | Int(ext[1])
            } else if len == 127 {
                let ext = try readExact(8)
                var value: UInt64 = 0
                for byte in ext { value = (value << 8) | UInt64(byte) }
                len = Int(value)
            }
            var mask = [UInt8](repeating: 0, count: 4)
            if masked {
                mask = [UInt8](try readExact(4))
            }
            var payload = [UInt8](try readExact(len))
            if masked {
                for i in payload.indices {
                    payload[i] ^= mask[i % 4]
                }
            }
            switch opcode {
            case 0x1, 0x2:
                return Data(payload)
            case 0x8:
                throw E2EError.websocket("closed by peer")
            case 0x9:
                continue
            case 0xA:
                continue
            default:
                throw E2EError.websocket("opcode \(opcode)")
            }
        }
    }

    private func readExact(_ count: Int) throws -> Data {
        let deadline = Date().addingTimeInterval(10)
        while buffer.count < count {
            if Date() >= deadline { throw E2EError.timeout("websocket frame") }
            let chunk = try readSome(fd: fd, max: 4096)
            if chunk.isEmpty { throw E2EError.websocket("eof") }
            buffer.append(chunk)
        }
        let out = buffer.prefix(count)
        buffer.removeFirst(count)
        return Data(out)
    }
}

private enum DarwinOrGlibc {
    @discardableResult
    static func close(_ fd: Int32) -> Int32 {
        #if canImport(Glibc)
        Glibc.close(fd)
        #elseif canImport(Musl)
        Musl.close(fd)
        #else
        Darwin.close(fd)
        #endif
    }

    static func write(_ fd: Int32, _ buf: UnsafeRawPointer?, _ n: Int) -> Int {
        #if canImport(Glibc)
        Glibc.write(fd, buf, n)
        #elseif canImport(Musl)
        Musl.write(fd, buf, n)
        #else
        Darwin.write(fd, buf, n)
        #endif
    }
}

private func posixConnect(host: String, port: Int) throws -> Int32 {
    var hints = addrinfo()
    hints.ai_family = AF_INET
    #if canImport(Glibc) || canImport(Musl)
    hints.ai_socktype = numericCast(SOCK_STREAM.rawValue)
    #else
    hints.ai_socktype = SOCK_STREAM
    #endif
    hints.ai_protocol = Int32(IPPROTO_TCP)

    var info: UnsafeMutablePointer<addrinfo>?
    let status = host.withCString { hostC in
        String(port).withCString { portC in
            getaddrinfo(hostC, portC, &hints, &info)
        }
    }
    guard status == 0, let info else {
        throw E2EError.websocket("getaddrinfo \(status)")
    }
    defer { freeaddrinfo(info) }

    let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
    guard fd >= 0 else { throw E2EError.websocket("socket") }

    var tv = timeval(tv_sec: 10, tv_usec: 0)
    _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

    let connected = connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen)
    guard connected == 0 else {
        DarwinOrGlibc.close(fd)
        throw E2EError.websocket("connect errno=\(errno)")
    }
    return fd
}

private func writeAll(fd: Int32, _ data: Data) throws {
    try data.withUnsafeBytes { raw in
        var sent = 0
        let total = raw.count
        while sent < total {
            let n = DarwinOrGlibc.write(fd, raw.baseAddress!.advanced(by: sent), total - sent)
            if n <= 0 { throw E2EError.websocket("write") }
            sent += n
        }
    }
}

private func readSome(fd: Int32, max: Int) throws -> Data {
    var buf = [UInt8](repeating: 0, count: max)
    let n = buf.withUnsafeMutableBytes { raw in
        #if canImport(Glibc)
        Glibc.read(fd, raw.baseAddress, max)
        #elseif canImport(Musl)
        Musl.read(fd, raw.baseAddress, max)
        #else
        Darwin.read(fd, raw.baseAddress, max)
        #endif
    }
    if n < 0 { throw E2EError.websocket("read errno=\(errno)") }
    if n == 0 { return Data() }
    return Data(buf.prefix(n))
}

func waitForWorker(url: URL, attempts: Int = 5) async throws {
    let transport = AbsoluteURLHTTPTransport(baseURL: url)
    var last = "no attempt"
    for _ in 0..<attempts {
        do {
            let response = try await transport.perform(
                HTTPRequest(
                    method: "POST",
                    path: "/v1/offers",
                    headers: ["Content-Type": "application/json"],
                    body: Data(#"{"x":"nope"}"#.utf8)
                )
            )
            if response.status == 400 { return }
            last = "status \(response.status)"
        } catch {
            last = String(describing: error)
        }
        try await Task.sleep(nanoseconds: 200_000_000)
    }
    throw E2EError.workerUnreachable("\(url.absoluteString) last=\(last). Run ./sync/e2e/run.sh")
}

func bindUntilBound(_ flow: PairingFlow) async throws {
    for _ in 0..<40 {
        let response = try await flow.refreshBind()
        if response.bound { return }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    throw E2EError.timeout("bind")
}

func confirmUntilEstablished(_ flow: PairingFlow) async throws {
    for _ in 0..<40 {
        try await flow.authenticateAndConfirm()
        if await flow.phase == .established { return }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    throw E2EError.timeout("confirm")
}

func seal<T: Encodable>(
    _ value: T,
    pairingId: UUID,
    kind: WireKind,
    rev: Int,
    encKey: Data
) throws -> Envelope {
    let plaintext = try SyncCrypto.encodeJSON(value)
    return try SyncCrypto.seal(
        plaintext: plaintext,
        pairingId: pairingId,
        kind: kind,
        rev: rev,
        encKey: encKey,
        nonce: SyncCrypto.randomBytes(12)
    )
}

func openJSON<T: Decodable>(_ type: T.Type, envelope: Envelope, pairingId: UUID, encKey: Data) throws -> T {
    let data = try SyncCrypto.open(envelope, pairingId: pairingId, encKey: encKey)
    return try SyncCrypto.decodeJSON(type, from: data)
}

func assertOpaqueEnvelopeJSON(_ data: Data, expectedKind: WireKind) throws {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw E2EError.unexpectedJSON("not an object")
    }
    let keys = Set(object.keys)
    guard keys == ["rev", "kind", "n", "ct"] else {
        throw E2EError.unexpectedJSON("keys \(keys.sorted())")
    }
    guard object["kind"] as? String == expectedKind.rawValue else {
        throw E2EError.unexpectedJSON("kind \(String(describing: object["kind"]))")
    }
    if object["title"] != nil {
        throw E2EError.plaintextLeaked("snap JSON title key")
    }
}

func assertNoPlaintextTitle(in exchanges: [(HTTPRequest, HTTPResponse)], title: String) throws {
    for (request, response) in exchanges {
        if let body = request.body, let text = String(data: body, encoding: .utf8), text.contains(title) {
            throw E2EError.plaintextLeaked("\(request.method) \(request.path) request")
        }
        if let text = String(data: response.body, encoding: .utf8), text.contains(title) {
            throw E2EError.plaintextLeaked("\(request.method) \(request.path) response")
        }
    }
}
