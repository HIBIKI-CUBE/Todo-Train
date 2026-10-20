//
//  ArrivalForecastStoreTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
final class StubArrivalForecastEngine: ArrivalForecasting {
    var calls = 0
    var prepareCalls = 0
    var result: Int? = 40

    func prepareForInference() {
        prepareCalls += 1
    }

    func refine(_ context: ArrivalForecastContext) async -> Int? {
        calls += 1
        return result
    }
}

@MainActor
final class HoldingForecastEngine: ArrivalForecasting {
    private(set) var order: [String] = []
    private var hold: CheckedContinuation<Void, Never>?
    private var started = 0

    func refine(_ context: ArrivalForecastContext) async -> Int? {
        await withCheckedContinuation { continuation in
            order.append(context.title)
            started += 1
            if started == 1 {
                hold = continuation
            } else {
                continuation.resume()
            }
        }
        return 40
    }

    func waitUntilStarted(_ count: Int) async {
        while started < count {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func release() {
        hold?.resume()
        hold = nil
    }
}

@MainActor
struct ArrivalForecastStoreTests {
    @Test func refresh_reusesCacheAcrossNewArrivals() async throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let ticket = Ticket(title: "レビュー", estimatedSeconds: 30 * 60)
        context.insert(ticket)
        let sessions = [
            arrived(context, ticket: ticket, active: 32 * 60),
            arrived(context, ticket: ticket, active: 34 * 60),
            arrived(context, ticket: ticket, active: 36 * 60),
        ]
        let stub = StubArrivalForecastEngine()
        let store = ArrivalForecastStore()
        store.engine = stub

        let first = await store.refresh(ticket: ticket, sessions: sessions)
        #expect(first == 40)
        #expect(stub.calls == 1)
        #expect(stub.prepareCalls == 1)
        #expect(store.lookup(ticket: ticket, sessions: sessions) == .hit(40))

        let second = await store.refresh(ticket: ticket, sessions: sessions)
        #expect(second == 40)
        #expect(stub.calls == 1)
        #expect(stub.prepareCalls == 1)

        let extra = arrived(context, ticket: ticket, active: 50 * 60)
        let withExtra = sessions + [extra]
        let third = await store.refresh(ticket: ticket, sessions: withExtra)
        #expect(third == 41)
        #expect(stub.calls == 1)
        #expect(store.lookup(ticket: ticket, sessions: withExtra) == .hit(41))
    }

    @Test func refresh_rerunsWhenHourBandChanges() async throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let ticket = Ticket(title: "レビュー", estimatedSeconds: 30 * 60)
        context.insert(ticket)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let afternoon = Date(timeIntervalSince1970: 12 * 3600)
        let evening = Date(timeIntervalSince1970: 18 * 3600)
        let sessions = [
            arrived(context, ticket: ticket, active: 32 * 60, startedAt: afternoon),
            arrived(context, ticket: ticket, active: 34 * 60, startedAt: afternoon),
            arrived(context, ticket: ticket, active: 36 * 60, startedAt: afternoon),
        ]
        let stub = StubArrivalForecastEngine()
        let store = ArrivalForecastStore()
        store.engine = stub

        let first = await store.refresh(
            ticket: ticket,
            sessions: sessions,
            now: afternoon,
            calendar: calendar
        )
        #expect(first == 40)
        #expect(stub.calls == 1)

        let second = await store.refresh(
            ticket: ticket,
            sessions: sessions,
            now: evening,
            calendar: calendar
        )
        #expect(second == 40)
        #expect(stub.calls == 2)
    }

    @Test func refresh_doesNotRewriteInFlightFingerprint() async throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let ticket = Ticket(title: "レビュー", estimatedSeconds: 30 * 60)
        context.insert(ticket)
        let sessions = [
            arrived(context, ticket: ticket, active: 32 * 60),
            arrived(context, ticket: ticket, active: 34 * 60),
            arrived(context, ticket: ticket, active: 36 * 60),
        ]
        let stub = HoldingForecastEngine()
        let store = ArrivalForecastStore()
        store.engine = stub

        let first = Task { await store.refresh(ticket: ticket, sessions: sessions) }
        await stub.waitUntilStarted(1)
        ticket.estimatedSeconds = 45 * 60
        let second = Task { await store.refresh(ticket: ticket, sessions: sessions) }
        for _ in 0..<30 { await Task.yield() }
        stub.release()
        _ = await first.value
        _ = await second.value
        #expect(stub.order.count == 2)
    }

    @Test func warm_coversEveryOpenTicket() async throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let tickets = (0..<4).map { index in
            let ticket = Ticket(title: "T\(index)", estimatedSeconds: 30 * 60)
            context.insert(ticket)
            return ticket
        }
        let sessions = [
            arrived(context, ticket: tickets[0], active: 32 * 60),
            arrived(context, ticket: tickets[0], active: 34 * 60),
            arrived(context, ticket: tickets[0], active: 36 * 60),
        ]
        let stub = StubArrivalForecastEngine()
        let store = ArrivalForecastStore()
        store.engine = stub
        store.warm(tickets: tickets, sessions: sessions)
        for ticket in tickets {
            _ = await store.refresh(ticket: ticket, sessions: sessions)
        }
        #expect(stub.calls == 4)

        store.warm(tickets: tickets, sessions: sessions)
        for ticket in tickets {
            _ = await store.refresh(ticket: ticket, sessions: sessions)
        }
        #expect(stub.calls == 4)
    }

    @Test func userRefresh_jumpsAheadOfWarmQueue() async throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let tickets = ["A", "B", "C", "D"].map { title in
            let ticket = Ticket(title: title, estimatedSeconds: 30 * 60)
            context.insert(ticket)
            return ticket
        }
        let sessions = [
            arrived(context, ticket: tickets[0], active: 32 * 60),
            arrived(context, ticket: tickets[0], active: 34 * 60),
            arrived(context, ticket: tickets[0], active: 36 * 60),
        ]
        let stub = HoldingForecastEngine()
        let store = ArrivalForecastStore()
        store.engine = stub

        let first = Task { await store.refresh(ticket: tickets[0], sessions: sessions, priority: .user) }
        await stub.waitUntilStarted(1)
        let warmB = Task { await store.refresh(ticket: tickets[1], sessions: sessions, priority: .warm) }
        let warmC = Task { await store.refresh(ticket: tickets[2], sessions: sessions, priority: .warm) }
        for _ in 0..<30 { await Task.yield() }
        let lifted = Task { await store.refresh(ticket: tickets[3], sessions: sessions, priority: .user) }
        for _ in 0..<30 { await Task.yield() }
        stub.release()
        _ = await first.value
        _ = await lifted.value
        #expect(Array(stub.order.prefix(2)) == ["A", "D"])
        _ = await warmB.value
        _ = await warmC.value
        #expect(Set(stub.order) == Set(["A", "B", "C", "D"]))
    }

    private func arrived(
        _ context: ModelContext,
        ticket: Ticket,
        active: TimeInterval,
        startedAt: Date = .now
    ) -> WorkSession {
        let session = WorkSession(
            startedAt: startedAt,
            estimatedSecondsAtStart: ticket.estimatedSeconds,
            ticket: ticket
        )
        session.endedAt = .now
        session.outcome = .arrived
        session.accumulatedActiveSeconds = active
        context.insert(session)
        return session
    }
}
