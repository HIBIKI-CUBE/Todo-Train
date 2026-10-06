//
//  PassengerLane.swift
//  Todo train
//
//  予定区間の乗客レーン。切符の SessionPhase には足さない。
//  自動では aboard にしない。
//

import Foundation

nonisolated enum PassengerRideSource: String, Codable, Sendable, Equatable {
    case adoptedBlock
    case manualInterval
}

nonisolated enum PassengerEndReason: String, Codable, Sendable, Equatable {
    case arrived
    case emergency
    case cancelled
}

nonisolated enum PassengerGuidePhrase: Equatable, Sendable {
    case next
    case soon
    case now

    var japanese: String {
        switch self {
        case .next: PassengerCopy.next
        case .soon: PassengerCopy.soon
        case .now: PassengerCopy.now
        }
    }

    var english: String {
        switch self {
        case .next: PassengerCopy.nextEn
        case .soon: PassengerCopy.soonEn
        case .now: PassengerCopy.nowEn
        }
    }
}

nonisolated struct PassengerInterval: Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var startsAt: Date
    var endsAt: Date
    var source: PassengerRideSource
    var isCancelled: Bool
}

nonisolated struct PassengerBlockInput: Equatable, Sendable {
    var id: String
    var title: String
    var startsAt: Date
    var endsAt: Date
    var source: PassengerRideSource
    var isCancelled: Bool
}

nonisolated struct PassengerRideSnapshot: Equatable, Sendable, Identifiable {
    var id: UUID
    var intervalId: String
    var title: String
    var intervalStart: Date
    var intervalEnd: Date
    var boardedAt: Date
    var endedAt: Date?
    var endReason: PassengerEndReason?
    var source: PassengerRideSource
    var deviceId: String?
}

nonisolated enum PassengerChrome: Equatable, Sendable {
    case none
    case soon(PassengerInterval)
    case offer(PassengerInterval, collapsed: Bool)
    case aboard(PassengerRideSnapshot, phrase: PassengerGuidePhrase, progress: Double)
    case arrived(PassengerRideSnapshot)
    case doorOpened(PassengerRideSnapshot)

    var isFullScreen: Bool {
        switch self {
        case .aboard, .arrived, .doorOpened: true
        default: false
        }
    }

    var locksDriving: Bool { isFullScreen }

    /// 申し出と乗車中は接近クリアランスより先。まもなく帯はまだ申し出ではない。
    var blocksApproachClear: Bool {
        switch self {
        case .offer, .aboard, .arrived, .doorOpened: true
        default: false
        }
    }

    var showsHubOffer: Bool {
        switch self {
        case .soon, .offer: true
        default: false
        }
    }
}

nonisolated struct PassengerGreeting: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case arrived
        case doorOpened
    }

    var kind: Kind
    var until: Date
    var ride: PassengerRideSnapshot
}

nonisolated struct PassengerLaneMemory: Equatable, Sendable {
    var offerAnchor: Date?
    var offerAnchorIntervalID: String?
    var collapsedIntervalID: String?
    var greeting: PassengerGreeting?
    var notifiedIntervalID: String?

    static let empty = PassengerLaneMemory()
}

nonisolated struct PassengerIntervalFollow: Equatable, Sendable {
    var title: String
    var startsAt: Date
    var endsAt: Date
}

nonisolated struct PassengerClose: Equatable, Sendable {
    var reason: PassengerEndReason
    var at: Date
}

nonisolated enum PassengerNotify: Equatable, Sendable {
    case none
    case schedule(intervalID: String, title: String, fireAt: Date)
    case cancel
}

nonisolated struct PassengerLaneEffect: Equatable, Sendable {
    var chrome: PassengerChrome
    var memory: PassengerLaneMemory
    var follow: PassengerIntervalFollow?
    var close: PassengerClose?
    var notify: PassengerNotify
}

nonisolated enum PassengerEligibility {
    /// 終日・辞退は着発ブロックにならない。ここへ来るのは着発済みと手動枠だけ。
    static func intervals(
        from blocks: [PassengerBlockInput],
        calendarAuthorized: Bool,
        keepingIntervalID: String? = nil
    ) -> [PassengerInterval] {
        blocks.compactMap { block in
            guard block.endsAt > block.startsAt else { return nil }
            if block.source == .adoptedBlock, !calendarAuthorized, block.id != keepingIntervalID {
                return nil
            }
            return PassengerInterval(
                id: block.id,
                title: block.title,
                startsAt: block.startsAt,
                endsAt: block.endsAt,
                source: block.source,
                isCancelled: block.isCancelled
            )
        }
    }
}

nonisolated enum PassengerLane {
    /// 開始の数分前。帯の「まもなく」。
    static let soonLead: TimeInterval = 5 * 60
    /// 目立つ［乗る］を帯に縮めるまで。
    static let collapseDelay: TimeInterval = 45
    /// 終盤の「まもなく」と開扉矢印。
    static let soonBeforeArrival: TimeInterval = 3 * 60
    static let arrivedGreeting: TimeInterval = 2.5
    static let doorOpenedGreeting: TimeInterval = 1.8
    static let emergencyHold: TimeInterval = 1.5
    /// 最初の切れ端に自動乗車はない。
    static let boardsAutomatically = false

    static func progress(start: Date, end: Date, now: Date) -> Double {
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return 0 }
        let raw = now.timeIntervalSince(start) / span
        return min(1, max(0, raw))
    }

    static func aboardPhrase(end: Date, now: Date) -> PassengerGuidePhrase {
        let remaining = end.timeIntervalSince(now)
        if remaining <= soonBeforeArrival { return .soon }
        return .next
    }

    static func ride(
        on interval: PassengerInterval,
        now: Date,
        id: UUID = UUID(),
        deviceID: String?
    ) -> PassengerRideSnapshot {
        PassengerRideSnapshot(
            id: id,
            intervalId: interval.id,
            title: interval.title,
            intervalStart: interval.startsAt,
            intervalEnd: interval.endsAt,
            boardedAt: now,
            endedAt: nil,
            endReason: nil,
            source: interval.source,
            deviceId: deviceID
        )
    }

    static func emergency(
        ride: PassengerRideSnapshot,
        now: Date
    ) -> (ride: PassengerRideSnapshot, greeting: PassengerGreeting) {
        var ended = ride
        ended.endedAt = now
        ended.endReason = .emergency
        let greeting = PassengerGreeting(
            kind: .doorOpened,
            until: now.addingTimeInterval(doorOpenedGreeting),
            ride: ended
        )
        return (ended, greeting)
    }

    static func resolve(
        intervals: [PassengerInterval],
        openRide: PassengerRideSnapshot?,
        now: Date,
        memory: PassengerLaneMemory,
        ticketRunning: Bool
    ) -> PassengerLaneEffect {
        var memory = memory
        if let greeting = memory.greeting, now >= greeting.until {
            memory.greeting = nil
        }

        if let openRide, openRide.endedAt == nil {
            if let interval = intervals.first(where: { $0.id == openRide.intervalId }), !interval.isCancelled {
                return ridingEffect(openRide, interval: interval, now: now, memory: &memory)
            }
            var effect = offerEffect(
                intervals: intervals,
                now: now,
                memory: &memory,
                ticketRunning: ticketRunning
            )
            effect.close = PassengerClose(reason: .cancelled, at: now)
            return effect
        }

        if let greeting = memory.greeting, now < greeting.until {
            let chrome: PassengerChrome = greeting.kind == .arrived
                ? .arrived(greeting.ride)
                : .doorOpened(greeting.ride)
            return PassengerLaneEffect(
                chrome: chrome,
                memory: memory,
                follow: nil,
                close: nil,
                notify: .none
            )
        }

        return offerEffect(
            intervals: intervals,
            now: now,
            memory: &memory,
            ticketRunning: ticketRunning
        )
    }

    private static func ridingEffect(
        _ openRide: PassengerRideSnapshot,
        interval: PassengerInterval,
        now: Date,
        memory: inout PassengerLaneMemory
    ) -> PassengerLaneEffect {
        let follow = PassengerIntervalFollow(
            title: interval.title,
            startsAt: interval.startsAt,
            endsAt: interval.endsAt
        )
        memory.offerAnchor = nil
        memory.offerAnchorIntervalID = nil
        let notify = clearNotification(&memory)

        if now >= interval.endsAt {
            var ended = openRide
            ended.title = interval.title
            ended.intervalStart = interval.startsAt
            ended.intervalEnd = interval.endsAt
            ended.endedAt = now
            ended.endReason = .arrived
            memory.greeting = PassengerGreeting(
                kind: .arrived,
                until: now.addingTimeInterval(arrivedGreeting),
                ride: ended
            )
            memory.collapsedIntervalID = nil
            return PassengerLaneEffect(
                chrome: .arrived(ended),
                memory: memory,
                follow: follow,
                close: PassengerClose(reason: .arrived, at: now),
                notify: notify
            )
        }

        var riding = openRide
        riding.title = interval.title
        riding.intervalStart = interval.startsAt
        riding.intervalEnd = interval.endsAt
        memory.collapsedIntervalID = nil
        return PassengerLaneEffect(
            chrome: .aboard(
                riding,
                phrase: aboardPhrase(end: interval.endsAt, now: now),
                progress: progress(start: interval.startsAt, end: interval.endsAt, now: now)
            ),
            memory: memory,
            follow: follow,
            close: nil,
            notify: notify
        )
    }

    private static func offerEffect(
        intervals: [PassengerInterval],
        now: Date,
        memory: inout PassengerLaneMemory,
        ticketRunning: Bool
    ) -> PassengerLaneEffect {
        let live = intervals.filter { interval in
            !interval.isCancelled && interval.endsAt > interval.startsAt && now < interval.endsAt
        }
        if let current = earliest(live.filter { $0.startsAt <= now }) {
            noteOfferAnchor(current, now: now, memory: &memory)
            let collapsed = isCollapsed(current, now: now, memory: memory)
            if collapsed {
                memory.collapsedIntervalID = current.id
            }
            let notify = arm(current, now: now, ticketRunning: ticketRunning, memory: &memory)
            return PassengerLaneEffect(
                chrome: .offer(current, collapsed: collapsed),
                memory: memory,
                follow: nil,
                close: nil,
                notify: notify
            )
        }

        let upcoming = live.filter { interval in
            interval.startsAt > now && interval.startsAt.timeIntervalSince(now) <= soonLead
        }
        if let soon = earliest(upcoming) {
            if memory.offerAnchorIntervalID != soon.id {
                memory.offerAnchor = nil
                memory.offerAnchorIntervalID = nil
                memory.collapsedIntervalID = nil
            }
            let notify = arm(soon, now: now, ticketRunning: ticketRunning, memory: &memory)
            return PassengerLaneEffect(
                chrome: .soon(soon),
                memory: memory,
                follow: nil,
                close: nil,
                notify: notify
            )
        }

        let notify = clearNotification(&memory)
        memory.offerAnchor = nil
        memory.offerAnchorIntervalID = nil
        return PassengerLaneEffect(
            chrome: .none,
            memory: memory,
            follow: nil,
            close: nil,
            notify: notify
        )
    }

    private static func noteOfferAnchor(
        _ interval: PassengerInterval,
        now: Date,
        memory: inout PassengerLaneMemory
    ) {
        if memory.offerAnchorIntervalID != interval.id || memory.offerAnchor == nil {
            memory.offerAnchor = now
            memory.offerAnchorIntervalID = interval.id
            if memory.collapsedIntervalID != interval.id {
                memory.collapsedIntervalID = nil
            }
        }
    }

    private static func isCollapsed(
        _ interval: PassengerInterval,
        now: Date,
        memory: PassengerLaneMemory
    ) -> Bool {
        if memory.collapsedIntervalID == interval.id { return true }
        guard let anchor = memory.offerAnchor else { return false }
        return now.timeIntervalSince(anchor) >= collapseDelay
    }

    private static func arm(
        _ interval: PassengerInterval,
        now: Date,
        ticketRunning: Bool,
        memory: inout PassengerLaneMemory
    ) -> PassengerNotify {
        if ticketRunning {
            return clearNotification(&memory)
        }
        guard interval.startsAt > now else { return .none }
        if memory.notifiedIntervalID == interval.id { return .none }
        memory.notifiedIntervalID = interval.id
        return .schedule(intervalID: interval.id, title: interval.title, fireAt: interval.startsAt)
    }

    private static func clearNotification(_ memory: inout PassengerLaneMemory) -> PassengerNotify {
        guard memory.notifiedIntervalID != nil else { return .none }
        memory.notifiedIntervalID = nil
        return .cancel
    }

    private static func earliest(_ intervals: [PassengerInterval]) -> PassengerInterval? {
        intervals.min { lhs, rhs in
            if lhs.startsAt != rhs.startsAt { return lhs.startsAt < rhs.startsAt }
            if lhs.endsAt != rhs.endsAt { return lhs.endsAt < rhs.endsAt }
            return lhs.id < rhs.id
        }
    }
}
