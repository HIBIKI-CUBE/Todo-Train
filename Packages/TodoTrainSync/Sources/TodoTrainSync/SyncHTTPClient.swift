import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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

private struct ErrorBody: Codable {
    var error: String
}

public struct SyncHTTPClient: Sendable {
    public static let pairingIdHeaderName = "X-Pairing-Id"

    public var baseURL: URL
    public var transport: any HTTPTransport
    public var writeToken: Data?
    public var pairingId: UUID?

    public init(baseURL: URL, transport: any HTTPTransport, writeToken: Data? = nil, pairingId: UUID? = nil) {
        self.baseURL = baseURL
        self.transport = transport
        self.writeToken = writeToken
        self.pairingId = pairingId
    }

    public func createOffer(x: Data) async throws -> OfferCreated {
        try await send(
            method: "POST",
            path: "/v1/offers",
            auth: false,
            body: ["x": Base64URL.encode(x)],
            expected: [201]
        )
    }

    public func bindOffer(id: UUID, request: BindRequest) async throws -> BindResponse {
        try await send(
            method: "POST",
            path: "/v1/offers/\(id.canonicalLowercase)/bind",
            auth: false,
            body: request,
            expected: [200]
        )
    }

    public func confirmIphone(id: UUID, hmac: String) async throws -> ConfirmResponse {
        try await send(
            method: "POST",
            path: "/v1/offers/\(id.canonicalLowercase)/confirm-iphone",
            auth: false,
            body: ["hmac": hmac],
            expected: [200]
        )
    }

    public func confirmMac(id: UUID, hmac: String) async throws -> ConfirmResponse {
        try await send(
            method: "POST",
            path: "/v1/offers/\(id.canonicalLowercase)/confirm-mac",
            auth: false,
            body: ["hmac": hmac],
            expected: [200]
        )
    }

    public func deleteOffer(id: UUID) async throws {
        _ = try await raw(method: "DELETE", path: "/v1/offers/\(id.canonicalLowercase)", auth: false, body: nil as Data?, expected: [204])
    }

    public func putPairing(id: UUID, tokenHash: String) async throws -> PairingRegistered {
        try await send(
            method: "PUT",
            path: "/v1/pairings/\(id.canonicalLowercase)",
            auth: false,
            body: ["tokenHash": tokenHash],
            expected: [200]
        )
    }

    public func getSnap() async throws -> Envelope {
        try await send(method: "GET", path: "/v1/snap", auth: true, body: nil as Data?, expected: [200])
    }

    public func putSnap(_ envelope: Envelope) async throws -> SnapPutResponse {
        try await send(method: "PUT", path: "/v1/snap", auth: true, body: envelope, expected: [200])
    }

    public func postCmd(_ envelope: Envelope) async throws -> CmdQueued {
        try await send(method: "POST", path: "/v1/cmd", auth: true, body: envelope, expected: [201])
    }

    public func getCmd() async throws -> CmdList {
        try await send(method: "GET", path: "/v1/cmd", auth: true, body: nil as Data?, expected: [200])
    }

    public func putAck(_ envelope: Envelope) async throws -> AckStored {
        try await send(method: "PUT", path: "/v1/ack", auth: true, body: envelope, expected: [200])
    }

    public func getAck() async throws -> Envelope {
        try await send(method: "GET", path: "/v1/ack", auth: true, body: nil as Data?, expected: [200])
    }

    private func send<Body: Encodable, Response: Decodable>(
        method: String,
        path: String,
        auth: Bool,
        body: Body?,
        expected: Set<Int>
    ) async throws -> Response {
        let data: Data?
        if let body {
            data = try WireJSON.encoder().encode(body)
        } else {
            data = nil
        }
        let response = try await raw(method: method, path: path, auth: auth, body: data, expected: expected)
        return try WireJSON.decoder().decode(Response.self, from: response.body)
    }

    private func raw(method: String, path: String, auth: Bool, body: Data?, expected: Set<Int>) async throws -> HTTPResponse {
        var headers: [String: String] = [:]
        if body != nil {
            headers["Content-Type"] = "application/json"
        }
        if auth {
            guard let writeToken else { throw SyncError.notPaired }
            headers["Authorization"] = "Bearer \(Base64URL.encode(writeToken))"
            if let pairingId {
                headers[Self.pairingIdHeaderName] = pairingId.canonicalLowercase
            }
        }
        let request = HTTPRequest(method: method, path: path, headers: headers, body: body)
        let response = try await transport.perform(request)
        if !expected.contains(response.status) {
            let code = (try? WireJSON.decoder().decode(ErrorBody.self, from: response.body).error) ?? "invalid"
            throw SyncError.transport(status: response.status, code: code)
        }
        return response
    }
}

public final class URLSessionHTTPTransport: HTTPTransport, @unchecked Sendable {
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        let url = baseURL.appendingPathComponent(String(request.path.drop(while: { $0 == "/" })))
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
}
