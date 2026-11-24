//
//  OpeningPanelTicketsTests.swift
//  Todo trainTests
//
//  並べ替え、TODAY の区切り、所要の伸び。起動の段は OpeningPanelStateTests。
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct OpeningPanelTicketsTests {
    @Test func rowsMatchHubOrderAndSkipClosed() {
        let closed = Ticket(title: "済", estimatedSeconds: 600, sortOrder: 0)
        closed.closedAt = .now
        let later = Ticket(title: "後", estimatedSeconds: 25 * 60, sortOrder: 2)
        let earlier = Ticket(title: "先", estimatedSeconds: 90, sortOrder: 1)
        let rows = OpeningPanelTickets.rows(from: [closed, later, earlier], sessions: [])
        let consist = ServiceCabinSequence.consistItems(from: [closed, later, earlier])
        #expect(rows.map(\.id) == consist.map(\.id))
        #expect(rows.map(\.title) == ["先", "後"])
        #expect(rows.map(\.estimateMinutes) == [1, 25])
        #expect(rows.map(\.actualMinutes) == [1, 25])
    }

    @Test func actualMinutes_useMedianThenArrivalRefine() {
        let samples: [TimeInterval] = [10 * 60, 20 * 60, 40 * 60]
        let median = OpeningPanelTickets.resolveMinutes(
            estimatedSeconds: 45 * 60,
            samples: samples,
            refined: nil
        )
        #expect(median.estimate == 45)
        #expect(median.actual == 20)

        let refined = OpeningPanelTickets.resolveMinutes(
            estimatedSeconds: 45 * 60,
            samples: samples,
            refined: 28
        )
        #expect(refined.actual == 28)

        let none = OpeningPanelTickets.resolveMinutes(
            estimatedSeconds: 45 * 60,
            samples: [],
            refined: nil
        )
        #expect(none.actual == 45)
    }

    @Test func durationGrowsInSixStepsAndHatchesOnlyTheExtra() {
        #expect(OpeningPanelTickets.shownMinutes(estimate: 45, actual: 60, step: 0) == 45)
        #expect(OpeningPanelTickets.shownMinutes(estimate: 45, actual: 60, step: 1) == 48)
        #expect(OpeningPanelTickets.shownMinutes(estimate: 45, actual: 60, step: 3) == 53)
        #expect(OpeningPanelTickets.shownMinutes(estimate: 45, actual: 60, step: 6) == 60)
        #expect(OpeningPanelTickets.shownMinutes(estimate: 45, actual: 20, step: 6) == 20)
        #expect(OpeningPanelTickets.durationText(minutes: 45) == "0:45")
        #expect(OpeningPanelTickets.durationText(minutes: 75) == "1:15")
        #expect(OpeningPanelTickets.durationText(minutes: 5) == "0:05")

        let grown = OpeningPanelTickets.bandWidths(estimate: 60, shown: 90, rowWidth: 200)
        #expect(grown.fill == 100)
        #expect(grown.hatch == 50)
        let same = OpeningPanelTickets.bandWidths(estimate: 60, shown: 45, rowWidth: 200)
        #expect(same.fill == 100)
        #expect(same.hatch == 0)
        let full = OpeningPanelTickets.bandWidths(estimate: 180, shown: 200, rowWidth: 200)
        #expect(full.fill == 200)
        #expect(full.hatch == 0)
    }

    @Test func todayCut_defaultsUnderTheThirdAndFollowsTheRow() {
        #expect(OpeningPanelTickets.initialCut(count: 5) == 3)
        #expect(OpeningPanelTickets.initialCut(count: 2) == 2)
        #expect(OpeningPanelTickets.initialCut(count: 0) == 0)
        #expect(OpeningPanelTickets.rowOpacity(index: 2, cut: 3) == 1)
        #expect(OpeningPanelTickets.rowOpacity(index: 3, cut: 3) == 0.55)
        #expect(OpeningPanelTickets.rankFilled(index: 2, cut: 3, settled: true))
        #expect(!OpeningPanelTickets.rankFilled(index: 3, cut: 3, settled: true))
        #expect(!OpeningPanelTickets.rankFilled(index: 0, cut: 3, settled: false))

        let ids = (0..<5).map { _ in UUID() }
        let moved = OpeningPanelTickets.touchRow(
            index: 0,
            ids: ids,
            cut: 3,
            sequencing: false,
            confirmed: true,
            powered: true,
            departed: false
        )
        #expect(moved == .placeCut(1))
        let same = OpeningPanelTickets.touchRow(
            index: 2,
            ids: ids,
            cut: 3,
            sequencing: false,
            confirmed: true,
            powered: true,
            departed: false
        )
        #expect(same == .cutStays)
        let beforeConfirm = OpeningPanelTickets.touchRow(
            index: 1,
            ids: ids,
            cut: 3,
            sequencing: false,
            confirmed: false,
            powered: true,
            departed: false
        )
        #expect(beforeConfirm == .reject)
        let duringSequence = OpeningPanelTickets.touchRow(
            index: 1,
            ids: ids,
            cut: 3,
            sequencing: true,
            confirmed: true,
            powered: true,
            departed: false
        )
        #expect(duringSequence == .reject)
    }

    @Test func syncKeepsOrderAndCutWhenTheSameTicketsArrive() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let tickets = (0..<5).map { index in
            Ticket(title: "切符\(index)", estimatedSeconds: (index + 1) * 600, sortOrder: index)
        }
        tickets.forEach { context.insert($0) }
        let model = OpeningPanelTicketsModel()
        model.sync(tickets: tickets, sessions: [])
        #expect(model.cut == 3)
        model.placeCut(4)
        tickets[2].title = "改題"
        model.sync(tickets: tickets, sessions: [])
        #expect(model.cut == 4)
        #expect(model.rows.map(\.id) == tickets.map(\.id))
        #expect(model.rows[2].title == "改題")
        model.commitSequenceOrder(in: context)
        #expect(model.rows.map(\.id) == tickets.map(\.id))
        #expect(model.engine == nil)
    }

    @Test func waitingRows_showEstimateOverMedianAndAShortTail() {
        let few = OpeningPanelTickets.pair(estimate: 20, similarCount: 1, median: 0)
        #expect(few == OpeningPanelTicketPair(estimate: "20", median: "--"))
        let enough = OpeningPanelTickets.pair(estimate: 45, similarCount: 6, median: 52)
        #expect(enough == OpeningPanelTicketPair(estimate: "45", median: "52"))
        #expect(OpeningPanelTickets.readout(today: 3, total: 16, freeMinutes: 180) == "TODAY 3/16 · 空き3:00")
        #expect(OpeningPanelTickets.readout(today: 0, total: 4, freeMinutes: 5) == "TODAY 0/4 · 空き0:05")

        #expect(OpeningPanelSequenceMath.visibleSpan(line: 3, total: 16) == (6, 10))
        #expect(OpeningPanelSequenceMath.visibleSpan(line: 0, total: 5) == (3, 2))
        #expect(OpeningPanelSequenceMath.visibleSpan(line: 6, total: 6) == (6, 0))
        #expect(OpeningPanelSequenceMath.visibleSpan(line: 8, total: 10) == (9, 1))

        let idle = OpeningPanelTickets.pileKeys(sequencing: false, powered: true, keys: [])
        #expect(idle.map(\.title) == ["今日", "できれば", "あとで"])
        #expect(idle.allSatisfy { !$0.lit && $0.count.isEmpty })
        let sorting = OpeningPanelTickets.pileKeys(
            sequencing: true,
            powered: true,
            keys: [
                OpeningPanelSequencePicture.Key(id: 0, title: "今日", count: "2", enabled: true),
                OpeningPanelSequencePicture.Key(id: 1, title: "できれば", count: "1", enabled: true),
                OpeningPanelSequencePicture.Key(id: 2, title: "あとで", count: "0", enabled: true),
            ]
        )
        #expect(sorting.map(\.lit) == [true, true, true])
        #expect(sorting.map(\.count) == ["2", "1", "0"])
        let comparing = OpeningPanelTickets.pileKeys(
            sequencing: true,
            powered: true,
            keys: [
                OpeningPanelSequencePicture.Key(id: 0, title: "上が先", count: "", enabled: true),
                OpeningPanelSequencePicture.Key(id: 1, title: "下が先", count: "", enabled: true),
                OpeningPanelSequencePicture.Key(id: 2, title: "", count: "", enabled: false),
            ]
        )
        #expect(comparing.map(\.lit) == [true, true, false])
    }

    @Test func similarRide_staysUnderThreeWhenOnlyOtherTicketsArrived() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let own = Ticket(title: "報告書", estimatedSeconds: 25 * 60, sortOrder: 0)
        let other = Ticket(title: "メール", estimatedSeconds: 10 * 60, sortOrder: 1)
        let sessions = [22, 28, 24].enumerated().map { index, minutes in
            let started = now.addingTimeInterval(-Double((index + 1) * 86_400))
            let session = WorkSession(
                startedAt: started,
                estimatedSecondsAtStart: 25 * 60,
                ticket: own
            )
            session.endedAt = started.addingTimeInterval(Double(minutes * 60))
            session.outcome = .arrived
            session.accumulatedActiveSeconds = Double(minutes * 60)
            return session
        }
        let matched = OpeningPanelTickets.similarRide(ticket: own, sessions: sessions, now: now)
        #expect(matched.count == 3)
        #expect(matched.medianMinutes == 24)
        let unmatched = OpeningPanelTickets.similarRide(ticket: other, sessions: sessions, now: now)
        #expect(unmatched.count < EstimateHeuristic.minimumSampleCount)
        let pair = OpeningPanelTickets.pair(
            estimate: 10,
            similarCount: unmatched.count,
            median: unmatched.medianMinutes
        )
        #expect(pair.median == "--")
    }
}
