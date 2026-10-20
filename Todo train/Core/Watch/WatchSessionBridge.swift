//
//  WatchSessionBridge.swift
//  Todo train
//

import Foundation
import TodoTrainSync
import WatchConnectivity

/// iPhone side of the Watch copy. Latest state goes out as application context.
/// A reply comes back as a message, or as user info when the message cannot be delivered.
@MainActor
final class WatchSessionBridge {
    static let shared = WatchSessionBridge()

    private enum Defaults {
        static let rev = "watch.snapRev"
        static let processed = "watch.processedCmdIDs"
    }

    private let defaults: UserDefaults
    private let link = WatchPhoneLink()
    private var processedCommandIDs: Set<UUID>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: Defaults.processed) ?? []
        self.processedCommandIDs = Set(stored.compactMap(UUID.init(uuidString:)))
        link.onCommand = { [weak self] data in
            self?.apply(commandData: data)
        }
    }

    func activate() {
        link.activate()
    }

    func publishCurrent() {
        guard let sessionManager = AppRuntime.sessionManager else { return }
        let rev = defaults.integer(forKey: Defaults.rev) + 1
        defaults.set(rev, forKey: Defaults.rev)
        let snap = RideWireSnap.make(
            sessionManager: sessionManager,
            settings: sessionManager.settings,
            rev: rev,
            now: Date()
        )
        guard let context = try? WatchLink.context(for: snap),
              let data = context[WatchLink.snapKey] as? Data else { return }
        link.update(snapData: data)
    }

    func apply(commandData: Data) {
        guard let command = WatchLink.command(fromBody: commandData) else { return }
        guard WatchLink.maySendReply(peer: command.announcement) else { return }
        guard let sessionManager = AppRuntime.sessionManager else { return }
        guard !processedCommandIDs.contains(command.id) else { return }
        do {
            _ = try CompanionCommandApplying.apply(command, sessionManager: sessionManager)
        } catch {
            return
        }
        processedCommandIDs.insert(command.id)
        let kept = processedCommandIDs.prefix(32).map(\.uuidString)
        defaults.set(Array(kept), forKey: Defaults.processed)
    }
}

nonisolated final class WatchPhoneLink: NSObject, WCSessionDelegate {
    nonisolated(unsafe) var onCommand: (@MainActor (Data) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func update(snapData: Data) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        try? session.updateApplicationContext(WatchLink.context(snapData: snapData))
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            WatchSessionBridge.shared.publishCurrent()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        deliver(message[WatchLink.commandKey] as? Data)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        deliver(message[WatchLink.commandKey] as? Data)
        replyHandler([:])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        deliver(userInfo[WatchLink.commandKey] as? Data)
    }

    private func deliver(_ data: Data?) {
        guard let data else { return }
        let handler = onCommand
        Task { @MainActor in
            handler?(data)
        }
    }
}
