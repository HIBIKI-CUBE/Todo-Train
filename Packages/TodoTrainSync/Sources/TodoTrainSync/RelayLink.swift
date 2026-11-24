import Foundation

public enum RelaySocketResult: Equatable, Sendable {
    case cancelled
    case unauthorized
    case rateLimited
    case dropped(healthy: Bool)
}

public enum HintWatch: Equatable, Sendable {
    case elapsed
    case cancelled
    case unauthorized
}

/// One socket, then a widening gap. `6c5bf0e` stopped automatic reconnect: a two-second
/// loop, together with a Directory lookup on every request, used up the Durable Object
/// request budget. Callers keep a single task, close the old socket before opening
/// another, and stop after `maximumAttempts` failures or `maximumElapsedSeconds`.
public enum RelayReconnect: Sendable {
    public static let minimumSeconds = 1.0
    public static let maximumSeconds = 60.0
    public static let maximumAttempts = 8
    public static let maximumElapsedSeconds = 60.0

    /// `attempt` is the 1-based failure count. `unit` is in `0..<1` and supplies the jitter.
    /// Equal jitter keeps the lower half, so the gap still grows. Never under 1s, never over 60s.
    public static func delaySeconds(attempt: Int, unit: Double) -> Double {
        let ceiling = ceilingSeconds(attempt: attempt)
        let u = min(max(unit, 0), nextDownFromOne)
        let half = ceiling / 2
        return min(maximumSeconds, max(minimumSeconds, half + u * half))
    }

    /// False once this streak has failed enough times, or has been failing for a minute.
    public static func shouldRetry(attempt: Int, elapsedSeconds: Double) -> Bool {
        attempt > 0 && attempt < maximumAttempts && elapsedSeconds < maximumElapsedSeconds
    }

    public static func transportStatus(_ error: Error) -> Int? {
        guard let sync = error as? SyncError, case .transport(let status, _) = sync else { return nil }
        return status
    }

    private static let nextDownFromOne = 0.999_999_999

    private static func ceilingSeconds(attempt: Int) -> Double {
        var value = minimumSeconds
        let steps = min(max(attempt, 1) - 1, 16)
        for _ in 0..<steps {
            value = min(maximumSeconds, value * 2)
        }
        return value
    }
}

/// What the menu bar and the ride card show. A fresh snap stays quiet even if the
/// socket is down, because hint polling is still delivering it.
public enum RelayRadioPhase: Equatable, Sendable {
    case quiet
    case reconnecting
    case outOfContact
    case recovered
}

public struct RelayRadioReading: Equatable, Sendable {
    public var phase: RelayRadioPhase
    public var blinks: Bool
    public var dimmed: Bool
    public var lastReceivedClock: String?

    public init(
        phase: RelayRadioPhase,
        blinks: Bool = false,
        dimmed: Bool = false,
        lastReceivedClock: String? = nil
    ) {
        self.phase = phase
        self.blinks = blinks
        self.dimmed = dimmed
        self.lastReceivedClock = lastReceivedClock
    }

    public static let quiet = RelayRadioReading(phase: .quiet)
}

public enum RelayRadio: Sendable {
    public static let utc = TimeZone(secondsFromGMT: 0) ?? TimeZone.current

    /// Hint interval is 5 seconds. One missed poll must not light the lamp.
    public static let freshSeconds = 15
    /// Amber blinks for the first 10 seconds of a stale snap, then stays lit.
    public static let blinkSeconds = 10
    /// Red when the snap has been missing this long, or the retry streak has.
    public static let outOfContactSeconds = 60
    public static let recoveredSeconds = 2

    public struct Input: Equatable, Sendable {
        public var now: Int
        public var snapConfirmedAt: Int?
        public var retryingSince: Int?
        public var exhausted: Bool
        public var acknowledged: Bool
        public var prior: RelayRadioPhase
        public var recoveredUntil: Int?
        public var timeZone: TimeZone

        public init(
            now: Int,
            snapConfirmedAt: Int? = nil,
            retryingSince: Int? = nil,
            exhausted: Bool = false,
            acknowledged: Bool = false,
            prior: RelayRadioPhase = .quiet,
            recoveredUntil: Int? = nil,
            timeZone: TimeZone = RelayRadio.utc
        ) {
            self.now = now
            self.snapConfirmedAt = snapConfirmedAt
            self.retryingSince = retryingSince
            self.exhausted = exhausted
            self.acknowledged = acknowledged
            self.prior = prior
            self.recoveredUntil = recoveredUntil
            self.timeZone = timeZone
        }
    }

    public struct Output: Equatable, Sendable {
        public var reading: RelayRadioReading
        public var recoveredUntil: Int?
        public var clearAcknowledged: Bool

        public init(reading: RelayRadioReading, recoveredUntil: Int?, clearAcknowledged: Bool) {
            self.reading = reading
            self.recoveredUntil = recoveredUntil
            self.clearAcknowledged = clearAcknowledged
        }
    }

    public static func judge(_ input: Input) -> Output {
        let clock = input.snapConfirmedAt.map { self.clock(unix: $0, timeZone: input.timeZone) }
        if !isStale(now: input.now, snapConfirmedAt: input.snapConfirmedAt, retryingSince: input.retryingSince) {
            return recoveredOrQuiet(input, clock: clock)
        }
        let silence = silenceSeconds(now: input.now, snapConfirmedAt: input.snapConfirmedAt, retryingSince: input.retryingSince)
        let retryAge = input.retryingSince.map { input.now - $0 } ?? 0
        let hard = input.exhausted || silence >= outOfContactSeconds || retryAge >= outOfContactSeconds
        if hard {
            return Output(
                reading: RelayRadioReading(
                    phase: .outOfContact,
                    blinks: false,
                    dimmed: input.acknowledged,
                    lastReceivedClock: clock
                ),
                recoveredUntil: nil,
                clearAcknowledged: false
            )
        }
        let blinks = !input.acknowledged && silence < freshSeconds + blinkSeconds
        return Output(
            reading: RelayRadioReading(
                phase: .reconnecting,
                blinks: blinks,
                dimmed: input.acknowledged,
                lastReceivedClock: clock
            ),
            recoveredUntil: nil,
            clearAcknowledged: false
        )
    }

    public static func isStale(now: Int, snapConfirmedAt: Int?, retryingSince: Int?) -> Bool {
        if let snapConfirmedAt {
            return now - snapConfirmedAt >= freshSeconds
        }
        if let retryingSince {
            return now - retryingSince >= freshSeconds
        }
        return false
    }

    public static func clock(unix: Int, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = Date(timeIntervalSince1970: TimeInterval(unix))
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }

    /// One notice per ride, and only while that ride is still out of contact.
    public static func shouldPostNotice(
        phase: RelayRadioPhase,
        riding: Bool,
        session: UUID?,
        postedFor: UUID?
    ) -> Bool {
        guard phase == .outOfContact, riding, let session else { return false }
        return postedFor != session
    }

    public static func riding(_ phase: WirePhase) -> Bool {
        switch phase {
        case .running, .paused, .overtime: true
        case .idle, .unknown: false
        }
    }

    private static func silenceSeconds(now: Int, snapConfirmedAt: Int?, retryingSince: Int?) -> Int {
        if let snapConfirmedAt { return max(0, now - snapConfirmedAt) }
        if let retryingSince { return max(0, now - retryingSince) }
        return freshSeconds
    }

    private static func recoveredOrQuiet(_ input: Input, clock: String?) -> Output {
        if input.prior == .recovered {
            if let until = input.recoveredUntil, input.now < until {
                return Output(
                    reading: RelayRadioReading(phase: .recovered, lastReceivedClock: clock),
                    recoveredUntil: until,
                    clearAcknowledged: false
                )
            }
            return Output(
                reading: RelayRadioReading(phase: .quiet, lastReceivedClock: clock),
                recoveredUntil: nil,
                clearAcknowledged: true
            )
        }
        if input.prior == .outOfContact {
            let until = input.now + recoveredSeconds
            return Output(
                reading: RelayRadioReading(phase: .recovered, lastReceivedClock: clock),
                recoveredUntil: until,
                clearAcknowledged: false
            )
        }
        return Output(
            reading: RelayRadioReading(phase: .quiet, lastReceivedClock: clock),
            recoveredUntil: nil,
            clearAcknowledged: true
        )
    }
}
