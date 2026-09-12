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
        localDevURLString
        #else
        productionURLString
        #endif
    }
}
