import Foundation

/// Wire `pendingCabin`. Unknown values must not crash; Mac ignores them.
public enum CabinKind: Sendable, Equatable {
    case progress
    case away
    case idle
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .progress: "progress"
        case .away: "away"
        case .idle: "idle"
        case .unknown(let value): value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "progress": self = .progress
        case "away": self = .away
        case "idle": self = .idle
        default: self = .unknown(rawValue)
        }
    }
}

extension CabinKind: Codable {
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self.init(rawValue: value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Where Mac should put a cabin prompt. Notification is reserved for idle / no-ride.
public enum CabinDelivery: Equatable, Sendable {
    case pip
    case notification
    case ignore

    public static func surface(kind: CabinKind?, hasRide: Bool) -> CabinDelivery {
        switch kind {
        case .progress:
            hasRide ? .pip : .notification
        case .idle:
            .notification
        case .away, .unknown, .none:
            .ignore
        }
    }
}

public enum CabinCopy {
    /// Progress interrupt on Mac PiP. Title is already on the card.
    public static let prompt = "まだ乗ってる？"
    public static let still = "まだやってる"
}

/// Shared progress 車内放送 offsets. Same numbers as iOS `CheckInScheduling`.
public enum CabinBroadcastScheduling: Sendable {
    public static let shortTripMaxSeconds = 10 * 60
    public static let singleCheckInMaxSeconds = 25 * 60
    public static let firstBand: ClosedRange<Double> = 0.32...0.48
    public static let secondBand: ClosedRange<Double> = 0.62...0.78
    public static let overtimeGuardSeconds: TimeInterval = 30

    public static func progressCount(estimatedSeconds: Int) -> Int {
        if estimatedSeconds <= shortTripMaxSeconds { return 0 }
        if estimatedSeconds <= singleCheckInMaxSeconds { return 1 }
        return 2
    }

    public static func offsets(estimatedSeconds: Int, seed: UUID) -> [TimeInterval] {
        let count = progressCount(estimatedSeconds: estimatedSeconds)
        guard count > 0, estimatedSeconds > 0 else { return [] }
        let budget = TimeInterval(estimatedSeconds)
        let bands: [ClosedRange<Double>] = count == 1 ? [firstBand] : [firstBand, secondBand]
        return bands.enumerated().map { index, band in
            let t = unit(seed: seed, salt: UInt64(index + 1))
            let fraction = band.lowerBound + (band.upperBound - band.lowerBound) * t
            return budget * fraction
        }
    }

    public static func dueProgressOffset(
        offsets: [TimeInterval],
        firedCount: Int,
        elapsedSeconds: TimeInterval,
        remainingSeconds: TimeInterval,
        hasPending: Bool
    ) -> TimeInterval? {
        guard !hasPending else { return nil }
        guard remainingSeconds > overtimeGuardSeconds else { return nil }
        guard firedCount >= 0, firedCount < offsets.count else { return nil }
        let offset = offsets[firedCount]
        guard elapsedSeconds >= offset else { return nil }
        return offset
    }

    public static func wallFireAt(
        offset: TimeInterval,
        elapsedSeconds: TimeInterval,
        now: Date
    ) -> Date? {
        let remainingUntil = offset - elapsedSeconds
        guard remainingUntil > 0 else { return nil }
        return now.addingTimeInterval(remainingUntil)
    }

    public static func unit(seed: UUID, salt: UInt64) -> Double {
        var hash: UInt64 = salt &* 0x9E3779B97F4A7C15
        for byte in uuidBytes(seed) {
            hash ^= UInt64(byte)
            hash &*= 0x100000001B3
        }
        return Double(hash % 10_000) / 10_000.0
    }

    private static func uuidBytes(_ uuid: UUID) -> [UInt8] {
        let u = uuid.uuid
        return [
            u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7,
            u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15,
        ]
    }
}

public struct CabinInterrupt: Equatable, Sendable {
    public var kind: CabinKind?
    public var delivery: CabinDelivery
    public var prompt: String?
    public var isDue: Bool

    public static let idle = CabinInterrupt(
        kind: nil,
        delivery: .ignore,
        prompt: nil,
        isDue: false
    )

    public init(kind: CabinKind?, delivery: CabinDelivery, prompt: String?, isDue: Bool) {
        self.kind = kind
        self.delivery = delivery
        self.prompt = prompt
        self.isDue = isDue
    }

    public var showsPip: Bool { isDue && delivery == .pip }
}

/// Mac-side watch. Progress uses the same offsets as iPhone. Idle has no scheduler this slice.
public enum CabinInterruptWatch: Sendable {
    public static func evaluate(
        snap: SnapPlaintext?,
        now: Int,
        localEnabled: Bool,
        optimisticFiredCount: Int
    ) -> CabinInterrupt {
        guard let snap, localEnabled, snap.cabinEnabled else { return .idle }
        let hasRide: Bool
        switch snap.phase {
        case .running, .paused, .overtime:
            hasRide = snap.sessionId != nil
        case .idle, .unknown:
            hasRide = false
        }

        if snap.pendingCabin == .idle {
            return CabinInterrupt(
                kind: .idle,
                delivery: CabinDelivery.surface(kind: .idle, hasRide: hasRide),
                prompt: nil,
                isDue: snap.serviceActive
            )
        }

        if snap.pendingCabin == .away {
            return CabinInterrupt(
                kind: .away,
                delivery: .ignore,
                prompt: nil,
                isDue: false
            )
        }

        if optimisticFiredCount > snap.checkInFiredCount {
            return .idle
        }

        let progressDue = isProgressDue(snap: snap, now: now, firedCount: snap.checkInFiredCount)
        guard progressDue else { return .idle }
        return CabinInterrupt(
            kind: .progress,
            delivery: CabinDelivery.surface(kind: .progress, hasRide: hasRide),
            prompt: CabinCopy.prompt,
            isDue: true
        )
    }

    /// Idle scheduler is empty this slice. Never becomes due unless snap already has `pendingCabin=idle`.
    public static func isIdleSchedulerDue(serviceActive: Bool, pendingCabin: CabinKind?) -> Bool {
        serviceActive && pendingCabin == .idle
    }

    private static func isProgressDue(snap: SnapPlaintext, now: Int, firedCount: Int) -> Bool {
        if snap.pendingCabin == .progress { return true }
        guard snap.phase == .running, let sessionId = snap.sessionId else { return false }
        let remaining = TimeInterval(snap.remainingSeconds(at: now) ?? 0)
        let elapsed = TimeInterval(snap.elapsedActiveSeconds(at: now) ?? 0)
        let offsets = CabinBroadcastScheduling.offsets(
            estimatedSeconds: snap.estimatedSeconds ?? 0,
            seed: sessionId
        )
        return CabinBroadcastScheduling.dueProgressOffset(
            offsets: offsets,
            firedCount: firedCount,
            elapsedSeconds: elapsed,
            remainingSeconds: remaining,
            hasPending: false
        ) != nil
    }
}
