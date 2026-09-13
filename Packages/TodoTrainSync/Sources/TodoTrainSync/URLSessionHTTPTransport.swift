import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct URLSessionHTTPTransport: HTTPTransport, @unchecked Sendable {
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        let url = try Self.resourceURL(baseURL: baseURL, path: request.path)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await session.data(for: urlRequest)
        if let http = response as? HTTPURLResponse {
            return HTTPResponse(http: http, body: data)
        }
        return HTTPResponse(status: 0, body: data)
    }

    /// Replace the base URL path with the request path. `appendingPathComponent` mangles `/v1/...`.
    public static func resourceURL(baseURL: URL, path: String) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw SyncError.invalidPairingURL
        }
        components.path = path.hasPrefix("/") ? path : "/" + path
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw SyncError.invalidPairingURL }
        return url
    }
}
