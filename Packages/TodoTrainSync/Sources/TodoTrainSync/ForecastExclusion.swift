import Foundation

/// One pause's stored reason and measured input. The strings are not rewritten here.
public struct PauseInputReading: Sendable, Equatable {
    public var heldByRaw: String?
    public var macActiveSeconds: Double

    public init(heldByRaw: String?, macActiveSeconds: Double) {
        self.heldByRaw = heldByRaw
        self.macActiveSeconds = macActiveSeconds
    }
}

/// Which arrived rides stay out of 予測の到着. The quarter is not stored.
public enum ForecastExclusion {
    /// Five minutes of input while `heldBy` is `user`.
    public static let minimumSeconds: TimeInterval = 5 * 60

    /// Sum of stored `macActiveSeconds` on pauses whose stored `heldBy` is `user`.
    /// `timetable` stays out after `timetableHeld` clears. Other reasons stay out.
    public static func pauseInputSeconds(_ readings: [PauseInputReading]) -> TimeInterval {
        readings.reduce(0) { total, reading in
            guard reading.heldByRaw == PauseHeldBy.user.rawValue else { return total }
            return total + reading.macActiveSeconds
        }
    }

    /// At least five minutes, and at least a quarter of the active ride.
    public static func excludes(pauseInputSeconds: TimeInterval, activeSeconds: TimeInterval) -> Bool {
        guard pauseInputSeconds.isFinite, activeSeconds.isFinite else { return false }
        guard pauseInputSeconds >= minimumSeconds else { return false }
        return pauseInputSeconds * 4 >= activeSeconds
    }
}
