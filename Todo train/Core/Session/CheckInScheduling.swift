//
//  CheckInScheduling.swift
//  Todo train
//
//  Pure scheduling for 車内放送. No UI, no SessionManager.
//  Offsets are elapsed-active seconds from board, not wall-clock dates,
//  so pause delays the broadcast instead of piling them up on resume.
//

import Foundation

enum CheckInKind: String, Codable, Sendable, Equatable {
    case progress
    case away
}

enum CheckInAnswerKind: String, Codable, Sendable, Equatable {
    case stillOnIt
    case paused
    case alreadyDone
    case willExtend
}

struct CheckInAnswerRecord: Codable, Equatable, Sendable {
    var kind: CheckInKind
    var answer: CheckInAnswerKind
    var answeredAt: Date
}

enum CheckInCopy {
    static func fallback(title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "まだこれ？" }
        return "まだ『\(trimmed)』？"
    }

    static let away = "まだ乗ってる？"
}

enum CheckInScheduling: Sendable {
    /// 10 minutes or less: no progress broadcasts.
    static let shortTripMaxSeconds = 10 * 60
    /// 11–25 minutes: one progress broadcast.
    static let singleCheckInMaxSeconds = 25 * 60

    static let firstBand: ClosedRange<Double> = 0.32...0.48
    static let secondBand: ClosedRange<Double> = 0.62...0.78

    static let awayDelayRange: ClosedRange<TimeInterval> = 45...90
    /// Do not flash a progress panel in the last half-minute before overtime.
    static let overtimeGuardSeconds: TimeInterval = 30

    static func progressCount(estimatedSeconds: Int) -> Int {
        if estimatedSeconds <= shortTripMaxSeconds { return 0 }
        if estimatedSeconds <= singleCheckInMaxSeconds { return 1 }
        return 2
    }

    /// Elapsed-active offsets at which progress broadcasts fire.
    static func offsets(estimatedSeconds: Int, seed: UUID) -> [TimeInterval] {
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

    static func awayDelay(seed: UUID, salt: UInt64 = 99) -> TimeInterval {
        let t = unit(seed: seed, salt: salt)
        return awayDelayRange.lowerBound
            + (awayDelayRange.upperBound - awayDelayRange.lowerBound) * t
    }

    /// Next progress offset that is due. Nil when paused/overtime/pending is handled by the caller.
    static func dueProgressOffset(
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

    /// Wall-clock fire time for a still-future elapsed offset, given current active elapsed.
    static func wallFireAt(
        offset: TimeInterval,
        elapsedSeconds: TimeInterval,
        now: Date
    ) -> Date? {
        let remainingUntil = offset - elapsedSeconds
        guard remainingUntil > 0 else { return nil }
        return now.addingTimeInterval(remainingUntil)
    }

    /// Deterministic 0..<1. Stable across processes (not `Hasher`).
    static func unit(seed: UUID, salt: UInt64) -> Double {
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
