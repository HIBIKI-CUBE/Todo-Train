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
        self.ticket = ticket
        self.extensions = []
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
