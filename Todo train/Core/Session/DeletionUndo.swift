//
//  DeletionUndo.swift
//  Todo train
//
//  Snapshot restore for physical delete. UndoManager is not used: it would
//  mix title edits with deletions. Banner "取り消す" restores this snapshot.
//

import Foundation
import SwiftData

enum DeletionUndo {
    static let bannerDurationSeconds: TimeInterval = 8

    struct TicketRecord: Equatable {
        var id: UUID
        var title: String
        var estimatedSeconds: Int
        var sortOrder: Int
        var createdAt: Date
        var dueDate: Date?
        var closedAt: Date?
        var closureKindRaw: String?
        var tagIDs: [UUID]
        var sessions: [SessionRecord]
        var lineages: [LineageRecord]
    }

    struct SessionRecord: Equatable {
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
        var ticketID: UUID?
        var extensions: [ExtensionRecord]
        var pauses: [PauseRecord]
    }

    struct ExtensionRecord: Equatable {
        var id: UUID
        var addedSeconds: Int
        var reason: String?
        var createdAt: Date
    }

    struct PauseRecord: Equatable {
        var id: UUID
        var startedAt: Date
        var endedAt: Date?
    }

    struct LineageRecord: Equatable {
        var id: UUID
        var kindRaw: String
        var createdAt: Date
        var fromSessionID: UUID?
        var aiGenerated: Bool
        var parentID: UUID?
        var childID: UUID?
    }

    struct TagRecord: Equatable {
        var id: UUID
        var name: String
        var colorHex: String
        var sortOrder: Int
        var createdAt: Date
        var ticketIDs: [UUID]
        var siblingOrders: [UUID: Int]
    }

    static func captureTicket(_ ticket: Ticket) -> TicketRecord {
        let lineages = uniqueLineages(ticket.parentLineages + ticket.childLineages)
        return TicketRecord(
            id: ticket.id,
            title: ticket.title,
            estimatedSeconds: ticket.estimatedSeconds,
            sortOrder: ticket.sortOrder,
            createdAt: ticket.createdAt,
            dueDate: ticket.dueDate,
            closedAt: ticket.closedAt,
            closureKindRaw: ticket.closureKindRaw,
            tagIDs: ticket.tags.map(\.id),
            sessions: ticket.sessions.map(captureSession),
            lineages: lineages
        )
    }

    static func captureSession(_ session: WorkSession) -> SessionRecord {
        SessionRecord(
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
            ticketID: session.ticket?.id,
            extensions: session.extensions.map {
                ExtensionRecord(
                    id: $0.id,
                    addedSeconds: $0.addedSeconds,
                    reason: $0.reason,
                    createdAt: $0.createdAt
                )
            },
            pauses: session.pauses.map {
                PauseRecord(
                    id: $0.id,
                    startedAt: $0.startedAt,
                    endedAt: $0.endedAt
                )
            }
        )
    }

    static func captureTag(_ tag: Tag, allTags: [Tag]) -> TagRecord {
        TagRecord(
            id: tag.id,
            name: tag.name,
            colorHex: tag.colorHex,
            sortOrder: tag.sortOrder,
            createdAt: tag.createdAt,
            ticketIDs: tag.tickets.map(\.id),
            siblingOrders: Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0.sortOrder) })
        )
    }

    static func restoreTicket(_ record: TicketRecord, into context: ModelContext) throws {
        let ticket = fetchTicket(record.id, in: context) ?? {
            let created = Ticket(
                id: record.id,
                title: record.title,
                estimatedSeconds: record.estimatedSeconds,
                sortOrder: record.sortOrder,
                createdAt: record.createdAt
            )
            context.insert(created)
            return created
        }()
        ticket.title = record.title
        ticket.estimatedSeconds = record.estimatedSeconds
        ticket.sortOrder = record.sortOrder
        ticket.createdAt = record.createdAt
        ticket.dueDate = record.dueDate
        ticket.closedAt = record.closedAt
        ticket.closureKindRaw = record.closureKindRaw
        ticket.tags = record.tagIDs.compactMap { fetchTag($0, in: context) }
        for sessionRecord in record.sessions {
            restoreSession(sessionRecord, onto: ticket, into: context)
        }
        for lineage in record.lineages {
            restoreLineage(lineage, into: context)
        }
    }

    static func restoreSession(
        _ record: SessionRecord,
        onto ticket: Ticket?,
        into context: ModelContext
    ) {
        let parent = ticket ?? record.ticketID.flatMap { fetchTicket($0, in: context) }
        let session = fetchSession(record.id, in: context) ?? {
            let created = WorkSession(
                id: record.id,
                startedAt: record.startedAt,
                estimatedSecondsAtStart: record.estimatedSecondsAtStart,
                ticket: parent
            )
            context.insert(created)
            return created
        }()
        session.startedAt = record.startedAt
        session.endedAt = record.endedAt
        session.segmentStartedAt = record.segmentStartedAt
        session.pausedAt = record.pausedAt
        session.accumulatedActiveSeconds = record.accumulatedActiveSeconds
        session.estimatedSecondsAtStart = record.estimatedSecondsAtStart
        session.budgetSecondsAtStart = record.budgetSecondsAtStart
        session.outcomeRaw = record.outcomeRaw
        session.overtimeResolutionRaw = record.overtimeResolutionRaw
        session.checkInOffsetSeconds = record.checkInOffsetSeconds
        session.checkInFiredCount = record.checkInFiredCount
        session.pendingCheckInKindRaw = record.pendingCheckInKindRaw
        session.checkInPromptLine = record.checkInPromptLine
        session.checkInAnswersJSON = record.checkInAnswersJSON
        session.awayDueAt = record.awayDueAt
        session.boardedDeviceID = record.boardedDeviceID
        session.ticket = parent
        for ext in record.extensions {
            let existing = session.extensions.first { $0.id == ext.id } ?? {
                let created = SessionExtension(
                    id: ext.id,
                    addedSeconds: ext.addedSeconds,
                    reason: ext.reason,
                    createdAt: ext.createdAt,
                    session: session
                )
                context.insert(created)
                return created
            }()
            existing.addedSeconds = ext.addedSeconds
            existing.reason = ext.reason
            existing.createdAt = ext.createdAt
            existing.session = session
        }
        for pause in record.pauses {
            let existing = session.pauses.first { $0.id == pause.id } ?? {
                let created = SessionPause(
                    id: pause.id,
                    startedAt: pause.startedAt,
                    endedAt: pause.endedAt,
                    session: session
                )
                context.insert(created)
                return created
            }()
            existing.startedAt = pause.startedAt
            existing.endedAt = pause.endedAt
            existing.session = session
        }
    }

    static func restoreTag(_ record: TagRecord, into context: ModelContext) {
        let tag = fetchTag(record.id, in: context) ?? {
            let created = Tag(
                id: record.id,
                name: record.name,
                colorHex: record.colorHex,
                sortOrder: record.sortOrder,
                createdAt: record.createdAt
            )
            context.insert(created)
            return created
        }()
        tag.name = record.name
        tag.colorHex = record.colorHex
        tag.sortOrder = record.sortOrder
        tag.createdAt = record.createdAt
        let tickets = record.ticketIDs.compactMap { fetchTicket($0, in: context) }
        tag.tickets = tickets
        for ticket in tickets where !ticket.tags.contains(where: { $0.id == tag.id }) {
            ticket.tags.append(tag)
        }
        for (id, order) in record.siblingOrders {
            fetchTag(id, in: context)?.sortOrder = order
        }
    }

    static func bannerMessage(ticketTitle: String) -> String {
        "「\(TicketDeletion.displayTitle(ticketTitle, fallback: "無題の切符"))」を削除しました"
    }

    static func bannerMessage(historyTicketTitle: String, deletedTicketToo: Bool) -> String {
        let name = TicketDeletion.displayTitle(historyTicketTitle, fallback: "不明な切符")
        if deletedTicketToo {
            return "「\(name)」の履歴と切符を削除しました"
        }
        return "「\(name)」の履歴を削除しました"
    }

    static func bannerMessage(tagName: String) -> String {
        "「\(TicketDeletion.displayTitle(tagName, fallback: "無題のタグ"))」を削除しました"
    }

    static func bannerMessageForCanvasRow() -> String {
        "行を削除しました"
    }

    private static func restoreLineage(_ record: LineageRecord, into context: ModelContext) {
        let lineage = fetchLineage(record.id, in: context) ?? {
            let created = TaskLineage(
                id: record.id,
                kind: LineageKind(rawValue: record.kindRaw) ?? .manual,
                parent: record.parentID.flatMap { fetchTicket($0, in: context) },
                child: record.childID.flatMap { fetchTicket($0, in: context) },
                createdAt: record.createdAt,
                fromSessionID: record.fromSessionID,
                aiGenerated: record.aiGenerated
            )
            context.insert(created)
            return created
        }()
        lineage.kindRaw = record.kindRaw
        lineage.createdAt = record.createdAt
        lineage.fromSessionID = record.fromSessionID
        lineage.aiGenerated = record.aiGenerated
        lineage.parent = record.parentID.flatMap { fetchTicket($0, in: context) }
        lineage.child = record.childID.flatMap { fetchTicket($0, in: context) }
    }

    private static func uniqueLineages(_ lineages: [TaskLineage]) -> [LineageRecord] {
        var seen = Set<UUID>()
        var records: [LineageRecord] = []
        for lineage in lineages where seen.insert(lineage.id).inserted {
            records.append(
                LineageRecord(
                    id: lineage.id,
                    kindRaw: lineage.kindRaw,
                    createdAt: lineage.createdAt,
                    fromSessionID: lineage.fromSessionID,
                    aiGenerated: lineage.aiGenerated,
                    parentID: lineage.parent?.id,
                    childID: lineage.child?.id
                )
            )
        }
        return records
    }

    private static func fetchTicket(_ id: UUID, in context: ModelContext) -> Ticket? {
        let target = id
        var descriptor = FetchDescriptor<Ticket>(predicate: #Predicate { $0.id == target })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func fetchTag(_ id: UUID, in context: ModelContext) -> Tag? {
        let target = id
        var descriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.id == target })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func fetchSession(_ id: UUID, in context: ModelContext) -> WorkSession? {
        let target = id
        var descriptor = FetchDescriptor<WorkSession>(predicate: #Predicate { $0.id == target })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func fetchLineage(_ id: UUID, in context: ModelContext) -> TaskLineage? {
        let target = id
        var descriptor = FetchDescriptor<TaskLineage>(predicate: #Predicate { $0.id == target })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
