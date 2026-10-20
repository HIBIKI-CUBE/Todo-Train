import Foundation

/// In-ride progress check timing shared by iPhone and Mac.
public enum CheckInTiming: Sendable {
    /// Stage 1 exists only when the estimate is strictly above this.
    public static let minimumEstimateSeconds: TimeInterval = 10 * 60
    public static let fractionBand: ClosedRange<Double> = 0.40...0.50
    public static let minimumRunningSeconds: TimeInterval = 5 * 60
    /// Salt for `CabinBroadcastScheduling.unit(seed:salt:)`. Same ride id keeps one offset.
    public static let rideSalt: UInt64 = 1

    /// Working-second band before the five-minute floor. Nil when the estimate is 10 minutes or less.
    public static func fractionBandRange(estimateSeconds: Int) -> ClosedRange<TimeInterval>? {
        let estimate = TimeInterval(estimateSeconds)
        guard estimate > minimumEstimateSeconds else { return nil }
        let band = fractionBand
        return (estimate * band.lowerBound)...(estimate * band.upperBound)
    }

    /// Stable offset for this ride from the departure budget. Nil when the estimate is 10 minutes or less.
    public static func offset(rideID: UUID, estimateSeconds: Int) -> TimeInterval? {
        guard fractionBandRange(estimateSeconds: estimateSeconds) != nil else { return nil }
        let band = fractionBand
        let unit = CabinBroadcastScheduling.unit(seed: rideID, salt: rideSalt)
        let fraction = band.lowerBound + (band.upperBound - band.lowerBound) * unit
        let scaled = TimeInterval(estimateSeconds) * fraction
        return max(scaled, minimumRunningSeconds)
    }

    public static func progressOffsets(rideID: UUID, budgetSecondsAtStart: Int) -> [TimeInterval] {
        guard let single = offset(rideID: rideID, estimateSeconds: budgetSecondsAtStart) else { return [] }
        return [single]
    }

    public static func dueProgressOffset(
        offsets: [TimeInterval],
        firedCount: Int,
        elapsedSeconds: TimeInterval,
        remainingSeconds: TimeInterval,
        hasPending: Bool,
        overtimeGuardSeconds: TimeInterval = CabinBroadcastScheduling.overtimeGuardSeconds
    ) -> TimeInterval? {
        guard !hasPending else { return nil }
        guard remainingSeconds > overtimeGuardSeconds else { return nil }
        guard firedCount >= 0, firedCount < offsets.count else { return nil }
        let offset = offsets[firedCount]
        guard elapsedSeconds >= offset else { return nil }
        return offset
    }
}
