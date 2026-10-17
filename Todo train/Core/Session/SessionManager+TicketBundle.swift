//
//  SessionManager+TicketBundle.swift
//  Todo train
//

import Foundation
import SwiftData

extension SessionManager {
    func fetchServiceDays() -> [ServiceDay] {
        let descriptor = FetchDescriptor<ServiceDay>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchEndedWorkSessions() -> [WorkSession] {
        let descriptor = FetchDescriptor<WorkSession>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func ticketStampBundles() -> [TicketStampBundleAssembly.DayBundle] {
        let sessions = fetchEndedWorkSessions().map(TicketStampBundleAssembly.sessionInput)
        let days = fetchServiceDays().map(TicketStampBundleAssembly.serviceDayInput)
        return TicketStampBundleAssembly.buildDayBundles(sessions: sessions, serviceDays: days)
    }

    func ticketStampBundle(forCalendarDayKey dayKey: String) -> TicketStampBundleAssembly.DayBundle? {
        TicketStampBundleAssembly.bundle(
            forCalendarDayKey: dayKey,
            in: ticketStampBundles()
        )
    }
}
