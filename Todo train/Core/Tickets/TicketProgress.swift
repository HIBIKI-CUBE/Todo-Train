//
//  TicketProgress.swift
//  Todo train
//

import Foundation

enum TicketProgress {
    /// Total active seconds across all sessions (Date-based for open rides).
    static func totalActiveSeconds(for ticket: Ticket, at now: Date = .now) -> TimeInterval {
        ticket.sessions.reduce(0) { partial, session in
            partial + session.elapsedSeconds(at: now)
        }
    }

    static func hasStarted(_ ticket: Ticket) -> Bool {
        !ticket.sessions.isEmpty
    }

    /// Ratio of actual / estimate. Nil when not started or estimate is 0.
    static func ratio(for ticket: Ticket, at now: Date = .now) -> Double? {
        guard hasStarted(ticket), ticket.estimatedSeconds > 0 else { return nil }
        return totalActiveSeconds(for: ticket, at: now) / Double(ticket.estimatedSeconds)
    }

    static func caption(for ticket: Ticket, at now: Date = .now) -> String? {
        guard hasStarted(ticket) else { return nil }
        let actualMinutes = Int((totalActiveSeconds(for: ticket, at: now) / 60).rounded())
        let estimateMinutes = ticket.estimatedSeconds / 60
        return "実績 \(actualMinutes)分 / 見積 \(estimateMinutes)分"
    }
}
