//
//  WorkSession.swift
//  Todo train
//

import Foundation
import SwiftData

@Model
final class WorkSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?
    /// Start of the current active segment while running.
    var segmentStartedAt: Date?
    var pausedAt: Date?
    /// Accumulated active seconds from completed (non-paused) segments.
    var accumulatedActiveSeconds: TimeInterval
    var estimatedSecondsAtStart: Int
    /// Budget including extensions.
    var budgetSecondsAtStart: Int
    /// Raw value of `SessionOutcome`
    var outcomeRaw: String?
    /// Raw value of `OvertimeResolution` when closed from overtime UI.
    var overtimeResolutionRaw: String?

    /// Elapsed-active offsets (seconds) for progress 車内放送.
    var checkInOffsetSeconds: [Double] = []
    /// How many progress broadcasts have been consumed (answered or skipped for overtime).
    var checkInFiredCount: Int = 0
    /// Raw value of `CheckInKind` while a broadcast is waiting for an answer.
    var pendingCheckInKindRaw: String?
    /// One-line prompt prepared at board (heuristic, then on-device if available).
    var checkInPromptLine: String?
    /// JSON array of `CheckInAnswerRecord`.
    var checkInAnswersJSON: String = "[]"
    /// Wall-clock due for the current away watch. Cleared on foreground or answer.
    var awayDueAt: Date?

    var ticket: Ticket?

    @Relationship(deleteRule: .cascade, inverse: \SessionExtension.session)
    var extensions: [SessionExtension]

    var outcome: SessionOutcome? {
        get { outcomeRaw.flatMap(SessionOutcome.init(rawValue:)) }
        set { outcomeRaw = newValue?.rawValue }
    }

    var overtimeResolution: OvertimeResolution? {
        get { overtimeResolutionRaw.flatMap(OvertimeResolution.init(rawValue:)) }
        set { overtimeResolutionRaw = newValue?.rawValue }
    }

    var isOpen: Bool { endedAt == nil }
    var isPaused: Bool { pausedAt != nil && endedAt == nil }

    init(
        id: UUID = UUID(),
        startedAt: Date,
        estimatedSecondsAtStart: Int,
        ticket: Ticket? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = nil
        self.segmentStartedAt = startedAt
        self.pausedAt = nil
        self.accumulatedActiveSeconds = 0
        self.estimatedSecondsAtStart = estimatedSecondsAtStart
        self.budgetSecondsAtStart = estimatedSecondsAtStart
        self.outcomeRaw = nil
        self.overtimeResolutionRaw = nil
        self.checkInOffsetSeconds = []
        self.checkInFiredCount = 0
        self.pendingCheckInKindRaw = nil
        self.checkInPromptLine = nil
        self.checkInAnswersJSON = "[]"
        self.awayDueAt = nil
        self.ticket = ticket
        self.extensions = []
    }

    var pendingCheckIn: CheckInKind? {
        get { pendingCheckInKindRaw.flatMap(CheckInKind.init(rawValue:)) }
        set { pendingCheckInKindRaw = newValue?.rawValue }
    }

    var checkInOffsets: [TimeInterval] {
        get { checkInOffsetSeconds }
        set { checkInOffsetSeconds = newValue }
    }

    var checkInAnswers: [CheckInAnswerRecord] {
        get { Self.decodeAnswers(checkInAnswersJSON) }
        set { checkInAnswersJSON = Self.encodeAnswers(newValue) }
    }

    private static func decodeAnswers(_ json: String) -> [CheckInAnswerRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = json.data(using: .utf8),
              let values = try? decoder.decode([CheckInAnswerRecord].self, from: data) else {
            return []
        }
        return values
    }

    private static func encodeAnswers(_ values: [CheckInAnswerRecord]) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(values),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    func elapsedSeconds(at now: Date) -> TimeInterval {
        if let pausedAt {
            return accumulatedActiveSeconds
        }
        guard let segmentStartedAt else {
            return accumulatedActiveSeconds
        }
        return accumulatedActiveSeconds + now.timeIntervalSince(segmentStartedAt)
    }

    func remainingSeconds(at now: Date) -> TimeInterval {
        TimeInterval(budgetSecondsAtStart) - elapsedSeconds(at: now)
    }
}
