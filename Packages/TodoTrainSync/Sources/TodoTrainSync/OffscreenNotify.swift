import Foundation

/// Safety-net notices. Progress questions are not in this set.
public enum OffscreenKind: Sendable, Equatable {
    case overtime
    case away
    case idle
    case progress
}

/// What each screen is doing. `macKnown` is false when presence has not arrived or the link dropped.
public struct OffscreenScreens: Equatable, Sendable {
    public var sceneActive: Bool
    public var focusVisible: Bool
    public var riding: Bool
    public var hubVisible: Bool
    public var macPipVisible: Bool
    public var macAttending: Bool
    public var macKnown: Bool

    public init(
        sceneActive: Bool,
        focusVisible: Bool,
        riding: Bool,
        hubVisible: Bool,
        macPipVisible: Bool,
        macAttending: Bool,
        macKnown: Bool
    ) {
        self.sceneActive = sceneActive
        self.focusVisible = focusVisible
        self.riding = riding
        self.hubVisible = hubVisible
        self.macPipVisible = macPipVisible
        self.macAttending = macAttending
        self.macKnown = macKnown
    }
}

public enum OffscreenDelivery: Equatable, Sendable {
    case none
    case iphone
    case mac
}

/// Last-line local notification. One device, or none.
/// Unknown Mac presence sends on iPhone. A visible Mac PiP sends nowhere.
public enum OffscreenNotify {
    public static func iphoneOnScreen(kind: OffscreenKind, screens: OffscreenScreens) -> Bool {
        switch kind {
        case .idle:
            return screens.sceneActive && (screens.hubVisible || screens.focusVisible)
        case .overtime, .away, .progress:
            guard screens.sceneActive else { return false }
            if screens.riding { return screens.focusVisible }
            return true
        }
    }

    public static func delivery(
        kind: OffscreenKind,
        screens: OffscreenScreens,
        turn: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> OffscreenDelivery {
        if kind == .progress { return .none }
        guard ReminderDay.allows(now, calendar: calendar) else { return .none }
        guard (0..<NudgeThresholds.maxRings).contains(turn) else { return .none }
        if screens.macKnown && screens.macPipVisible { return .none }
        if iphoneOnScreen(kind: kind, screens: screens) { return .none }
        if !screens.macKnown { return .iphone }
        switch NudgePlanner.offscreenSurface(turn: turn, macAttending: screens.macAttending) {
        case .mac: return .mac
        case .iphone: return .iphone
        case .watch, .none: return .none
        }
    }
}

public struct MacOffscreenRequest: Equatable, Sendable {
    public var identifier: String
    public var title: String
    public var body: String
    public var fireAt: Date

    public init(identifier: String, title: String, body: String, fireAt: Date) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.fireAt = fireAt
    }
}

/// Mac's own local notifications. Push is not used.
public enum MacOffscreenPlanning {
    public static let overtimeID = "todotrain.offscreen.overtime"
    public static let awayID = "todotrain.offscreen.away"

    public static func idleID(turn: Int) -> String {
        "todotrain.offscreen.idle.\(turn)"
    }

    public static func requests(
        snap: SnapPlaintext?,
        pipVisible: Bool,
        now: Date,
        calendar: Calendar = .current
    ) -> [MacOffscreenRequest] {
        guard let snap, snap.notifyOn == .mac, !pipVisible else { return [] }
        guard ReminderDay.allows(now, calendar: calendar) else { return [] }
        let turn = snap.notifyTurn ?? 0
        guard (0..<NudgeThresholds.maxRings).contains(turn) else { return [] }
        let unix = Int(now.timeIntervalSince1970)
        switch snap.phase {
        case .running, .overtime:
            return rideRequests(snap: snap, turn: turn, now: now, unix: unix)
        case .idle:
            return idleRequests(snap: snap, turn: turn, now: now, unix: unix)
        case .paused, .unknown:
            return []
        }
    }

    private static func rideRequests(
        snap: SnapPlaintext,
        turn: Int,
        now: Date,
        unix: Int
    ) -> [MacOffscreenRequest] {
        _ = turn
        var out: [MacOffscreenRequest] = []
        if let remaining = snap.remainingSeconds(at: unix), snap.phase == .overtime || remaining > 0 {
            let fire = remaining > 1 ? now.addingTimeInterval(TimeInterval(remaining)) : now
            out.append(
                MacOffscreenRequest(
                    identifier: overtimeID,
                    title: "Todo train",
                    body: CabinCopy.overtimePassed(title: snap.title ?? ""),
                    fireAt: fire
                )
            )
        }
        if snap.pendingCabin == .away || (snap.phase == .running && snap.notifyFireAt != nil) {
            let fire = snap.notifyFireAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? now
            out.append(
                MacOffscreenRequest(
                    identifier: awayID,
                    title: CabinCopy.prompt,
                    body: snap.title ?? "",
                    fireAt: fire
                )
            )
        }
        return out
    }

    private static func idleRequests(
        snap: SnapPlaintext,
        turn: Int,
        now: Date,
        unix: Int
    ) -> [MacOffscreenRequest] {
        guard snap.pendingCabin == .idle || snap.notifyFireAt != nil else { return [] }
        let fire: Date
        if snap.pendingCabin == .idle {
            fire = now
        } else {
            fire = Date(timeIntervalSince1970: TimeInterval(snap.notifyFireAt ?? unix))
        }
        return [
            MacOffscreenRequest(
                identifier: idleID(turn: turn),
                title: CabinCopy.idle,
                body: "",
                fireAt: fire
            ),
        ]
    }
}
