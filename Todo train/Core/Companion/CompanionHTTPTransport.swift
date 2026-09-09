import Foundation
import TodoTrainSync

struct CompanionHTTPTransport: HTTPTransport, @unchecked Sendable {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw SyncError.invalidPairingURL
        }
        components.path = request.path.hasPrefix("/") ? request.path : "/" + request.path
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw SyncError.invalidPairingURL }
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

enum CompanionEnvelope {
    static func seal<T: Encodable>(
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

    static func open<T: Decodable>(
        _ type: T.Type,
        envelope: Envelope,
        pairingId: UUID,
        encKey: Data
    ) throws -> T {
        let data = try SyncCrypto.open(envelope, pairingId: pairingId, encKey: encKey)
        return try SyncCrypto.decodeJSON(type, from: data)
    }
}
