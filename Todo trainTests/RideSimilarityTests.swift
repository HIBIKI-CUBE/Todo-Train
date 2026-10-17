//
//  RideSimilarityTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct RideSimilarityTests {
    @Test func titleNGram_usesCharacterBigramsAndFoldsCase() {
        let calendar = tokyo
        let at = date(2026, 1, 5, 9, calendar)
        let sample = makeQuery(title: "週報作成", at: at)
        let partial = ride(title: "週報", at: at)
        let identical = ride(title: "週報作成", at: at)
        let other = ride(title: "週次", at: at)
        let folded = ride(title: "AB", at: at)
        let wide = ride(title: "ａｂ", at: at)
        let short = ride(title: "家", at: at)
        let longer = ride(title: "家族", at: at)

        let scored = RideSimilarity.rank(
            query: sample,
            rides: [partial, identical, other],
            calendar: calendar
        )
        #expect(cue(scored, partial).titleNGram == 0.5)
        #expect(cue(scored, identical).titleNGram == 1)
        #expect(cue(scored, other).titleNGram == 0)

        let letters = RideSimilarity.rank(
            query: makeQuery(title: "ab", at: at),
            rides: [folded, wide],
            calendar: calendar
        )
        #expect(cue(letters, folded).titleNGram == 1)
        #expect(cue(letters, wide).titleNGram == 1)

        let family = RideSimilarity.rank(
            query: makeQuery(title: "家", at: at),
            rides: [short, longer],
            calendar: calendar
        )
        #expect(cue(family, short).titleNGram == 1)
        #expect(abs(cue(family, longer).titleNGram - (2.0 / 3.0)) < 0.000_001)
    }

    @Test func tagScore_isJaccardAndIgnoresEmptySets() {
        let calendar = tokyo
        let at = date(2026, 1, 5, 9, calendar)
        let shared = UUID()
        let left = UUID()
        let right = UUID()
        let query = makeQuery(title: "", tagIDs: [shared, left], at: at)
        let overlap = ride(title: "", tags: [shared, right], at: at)
        let none = ride(title: "", tags: [right], at: at)
        let empty = ride(title: "", tags: [], at: at)
        let scored = RideSimilarity.rank(
            query: query,
            rides: [overlap, none, empty],
            calendar: calendar
        )
        #expect(abs(cue(scored, overlap).tag - (1.0 / 3.0)) < 0.000_001)
        #expect(cue(scored, none).tag == 0)
        #expect(cue(scored, empty).tag == 0)

        let bothEmpty = RideSimilarity.rank(
            query: makeQuery(title: "", at: at),
            rides: [empty],
            calendar: calendar
        )
        #expect(cue(bothEmpty, empty).tag == 0)
    }

    @Test func lineageOutranksAPerfectTitleAndSameTicketDoesNotCount() {
        let calendar = tokyo
        let at = date(2026, 1, 5, 9, calendar)
        let group = UUID()
        let child = UUID()
        let parent = UUID()
        let stranger = ride(title: "週報作成", ticketID: UUID(), group: UUID(), at: at)
        let linked = ride(title: "", ticketID: parent, group: group, at: at.addingTimeInterval(-60))
        let sameTicket = ride(title: "", ticketID: child, group: group, at: at.addingTimeInterval(-120))
        let ranked = RideSimilarity.rank(
            query: makeQuery(title: "週報作成", ticketID: child, group: group, at: at),
            rides: [stranger, linked, sameTicket],
            calendar: calendar
        )
        #expect(ranked.map(\.ride.id) == [linked.id, stranger.id, sameTicket.id])
        #expect(cue(ranked, linked).lineage == 1)
        #expect(cue(ranked, sameTicket).lineage == 0)
        #expect(cue(ranked, stranger).lineage == 0)
        #expect(ranked[0].score >= RideSimilarity.lineageBase)
        #expect(ranked[1].score < RideSimilarity.lineageBase)
    }

    @Test func hourBandAndDayKindAreSmallMultipliers() {
        let calendar = tokyo
        let mondayMorning = date(2026, 1, 5, 9, calendar)
        let mondayEvening = date(2026, 1, 5, 20, calendar)
        let sundayEvening = date(2026, 1, 4, 20, calendar)
        let newYear = date(2026, 1, 1, 20, calendar)
        let morning = ride(title: "週報作成", at: mondayMorning)
        let evening = ride(title: "週報作成", at: mondayEvening)
        let weekend = ride(title: "週報作成", at: sundayEvening)
        let holiday = ride(title: "週報作成", at: newYear)

        let atEvening = RideSimilarity.rank(
            query: makeQuery(title: "週報作成", at: mondayEvening),
            rides: [morning, evening],
            calendar: calendar
        )
        #expect(atEvening.map(\.ride.id) == [evening.id, morning.id])
        #expect(cue(atEvening, evening).hourBand == 1)
        #expect(cue(atEvening, morning).hourBand == 0)
        let ratio = atEvening[0].score / atEvening[1].score
        #expect(abs(ratio - RideSimilarity.hourBandFactor) < 0.000_001)

        let onMonday = RideSimilarity.rank(
            query: makeQuery(title: "週報作成", at: mondayEvening),
            rides: [weekend, evening],
            calendar: calendar
        )
        #expect(onMonday.map(\.ride.id) == [evening.id, weekend.id])
        #expect(cue(onMonday, evening).dayKind == 1)
        #expect(cue(onMonday, weekend).dayKind == 0)

        let onHoliday = RideSimilarity.rank(
            query: makeQuery(title: "週報作成", at: newYear),
            rides: [holiday, evening],
            calendar: calendar
        )
        #expect(onHoliday.map(\.ride.id) == [holiday.id, evening.id])
        #expect(cue(onHoliday, holiday).dayKind == 1)
        #expect(cue(onHoliday, evening).dayKind == 0)
    }

    @Test func rank_isDeterministicAndBreaksTiesByRecencyThenID() {
        let calendar = tokyo
        let at = date(2026, 1, 5, 9, calendar)
        let older = ride(title: "週報", at: at.addingTimeInterval(-60))
        let newer = ride(title: "週報", at: at.addingTimeInterval(60))
        var firstID = UUID()
        var secondID = UUID()
        if firstID.uuidString > secondID.uuidString {
            swap(&firstID, &secondID)
        }
        let lowID = ride(title: "週報", id: firstID, at: at)
        let highID = ride(title: "週報", id: secondID, at: at)
        let rides = [highID, older, lowID, newer]
        let forward = RideSimilarity.rank(
            query: makeQuery(title: "週報", at: at),
            rides: rides,
            calendar: calendar
        )
        let backward = RideSimilarity.rank(
            query: makeQuery(title: "週報", at: at),
            rides: rides.reversed(),
            calendar: calendar
        )
        #expect(forward.map(\.ride.id) == backward.map(\.ride.id))
        #expect(forward.map(\.ride.id) == [newer.id, lowID.id, highID.id, older.id])
    }

    @Test func estimateUsesSimilarRidesOnceThreeExist() {
        let matches = (0..<3).map { _ in scored(title: 1, tag: 0, lineage: 0) }
        let weak = scored(title: 0, tag: 0, lineage: 0)
        let enough = RideSimilarity.ridesForEstimate(matches + [weak])
        #expect(enough.count == 3)
        #expect(enough.allSatisfy { $0.hasContentMatch })
        #expect(RideSimilarity.ridesForEstimate([matches[0], weak, weak]).count == 3)
    }

    @Test func lineageBaseStaysAboveAPerfectSituationalScore() {
        let ceiling = RideSimilarity.hourBandFactor * RideSimilarity.dayKindFactor
        #expect(RideSimilarity.lineageBase > ceiling)
    }

    @Test func batchSlackAndDaySlots() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let batches = RideSimilarity.batchIDs([
            .init(id: second, createdAt: start.addingTimeInterval(10 * 60)),
            .init(id: first, createdAt: start),
            .init(id: third, createdAt: start.addingTimeInterval(10 * 60 + RideSimilarity.batchGap + 1)),
        ])
        #expect(batches[first] == first)
        #expect(batches[second] == first)
        #expect(batches[third] == third)

        let soon = UUID()
        let later = UUID()
        let cancelled = UUID()
        let underway = UUID()
        let slack = RideSimilarity.slack(
            departedAt: start,
            blocks: [
                .init(id: cancelled, startsAt: start, endsAt: start.addingTimeInterval(60), isCancelled: true),
                .init(id: underway, startsAt: start.addingTimeInterval(-30), endsAt: start.addingTimeInterval(600), isCancelled: false),
                .init(id: later, startsAt: start.addingTimeInterval(500), endsAt: start.addingTimeInterval(800), isCancelled: false),
                .init(id: soon, startsAt: start.addingTimeInterval(120), endsAt: start.addingTimeInterval(200), isCancelled: false),
            ]
        )
        #expect(slack == 120)

        let nextDay = RideSimilarity.slack(
            departedAt: start.addingTimeInterval(22 * 3_600),
            blocks: [
                .init(id: soon, startsAt: start.addingTimeInterval(120), endsAt: start.addingTimeInterval(200), isCancelled: false),
                .init(id: later, startsAt: start.addingTimeInterval(86_400 + 120), endsAt: start.addingTimeInterval(86_400 + 200), isCancelled: false),
            ],
            calendar: tokyo
        )
        #expect(nextDay == nil)

        let day = UUID()
        let early = UUID()
        let late = UUID()
        let outside = UUID()
        let slots = RideSimilarity.daySlots([
            .init(id: late, serviceDayID: day, startedAt: start.addingTimeInterval(100), endedAt: start.addingTimeInterval(160), activeSeconds: 40),
            .init(id: early, serviceDayID: day, startedAt: start, endedAt: nil, activeSeconds: 30),
            .init(id: outside, serviceDayID: nil, startedAt: start, endedAt: start, activeSeconds: 5),
        ])
        #expect(slots[outside] == nil)
        #expect(slots[early]?.ordinal == 1)
        #expect(slots[early]?.cumulativeActiveSecondsBefore == 0)
        #expect(slots[early]?.nextRideID == late)
        #expect(slots[early]?.secondsSincePreviousArrival == nil)
        #expect(slots[late]?.ordinal == 2)
        #expect(slots[late]?.previousRideID == early)
        #expect(slots[late]?.cumulativeActiveSecondsBefore == 30)
        #expect(slots[late]?.secondsSincePreviousArrival == nil)
    }

    @Test func lineageGroup_usesTheMinimumUUID() {
        let ids = [UUID(), UUID(), UUID()].sorted { $0.uuidString < $1.uuidString }
        let groups = RideSimilarity.lineageGroups(
            ticketIDs: ids,
            links: [(ids[2], ids[1]), (ids[1], ids[0])]
        )
        #expect(groups[ids[0]] == ids[0])
        #expect(groups[ids[1]] == ids[0])
        #expect(groups[ids[2]] == ids[0])
    }

    @Test func priorCandidates_skipTheRideItselfAndTheFuture() {
        let calendar = tokyo
        let start = date(2026, 1, 5, 9, calendar)
        let rides = (0..<25).map { index in
            ride(title: "週報", at: start.addingTimeInterval(TimeInterval(index) * 60))
        }
        let found = RideSimilarity.priorCandidates(for: rides, among: rides, calendar: calendar)
        #expect(found[rides[0].id]?.isEmpty == true)
        let last = found[rides[24].id] ?? []
        #expect(last.count == RideSimilarity.candidateLimit)
        #expect(!last.contains { $0.ride.id == rides[24].id })
        #expect(last.allSatisfy { $0.ride.startedAt < rides[24].startedAt })
    }

    @Test func rank_oneThousandRidesFitsInOneFrame() {
        let calendar = tokyo
        let at = date(2026, 1, 5, 9, calendar)
        let tags = [UUID(), UUID(), UUID()]
        let rides = (0..<1_000).map { index in
            ride(
                title: "週報作成\(index % 40)",
                tags: [tags[index % tags.count]],
                at: at.addingTimeInterval(TimeInterval(index))
            )
        }
        let query = makeQuery(title: "週報作成", tagIDs: [tags[0]], at: at)
        _ = RideSimilarity.rank(query: query, rides: rides, calendar: calendar)
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = RideSimilarity.rank(query: query, rides: rides, calendar: calendar)
        }
        #expect(elapsed < .milliseconds(16))
    }

    @Test func suggestionAndForecastDropExcludedRides() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let ticket = Ticket(title: "週報", estimatedSeconds: 20 * 60)
        context.insert(ticket)
        let kept = [
            arrived(context, ticket: ticket, active: 20 * 60),
            arrived(context, ticket: ticket, active: 22 * 60),
            arrived(context, ticket: ticket, active: 24 * 60),
        ]
        let pulled = arrived(context, ticket: ticket, active: 10 * 60)
        let pause = SessionPause(startedAt: .now, endedAt: .now, session: pulled)
        pause.heldByRaw = "user"
        pause.macActiveSeconds = 400
        context.insert(pause)

        let sessions = kept + [pulled]
        let suggestion = EstimateHeuristic.suggestion(
            title: ticket.title,
            tagIDs: [],
            ticket: ticket,
            sessions: sessions
        )
        #expect(suggestion?.sampleCount == 3)
        #expect(suggestion?.minutes == 20)

        let snapshot = BoardingForecast.make(now: .now, ticket: ticket, sessions: sessions)
        #expect(snapshot.sampleCount == 3)
        #expect(snapshot.predictedMinutes == 22)
    }

    @Test func suggestion_fallsBackUntilThreeSimilarRidesExist() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let named = Ticket(title: "週報", estimatedSeconds: 20 * 60)
        let other = Ticket(title: "買い物", estimatedSeconds: 5 * 60)
        context.insert(named)
        context.insert(other)
        let sessions = [
            arrived(context, ticket: named, active: 20 * 60),
            arrived(context, ticket: named, active: 20 * 60),
            arrived(context, ticket: other, active: 5 * 60),
            arrived(context, ticket: other, active: 5 * 60),
            arrived(context, ticket: other, active: 5 * 60),
        ]
        let broad = EstimateHeuristic.suggestion(title: "週報", sessions: sessions)
        #expect(broad?.sampleCount == 5)

        let focused = EstimateHeuristic.suggestion(
            title: "週報",
            sessions: sessions + [arrived(context, ticket: named, active: 20 * 60)]
        )
        #expect(focused?.minutes == 20)
        #expect(focused?.sampleCount == 3)
    }

    @Test func boardingForecast_includesALinkedTicketWithADifferentTitle() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let parent = Ticket(title: "下書き", estimatedSeconds: 40 * 60)
        let child = Ticket(title: "清書", estimatedSeconds: 20 * 60)
        let stranger = Ticket(title: "清書", estimatedSeconds: 10 * 60)
        let unrelated = Ticket(title: "買い物", estimatedSeconds: 30 * 60)
        context.insert(parent)
        context.insert(child)
        context.insert(stranger)
        context.insert(unrelated)
        context.insert(TaskLineage(kind: .continuation, parent: parent, child: child))
        try context.save()

        let sessions = [
            arrived(context, ticket: parent, active: 50 * 60),
            arrived(context, ticket: stranger, active: 10 * 60),
            arrived(context, ticket: stranger, active: 10 * 60),
            arrived(context, ticket: unrelated, active: 30 * 60),
        ]
        let snapshot = BoardingForecast.make(now: .now, ticket: child, sessions: sessions)
        #expect(snapshot.sampleCount == 3)
        #expect(snapshot.predictedMinutes == 10)
    }

    @Test func exportOmitsExcludedRidesFromCandidatesAndReadsSlackFromBlockTimes() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        var calendar = tokyo
        let start = date(2026, 1, 5, 9, calendar)
        let ticket = Ticket(title: "週報", estimatedSeconds: 20 * 60, createdAt: start.addingTimeInterval(-30))
        context.insert(ticket)
        let kept = arrived(context, ticket: ticket, active: 20 * 60, at: start)
        let pulled = arrived(context, ticket: ticket, active: 10 * 60, at: start.addingTimeInterval(60))
        let pause = SessionPause(startedAt: start, endedAt: start.addingTimeInterval(400), session: pulled)
        pause.heldByRaw = "user"
        pause.macActiveSeconds = 400
        context.insert(pause)
        let later = arrived(context, ticket: ticket, active: 22 * 60, at: start.addingTimeInterval(600))
        let block = TimetableBlock(
            title: "SECRET_BLOCK_TITLE_ZX9",
            startsAt: start.addingTimeInterval(900),
            endsAt: start.addingTimeInterval(1_200),
            source: .manual
        )
        context.insert(block)
        try context.save()

        let document = PDCAExport.make(
            exportedAt: start,
            serviceDays: [],
            tickets: [ticket],
            sessions: [kept, pulled, later],
            lineages: [],
            timetableBlocks: [block],
            timetableGuards: [],
            passengerRides: [],
            calendar: calendar
        )
        let row = try #require(document.rides.first { $0.id == later.id })
        #expect(row.similarityCandidates.map(\.rideId) == [kept.id])
        #expect(row.slackToNextTimetableBlockSeconds.value == 300)
        #expect(document.schema == "todotrain.pdca.v0")
        let encoded = try PDCAExport.encode(document)
        let text = try #require(String(data: encoded, encoding: .utf8))
        #expect(!text.contains("週報"))
        #expect(!text.contains("SECRET_BLOCK_TITLE_ZX9"))
    }

    private func cue(
        _ scored: [RideSimilarity.ScoredRide],
        _ ride: RideSimilarity.Ride
    ) -> RideSimilarity.CueScores {
        scored.first { $0.ride.id == ride.id }!.cues
    }

    private func scored(title: Double, tag: Double, lineage: Double) -> RideSimilarity.ScoredRide {
        RideSimilarity.ScoredRide(
            ride: ride(title: "", at: .now),
            cues: RideSimilarity.CueScores(
                titleNGram: title,
                tag: tag,
                lineage: lineage,
                hourBand: 0,
                dayKind: 0
            ),
            score: title + tag + lineage
        )
    }

    private func makeQuery(
        title: String,
        tagIDs: Set<UUID> = [],
        ticketID: UUID? = nil,
        group: UUID? = nil,
        at: Date
    ) -> RideSimilarity.Query {
        RideSimilarity.Query(
            title: title,
            tagIDs: tagIDs,
            ticketID: ticketID,
            lineageGroupID: group,
            at: at
        )
    }

    private func ride(
        title: String,
        id: UUID = UUID(),
        ticketID: UUID? = UUID(),
        tags: Set<UUID> = [],
        group: UUID? = nil,
        at: Date
    ) -> RideSimilarity.Ride {
        RideSimilarity.Ride(
            id: id,
            ticketID: ticketID,
            title: title,
            tagIDs: tags,
            lineageGroupID: group ?? ticketID,
            startedAt: at,
            activeSeconds: 600
        )
    }

    private var tokyo: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: 0))!
    }

    private func arrived(
        _ context: ModelContext,
        ticket: Ticket,
        active: TimeInterval,
        at startedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> WorkSession {
        let session = WorkSession(
            startedAt: startedAt,
            estimatedSecondsAtStart: ticket.estimatedSeconds,
            ticket: ticket
        )
        session.endedAt = startedAt.addingTimeInterval(active)
        session.outcome = .arrived
        session.accumulatedActiveSeconds = active
        session.budgetSecondsAtStart = ticket.estimatedSeconds
        context.insert(session)
        return session
    }
}
