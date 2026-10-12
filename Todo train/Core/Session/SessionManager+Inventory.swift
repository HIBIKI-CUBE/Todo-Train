//
//  SessionManager+Inventory.swift
//  Todo train
//
//  Inventory-only issue (Hub / App Intent). Does not board.
//

import Foundation
import SwiftData

extension SessionManager {
    /// Issue an open ticket into the manager's `modelContext` (Hub / Intent shared write path).
    @discardableResult
    func issueInventoryTicket(title: String, minutes: Int? = nil) throws -> (ticket: Ticket, minutes: Int) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SessionError.emptyTicketTitle
        }

        let sessions = (try? modelContext.fetch(FetchDescriptor<WorkSession>())) ?? []
        let resolved = TicketIssuer.resolveMinutes(
            requested: minutes,
            sessions: sessions,
            lastIssued: settings.lastIssuedEstimateMinutes
        )
        let ticket = try TicketIssuer.issue(title: trimmed, minutes: resolved, into: modelContext)
        settings.lastIssuedEstimateMinutes = resolved
        ArrivalForecastStore.shared.prefetch(ticket: ticket, sessions: sessions, priority: .user)
        noteCabinActivity()
        return (ticket, resolved)
    }
}
