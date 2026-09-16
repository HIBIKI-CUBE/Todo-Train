//
//  AppStoreSnapshot.swift
//  Todo train
//
//  未バージョン store が V2 に載らないときの退避。関係は UUID で結び直す。
//

import Foundation
import SwiftData

struct AppStoreSnapshot: Sendable {
    var tags: [TagRow]
    var tickets: [TicketRow]
    var lineages: [LineageRow]
    var serviceDays: [ServiceDayRow]
    var sessions: [SessionRow]
    var extensions: [ExtensionRow]
    var pauses: [PauseRow]

    struct TagRow: Sendable {
        var id: UUID
        var name: String
        var colorHex: String
        var sortOrder: Int
        var createdAt: Date
    }

    struct TicketRow: Sendable {
        var id: UUID
        var title: String
        var estimatedSeconds: Int
        var sortOrder: Int
        var createdAt: Date
        var dueDate: Date?
        var closedAt: Date?
        var closureKindRaw: String?
        var tagIDs: [UUID]
    }

    struct LineageRow: Sendable {
        var id: UUID
        var kindRaw: String
        var createdAt: Date
        var fromSessionID: UUID?
        var aiGenerated: Bool
        var parentID: UUID?
        var childID: UUID?
    }

    struct ServiceDayRow: Sendable {
        var id: UUID
        var startedAt: Date
        var endedAt: Date?
        var calendarDayKey: String
        var pendingCabinKindRaw: String?
        var cabinIdleFiredCount: Int
        var lastCabinActivityAt: Date?
    }

    struct SessionRow: Sendable {
        var id: UUID
        var startedAt: Date
        var endedAt: Date?
        var segmentStartedAt: Date?
        var pausedAt: Date?
        var accumulatedActiveSeconds: TimeInterval
        var estimatedSecondsAtStart: Int
        var budgetSecondsAtStart: Int
        var outcomeRaw: String?
        var overtimeResolutionRaw: String?
        var checkInOffsetSeconds: [Double]
        var checkInFiredCount: Int
        var pendingCheckInKindRaw: String?
        var checkInPromptLine: String?
        var checkInAnswersJSON: String
        var awayDueAt: Date?
        var boardedDeviceID: String?
        var timetableHeld: Bool
        var ticketID: UUID?
    }

    struct ExtensionRow: Sendable {
        var id: UUID
        var addedSeconds: Int
        var reason: String?
        var createdAt: Date
        var sessionID: UUID?
    }

    struct PauseRow: Sendable {
        var id: UUID
        var startedAt: Date
        var endedAt: Date?
        var sessionID: UUID?
    }

    static func capture(from context: ModelContext) throws -> AppStoreSnapshot {
        let tags = try context.fetch(FetchDescriptor<Tag>()).map { tag in
            TagRow(
                id: tag.id,
                name: tag.name,
                colorHex: tag.colorHex,
                sortOrder: tag.sortOrder,
                createdAt: tag.createdAt
            )
        }
        let tickets = try context.fetch(FetchDescriptor<Ticket>()).map { ticket in
            TicketRow(
                id: ticket.id,
                title: ticket.title,
                estimatedSeconds: ticket.estimatedSeconds,
                sortOrder: ticket.sortOrder,
                createdAt: ticket.createdAt,
                dueDate: ticket.dueDate,
                closedAt: ticket.closedAt,
                closureKindRaw: ticket.closureKindRaw,
                tagIDs: ticket.tags.map(\.id)
            )
        }
        let lineages = try context.fetch(FetchDescriptor<TaskLineage>()).map { lineage in
            LineageRow(
                id: lineage.id,
                kindRaw: lineage.kindRaw,
                createdAt: lineage.createdAt,
                fromSessionID: lineage.fromSessionID,
                aiGenerated: lineage.aiGenerated,
                parentID: lineage.parent?.id,
                childID: lineage.child?.id
            )
        }
        let serviceDays = try context.fetch(FetchDescriptor<ServiceDay>()).map { day in
            ServiceDayRow(
                id: day.id,
                startedAt: day.startedAt,
                endedAt: day.endedAt,
                calendarDayKey: day.calendarDayKey,
                pendingCabinKindRaw: day.pendingCabinKindRaw,
                cabinIdleFiredCount: day.cabinIdleFiredCount,
                lastCabinActivityAt: day.lastCabinActivityAt
            )
        }
        let sessions = try context.fetch(FetchDescriptor<WorkSession>()).map { session in
            SessionRow(
                id: session.id,
                startedAt: session.startedAt,
                endedAt: session.endedAt,
                segmentStartedAt: session.segmentStartedAt,
                pausedAt: session.pausedAt,
                accumulatedActiveSeconds: session.accumulatedActiveSeconds,
                estimatedSecondsAtStart: session.estimatedSecondsAtStart,
                budgetSecondsAtStart: session.budgetSecondsAtStart,
                outcomeRaw: session.outcomeRaw,
                overtimeResolutionRaw: session.overtimeResolutionRaw,
                checkInOffsetSeconds: session.checkInOffsetSeconds,
                checkInFiredCount: session.checkInFiredCount,
                pendingCheckInKindRaw: session.pendingCheckInKindRaw,
                checkInPromptLine: session.checkInPromptLine,
                checkInAnswersJSON: session.checkInAnswersJSON,
                awayDueAt: session.awayDueAt,
                boardedDeviceID: session.boardedDeviceID,
                timetableHeld: session.timetableHeld,
                ticketID: session.ticket?.id
            )
        }
        let extensions = try context.fetch(FetchDescriptor<SessionExtension>()).map { item in
            ExtensionRow(
                id: item.id,
                addedSeconds: item.addedSeconds,
                reason: item.reason,
                createdAt: item.createdAt,
                sessionID: item.session?.id
            )
        }
        let pauses = try context.fetch(FetchDescriptor<SessionPause>()).map { pause in
            PauseRow(
                id: pause.id,
                startedAt: pause.startedAt,
                endedAt: pause.endedAt,
                sessionID: pause.session?.id
            )
        }
        return AppStoreSnapshot(
            tags: tags,
            tickets: tickets,
            lineages: lineages,
            serviceDays: serviceDays,
            sessions: sessions,
            extensions: extensions,
            pauses: pauses
        )
    }

    func restore(into context: ModelContext) {
        var tagsByID: [UUID: Tag] = [:]
        for row in tags {
            let tag = Tag(
                id: row.id,
                name: row.name,
                colorHex: row.colorHex,
                sortOrder: row.sortOrder,
                createdAt: row.createdAt
            )
            context.insert(tag)
            tagsByID[row.id] = tag
        }

        var ticketsByID: [UUID: Ticket] = [:]
        for row in tickets {
            let ticket = Ticket(
                id: row.id,
                title: row.title,
                estimatedSeconds: row.estimatedSeconds,
                sortOrder: row.sortOrder,
                createdAt: row.createdAt
            )
            ticket.dueDate = row.dueDate
            ticket.closedAt = row.closedAt
            ticket.closureKindRaw = row.closureKindRaw
            ticket.tags = row.tagIDs.compactMap { tagsByID[$0] }
            context.insert(ticket)
            ticketsByID[row.id] = ticket
        }

        for row in lineages {
            let lineage = TaskLineage(
                id: row.id,
                kind: LineageKind(rawValue: row.kindRaw) ?? .manual,
                parent: row.parentID.flatMap { ticketsByID[$0] },
                child: row.childID.flatMap { ticketsByID[$0] },
                createdAt: row.createdAt,
                fromSessionID: row.fromSessionID,
                aiGenerated: row.aiGenerated
            )
            context.insert(lineage)
        }

        for row in serviceDays {
            let day = ServiceDay(
                id: row.id,
                startedAt: row.startedAt,
                calendarDayKey: row.calendarDayKey
            )
            day.endedAt = row.endedAt
            day.pendingCabinKindRaw = row.pendingCabinKindRaw
            day.cabinIdleFiredCount = row.cabinIdleFiredCount
            day.lastCabinActivityAt = row.lastCabinActivityAt
            context.insert(day)
        }

        var sessionsByID: [UUID: WorkSession] = [:]
        for row in sessions {
            let session = WorkSession(
                id: row.id,
                startedAt: row.startedAt,
                estimatedSecondsAtStart: row.estimatedSecondsAtStart,
                ticket: row.ticketID.flatMap { ticketsByID[$0] },
                boardedDeviceID: row.boardedDeviceID
            )
            session.endedAt = row.endedAt
            session.segmentStartedAt = row.segmentStartedAt
            session.pausedAt = row.pausedAt
            session.accumulatedActiveSeconds = row.accumulatedActiveSeconds
            session.budgetSecondsAtStart = row.budgetSecondsAtStart
            session.outcomeRaw = row.outcomeRaw
            session.overtimeResolutionRaw = row.overtimeResolutionRaw
            session.checkInOffsetSeconds = row.checkInOffsetSeconds
            session.checkInFiredCount = row.checkInFiredCount
            session.pendingCheckInKindRaw = row.pendingCheckInKindRaw
            session.checkInPromptLine = row.checkInPromptLine
            session.checkInAnswersJSON = row.checkInAnswersJSON
            session.awayDueAt = row.awayDueAt
            session.timetableHeld = row.timetableHeld
            context.insert(session)
            sessionsByID[row.id] = session
        }

        for row in extensions {
            let item = SessionExtension(
                id: row.id,
                addedSeconds: row.addedSeconds,
                reason: row.reason,
                createdAt: row.createdAt,
                session: row.sessionID.flatMap { sessionsByID[$0] }
            )
            context.insert(item)
        }

        for row in pauses {
            let pause = SessionPause(
                id: row.id,
                startedAt: row.startedAt,
                endedAt: row.endedAt,
                session: row.sessionID.flatMap { sessionsByID[$0] }
            )
            context.insert(pause)
        }
    }
}
