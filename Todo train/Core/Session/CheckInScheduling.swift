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
    /// Stages 3...6. Stage 1 stays `progress`.
    case overrun
    /// Arrival gap.
    case gap

    var cabin: CabinKind {
        switch self {
        case .progress: .progress
        case .away: .away
        case .idle: .idle
        case .overrun: .overrun
        case .gap: .gap
        }
    }

    /// Stage 1 is `progress`. Later ride stages are `overrun`.
    static func recorded(for stage: NudgeStage) -> CheckInKind {
        stage.number >= 3 ? .overrun : .progress
    }
}

enum CheckInAnswerKind: String, Codable, Sendable, Equatable {
    case stillOnIt
    case paused
    case alreadyDone
    case willExtend
    /// Boarded the reserved ticket from the arrival gap.
    case board
}

struct CheckInAnswerRecord: Equatable, Sendable {
    var kind: CheckInKind
    var answer: CheckInAnswerKind
    var answeredAt: Date
    /// Stable nudge id. Absent on answers recorded before the nudge stamp.
    var nudgeID: String?
    /// Set for `willExtend` once the minutes are known.
    var addSeconds: Int?
    /// `iphone` or `mac`.
    var answeredOn: String?
    /// Ride stage or gap name. Absent on answers recorded before the stage stamp.
    var answeredStage: String?

    init(
        kind: CheckInKind,
        answer: CheckInAnswerKind,
        answeredAt: Date,
        nudgeID: String? = nil,
        addSeconds: Int? = nil,
        answeredOn: String? = nil,
        answeredStage: String? = nil
    ) {
        self.kind = kind
        self.answer = answer
        self.answeredAt = answeredAt
        self.nudgeID = nudgeID
        self.addSeconds = addSeconds
        self.answeredOn = answeredOn
        self.answeredStage = answeredStage
    }
}

extension CheckInAnswerRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case kind, answer, answeredAt, nudgeID, addSeconds, answeredOn, answeredStage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(CheckInKind.self, forKey: .kind)
        answer = try container.decode(CheckInAnswerKind.self, forKey: .answer)
        answeredAt = try container.decode(Date.self, forKey: .answeredAt)
        nudgeID = try container.decodeIfPresent(String.self, forKey: .nudgeID)
        addSeconds = try container.decodeIfPresent(Int.self, forKey: .addSeconds)
        answeredOn = try container.decodeIfPresent(String.self, forKey: .answeredOn)
        answeredStage = try container.decodeIfPresent(String.self, forKey: .answeredStage)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(answer, forKey: .answer)
        try container.encode(answeredAt, forKey: .answeredAt)
        try container.encodeIfPresent(nudgeID, forKey: .nudgeID)
        try container.encodeIfPresent(addSeconds, forKey: .addSeconds)
        try container.encodeIfPresent(answeredOn, forKey: .answeredOn)
        try container.encodeIfPresent(answeredStage, forKey: .answeredStage)
    }
}

enum CheckInCopy {
    static func fallback(title: String) -> String {
        CabinCopy.question(title: title)
    }

    static let away = CabinCopy.prompt
}

/// How to deliver the away interrupt. Not a self-report question.
nonisolated enum AwayInterruptChannel: Equatable, Sendable {
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
