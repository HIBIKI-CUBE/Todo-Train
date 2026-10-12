import Foundation

/// Thresholds for nudge stages. Grouped so a later export pass can tune them.
public enum NudgeThresholds: Sendable {
    /// Mac is attending when the screen is unlocked and the last input is inside this window.
    public static let presenceWindow: TimeInterval = 2 * 60
    /// Stage 1 exists only when the estimate is strictly above this.
    public static let checkInMinimumEstimate: TimeInterval = 10 * 60
    public static let checkInBand: ClosedRange<Double> = 0.62...0.78
    /// Salt for `CabinBroadcastScheduling.unit(seed:salt:)`. Same ride id keeps one offset.
    public static let checkInSalt: UInt64 = 1
    public static let approachFraction: Double = 0.17
    public static let approachMinimum: TimeInterval = 60
    public static let approachMaximum: TimeInterval = 3 * 60
    public static let handoffFraction: Double = 0.07
    public static let handoffMinimum: TimeInterval = 60
    public static let handoffMaximum: TimeInterval = 2 * 60
    /// Rings from stage 3, including an AlarmKit end bell that occupies stage 3.
    public static let maxRings: Int = 4
    /// Device column. `#100` extends this with `.watch` between iPhone and the repeat.
    public static let deviceOrder: [NudgeSurface] = [.mac, .iphone]
    public static let gap1Delay: TimeInterval = 3 * 60
    public static let gap2Delay: TimeInterval = 6 * 60
}

/// A device that can show or ring a nudge. `.watch` is accepted so `#100` can append it.
public enum NudgeSurface: String, Sendable, Equatable, Codable, CaseIterable {
    case mac
    case iphone
    case watch
    case none
}

/// Ride stages. 1 is the in-ride check, 2 is approach, 3 is the estimate, 4...6 hand off.
public enum NudgeStage: String, Sendable, Equatable, Codable, CaseIterable {
    case checkIn
    case approach
    case estimate
    case handoff1
    case handoff2
    case handoff3

    public var number: Int {
        switch self {
        case .checkIn: 1
        case .approach: 2
        case .estimate: 3
        case .handoff1: 4
        case .handoff2: 5
        case .handoff3: 6
        }
    }

    public static func stage(number: Int) -> NudgeStage? {
        allCases.first { $0.number == number }
    }
}

/// One recorded extension. Pass the full history; stage 1 is judged on the estimate before each entry.
public struct NudgeExtension: Sendable, Equatable {
    public var addedSeconds: Int
    public var createdAt: Date
    /// Active seconds at `createdAt`. Nil derives them from the ride clock.
    /// A pause that ends after this extension is still in the accumulated total, so record the reading here.
    public var workingSeconds: TimeInterval?

    public init(addedSeconds: Int, createdAt: Date, workingSeconds: TimeInterval? = nil) {
        self.addedSeconds = addedSeconds
        self.createdAt = createdAt
        self.workingSeconds = workingSeconds
    }
}

/// Working-second mark for one stage, measured from board and excluding pauses.
public struct NudgeStageMark: Sendable, Equatable {
    public var stage: NudgeStage
    public var offset: TimeInterval

    public init(stage: NudgeStage, offset: TimeInterval) {
        self.stage = stage
        self.offset = offset
    }
}

/// A stage that has not been reached yet.
public struct NudgePlanItem: Sendable, Equatable {
    public var stage: NudgeStage
    public var fireAt: Date
    public var surface: NudgeSurface
    /// The assigned device rings. Display-only stages, skipped turns, and the AlarmKit bell are false.
    public var rings: Bool

    public init(stage: NudgeStage, fireAt: Date, surface: NudgeSurface, rings: Bool) {
        self.stage = stage
        self.fireAt = fireAt
        self.surface = surface
        self.rings = rings
    }
}

public struct NudgeEvaluation: Sendable, Equatable {
    public var workingElapsed: TimeInterval
    public var isFrozen: Bool
    /// Latest stage whose offset is at or before `workingElapsed`.
    public var current: NudgeStage?
    /// Stages still ahead. Passed stages are omitted, so a return from sleep does not replay them.
    public var plan: [NudgePlanItem]

    public init(
        workingElapsed: TimeInterval,
        isFrozen: Bool,
        current: NudgeStage?,
        plan: [NudgePlanItem]
    ) {
        self.workingElapsed = workingElapsed
        self.isFrozen = isFrozen
        self.current = current
        self.plan = plan
    }
}

/// Clock and foreground inputs for one ride. `estimatedSeconds` is the current budget.
public struct NudgeRideInput: Sendable, Equatable {
    public var startedAt: Date
    /// Completed pauses only. The open pause is `pausedAt`.
    public var pausedAccumulated: TimeInterval
    public var pausedAt: Date?
    public var isPaused: Bool
    /// Completed passenger intervals. The open interval is `passengerSince`.
    public var passengerAccumulated: TimeInterval
    public var passengerSince: Date?
    public var isPassenger: Bool
    public var estimatedSeconds: Int
    public var rideID: UUID
    public var extensions: [NudgeExtension]
    public var alarmKitEndBell: Bool
    /// Foreground devices. Order does not decide who rings. `.watch` is ignored until it is in the device column.
    public var foreground: [NudgeSurface]
    /// Unlocked, and the last input is inside `NudgeThresholds.presenceWindow`.
    public var macAttending: Bool
    public var now: Date

    public init(
        startedAt: Date,
        pausedAccumulated: TimeInterval = 0,
        pausedAt: Date? = nil,
        isPaused: Bool = false,
        passengerAccumulated: TimeInterval = 0,
        passengerSince: Date? = nil,
        isPassenger: Bool = false,
        estimatedSeconds: Int,
        rideID: UUID,
        extensions: [NudgeExtension] = [],
        alarmKitEndBell: Bool = false,
        foreground: [NudgeSurface],
        macAttending: Bool = false,
        now: Date
    ) {
        self.startedAt = startedAt
        self.pausedAccumulated = pausedAccumulated
        self.pausedAt = pausedAt
        self.isPaused = isPaused
        self.passengerAccumulated = passengerAccumulated
        self.passengerSince = passengerSince
        self.isPassenger = isPassenger
        self.estimatedSeconds = estimatedSeconds
        self.rideID = rideID
        self.extensions = extensions
        self.alarmKitEndBell = alarmKitEndBell
        self.foreground = foreground
        self.macAttending = macAttending
        self.now = now
    }
}

public enum NudgeGap: String, Sendable, Equatable, Codable, CaseIterable {
    case gap1
    case gap2
}

public struct NudgeGapItem: Sendable, Equatable {
    public var stage: NudgeGap
    public var fireAt: Date
    public var surface: NudgeSurface
    public var rings: Bool

    public init(stage: NudgeGap, fireAt: Date, surface: NudgeSurface, rings: Bool) {
        self.stage = stage
        self.fireAt = fireAt
        self.surface = surface
        self.rings = rings
    }
}

/// Arrival-gap inputs. `stampedAt` is the arrival stamp, including a close without a reservation.
public struct NudgeGapInput: Sendable, Equatable {
    public var stampedAt: Date
    public var arrivalScreenOpen: Bool
    public var foreground: [NudgeSurface]
    public var macAttending: Bool
    public var now: Date

    public init(
        stampedAt: Date,
        arrivalScreenOpen: Bool,
        foreground: [NudgeSurface],
        macAttending: Bool = false,
        now: Date
    ) {
        self.stampedAt = stampedAt
        self.arrivalScreenOpen = arrivalScreenOpen
        self.foreground = foreground
        self.macAttending = macAttending
        self.now = now
    }
}

/// Pure nudge stages for iPhone and Mac. Callers poll; this type does not arm timers.
public enum NudgePlanner: Sendable {
    public static func macIsAttending(screenLocked: Bool, secondsSinceLastInput: TimeInterval) -> Bool {
        !screenLocked && secondsSinceLastInput < NudgeThresholds.presenceWindow
    }

    public static func approachRemaining(estimatedSeconds: Int) -> TimeInterval {
        scaled(
            estimate: TimeInterval(max(0, estimatedSeconds)),
            fraction: NudgeThresholds.approachFraction,
            minimum: NudgeThresholds.approachMinimum,
            maximum: NudgeThresholds.approachMaximum
        )
    }

    public static func handoffInterval(estimatedSeconds: Int) -> TimeInterval {
        scaled(
            estimate: TimeInterval(max(0, estimatedSeconds)),
            fraction: NudgeThresholds.handoffFraction,
            minimum: NudgeThresholds.handoffMinimum,
            maximum: NudgeThresholds.handoffMaximum
        )
    }

    /// Stage 1 band in working seconds. Nil when the estimate is 10 minutes or less.
    public static func checkInBand(estimatedSeconds: Int) -> ClosedRange<TimeInterval>? {
        let estimate = TimeInterval(estimatedSeconds)
        guard estimate > NudgeThresholds.checkInMinimumEstimate else { return nil }
        let band = NudgeThresholds.checkInBand
        return (estimate * band.lowerBound)...(estimate * band.upperBound)
    }

    /// Stable stage 1 offset for this ride. Nil when the estimate is 10 minutes or less.
    public static func checkInOffset(estimatedSeconds: Int, rideID: UUID) -> TimeInterval? {
        guard checkInBand(estimatedSeconds: estimatedSeconds) != nil else { return nil }
        let band = NudgeThresholds.checkInBand
        let unit = CabinBroadcastScheduling.unit(seed: rideID, salt: NudgeThresholds.checkInSalt)
        let fraction = band.lowerBound + (band.upperBound - band.lowerBound) * unit
        return TimeInterval(estimatedSeconds) * fraction
    }

    /// Working-second marks for the current estimate. Stages 2...6 follow that estimate.
    /// Stage 1 is the seeded point in `NudgeThresholds.checkInBand` when the estimate is above 10 minutes.
    /// The same ride id and salt keep that point stable.
    /// An extension before the point then in effect has been reached moves stage 1 once onto the new estimate.
    /// Once active seconds have reached that point, a later extension does not place it again.
    /// A moved point at or before `activeSeconds` is omitted, so it does not fire late.
    public static func marks(
        estimatedSeconds: Int,
        rideID: UUID,
        extensions: [NudgeExtension] = [],
        startedAt: Date? = nil,
        activeSeconds: TimeInterval? = nil,
        pausedAccumulated: TimeInterval = 0,
        pausedAt: Date? = nil,
        isPaused: Bool = false,
        passengerAccumulated: TimeInterval = 0,
        passengerSince: Date? = nil,
        isPassenger: Bool = false
    ) -> [NudgeStageMark] {
        let estimate = TimeInterval(estimatedSeconds)
        guard estimate > 0 else { return [] }
        var marks: [NudgeStageMark] = []
        if let checkIn = placedCheckInOffset(
            estimatedSeconds: estimatedSeconds,
            rideID: rideID,
            extensions: extensions,
            startedAt: startedAt,
            activeSeconds: activeSeconds,
            pausedAccumulated: pausedAccumulated,
            pausedAt: pausedAt,
            isPaused: isPaused,
            passengerAccumulated: passengerAccumulated,
            passengerSince: passengerSince,
            isPassenger: isPassenger
        ) {
            marks.append(NudgeStageMark(stage: .checkIn, offset: checkIn))
        }
        let approach = max(0, estimate - approachRemaining(estimatedSeconds: estimatedSeconds))
        marks.append(NudgeStageMark(stage: .approach, offset: approach))
        let interval = handoffInterval(estimatedSeconds: estimatedSeconds)
        for number in 3...6 {
            guard let stage = NudgeStage.stage(number: number) else { continue }
            let offset = estimate + interval * TimeInterval(number - 3)
            marks.append(NudgeStageMark(stage: stage, offset: offset))
        }
        return marks.sorted { lhs, rhs in
            if lhs.offset == rhs.offset { return lhs.stage.number < rhs.stage.number }
            return lhs.offset < rhs.offset
        }
    }

    public static func evaluate(
        _ input: NudgeRideInput,
        deviceOrder: [NudgeSurface] = NudgeThresholds.deviceOrder
    ) -> NudgeEvaluation {
        let elapsed = workingElapsed(input)
        let frozen = input.isPaused || input.isPassenger || input.pausedAt != nil
        let marks = marks(
            estimatedSeconds: input.estimatedSeconds,
            rideID: input.rideID,
            extensions: input.extensions,
            startedAt: input.startedAt,
            activeSeconds: elapsed,
            pausedAccumulated: input.pausedAccumulated,
            pausedAt: input.pausedAt,
            isPaused: input.isPaused,
            passengerAccumulated: input.passengerAccumulated,
            passengerSince: input.passengerSince,
            isPassenger: input.isPassenger
        )
        let current = marks.last { $0.offset <= elapsed }?.stage
        let foreground = foregroundSet(input.foreground)
        let column = ringColumn(deviceOrder, foreground: foreground, macAttending: input.macAttending)
        let plan = marks.filter { $0.offset > elapsed }.map { mark in
            let (surface, rings) = assignment(
                stage: mark.stage,
                column: column,
                alarmKitEndBell: input.alarmKitEndBell,
                foreground: foreground
            )
            return NudgePlanItem(
                stage: mark.stage,
                fireAt: input.now.addingTimeInterval(mark.offset - elapsed),
                surface: surface,
                rings: rings
            )
        }
        return NudgeEvaluation(
            workingElapsed: elapsed,
            isFrozen: frozen,
            current: current,
            plan: plan
        )
    }

    /// gap1 at +3 minutes on the first device, gap2 at +6 minutes on the other. Two gaps, then nothing.
    public static func gaps(
        _ input: NudgeGapInput,
        deviceOrder: [NudgeSurface] = NudgeThresholds.deviceOrder
    ) -> [NudgeGapItem] {
        guard !input.arrivalScreenOpen else { return [] }
        let elapsed = input.now.timeIntervalSince(input.stampedAt)
        let foreground = foregroundSet(input.foreground)
        let column = ringColumn(deviceOrder, foreground: foreground, macAttending: input.macAttending)
        let slots: [(NudgeGap, TimeInterval, Int)] = [
            (.gap1, NudgeThresholds.gap1Delay, 0),
            (.gap2, NudgeThresholds.gap2Delay, 1),
        ]
        return slots.compactMap { stage, delay, index in
            guard delay > elapsed else { return nil }
            let surface = index < column.count ? column[index] : .none
            let rings = surface != .none && foreground.contains(surface)
            return NudgeGapItem(
                stage: stage,
                fireAt: input.stampedAt.addingTimeInterval(delay),
                surface: surface,
                rings: rings
            )
        }
    }

    /// Completed pauses and passenger intervals stay in the accumulated fields.
    /// An open pause or passenger interval holds the clock at its start.
    public static func workingElapsed(_ input: NudgeRideInput) -> TimeInterval {
        var end = input.now
        if input.isPaused || input.pausedAt != nil {
            end = min(end, input.pausedAt ?? input.now)
        }
        if input.isPassenger {
            end = min(end, input.passengerSince ?? input.now)
        }
        let excluded = input.pausedAccumulated + input.passengerAccumulated
        return max(0, end.timeIntervalSince(input.startedAt) - excluded)
    }

    /// Stage 1 for this ride, or nil when it does not run.
    /// With no extensions the seeded offset stays, including after it has passed, so `current` can name it.
    /// With extensions, a point that had not been reached moves once onto the new estimate.
    /// A moved point at or before the live active second is omitted.
    private static func placedCheckInOffset(
        estimatedSeconds: Int,
        rideID: UUID,
        extensions: [NudgeExtension],
        startedAt: Date?,
        activeSeconds: TimeInterval?,
        pausedAccumulated: TimeInterval,
        pausedAt: Date?,
        isPaused: Bool,
        passengerAccumulated: TimeInterval,
        passengerSince: Date?,
        isPassenger: Bool
    ) -> TimeInterval? {
        let ordered = extensions.sorted { $0.createdAt < $1.createdAt }
        if ordered.isEmpty {
            return checkInOffset(estimatedSeconds: estimatedSeconds, rideID: rideID)
        }

        var estimate = estimatedSeconds - ordered.reduce(0) { $0 + $1.addedSeconds }
        for item in ordered {
            if let offset = checkInOffset(estimatedSeconds: estimate, rideID: rideID),
               let elapsed = sampledActiveSeconds(
                   at: item,
                   startedAt: startedAt,
                   pausedAccumulated: pausedAccumulated,
                   pausedAt: pausedAt,
                   isPaused: isPaused,
                   passengerAccumulated: passengerAccumulated,
                   passengerSince: passengerSince,
                   isPassenger: isPassenger
               ),
               elapsed >= offset
            {
                return nil
            }
            estimate += item.addedSeconds
        }

        guard let placed = checkInOffset(estimatedSeconds: estimatedSeconds, rideID: rideID) else {
            return nil
        }
        if let activeSeconds, placed <= activeSeconds {
            return nil
        }
        return placed
    }

    /// Active seconds at an extension. A recorded reading wins.
    /// Otherwise the ride clock subtracts completed pauses and passenger intervals,
    /// and an open pause or passenger interval freezes the sample only after it has started.
    private static func sampledActiveSeconds(
        at item: NudgeExtension,
        startedAt: Date?,
        pausedAccumulated: TimeInterval,
        pausedAt: Date?,
        isPaused: Bool,
        passengerAccumulated: TimeInterval,
        passengerSince: Date?,
        isPassenger: Bool
    ) -> TimeInterval? {
        if let workingSeconds = item.workingSeconds {
            return workingSeconds
        }
        guard let startedAt else { return nil }
        var end = item.createdAt
        if isPaused || pausedAt != nil, let pausedAt, pausedAt <= item.createdAt {
            end = min(end, pausedAt)
        }
        if isPassenger, let passengerSince, passengerSince <= item.createdAt {
            end = min(end, passengerSince)
        }
        let excluded = pausedAccumulated + passengerAccumulated
        return max(0, end.timeIntervalSince(startedAt) - excluded)
    }

    private static func scaled(
        estimate: TimeInterval,
        fraction: Double,
        minimum: TimeInterval,
        maximum: TimeInterval
    ) -> TimeInterval {
        min(max(estimate * fraction, minimum), maximum)
    }

    private static func foregroundSet(_ devices: [NudgeSurface]) -> Set<NudgeSurface> {
        Set(devices.filter { $0 != .none })
    }

    /// Canonical column, rotated so the first ringer is Mac only when Mac is foreground and attending.
    private static func ringColumn(
        _ order: [NudgeSurface],
        foreground: Set<NudgeSurface>,
        macAttending: Bool
    ) -> [NudgeSurface] {
        var seen = Set<NudgeSurface>()
        let column = order.filter { device in
            device != .none && seen.insert(device).inserted
        }
        let first: NudgeSurface = (foreground.contains(.mac) && macAttending) ? .mac : .iphone
        guard let index = column.firstIndex(of: first) else { return column }
        return Array(column[index...]) + Array(column[..<index])
    }

    /// Stage 3 occupies the bell when AlarmKit is on, and the device column starts at stage 4.
    /// A device that is not foreground keeps its turn and does not ring, so one device rings twice.
    private static func assignment(
        stage: NudgeStage,
        column: [NudgeSurface],
        alarmKitEndBell: Bool,
        foreground: Set<NudgeSurface>
    ) -> (NudgeSurface, Bool) {
        guard stage.number >= 3 else { return (.none, false) }
        if alarmKitEndBell && stage == .estimate { return (.none, false) }
        let slot = stage.number - 3 - (alarmKitEndBell ? 1 : 0)
        guard slot >= 0, slot < NudgeThresholds.maxRings, !column.isEmpty else {
            return (.none, false)
        }
        let surface = column[slot % column.count]
        return (surface, foreground.contains(surface))
    }
}
