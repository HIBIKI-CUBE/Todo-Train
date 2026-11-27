import Foundation

/// Wall-clock seconds for the ride countdown.
///
/// Instants that feed remaining or elapsed are floored when recorded, and again
/// when an older fractional value is read. Digits are the ceiling of
/// `deadline - now`. That is what `Text(timerInterval:countsDown:)` shows:
/// 59.4s remaining stays `1:00` until the remaining time reaches 59.0.
public enum WholeSecond {
    /// Unix second that contains `date`.
    public static func floor(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    /// Drop the fraction. Negative intervals move away from zero.
    public static func floor(_ interval: TimeInterval) -> TimeInterval {
        interval.rounded(.down)
    }

    public static func unix(_ date: Date) -> Int {
        Int(floor(date).timeIntervalSince1970.rounded())
    }

    public static func seconds(_ interval: TimeInterval) -> Int {
        guard interval.isFinite else { return 0 }
        return Int(interval.rounded(.down))
    }

    /// Countdown digits. `0` stays `0`. A positive fraction rounds up.
    /// The same ceiling on a negative remaining matches a count-up of overtime:
    /// 0.4s past the deadline is still `0`, and 1.4s past is `-1`.
    public static func countdownSeconds(_ remaining: TimeInterval) -> Int {
        guard remaining.isFinite else { return 0 }
        return Int(remaining.rounded(.up))
    }

    /// `TimelineView` schedule start. The next fire is the next whole second,
    /// the same grid as `OpeningPanelClockTiming.floor(_:step:)` with step 1.
    public static func scheduleStart(_ date: Date = .now) -> Date {
        floor(date)
    }

    /// Sleep length that wakes on the next whole second. An exact boundary waits one second.
    /// Sub-millisecond delays wait 1ms so a slightly early wake does not spin.
    public static func nanosecondsUntilNextBoundary(after date: Date) -> UInt64 {
        let time = date.timeIntervalSince1970
        let fractional = time - time.rounded(.down)
        let delay = fractional == 0 ? 1.0 : (1.0 - fractional)
        let nanos = (delay * 1_000_000_000).rounded(.up)
        guard nanos.isFinite, nanos > 0 else { return 1_000_000_000 }
        return max(UInt64(nanos), 1_000_000)
    }
}
