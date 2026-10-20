import Foundation

/// Pure local-notification timing for check-in related posts.
public enum CheckInNotificationSchedule: Sendable {
    public static let awayDelayRange: ClosedRange<TimeInterval> = 45...90

    public static func awayDelay(seed: UUID, salt: UInt64 = 99) -> TimeInterval {
        let t = CabinBroadcastScheduling.unit(seed: seed, salt: salt)
        return awayDelayRange.lowerBound
            + (awayDelayRange.upperBound - awayDelayRange.lowerBound) * t
    }

    public static func awayFireAt(now: Date, seed: UUID, salt: UInt64 = 99) -> Date {
        now.addingTimeInterval(awayDelay(seed: seed, salt: salt))
    }

    public static func idleFireAt(
        firedCount: Int,
        elapsedSinceActivity: TimeInterval,
        seed: UUID,
        now: Date
    ) -> Date? {
        CabinIdleScheduling.wallFireAt(
            firedCount: firedCount,
            elapsedSinceActivity: elapsedSinceActivity,
            seed: seed,
            now: now
        )
    }

    public static func progressFireAt(
        offset: TimeInterval,
        elapsedSeconds: TimeInterval,
        now: Date
    ) -> Date? {
        CabinBroadcastScheduling.wallFireAt(
            offset: offset,
            elapsedSeconds: elapsedSeconds,
            now: now
        )
    }
}
