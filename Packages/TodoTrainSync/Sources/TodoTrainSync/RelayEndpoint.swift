import Foundation

/// Default relay hosts. Pairing still lets the user paste a preview URL.
public enum RelayEndpoint: Sendable {
    /// Cloudflare Worker custom domain (`todotrain-sync` / `--env production`).
    public static let productionURLString = "https://todo-train.hibiki-cube.dev"
    /// `todotrain-sync-develop` / `--env develop`.
    public static let developURLString = "https://dev.todo-train.hibiki-cube.dev"
    public static let localDevURLString = "http://127.0.0.1:8787"

    public static var defaultURLString: String {
        #if DEBUG
        developURLString
        #else
        productionURLString
        #endif
    }

    /// Stored `127.0.0.1` was the old DEBUG default. Treat it as unset.
    public static func coalesceStored(_ stored: String?) -> String {
        guard let stored else { return defaultURLString }
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == localDevURLString {
            return defaultURLString
        }
        return trimmed
    }
}
