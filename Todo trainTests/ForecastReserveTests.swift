//
//  ForecastReserveTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

struct ForecastReserveTests {
    private let day = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func titleChangeRebuildsThatTicketsSummaryOnly() {
        let ticketA = UUID()
        let ticketB = UUID()
        let sessionA = UUID()
        let sessionB = UUID()
        let rides = [
            ride(sessionA, ticket: ticketA, title: "レビュー"),
            ride(sessionB, ticket: ticketB, title: "下書き"),
        ]
        let tickets = [
            ticket(ticketA, title: "レビュー", sort: 0),
            ticket(ticketB, title: "下書き", sort: 1),
        ]
        let fresh = stored(matching: rides, tickets: tickets)
        var renamed = tickets
        renamed[0].title = "見直し"
        var renamedRides = rides
        renamedRides[0].title = "見直し"
        let plan = ForecastReserve.plan(
            snapshot: snapshot(tickets: renamed, rides: renamedRides, summaries: fresh.summaries, arrivals: fresh.arrivals),
            rowOrder: [ticketA, ticketB],
            cut: 2
        )
        #expect(plan.summaryWrites == [sessionA])
        #expect(plan.summaryDeletes.isEmpty)
        #expect(plan.arrivalWrites.contains(ticketA))
        #expect(plan.arrivalWrites.contains(ticketB))
    }

    @Test func titleChangeWithoutRidesRebuildsOnlyThatForecast() {
        let ticketA = UUID()
        let ticketC = UUID()
        let sessionA = UUID()
        let rides = [ride(sessionA, ticket: ticketA, title: "レビュー")]
        var tickets = [
            ticket(ticketA, title: "レビュー", sort: 0),
            ticket(ticketC, title: "メモ", sort: 1),
        ]
        let fresh = stored(matching: rides, tickets: tickets)
        tickets[1].title = "控え"
        let plan = ForecastReserve.plan(
            snapshot: snapshot(tickets: tickets, rides: rides, summaries: fresh.summaries, arrivals: fresh.arrivals),
            rowOrder: [ticketA, ticketC],
            cut: 2
        )
        #expect(plan.summaryWrites.isEmpty)
        #expect(plan.arrivalWrites == [ticketC])
        #expect(plan.places[ticketA] == .current(30))
        #expect(plan.places[ticketC] == .previous(30))
    }

    @Test func tagChangeRebuildsThatTicketsSummary() {
        let ticketA = UUID()
        let sessionA = UUID()
        let tag = UUID()
        let rides = [ride(sessionA, ticket: ticketA, title: "レビュー", tags: [tag])]
        let tickets = [ticket(ticketA, title: "レビュー", tags: [tag], sort: 0)]
        let fresh = stored(matching: rides, tickets: tickets)
        var retagged = rides
        retagged[0].tagIDs = []
        var ticketsNow = tickets
        ticketsNow[0].tagIDs = []
        let plan = ForecastReserve.plan(
            snapshot: snapshot(tickets: ticketsNow, rides: retagged, summaries: fresh.summaries, arrivals: fresh.arrivals),
            rowOrder: [ticketA],
            cut: 1
        )
        #expect(plan.summaryWrites == [sessionA])
        #expect(plan.arrivalWrites == [ticketA])
    }

    @Test func pauseChangeRebuildsThatRideOnly() {
        let ticketA = UUID()
        let ticketB = UUID()
        let sessionA = UUID()
        let sessionB = UUID()
        let pause = ForecastPauseSource(
            id: UUID(),
            startedAt: day,
            endedAt: day.addingTimeInterval(60),
            heldByRaw: "user",
            macActiveSeconds: 0,
            undoneAt: nil
        )
        var rides = [
            ride(sessionA, ticket: ticketA, title: "レビュー", pauses: [pause]),
            ride(sessionB, ticket: ticketB, title: "下書き"),
        ]
        let tickets = [
            ticket(ticketA, title: "レビュー", sort: 0),
            ticket(ticketB, title: "下書き", sort: 1),
        ]
        let fresh = stored(matching: rides, tickets: tickets)
        rides[0].pauses[0].endedAt = day.addingTimeInterval(120)
        let plan = ForecastReserve.plan(
            snapshot: snapshot(tickets: tickets, rides: rides, summaries: fresh.summaries, arrivals: fresh.arrivals),
            rowOrder: [ticketA, ticketB],
            cut: 2
        )
        #expect(plan.summaryWrites == [sessionA])
        #expect(!plan.summaryWrites.contains(sessionB))
        #expect(Set(plan.arrivalWrites) == Set([ticketA, ticketB]))
    }

    @Test func deletedRideDropsOnlyThatSummary() {
        let ticketA = UUID()
        let ticketB = UUID()
        let sessionA = UUID()
        let sessionB = UUID()
        let rides = [
            ride(sessionA, ticket: ticketA, title: "レビュー"),
            ride(sessionB, ticket: ticketB, title: "下書き"),
        ]
        let tickets = [
            ticket(ticketA, title: "レビュー", sort: 0),
            ticket(ticketB, title: "下書き", sort: 1),
        ]
        let fresh = stored(matching: rides, tickets: tickets)
        let kept = [rides[1]]
        let plan = ForecastReserve.plan(
            snapshot: snapshot(tickets: tickets, rides: kept, summaries: fresh.summaries, arrivals: fresh.arrivals),
            rowOrder: [ticketA, ticketB],
            cut: 2
        )
        #expect(plan.summaryDeletes == [sessionA])
        #expect(!plan.summaryWrites.contains(sessionB))
    }

    @Test func methodVersionRebuildsEveryReserve() {
        let ticketA = UUID()
        let sessionA = UUID()
        let rides = [ride(sessionA, ticket: ticketA, title: "レビュー")]
        let tickets = [ticket(ticketA, title: "レビュー", sort: 0)]
        let fresh = stored(matching: rides, tickets: tickets)
        let plan = ForecastReserve.plan(
            snapshot: snapshot(tickets: tickets, rides: rides, summaries: fresh.summaries, arrivals: fresh.arrivals),
            rowOrder: [ticketA],
            cut: 1,
            rideMethod: ForecastReserve.rideSummaryMethod + 1,
            arrivalMethod: ForecastReserve.arrivalMethod + 1
        )
        #expect(plan.summaryWrites == [sessionA])
        #expect(plan.arrivalWrites == [ticketA])
    }

    @Test func corruptSummaryIsRebuiltAndTheOtherStays() {
        let ticketA = UUID()
        let ticketB = UUID()
        let sessionA = UUID()
        let sessionB = UUID()
        let rides = [
            ride(sessionA, ticket: ticketA, title: "レビュー"),
            ride(sessionB, ticket: ticketB, title: "下書き"),
        ]
        let tickets = [
            ticket(ticketA, title: "レビュー", sort: 0),
            ticket(ticketB, title: "下書き", sort: 1),
        ]
        var fresh = stored(matching: rides, tickets: tickets)
        fresh.summaries[0].readable = false
        fresh.summaries[0].payload = nil
        let plan = ForecastReserve.plan(
            snapshot: snapshot(tickets: tickets, rides: rides, summaries: fresh.summaries, arrivals: fresh.arrivals),
            rowOrder: [ticketA, ticketB],
            cut: 2
        )
        #expect(plan.summaryWrites == [sessionA])
        #expect(!plan.summaryWrites.contains(sessionB))
    }

    @Test func freshReserveIsKept() {
        let ticketA = UUID()
        let sessionA = UUID()
        let rides = [ride(sessionA, ticket: ticketA, title: "レビュー")]
        let tickets = [ticket(ticketA, title: "レビュー", sort: 0)]
        let fresh = stored(matching: rides, tickets: tickets)
        let plan = ForecastReserve.plan(
            snapshot: snapshot(tickets: tickets, rides: rides, summaries: fresh.summaries, arrivals: fresh.arrivals),
            rowOrder: [ticketA],
            cut: 1
        )
        #expect(plan.summaryWrites.isEmpty)
        #expect(plan.summaryDeletes.isEmpty)
        #expect(plan.arrivalWrites.isEmpty)
        #expect(plan.places[ticketA] == .current(30))
    }

    @Test func whileComputingThePreviousValueStaysAndAMissIsEmpty() {
        let ticketA = UUID()
        let ticketB = UUID()
        let sessionA = UUID()
        let rides = [ride(sessionA, ticket: ticketA, title: "レビュー")]
        var tickets = [
            ticket(ticketA, title: "レビュー", sort: 0),
            ticket(ticketB, title: "新規", sort: 1),
        ]
        var fresh = stored(matching: rides, tickets: [tickets[0]])
        fresh.arrivals[0].payload?.medianMinutes = 44
        tickets[0].title = "見直し"
        let renamedRide = ride(sessionA, ticket: ticketA, title: "見直し")
        let plan = ForecastReserve.plan(
            snapshot: snapshot(
                tickets: tickets,
                rides: [renamedRide],
                summaries: fresh.summaries,
                arrivals: fresh.arrivals
            ),
            rowOrder: [ticketA, ticketB],
            cut: 2
        )
        #expect(plan.places[ticketA] == .previous(44))
        #expect(plan.places[ticketB] == .empty)
        #expect(plan.arrivalWrites == [ticketA, ticketB])
    }

    @Test func workOrderStartsAboveTheCutAndSkipsClosedTickets() {
        let above = UUID()
        let below = UUID()
        let closed = UUID()
        let order = ForecastReserve.orderedWork(
            rowIDs: [above, UUID(), below],
            cut: 1,
            stale: [below, above]
        )
        #expect(order == [above, below])

        let closedTicket = ticket(closed, title: "済", sort: 0, open: false)
        let openTicket = ticket(above, title: "開", sort: 1)
        let plan = ForecastReserve.plan(
            snapshot: snapshot(tickets: [closedTicket, openTicket], rides: [], summaries: [], arrivals: []),
            rowOrder: [closed, above],
            cut: 2
        )
        #expect(plan.arrivalWrites == [above])
        #expect(plan.displayOrder == [above])
    }

    @Test func computationRunsOffTheMainThread() async {
        let ticketA = UUID()
        let output = await ForecastComputation.evaluate(
            ForecastComputation.Input(
                ticket: ticket(ticketA, title: "レビュー", sort: 0),
                rides: [
                    ride(UUID(), ticket: ticketA, title: "レビュー", active: 20 * 60),
                    ride(UUID(), ticket: ticketA, title: "レビュー", active: 30 * 60),
                    ride(UUID(), ticket: ticketA, title: "レビュー", active: 40 * 60),
                ],
                ticketIDs: [ticketA],
                links: [],
                now: day,
                calendar: Calendar(identifier: .gregorian)
            )
        )
        #expect(output.ranOnMainThread == false)
        #expect(output.prediction.medianMinutes == 30)
    }

    @Test func offMainMedianMatchesTheExistingForecast() async throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let ticket = Ticket(title: "レビュー", estimatedSeconds: 30 * 60)
        context.insert(ticket)
        for minutes in [20, 30, 40] {
            let session = WorkSession(
                startedAt: day,
                estimatedSecondsAtStart: ticket.estimatedSeconds,
                ticket: ticket
            )
            session.endedAt = day.addingTimeInterval(TimeInterval(minutes * 60))
            session.outcome = .arrived
            session.accumulatedActiveSeconds = TimeInterval(minutes * 60)
            context.insert(session)
        }
        try context.save()
        let calendar = Calendar(identifier: .gregorian)
        let expected = BoardingForecast.make(
            now: day,
            ticket: ticket,
            sessions: try context.fetch(FetchDescriptor<WorkSession>()),
            calendar: calendar
        )
        let snapshot = await ForecastReserveReader(modelContainer: container).snapshot(now: day, calendar: calendar)
        let source = try #require(snapshot.tickets.first { $0.id == ticket.id })
        let output = await ForecastComputation.evaluate(
            ForecastComputation.Input(
                ticket: source,
                rides: snapshot.rides,
                ticketIDs: snapshot.tickets.map(\.id),
                links: snapshot.links,
                now: day,
                calendar: calendar
            )
        )
        #expect(output.ranOnMainThread == false)
        #expect(output.prediction.medianMinutes == expected.predictedMinutes)
    }

    @Test func durationWhileComputingShowsThePreviousValueOrStaysEmpty() {
        let previous = OpeningPanelTickets.durationPresentation(
            arrival: .previous(40),
            estimate: 30,
            growthStep: OpeningPanelTiming.ticketGrowthSteps
        )
        #expect(previous == OpeningPanelDurationPresentation(text: "0:40", faint: true))

        let empty = OpeningPanelTickets.durationPresentation(
            arrival: .empty,
            estimate: 30,
            growthStep: OpeningPanelTiming.ticketGrowthSteps
        )
        #expect(empty == OpeningPanelDurationPresentation(text: "", faint: false))

        let current = OpeningPanelTickets.durationPresentation(
            arrival: .current(40),
            estimate: 30,
            growthStep: OpeningPanelTiming.ticketGrowthSteps
        )
        #expect(current == OpeningPanelDurationPresentation(text: "0:40", faint: false))
    }

    private func ticket(
        _ id: UUID,
        title: String,
        tags: [UUID] = [],
        sort: Int,
        open: Bool = true
    ) -> ForecastTicketSource {
        ForecastTicketSource(
            id: id,
            title: title,
            tagIDs: tags,
            tagNames: [],
            estimatedSeconds: 30 * 60,
            isOpen: open,
            sortOrder: sort,
            createdAt: day
        )
    }

    private func ride(
        _ sessionID: UUID,
        ticket ticketID: UUID,
        title: String,
        tags: [UUID] = [],
        active: TimeInterval = 30 * 60,
        pauses: [ForecastPauseSource] = []
    ) -> ForecastRideSource {
        ForecastRideSource(
            sessionID: sessionID,
            ticketID: ticketID,
            title: title,
            tagIDs: tags,
            startedAt: day,
            endedAt: day.addingTimeInterval(active),
            activeSeconds: active,
            estimatedSeconds: 30 * 60,
            budgetSeconds: 30 * 60,
            extensionAddedSeconds: 0,
            extensionReasons: [],
            punctuality: .onTime,
            pauseInputSeconds: 0,
            outcomeArrived: true,
            pauses: pauses
        )
    }

    private func snapshot(
        tickets: [ForecastTicketSource],
        rides: [ForecastRideSource],
        summaries: [StoredRideSummary],
        arrivals: [StoredArrivalForecast]
    ) -> ForecastSnapshot {
        ForecastSnapshot(
            tickets: tickets,
            rides: rides,
            links: [],
            summaries: summaries,
            arrivals: arrivals,
            now: day,
            calendar: Calendar(identifier: .gregorian)
        )
    }

    /// いまの元記録から作った、作り直す必要のない控え。
    private func stored(
        matching rides: [ForecastRideSource],
        tickets: [ForecastTicketSource]
    ) -> (summaries: [StoredRideSummary], arrivals: [StoredArrivalForecast]) {
        let probe = ForecastReserve.plan(
            snapshot: snapshot(tickets: tickets, rides: rides, summaries: [], arrivals: []),
            rowOrder: tickets.map(\.id),
            cut: tickets.count
        )
        let summaries = rides.filter(ForecastReserve.isEligible).map { ride in
            StoredRideSummary(
                sessionID: ride.sessionID,
                payload: ForecastReserve.summaryPayload(ride),
                sourceUpdatedAt: ForecastReserve.sourceUpdatedAt(ride),
                methodVersion: ForecastReserve.rideSummaryMethod,
                readable: true
            )
        }
        let arrivals = tickets.filter(\.isOpen).map { ticket in
            StoredArrivalForecast(
                ticketID: ticket.id,
                payload: ArrivalForecastPayload(
                    ticketID: ticket.id,
                    title: ticket.title,
                    tagIDs: ForecastReserve.sortedTagIDs(ticket.tagIDs),
                    medianMinutes: 30,
                    refinedMinutes: nil,
                    modelRefined: false,
                    poolStamp: probe.poolStamp
                ),
                sourceUpdatedAt: day,
                methodVersion: ForecastReserve.arrivalMethod,
                readable: true
            )
        }
        return (summaries, arrivals)
    }
}
