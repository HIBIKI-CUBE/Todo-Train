//
//  CheckInScheduling.swift
//  Todo train
//
//  Pure scheduling for 車内放送. No UI, no SessionManager.
//  Offsets are elapsed-active seconds from board, not wall-clock dates,
//  so pause delays the broadcast instead of piling them up on resume.
//

import Foundation
import TodoTrainSync

enum CheckInKind: String, Codable, Sendable, Equatable {
    case progress
    case away
    case idle

    var cabin: CabinKind {
        switch self {
        case .progress: .progress
        case .away: .away
        case .idle: .idle
        }
    }
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

    static let away = CabinCopy.prompt
}

/// How to deliver the away interrupt. Not a self-report question.
enum AwayInterruptChannel: Equatable, Sendable {
    /// Session LA `AlertConfiguration` (end bell OFF, Activities on).
    case liveActivityAlert
    /// Time Sensitive local notification — only when there is no Session LA.
    case localNotification
    /// Cabin off, or AlarmKit already owns the lock-screen / Island surface.
    case none
}

enum CheckInScheduling: Sendable {
    static let shortTripMaxSeconds = CabinBroadcastScheduling.shortTripMaxSeconds
    static let singleCheckInMaxSeconds = CabinBroadcastScheduling.singleCheckInMaxSeconds
    static let firstBand = CabinBroadcastScheduling.firstBand
    static let secondBand = CabinBroadcastScheduling.secondBand
    static let awayDelayRange: ClosedRange<TimeInterval> = 45...90
    static let overtimeGuardSeconds = CabinBroadcastScheduling.overtimeGuardSeconds

    static func progressCount(estimatedSeconds: Int) -> Int {
        CabinBroadcastScheduling.progressCount(estimatedSeconds: estimatedSeconds)
    }

    static func offsets(estimatedSeconds: Int, seed: UUID) -> [TimeInterval] {
        CabinBroadcastScheduling.offsets(estimatedSeconds: estimatedSeconds, seed: seed)
    }

    static func awayInterruptChannel(
        cabinEnabled: Bool,
        alarmKitOwnsLiveActivity: Bool,
        sessionLiveActivityEnabled: Bool
    ) -> AwayInterruptChannel {
        guard cabinEnabled else { return .none }
        if alarmKitOwnsLiveActivity { return .none }
        if sessionLiveActivityEnabled { return .liveActivityAlert }
        return .localNotification
    }

    static func awayDelay(seed: UUID, salt: UInt64 = 99) -> TimeInterval {
        let t = CabinBroadcastScheduling.unit(seed: seed, salt: salt)
        return awayDelayRange.lowerBound
            + (awayDelayRange.upperBound - awayDelayRange.lowerBound) * t
    }

    static func dueProgressOffset(
        offsets: [TimeInterval],
        firedCount: Int,
        elapsedSeconds: TimeInterval,
        remainingSeconds: TimeInterval,
        hasPending: Bool
    ) -> TimeInterval? {
        CabinBroadcastScheduling.dueProgressOffset(
            offsets: offsets,
            firedCount: firedCount,
            elapsedSeconds: elapsedSeconds,
            remainingSeconds: remainingSeconds,
            hasPending: hasPending
        )
    }

    static func wallFireAt(
        offset: TimeInterval,
        elapsedSeconds: TimeInterval,
        now: Date
    ) -> Date? {
        CabinBroadcastScheduling.wallFireAt(offset: offset, elapsedSeconds: elapsedSeconds, now: now)
    }

    static func unit(seed: UUID, salt: UInt64) -> Double {
        CabinBroadcastScheduling.unit(seed: seed, salt: salt)
    }
}
