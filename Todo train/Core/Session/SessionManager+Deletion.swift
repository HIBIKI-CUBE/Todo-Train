//
//  SessionManager+Deletion.swift
//  Todo train
//

import Foundation
import Observation
import SwiftData
import TodoTrainSync
#if canImport(UIKit)
import UIKit
#endif

extension SessionManager {
    // MARK: - Physical deletion

    /// Removes a ticket and cascaded sessions from the store.
    /// Open sessions on the ticket are torn down (LA / alarms / activeSession) without archiving.
    func deleteTicket(_ ticket: Ticket, now: Date? = nil) throws {
        let now = now ?? clock.now
        for session in ticket.sessions where session.isOpen {
            tearDownOpenSessionSideEffects(session)
        }
        modelContext.delete(ticket)
        try save()
        reconcile(now: now)
    }

    /// Removes one ended history row. If the parent ticket has no sessions left, deletes the ticket too.
    func deleteEndedSession(_ session: WorkSession, now: Date? = nil) throws {
        let now = now ?? clock.now
        guard TicketDeletion.canDeleteEndedSession(session) else {
            throw SessionError.cannotDeleteOpenSession
        }
        let ticket = session.ticket
        let remainingIDs = ticket?.sessions.map(\.id) ?? []
        let shouldDeleteTicket = ticket != nil
            && TicketDeletion.shouldDeleteOrphanTicket(
                remainingSessionIDs: remainingIDs,
                removing: session.id
            )
        modelContext.delete(session)
        if shouldDeleteTicket, let ticket {
            modelContext.delete(ticket)
        }
        try save()
        reconcile(now: now)
    }

    func restoreDeletedTicket(_ record: DeletionUndo.TicketRecord) throws {
        try DeletionUndo.restoreTicket(record, into: modelContext)
        try save()
        try recoverOnLaunch()
    }

    func restoreDeletedSession(_ record: DeletionUndo.SessionRecord) throws {
        DeletionUndo.restoreSession(record, onto: nil, into: modelContext)
        try save()
        try recoverOnLaunch()
    }

    func restoreDeletedTag(_ record: DeletionUndo.TagRecord) throws {
        DeletionUndo.restoreTag(record, into: modelContext)
        try save()
    }

    func consumePunctualityMoment() {
        guard !punctualityQueue.isEmpty else { return }
        punctualityQueue.removeFirst()
    }

    /// Clears in-memory / external side effects for an open session without writing closure fields.
    func tearDownOpenSessionSideEffects(_ session: WorkSession) {
        if activeSession?.id == session.id {
            activeSession = nil
            phase = .idle
        }
        overtimeNotifier.cancel(sessionID: session.id)
        checkInNotifier.cancel(sessionID: session.id)
        cancelAwayFireTask()
        liveActivityManager.end()
        alarmScheduler.cancel(sessionID: session.id)
        suppressedEndBellSessionIDs.remove(session.id)
    }

    func close(
        session: WorkSession,
        outcome: SessionOutcome,
        closureKind: ClosureKind,
        now: Date
    ) throws {
        session.closeActiveSegment(at: now)
        endOpenPauseRecord(on: session, now: now)
        session.pausedAt = nil
        session.endedAt = now
        session.outcome = outcome

        if let ticket = session.ticket {
            ticket.closedAt = now
            ticket.closureKind = closureKind
        }

        if activeSession?.id == session.id {
            activeSession = nil
            phase = .idle
            noteCabinActivity(now: now, clearPendingIdle: true)
            bumpCompanionSync()
        }
        overtimeNotifier.cancel(sessionID: session.id)
        checkInNotifier.cancel(sessionID: session.id)
        cancelAwayFireTask()
        liveActivityManager.end()
        alarmScheduler.cancel(sessionID: session.id)
        suppressedEndBellSessionIDs.remove(session.id)
        try save()
        reconcile(now: now)
    }
}
