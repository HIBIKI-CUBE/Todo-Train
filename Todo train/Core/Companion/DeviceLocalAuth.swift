import Foundation
import LocalAuthentication
import TodoTrainSync

struct DeviceLocalAuth: LocalAuthenticating {
    func confirmPresence() async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw SyncError.pairingAborted
        }
        let reason = "画面を自分に戻して、この Mac との連携を確定します"
        let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        if !ok { throw SyncError.pairingAborted }
    }
}
