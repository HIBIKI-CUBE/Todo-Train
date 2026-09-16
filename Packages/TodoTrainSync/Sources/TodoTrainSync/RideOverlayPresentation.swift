import Foundation

public typealias RideOverlayTimerPhase = TimerUrgency

public struct RideOccupancyInstrument: Equatable, Sendable {
    public var prefix: String
    public var clock: String
    public var minutes: Int?
    public var title: String
    public var spokenLine: String
    /// Next occupancy on the ride progress bar (elapsed / estimated). Nil when past the ride.
    public var markPosition: Double?
    /// Current occupancy band on the same progress bar.
    public var spanStart: Double?
    public var spanEnd: Double?

    public init(
        prefix: String,
        clock: String,
        minutes: Int?,
        title: String,
        spokenLine: String,
        markPosition: Double?,
        spanStart: Double?,
        spanEnd: Double?
    ) {
        self.prefix = prefix
        self.clock = clock
        self.minutes = minutes
        self.title = title
        self.spokenLine = spokenLine
        self.markPosition = markPosition
        self.spanStart = spanStart
        self.spanEnd = spanEnd
    }
}

/// Mac ride PiP from the same snap input as the menu bar. Hidden when unpaired or idle.
public struct RideOverlayPresentation: Equatable, Sendable {
    public var isVisible: Bool
    public var title: String
    public var remainingLabel: String
    public var progress: Double
    public var timerPhase: RideOverlayTimerPhase
    public var isOvertime: Bool
    public var isPaused: Bool
    public var canPause: Bool
    public var canResume: Bool
    public var isSending: Bool
    public var failureLine: String?
    public var statusLine: String?
    public var peekTitle: String
    /// Progress 車内放送 on the PiP. Nil when idle.
    public var cabinPrompt: String?
    /// Next or current ダイヤ. Title and minutes from unix timestamps so tests stay timezone-stable.
    /// Occupancy as digits on the ride remaining fill. Spoken line stays on `nextBlockLine`.
    public var occupancy: RideOccupancyInstrument?
    public var nextBlockLine: String?

    public static let peekTitleLimit = 6

    public static let hidden = RideOverlayPresentation(
        isVisible: false,
        title: "",
        remainingLabel: "",
        progress: 0,
        timerPhase: .cruise,
        isOvertime: false,
        isPaused: false,
        canPause: false,
        canResume: false,
        isSending: false,
        failureLine: nil,
        statusLine: nil,
        peekTitle: "",
        cabinPrompt: nil,
        occupancy: nil,
        nextBlockLine: nil
    )

    public static func make(_ input: MenuBarInput) -> RideOverlayPresentation {
        let bar = MenuBarPresentation.make(input)
        guard input.pairing == .paired, let snap = input.snap else {
            return .hidden
        }
        switch snap.phase {
        case .idle, .unknown:
            return .hidden
        case .paused, .running, .overtime:
            break
        }

        let remaining = snap.remainingSeconds(at: input.now)
        let progress = Self.progress(
            remaining: remaining,
            estimated: snap.estimatedSeconds,
            overtime: bar.isOvertime
        )
        let title: String
        if let snapTitle = snap.title, !snapTitle.isEmpty {
            title = snapTitle
        } else if snap.phase == .paused {
            title = "停車中"
        } else {
            title = ""
        }
        let remainingLabel = remaining.map(MenuBarPresentation.formatRemaining) ?? ""
        let statusLine: String?
        if input.connection == .disconnected {
            statusLine = SyncCopy.relayDisconnected
        } else if bar.isSending {
            statusLine = SyncCopy.sentToIPhone
        } else {
            statusLine = nil
        }

        let cabin = CabinInterruptWatch.evaluate(
            snap: input.snap,
            now: input.now,
            localEnabled: input.cabinEnabledLocal,
            optimisticFiredCount: input.optimisticFiredCount,
            optimisticIdleConsumed: input.optimisticIdleConsumed
        )
        let cabinPrompt = (cabin.showsPip && !bar.isSending) ? cabin.prompt : nil

        return RideOverlayPresentation(
            isVisible: true,
            title: title,
            remainingLabel: remainingLabel,
            progress: progress,
            timerPhase: timerPhase(
                remaining: remaining,
                estimated: snap.estimatedSeconds,
                overtime: bar.isOvertime
            ),
            isOvertime: bar.isOvertime,
            isPaused: snap.phase == .paused,
            canPause: bar.canPause,
            canResume: bar.canResume,
            isSending: bar.isSending,
            failureLine: bar.failureLine,
            statusLine: statusLine,
            peekTitle: truncatedPeekTitle(title),
            cabinPrompt: cabinPrompt,
            occupancy: occupancyInstrument(snap: snap, now: input.now),
            nextBlockLine: nextBlockLine(snap: snap, now: input.now)
        )
    }

    public static func nextBlockLine(
        snap: SnapPlaintext,
        now: Int,
        timeZone: TimeZone = .current
    ) -> String? {
        guard let title = snap.nextBlockTitle, !title.isEmpty else { return nil }
        if let startsAt = snap.nextBlockStartsAt, startsAt > now {
            return occupancyLine(
                prefix: "次",
                title: title,
                unix: startsAt,
                now: now,
                timeZone: timeZone
            )
        }
        if let endsAt = snap.nextBlockEndsAt {
            return occupancyLine(
                prefix: "いま",
                title: title,
                unix: endsAt,
                now: now,
                timeZone: timeZone
            )
        }
        return "いま \(title)"
    }

    public static func occupancyInstrument(
        snap: SnapPlaintext,
        now: Int,
        timeZone: TimeZone = .current
    ) -> RideOccupancyInstrument? {
        guard let title = snap.nextBlockTitle, !title.isEmpty else { return nil }
        let remaining = snap.remainingSeconds(at: now)
        let estimated = snap.estimatedSeconds
        if let startsAt = snap.nextBlockStartsAt, startsAt > now {
            return RideOccupancyInstrument(
                prefix: "次",
                clock: clockTime(unix: startsAt, timeZone: timeZone),
                minutes: remainingMinutes(until: startsAt, now: now),
                title: title,
                spokenLine: occupancyLine(
                    prefix: "次",
                    title: title,
                    unix: startsAt,
                    now: now,
                    timeZone: timeZone
                ),
                markPosition: occupancyOnProgress(
                    secondsFromNow: startsAt - now,
                    remaining: remaining,
                    estimated: estimated
                ),
                spanStart: nil,
                spanEnd: nil
            )
        }
        let edge = snap.nextBlockEndsAt ?? now
        let occupancyRemaining = max(0, edge - now)
        let spanStart = occupancyOnProgress(
            secondsFromNow: 0,
            remaining: remaining,
            estimated: estimated
        )
        let mappedEnd = occupancyOnProgress(
            secondsFromNow: occupancyRemaining,
            remaining: remaining,
            estimated: estimated
        )
        let spanEnd: Double?
        if let spanStart {
            let end = mappedEnd ?? 1
            spanEnd = end > spanStart ? end : nil
        } else {
            spanEnd = nil
        }
        return RideOccupancyInstrument(
            prefix: "いま",
            clock: clockTime(unix: edge, timeZone: timeZone),
            minutes: remainingMinutes(until: edge, now: now),
            title: title,
            spokenLine: occupancyLine(
                prefix: "いま",
                title: title,
                unix: edge,
                now: now,
                timeZone: timeZone
            ),
            markPosition: nil,
            spanStart: spanEnd == nil ? nil : spanStart,
            spanEnd: spanEnd
        )
    }

    /// Map a wall-clock offset onto remaining ride progress (elapsed / estimated).
    public static func occupancyOnProgress(
        secondsFromNow: Int,
        remaining: Int?,
        estimated: Int?
    ) -> Double? {
        guard let estimated, estimated > 0, let remaining else { return nil }
        let elapsed = max(0, Double(estimated - remaining))
        let position = (elapsed + Double(secondsFromNow)) / Double(estimated)
        guard position >= 0, position <= 1 else { return nil }
        return position
    }

    /// Same window as iOS `TimetableFit.markMinutes`. Floor minutes, 1...60.
    public static func markMinutes(until unix: Int, now: Int) -> Int? {
        let interval = unix - now
        guard interval >= 30 else { return nil }
        let minutes = interval / 60
        guard (1...60).contains(minutes) else { return nil }
        return minutes
    }

    /// Floor minutes until a occupancy edge. 30s floor. No 60 cap.
    public static func remainingMinutes(until unix: Int, now: Int) -> Int? {
        let interval = unix - now
        guard interval >= 30 else { return nil }
        let minutes = interval / 60
        guard minutes >= 1 else { return nil }
        return minutes
    }

    public static func clockTime(unix: Int, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = Date(timeIntervalSince1970: TimeInterval(unix))
        return String(
            format: "%02d:%02d",
            calendar.component(.hour, from: date),
            calendar.component(.minute, from: date)
        )
    }

    private static func occupancyLine(
        prefix: String,
        title: String,
        unix: Int,
        now: Int,
        timeZone: TimeZone
    ) -> String {
        let clock = clockTime(unix: unix, timeZone: timeZone)
        if let minutes = remainingMinutes(until: unix, now: now) {
            return "\(prefix) \(clock) \(minutes)分 \(title)"
        }
        return "\(prefix) \(clock) \(title)"
    }

    public static func progress(
        remaining: Int?,
        estimated: Int?,
        overtime: Bool
    ) -> Double {
        if overtime { return 1 }
        guard let remaining, let estimated, estimated > 0 else { return 0 }
        let elapsed = Double(estimated - remaining)
        return min(1, max(0, elapsed / Double(estimated)))
    }

    /// Same cutoffs as iOS `FocusTimerPhase.phase(remaining:budgetSeconds:)`.
    public static func timerPhase(
        remaining: Int?,
        estimated: Int?,
        overtime: Bool
    ) -> RideOverlayTimerPhase {
        if overtime { return .overtime }
        guard let remaining else { return .cruise }
        return TimerUrgency.phase(
            remaining: TimeInterval(remaining),
            budgetSeconds: TimeInterval(estimated ?? 1)
        )
    }

    public static func truncatedPeekTitle(_ title: String) -> String {
        if title.isEmpty { return "乗務" }
        if title.count <= peekTitleLimit { return title }
        return String(title.prefix(peekTitleLimit))
    }
}
