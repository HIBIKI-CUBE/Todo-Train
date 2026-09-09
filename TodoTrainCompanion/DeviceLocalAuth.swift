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
        let reason = "画面を自分に戻して、iPhone との連携を確定します"
        let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        if !ok { throw SyncError.pairingAborted }
    }
}

/// develop の `PairingFlow.authenticateAndConfirm` は confirm 待ちで何度も呼ばれる。Touch ID は一度だけ。
final class OnceLocalAuth: LocalAuthenticating, @unchecked Sendable {
    private let inner: any LocalAuthenticating
    private let lock = NSLock()
    private var didConfirm = false

    init(_ inner: any LocalAuthenticating) {
        self.inner = inner
    }

    func confirmPresence() async throws {
        lock.lock()
        let already = didConfirm
        lock.unlock()
        if already { return }
        try await inner.confirmPresence()
        lock.lock()
        didConfirm = true
        lock.unlock()
    }
}
