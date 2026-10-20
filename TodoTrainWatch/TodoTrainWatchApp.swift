import SwiftUI
import TodoTrainSync
import WatchConnectivity

@main
struct TodoTrainWatchApp: App {
    @State private var session = WatchPhoneSession()

    var body: some Scene {
        WindowGroup {
            WatchRootView(session: session)
        }
    }
}

@MainActor
@Observable
final class WatchPhoneSession {
    private(set) var mirror = WatchMirror()
    private let link = WatchLinkSession()

    init() {
        if WCSession.isSupported(),
           let data = WCSession.default.receivedApplicationContext[WatchLink.snapKey] as? Data {
            mirror.receive(snapData: data)
        }
    }

    func activate() {
        link.onSnap = { [weak self] data in
            self?.mirror.receive(snapData: data)
        }
        link.activate()
    }

    /// Later screens call this. Out of range drops the reply before it is sent.
    func deliver(_ command: CommandPlaintext) {
        guard mirror.replyGate == .open else { return }
        var stamped = command
        stamped.contract = ContractVersion.contract
        stamped.minReadable = ContractVersion.minReadable
        let plan = WatchLink.plan(
            command: stamped,
            reachable: link.isReachable,
            peer: mirror.peer
        )
        link.send(plan)
    }
}

nonisolated final class WatchLinkSession: NSObject, WCSessionDelegate {
    nonisolated(unsafe) var onSnap: (@MainActor (Data) -> Void)?

    var isReachable: Bool {
        guard WCSession.isSupported() else { return false }
        return WCSession.default.isReachable
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func send(_ plan: WatchReplyPlan) {
        guard let body = plan.body else { return }
        guard WCSession.isSupported() else { return }
        let message = WatchLink.message(body: body)
        let session = WCSession.default
        switch plan.channel {
        case .displayOnly:
            return
        case .sendMessage:
            session.sendMessage(message, replyHandler: nil) { _ in
                session.transferUserInfo(message)
            }
        case .transferUserInfo:
            session.transferUserInfo(message)
        }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        deliver(session.receivedApplicationContext[WatchLink.snapKey] as? Data)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        deliver(applicationContext[WatchLink.snapKey] as? Data)
    }

    private func deliver(_ data: Data?) {
        guard let data else { return }
        let handler = onSnap
        Task { @MainActor in
            handler?(data)
        }
    }
}
