//
//  SessionManager+Inventory.swift
//  Todo train
//
//  Inventory-only issue for App Intents. Does not board.
//  Hub Quick Add keeps its own insert (tags and position).
//

import Foundation
import SwiftData

/// Where an inventory issue writes. Never opens a second container beside one
/// the process already has, and never builds a sibling `ModelContext`.
@MainActor
enum InventoryIssueTarget {
    case manager(SessionManager)
    case context(ModelContext)

    static func resolve(
        sessionManager: SessionManager?,
        modelContainer: ModelContainer?,
        makeContainer: () throws -> ModelContainer
    ) throws -> InventoryIssueTarget {
        if let sessionManager {
            return .manager(sessionManager)
        }
        let container: ModelContainer
        if let modelContainer {
            container = modelContainer
        } else {
            container = try makeContainer()
        }
        return .context(container.mainContext)
    }
}

enum InventoryTicketIssue {
    /// Insert an open ticket at the end of `context`. Does not board or touch cabin state.
    @MainActor
    @discardableResult
    static func issue(
        title: String,
        minutes: Int?,
        into context: ModelContext,
        settings: AppSettings
    ) throws -> (ticket: Ticket, minutes: Int) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SessionError.emptyTicketTitle
        }

        let sessions = (try? context.fetch(FetchDescriptor<WorkSession>())) ?? []
        let resolved = TicketIssuer.resolveMinutes(
            requested: minutes,
            lastIssued: settings.lastIssuedEstimateMinutes
        )
        let ticket = try TicketIssuer.issue(title: trimmed, minutes: resolved, into: context)
        settings.lastIssuedEstimateMinutes = resolved
        ArrivalForecastStore.shared.prefetch(ticket: ticket, sessions: sessions, priority: .user)
        return (ticket, resolved)
    }
}

extension SessionManager {
    /// Issue an open ticket into the manager's `modelContext`.
    @discardableResult
    func issueInventoryTicket(title: String, minutes: Int? = nil) throws -> (ticket: Ticket, minutes: Int) {
        let issued = try InventoryTicketIssue.issue(
            title: title,
            minutes: minutes,
            into: modelContext,
            settings: settings
        )
        noteCabinActivity()
        return issued
    }
}
