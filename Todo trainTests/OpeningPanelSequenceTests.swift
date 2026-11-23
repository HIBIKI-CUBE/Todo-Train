//
//  OpeningPanelSequenceTests.swift
//  Todo trainTests
//
//  TODAY の線、山の境目、取消、16 枚の例、記録。
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct OpeningPanelSequenceTests {
    @Test func lineUsesMedianWhenThreeSimilarRidesExist() {
        let order = [
            stat(estimate: 10, count: 6, median: 30, spread: 10),
            stat(estimate: 10, count: 6, median: 30, spread: 10),
            stat(estimate: 10, count: 6, median: 30, spread: 10),
        ]
        let line = OpeningPanelSequenceMath.lineIndex(order: order, freeMinutes: 80)
        let z = OpeningPanelSequenceMath.z90
        #expect(line == 2)
        #expect(60 + z * (200 as Double).squareRoot() <= 80)
        #expect(90 + z * (300 as Double).squareRoot() > 80)
    }

    @Test func lineUsesEstimateAndThirtyPercentWhenSimilarRidesAreFew() {
        let order = [
            stat(estimate: 40, count: 0, median: 0, spread: 0),
            stat(estimate: 40, count: 1, median: 0, spread: 0),
            stat(estimate: 40, count: 2, median: 99, spread: 99),
        ]
        let line = OpeningPanelSequenceMath.lineIndex(order: order, freeMinutes: 70)
        let z = OpeningPanelSequenceMath.z90
        let sigma = 0.3 * 40
        #expect(line == 1)
        #expect(40 + z * sigma <= 70)
        #expect(80 + z * (2 * sigma * sigma).squareRoot() > 70)
        #expect(OpeningPanelSequenceMath.sigmaMinutes(order[2]) == 12)
        #expect(OpeningPanelSequenceMath.meanMinutes(order[2]) == 40)
    }

    @Test func spreadIsThePopulationDeviationInMinutes() {
        let samples: [TimeInterval] = [0, 60, 120]
        #expect(abs(OpeningPanelSequenceMath.spreadMinutes(samples) - (2.0 / 3.0).squareRoot()) < 1e-9)
        #expect(OpeningPanelSequenceMath.spreadMinutes([60, 60]) == 0)
    }

    @Test func lineIgnoresPassingPlansBecauseTheyAreNotAnInput() {
        let order = [stat(estimate: 30, count: 4, median: 30, spread: 0)]
        let withPassingLeftIn = OpeningPanelSequenceMath.lineIndex(order: order, freeMinutes: 40)
        let ifPassingWereSubtracted = OpeningPanelSequenceMath.lineIndex(order: order, freeMinutes: 20)
        #expect(withPassingLeftIn == 1)
        #expect(ifPassingWereSubtracted == 0)
    }

    @Test func boundaryBetweenPilesDoesNotOpenAComparison() throws {
        let ids = [UUID(), UUID(), UUID()]
        var engine = try #require(OpeningPanelSequenceEngine.start(
            stats: [
                stat(id: ids[0], estimate: 10, count: 3, median: 10, spread: 0),
                stat(id: ids[1], estimate: 10, count: 3, median: 10, spread: 0),
                stat(id: ids[2], estimate: 100, count: 3, median: 100, spread: 0),
            ],
            freeMinutes: 25,
            queue: ids
        ))
        expectTrue(engine.choosePile(0))
        expectTrue(engine.choosePile(0))
        expectTrue(engine.choosePile(1))
        #expect(engine.phase == .result)
        #expect(engine.lineIndex == 2)
        #expect(engine.answers.allSatisfy { $0.kind == "sort" })
    }

    @Test func lineThroughAPileOpensATwoChoice() throws {
        let ids = [UUID(), UUID(), UUID()]
        var engine = try #require(OpeningPanelSequenceEngine.start(
            stats: [
                stat(id: ids[0], estimate: 10, count: 3, median: 10, spread: 0),
                stat(id: ids[1], estimate: 50, count: 3, median: 50, spread: 0),
                stat(id: ids[2], estimate: 100, count: 3, median: 100, spread: 0),
            ],
            freeMinutes: 25,
            queue: ids
        ))
        expectTrue(engine.choosePile(0))
        expectTrue(engine.choosePile(0))
        expectTrue(engine.choosePile(2))
        #expect(engine.phase == .comparing)
        #expect(engine.lineIndex == 1)
        let answersBeforeDisabledKey = engine.answers.count
        expectTrue(!engine.choosePile(2))
        #expect(engine.answers.count == answersBeforeDisabledKey)
        let pair = try #require(engine.comparison)
        #expect(engine.stat(at: pair.inserted)?.id == ids[1])
        #expect(engine.stat(at: pair.other)?.id == ids[0])
        expectTrue(engine.chooseInsertedFirst(true))
        #expect(engine.phase == .result)
        #expect(engine.orderIDs == [ids[1], ids[0], ids[2]])
    }

    @Test func undoRestoresOneMoveAndDoesNotRewindProgress() throws {
        let ids = [UUID(), UUID(), UUID()]
        var engine = try #require(OpeningPanelSequenceEngine.start(
            stats: ids.map { stat(id: $0, estimate: 10, count: 0, median: 0, spread: 0) },
            freeMinutes: 100,
            queue: ids
        ))
        expectTrue(engine.choosePile(0))
        let afterFirst = engine.progress
        expectTrue(engine.choosePile(1))
        let afterSecond = engine.progress
        #expect(afterSecond >= afterFirst)
        expectTrue(engine.undo())
        #expect(engine.queueIDs.first == ids[1])
        #expect(engine.pileCounts == [1, 0, 0])
        #expect(engine.progress == afterSecond)
        #expect(engine.answers.map(\.kind) == ["sort", "sort", "undoSort"])
        expectTrue(engine.undo())
        #expect(engine.queueIDs == ids)
        #expect(engine.progress == afterSecond)
        expectTrue(!engine.undo())
    }

    @Test func sixteenExampleTicketsFinishInAboutTwentyThreePresses() throws {
        let ids = (0..<16).map { _ in UUID() }
        let rows: [(Int, Int, Int, Double)] = [
            (45, 52, 6, 12), (30, 28, 9, 6), (15, 18, 12, 5), (60, 75, 4, 20),
            (20, 0, 1, 0), (25, 22, 5, 6), (30, 35, 7, 8), (40, 45, 3, 12),
            (10, 0, 0, 0), (5, 0, 2, 0), (60, 80, 3, 25), (45, 0, 0, 0),
            (30, 40, 4, 10), (50, 60, 8, 15), (30, 30, 10, 6), (40, 0, 1, 0),
        ]
        let stats = zip(ids, rows).map { id, row in
            stat(id: id, estimate: row.0, count: row.2, median: row.1, spread: row.3)
        }
        var engine = try #require(OpeningPanelSequenceEngine.start(
            stats: stats,
            freeMinutes: 180,
            seed: 52
        ))
        #expect(engine.queueIDs == [8, 9, 1, 7, 15, 12, 4, 11, 2, 14, 5, 13, 10, 6, 0, 3].map { ids[$0] })
        let preference = [0, 2, 9, 6, 3, 15, 1, 4, 8, 5, 11, 7, 14, 12, 13, 10]
        func rank(_ id: UUID) -> Int {
            let index = ids.firstIndex(of: id)!
            return preference.firstIndex(of: index)!
        }
        var taps = 0
        while engine.phase != .result, taps < 40 {
            switch engine.phase {
            case .sorting:
                let id = try #require(engine.queueIDs.first)
                let place = rank(id)
                let pile = place <= 4 ? 0 : place <= 8 ? 1 : 2
                expectTrue(engine.choosePile(pile))
            case .comparing:
                let pair = try #require(engine.comparison)
                let inserted = try #require(engine.stat(at: pair.inserted)?.id)
                let other = try #require(engine.stat(at: pair.other)?.id)
                expectTrue(engine.chooseInsertedFirst(rank(inserted) < rank(other)))
            case .result:
                break
            }
            taps += 1
        }
        #expect(taps == 22)
        #expect(engine.phase == .result)
        #expect(engine.lineIndex == 4)
        #expect(engine.orderIDs == [0, 2, 9, 6, 3, 8, 1, 15, 4, 7, 12, 11, 14, 5, 13, 10].map { ids[$0] })
        #expect(engine.answers.filter { $0.kind == "compare" }.count == 6)
    }

    @Test func recordsKeepPlacementsAnswersAndDaysWithoutTitles() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let titles = ["資料まとめ", "買い出し", "年賀状の下調べ"]
        let tickets = [
            Ticket(title: titles[0], estimatedSeconds: 10 * 60, sortOrder: 0),
            Ticket(title: titles[1], estimatedSeconds: 100 * 60, sortOrder: 1),
            Ticket(title: titles[2], estimatedSeconds: 100 * 60, sortOrder: 2),
        ]
        tickets.forEach { context.insert($0) }
        let model = OpeningPanelTicketsModel()
        model.sync(tickets: tickets, sessions: [])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let day = Date(timeIntervalSince1970: 1_763_942_400)
        #expect(model.beginSequence(
            sessions: [],
            freeMinutes: 50,
            now: day,
            calendar: calendar,
            in: context,
            seed: 7
        ))
        var undid = false
        var progressAfterUndo = 0.0
        while model.sequencePhase == .sorting {
            let engine = try #require(model.engine)
            if !undid, engine.sortedCount == 1 {
                let held = engine.progress
                #expect(model.undoSequence())
                #expect(model.engine?.sortedCount == 0)
                #expect(model.engine?.progress == held)
                progressAfterUndo = held
                undid = true
                continue
            }
            let id = try #require(model.engine?.queueIDs.first)
            let pile = id == tickets[0].id ? 0 : 2
            #expect(model.chooseSequencePile(pile))
        }
        #expect(undid)
        #expect(model.sequencePhase == .result)
        #expect(model.engine?.lineIndex == 1)
        #expect((model.engine?.progress ?? 0) >= progressAfterUndo)
        model.commitSequenceOrder(in: context, now: day, calendar: calendar)

        let records = try context.fetch(FetchDescriptor<OpeningSequenceRecord>())
        let record = try #require(records.first)
        let stored = record.placementsJSON + record.answersJSON
        for title in titles {
            #expect(!stored.contains(title))
            #expect(!stored.contains("題名"))
            #expect(!stored.contains("title"))
        }
        let placements = try JSONDecoder().decode(
            [OpeningPanelSequencePlacement].self,
            from: Data(record.placementsJSON.utf8)
        )
        #expect(placements.count == 3)
        #expect(placements.first { $0.ticketID == tickets[0].id }?.pile == .today)
        #expect(placements.first { $0.ticketID == tickets[0].id }?.aboveLine == true)
        #expect(placements.first { $0.ticketID == tickets[1].id }?.aboveLine == false)
        let answers = try JSONDecoder().decode(
            [OpeningPanelSequenceAnswer].self,
            from: Data(record.answersJSON.utf8)
        )
        #expect(answers.contains { $0.kind == "undoSort" })
        #expect(answers.allSatisfy { $0.kind == "sort" || $0.kind == "undoSort" })

        let marks = try context.fetch(FetchDescriptor<OpeningSequenceBelowDays>())
        #expect(marks.first { $0.ticketID == tickets[0].id }?.consecutiveDays == 0)
        #expect(marks.first { $0.ticketID == tickets[1].id }?.consecutiveDays == 1)
        #expect(marks.allSatisfy { $0.consecutiveDays >= 0 })

        model.sync(tickets: tickets, sessions: [])
        #expect(model.beginSequence(
            sessions: [],
            freeMinutes: 50,
            now: day,
            calendar: calendar,
            in: context,
            seed: 7
        ))
        try sortSameWay(model, first: tickets[0].id)
        model.commitSequenceOrder(in: context, now: day, calendar: calendar)
        let sameDay = try context.fetch(FetchDescriptor<OpeningSequenceBelowDays>())
        #expect(sameDay.first { $0.ticketID == tickets[1].id }?.consecutiveDays == 1)

        let nextDay = day.addingTimeInterval(86_400)
        model.sync(tickets: tickets, sessions: [])
        #expect(model.beginSequence(
            sessions: [],
            freeMinutes: 50,
            now: nextDay,
            calendar: calendar,
            in: context,
            seed: 7
        ))
        try sortSameWay(model, first: tickets[0].id)
        model.commitSequenceOrder(in: context, now: nextDay, calendar: calendar)
        let next = try context.fetch(FetchDescriptor<OpeningSequenceBelowDays>())
        #expect(next.first { $0.ticketID == tickets[1].id }?.consecutiveDays == 2)

        model.sync(tickets: tickets, sessions: [])
        #expect(model.beginSequence(
            sessions: [],
            freeMinutes: 10_000,
            now: nextDay.addingTimeInterval(86_400),
            calendar: calendar,
            in: context,
            seed: 7
        ))
        while model.sequencePhase == .sorting {
            #expect(model.chooseSequencePile(0))
        }
        model.commitSequenceOrder(
            in: context,
            now: nextDay.addingTimeInterval(86_400),
            calendar: calendar
        )
        let cleared = try context.fetch(FetchDescriptor<OpeningSequenceBelowDays>())
        #expect(cleared.allSatisfy { $0.consecutiveDays == 0 })
        #expect(tickets.map(\.sortOrder).sorted() == [0, 1, 2])
    }

    private func sortSameWay(_ model: OpeningPanelTicketsModel, first: UUID) throws {
        while model.sequencePhase == .sorting {
            let id = try #require(model.engine?.queueIDs.first)
            #expect(model.chooseSequencePile(id == first ? 0 : 2))
        }
        #expect(model.sequencePhase == .result)
    }

    private func expectTrue(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(value, sourceLocation: sourceLocation)
    }

    private func stat(
        id: UUID = UUID(),
        estimate: Int,
        count: Int,
        median: Int,
        spread: Double
    ) -> OpeningPanelSequenceStat {
        OpeningPanelSequenceStat(
            id: id,
            estimateMinutes: estimate,
            similarCount: count,
            similarMedianMinutes: median,
            similarSpreadMinutes: spread,
            daysBelowLine: 0,
            dueDate: nil
        )
    }
}
