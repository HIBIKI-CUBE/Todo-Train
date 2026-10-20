import Foundation

/// How a Watch reply leaves the watch. Out of range is display only.
public enum WatchChannel: Equatable, Sendable {
    case sendMessage
    case transferUserInfo
    case displayOnly
}

/// Whether the Watch may answer. Waiting means no snap has arrived.
public enum WatchReplyGate: Equatable, Sendable {
    case waiting
    case displayOnly
    case open
}

public struct WatchReplyPlan: Equatable, Sendable {
    public var channel: WatchChannel
    public var body: Data?

    public init(channel: WatchChannel, body: Data?) {
        self.channel = channel
        self.body = body
    }
}

/// Snap-shaped payload for WatchConnectivity. The relay is not on this path.
public enum WatchLink {
    public static let snapKey = "snap"
    public static let commandKey = "cmd"

    public static func context(for snap: SnapPlaintext) throws -> [String: Any] {
        context(snapData: try WireJSON.encoder().encode(snap))
    }

    public static func context(snapData: Data) -> [String: Any] {
        [snapKey: snapData]
    }

    public static func snap(from context: [String: Any]) -> SnapPlaintext? {
        guard let data = context[snapKey] as? Data else { return nil }
        return snap(fromSnapData: data)
    }

    public static func snap(fromSnapData data: Data) -> SnapPlaintext? {
        try? WireJSON.decoder().decode(SnapPlaintext.self, from: data)
    }

    public static func message(body: Data) -> [String: Any] {
        [commandKey: body]
    }

    public static func command(from payload: [String: Any]) -> CommandPlaintext? {
        guard let data = payload[commandKey] as? Data else { return nil }
        return command(fromBody: data)
    }

    public static func command(fromBody data: Data) -> CommandPlaintext? {
        try? WireJSON.decoder().decode(CommandPlaintext.self, from: data)
    }

    /// The peer is the other side's announcement. Out of range does not send.
    public static func maySendReply(
        peer: ContractAnnouncement,
        local: ContractAnnouncement = .current
    ) -> Bool {
        ContractCompat.evaluate(local: local, peer: peer).maySendOperations
    }

    public static func channel(
        reachable: Bool,
        peer: ContractAnnouncement,
        local: ContractAnnouncement = .current
    ) -> WatchChannel {
        guard maySendReply(peer: peer, local: local) else { return .displayOnly }
        return reachable ? .sendMessage : .transferUserInfo
    }

    /// `body` is nil when the reply must not be sent.
    public static func plan(
        command: CommandPlaintext,
        reachable: Bool,
        peer: ContractAnnouncement,
        local: ContractAnnouncement = .current
    ) -> WatchReplyPlan {
        let channel = channel(reachable: reachable, peer: peer, local: local)
        guard channel != .displayOnly else {
            return WatchReplyPlan(channel: .displayOnly, body: nil)
        }
        guard let body = try? WireJSON.encoder().encode(command) else {
            return WatchReplyPlan(channel: .displayOnly, body: nil)
        }
        return WatchReplyPlan(channel: channel, body: body)
    }
}

/// Where the Watch app opens. An open ride is the ride screen. Otherwise 発車.
public enum WatchOpenedScreen: Equatable, Sendable {
    case riding
    case board
}

/// The Watch's copy of the iPhone snap. A newer context replaces it.
public struct WatchMirror: Equatable, Sendable {
    public private(set) var snap: SnapPlaintext?

    public init() {}

    public mutating func receive(_ context: [String: Any]) {
        guard let snap = WatchLink.snap(from: context) else { return }
        self.snap = snap
    }

    public mutating func receive(snapData: Data) {
        guard let snap = WatchLink.snap(fromSnapData: snapData) else { return }
        self.snap = snap
    }

    public var title: String? { snap?.title }

    public func remainingSeconds(at now: Int) -> Int? {
        snap?.remainingSeconds(at: now)
    }

    public var peer: ContractAnnouncement {
        snap?.announcement ?? .legacyPeer
    }

    public var replyGate: WatchReplyGate {
        guard snap != nil else { return .waiting }
        return WatchLink.maySendReply(peer: peer) ? .open : .displayOnly
    }

    /// Live Activity launch lands here. Running, paused, and overtime stay on the ride.
    /// No snap yet is not a ride, so it opens 発車.
    public var openedScreen: WatchOpenedScreen {
        switch snap?.phase {
        case .running, .paused, .overtime:
            return .riding
        case .idle, .unknown, nil:
            return .board
        }
    }
}

/// Commit line for a Watch build. The Watch has no store, so the store version is omitted.
public enum WatchBuildLine {
    public static func line(sha: String, branch: String, dirty: Bool, builtAt: String) -> String {
        guard sha != BuildStamp.unknown else { return BuildInfoCopy.unrecorded }
        let when = BuildStamp.displayTime(builtAt) ?? builtAt
        var text = "\(sha) · \(branch) · \(when)"
        if dirty {
            text += " · \(BuildInfoCopy.dirty)"
        }
        return text
    }
}
