//
//  ArrivalForecastStore.swift
//  Todo train
//
//  Memory cache for on-device refine. Open tickets warm in the background;
//  lifting a ticket jumps the queue. Reuse while title, tags, estimate, and
//  hour band match. Stored minutes are a delta from the median at inference.
//

import Foundation
import Observation
import SwiftData

enum ArrivalForecastPriority: Equatable, Sendable {
    /// Issued or presented — run next after the current inference.
    case user
    /// Hub / backlog — fill the rest of the deck.
    case warm
}

@Observable
@MainActor
final class ArrivalForecastStore {
    static let shared = ArrivalForecastStore()

    var engine: any ArrivalForecasting = ArrivalForecastEngineFactory.make()

    private var cache: [UUID: Entry] = [:]
    private var jobs: [Job] = []
    private var running: Job?
    private var isRunning = false

    struct Entry: Equatable, Sendable {
        var fingerprint: ArrivalForecastFingerprint
        var medianAtRun: Int
        var minutes: Int?
    }

    enum Lookup: Equatable, Sendable {
        case miss
        case hit(Int?)
    }

    private final class Job {
        let ticketID: UUID
        var fingerprint: ArrivalForecastFingerprint
        var context: ArrivalForecastContext
        var priority: ArrivalForecastPriority
        var waiters: [CheckedContinuation<Int?, Never>]

        init(
            ticketID: UUID,
            fingerprint: ArrivalForecastFingerprint,
            context: ArrivalForecastContext,
            priority: ArrivalForecastPriority,
            waiters: [CheckedContinuation<Int?, Never>]
        ) {
            self.ticketID = ticketID
            self.fingerprint = fingerprint
            self.context = context
            self.priority = priority
            self.waiters = waiters
        }
    }

    func lookup(
        ticketID: UUID,
        fingerprint: ArrivalForecastFingerprint,
        currentMedian: Int
    ) -> Lookup {
        guard let entry = cache[ticketID], entry.fingerprint == fingerprint else {
            return .miss
        }
        return .hit(
            ArrivalForecast.appliedMinutes(
                resolved: entry.minutes,
                medianAtRun: entry.medianAtRun,
                currentMedian: currentMedian
            )
        )
    }

    func lookup(
        ticket: Ticket,
        sessions: [WorkSession],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Lookup {
        guard let context = BoardingForecast.forecastContext(
            ticket: ticket,
            sessions: sessions,
            now: now,
            calendar: calendar
        ) else {
            return .miss
        }
        return lookup(
            ticketID: ticket.id,
            fingerprint: context.fingerprint,
            currentMedian: context.medianMinutes
        )
    }

    private func isCached(ticketID: UUID, fingerprint: ArrivalForecastFingerprint) -> Bool {
        cache[ticketID]?.fingerprint == fingerprint
    }

    func prefetch(
        ticket: Ticket,
        sessions: [WorkSession],
        now: Date = .now,
        calendar: Calendar = .current,
        priority: ArrivalForecastPriority = .warm
    ) {
        Task { _ = await refresh(ticket: ticket, sessions: sessions, now: now, calendar: calendar, priority: priority) }
    }

    func prefetchIssued(_ ticket: Ticket, in modelContext: ModelContext) {
        let sessions = (try? modelContext.fetch(FetchDescriptor<WorkSession>())) ?? []
        prefetch(ticket: ticket, sessions: sessions, priority: .user)
    }

    func warm(
        tickets: [Ticket],
        sessions: [WorkSession],
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        var queued = false
        for ticket in tickets where ticket.isOpen {
            guard let context = BoardingForecast.forecastContext(
                ticket: ticket,
                sessions: sessions,
                now: now,
                calendar: calendar
            ) else { continue }
            guard !isCached(ticketID: ticket.id, fingerprint: context.fingerprint) else { continue }
            if !queued {
                engine.prepareForInference()
                queued = true
            }
            prefetch(ticket: ticket, sessions: sessions, now: now, calendar: calendar, priority: .warm)
        }
    }

    @discardableResult
    func refresh(
        ticket: Ticket,
        sessions: [WorkSession],
        now: Date = .now,
        calendar: Calendar = .current,
        priority: ArrivalForecastPriority = .user
    ) async -> Int? {
        let ticketID = ticket.id
        guard let context = BoardingForecast.forecastContext(
            ticket: ticket,
            sessions: sessions,
            now: now,
            calendar: calendar
        ) else {
            cache.removeValue(forKey: ticketID)
            return nil
        }
        let fingerprint = context.fingerprint
        if case .hit(let minutes) = lookup(
            ticketID: ticketID,
            fingerprint: fingerprint,
            currentMedian: context.medianMinutes
        ) {
            return minutes
        }

        return await withCheckedContinuation { continuation in
            if let running, running.ticketID == ticketID, running.fingerprint == fingerprint {
                running.waiters.append(continuation)
                return
            }
            if let existing = jobs.first(where: { $0.ticketID == ticketID }) {
                existing.waiters.append(continuation)
                if existing.fingerprint != fingerprint {
                    existing.fingerprint = fingerprint
                    existing.context = context
                }
                if priority == .user {
                    existing.priority = .user
                }
            } else {
                engine.prepareForInference()
                jobs.append(
                    Job(
                        ticketID: ticketID,
                        fingerprint: fingerprint,
                        context: context,
                        priority: priority,
                        waiters: [continuation]
                    )
                )
            }
            pump()
        }
    }

    private func pump() {
        guard !isRunning else { return }
        guard let job = takeNext() else { return }
        isRunning = true
        running = job
        Task { @MainActor in
            let minutes = await self.engine.refine(job.context)
            self.cache[job.ticketID] = Entry(
                fingerprint: job.fingerprint,
                medianAtRun: job.context.medianMinutes,
                minutes: minutes
            )
            for waiter in job.waiters {
                waiter.resume(returning: minutes)
            }
            self.running = nil
            self.isRunning = false
            self.pump()
        }
    }

    private func takeNext() -> Job? {
        if let index = jobs.firstIndex(where: { $0.priority == .user }) {
            return jobs.remove(at: index)
        }
        guard !jobs.isEmpty else { return nil }
        return jobs.removeFirst()
    }
}
