//
//  AppSchemaV6+Frozen.swift
//  Todo train
//
//  V6 の乗車グラフ。ライブ模型は V7 で見積もり直しの記録を足すので、ここは足す前の形で止める。
//

import Foundation
import SwiftData

extension AppSchemaV6 {
    @Model
    final class Ticket {
        var id: UUID = UUID()
        var title: String = ""
        var estimatedSeconds: Int = 0
        var sortOrder: Int = 0
        var createdAt: Date = Date.now
        var dueDate: Date?
        var closedAt: Date?
        var closureKindRaw: String?
        var reservedAt: Date?
        var reservedFromRideId: UUID?
        var reservedViaRaw: String?
        var tags: [Tag] = []

        @Relationship(deleteRule: .cascade, inverse: \WorkSession.ticket)
        var sessions: [WorkSession] = []

        @Relationship(deleteRule: .nullify, inverse: \TaskLineage.parent)
        var childLineages: [TaskLineage] = []

        @Relationship(deleteRule: .nullify, inverse: \TaskLineage.child)
        var parentLineages: [TaskLineage] = []

        init(
            id: UUID = UUID(),
            title: String,
            estimatedSeconds: Int,
            sortOrder: Int = 0,
            createdAt: Date = .now
        ) {
            self.id = id
            self.title = title
            self.estimatedSeconds = min(max(estimatedSeconds, 0), 3600)
            self.sortOrder = sortOrder
            self.createdAt = createdAt
        }
    }

    @Model
    final class WorkSession {
        var id: UUID = UUID()
        var startedAt: Date = Date.now
        var endedAt: Date?
        var segmentStartedAt: Date?
        var pausedAt: Date?
        var accumulatedActiveSeconds: TimeInterval = 0
        var estimatedSecondsAtStart: Int = 0
        var budgetSecondsAtStart: Int = 0
        var outcomeRaw: String?
        var overtimeResolutionRaw: String?
        var arrivalActionRaw: String?
        var arrivalStampedAt: Date?
        var startedFromRaw: String = RideStartOrigin.other.rawValue
        var checkInOffsetSeconds: [Double] = []
        var checkInFiredCount: Int = 0
        var pendingCheckInKindRaw: String?
        var checkInPromptLine: String?
        var checkInAnswersJSON: String = "[]"
        var awayDueAt: Date?
        var boardedDeviceID: String?
        var timetableHeld: Bool = false
        var nudgeFiredStagesRaw: [String] = []
        var nudgePendingStageRaw: String?
        var nudgeAnsweredAt: Date?
        var nudgeAnsweredOnRaw: String?
        var checkInFraction: Double?
        var nudgeEventsJSON: String = "[]"
        var ticket: Ticket?

        @Relationship(deleteRule: .cascade, inverse: \SessionExtension.session)
        var extensions: [SessionExtension] = []

        @Relationship(deleteRule: .cascade, inverse: \SessionPause.session)
        var pauses: [SessionPause] = []

        init(
            id: UUID = UUID(),
            startedAt: Date,
            estimatedSecondsAtStart: Int,
            ticket: Ticket? = nil,
            boardedDeviceID: String? = nil
        ) {
            self.id = id
            self.startedAt = startedAt
            self.segmentStartedAt = startedAt
            self.estimatedSecondsAtStart = estimatedSecondsAtStart
            self.budgetSecondsAtStart = estimatedSecondsAtStart
            self.boardedDeviceID = boardedDeviceID
            self.ticket = ticket
        }
    }

    @Model
    final class SessionExtension {
        var id: UUID = UUID()
        var addedSeconds: Int = 0
        var reason: String?
        var createdAt: Date = Date.now
        var workingSeconds: Double?
        var session: WorkSession?

        init(
            id: UUID = UUID(),
            addedSeconds: Int,
            reason: String? = nil,
            createdAt: Date = .now,
            workingSeconds: Double? = nil,
            session: WorkSession? = nil
        ) {
            self.id = id
            self.addedSeconds = max(0, addedSeconds)
            self.reason = reason
            self.createdAt = createdAt
            self.workingSeconds = workingSeconds
            self.session = session
        }
    }

    @Model
    final class SessionPause {
        var id: UUID = UUID()
        var startedAt: Date = Date.now
        var endedAt: Date?
        var heldByRaw: String?
        var pausedOnRaw: String?
        var heldByInferred: Bool = false
        var macSampledSeconds: Double = 0
        var macActiveSeconds: Double = 0
        var promptedAt: Date?
        var promptAnswerRaw: String?
        var session: WorkSession?

        init(
            id: UUID = UUID(),
            startedAt: Date = .now,
            endedAt: Date? = nil,
            session: WorkSession? = nil
        ) {
            self.id = id
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.session = session
        }
    }

    @Model
    final class Tag {
        var id: UUID = UUID()
        var name: String = ""
        var colorHex: String = "#888888"
        var sortOrder: Int = 0
        var createdAt: Date = Date.now

        @Relationship(inverse: \Ticket.tags)
        var tickets: [Ticket] = []

        init(
            id: UUID = UUID(),
            name: String,
            colorHex: String = "#888888",
            sortOrder: Int = 0,
            createdAt: Date = .now
        ) {
            self.id = id
            self.name = name
            self.colorHex = colorHex
            self.sortOrder = sortOrder
            self.createdAt = createdAt
        }
    }

    @Model
    final class TaskLineage {
        var id: UUID = UUID()
        var kindRaw: String = "manual"
        var createdAt: Date = Date.now
        var fromSessionID: UUID?
        var aiGenerated: Bool = false
        var parent: Ticket?
        var child: Ticket?

        init(
            id: UUID = UUID(),
            kindRaw: String,
            parent: Ticket?,
            child: Ticket?,
            createdAt: Date = .now,
            fromSessionID: UUID? = nil,
            aiGenerated: Bool = false
        ) {
            self.id = id
            self.kindRaw = kindRaw
            self.createdAt = createdAt
            self.fromSessionID = fromSessionID
            self.aiGenerated = aiGenerated
            self.parent = parent
            self.child = child
        }
    }
}
