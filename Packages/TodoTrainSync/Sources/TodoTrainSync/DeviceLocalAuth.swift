#if canImport(LocalAuthentication)
import Foundation
import LocalAuthentication

public struct DeviceLocalAuth: LocalAuthenticating {
    public var reason: String

    public init(reason: String) {
        self.reason = reason
    }

    public func confirmPresence() async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw SyncError.pairingAborted
        }
        let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        if !ok { throw SyncError.pairingAborted }
    }
}
#endif
