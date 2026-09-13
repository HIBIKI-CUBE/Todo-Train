import Foundation

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

/// iPhone-owned idle 車内放送. Mac does not schedule; it only watches `pendingCabin`.
public enum CabinIdleScheduling: Sendable {
    public static let maxCount = 2
    public static let firstBand: ClosedRange<TimeInterval> = (12 * 60)...(20 * 60)
    public static let secondBand: ClosedRange<TimeInterval> = (25 * 60)...(40 * 60)

    public static func delay(firedCount: Int, seed: UUID) -> TimeInterval? {
        guard firedCount >= 0, firedCount < maxCount else { return nil }
        let band = firedCount == 0 ? firstBand : secondBand
        let t = CabinBroadcastScheduling.unit(seed: seed, salt: UInt64(firedCount) &+ 10)
        return band.lowerBound + (band.upperBound - band.lowerBound) * t
    }

    public static func isDue(
        firedCount: Int,
        elapsedSinceActivity: TimeInterval,
        hasPending: Bool,
        seed: UUID
    ) -> Bool {
        guard !hasPending else { return false }
        guard let delay = delay(firedCount: firedCount, seed: seed) else { return false }
        return elapsedSinceActivity >= delay
    }

    public static func wallFireAt(
        firedCount: Int,
        elapsedSinceActivity: TimeInterval,
        seed: UUID,
        now: Date
    ) -> Date? {
        guard let delay = delay(firedCount: firedCount, seed: seed) else { return nil }
        let remaining = delay - elapsedSinceActivity
        guard remaining > 0 else { return nil }
        return now.addingTimeInterval(remaining)
    }
}
