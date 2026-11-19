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

    @Test func todayCut_defaultsUnderTheThirdAndFollowsTheRowOrRail() {
        #expect(OpeningPanelTickets.initialCut(count: 5) == 3)
        #expect(OpeningPanelTickets.initialCut(count: 2) == 2)
        #expect(OpeningPanelTickets.initialCut(count: 0) == 0)
        #expect(OpeningPanelTickets.numberOpacity(index: 2, cut: 3) == 1)
        #expect(OpeningPanelTickets.numberOpacity(index: 3, cut: 3) == 0.3)

        let ids = (0..<5).map { _ in UUID() }
        let moved = OpeningPanelTickets.touchRow(
            index: 0,
            ids: ids,
            cut: 3,
            picks: [],
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
            picks: [],
            sequencing: false,
            confirmed: true,
            powered: true,
            departed: false
        )
        #expect(same == .cutStays)

        #expect(OpeningPanelTickets.cut(atRailY: 2, count: 5) == 0)
        #expect(OpeningPanelTickets.cut(atRailY: 2 + 21, count: 5) == 1)
        #expect(OpeningPanelTickets.cut(atRailY: 2 + 21 * 3, count: 5) == 3)
        #expect(OpeningPanelTickets.cut(atRailY: 2 + 10.5, count: 5) == 1)
        #expect(OpeningPanelTickets.cut(atRailY: 400, count: 5) == 5)

        let drag = OpeningPanelTickets.touchRail(
            y: 2 + 21 * 4,
            began: false,
            count: 5,
            cut: 3,
            sequencing: false,
            confirmed: true,
            powered: true,
            departed: false
        )
        #expect(drag == .placeCut(4))
        let blocked = OpeningPanelTickets.touchRail(
            y: 20,
            began: true,
            count: 5,
            cut: 3,
            sequencing: true,
            confirmed: true,
            powered: true,
            departed: false
        )
        #expect(blocked == .reject)
        let beforeConfirm = OpeningPanelTickets.touchRow(
            index: 1,
            ids: ids,
            cut: 3,
            picks: [],
            sequencing: false,
            confirmed: false,
            powered: true,
            departed: false
        )
        #expect(beforeConfirm == .reject)
    }

    @Test func sequencePicks_putChosenFirstAndRejectARepeat() {
        let ids = (0..<5).map { _ in UUID() }
        let first = OpeningPanelTickets.touchRow(
            index: 3,
            ids: ids,
            cut: 3,
            picks: [],
            sequencing: true,
            confirmed: true,
            powered: true,
            departed: false
        )
        #expect(first == .select(ids[3]))
        let again = OpeningPanelTickets.touchRow(
            index: 3,
            ids: ids,
            cut: 3,
            picks: [ids[3]],
            sequencing: true,
            confirmed: true,
            powered: true,
            departed: false
        )
        #expect(again == .duplicate)

        let ordered = OpeningPanelTickets.reorderedIDs(ids, picks: [ids[3], ids[1]])
        #expect(ordered == [ids[3], ids[1], ids[0], ids[2], ids[4]])
        let orders = TicketSortOrdering.normalizedOrders(forOrderedIDs: ordered)
        #expect(orders[ids[3]] == 0)
        #expect(orders[ids[1]] == 1)
        #expect(orders[ids[0]] == 2)
        #expect(OpeningPanelTickets.reorderedIDs(ids, picks: []) == ids)

        #expect(
            OpeningPanelTickets.numberDigit(index: 3, id: ids[3], picks: [ids[3], ids[1]], sequencing: true) == "1"
        )
        #expect(
            OpeningPanelTickets.numberDigit(index: 1, id: ids[1], picks: [ids[3], ids[1]], sequencing: true) == "2"
        )
        #expect(OpeningPanelTickets.numberDigit(index: 0, id: ids[0], picks: [ids[3]], sequencing: true) == nil)
        #expect(OpeningPanelTickets.numberDigit(index: 4, id: ids[4], picks: [], sequencing: false) == "5")
    }

    @Test func commitSequenceOrder_savesHubOrderAndKeepsTheCut() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let tickets = (0..<5).map { index in
            Ticket(title: "切符\(index)", estimatedSeconds: (index + 1) * 600, sortOrder: index)
        }
        tickets.forEach { context.insert($0) }
        let model = OpeningPanelTicketsModel()
        model.sync(tickets: tickets, sessions: [])
        #expect(model.cut == 3)
        #expect(model.rows.map(\.title) == ["切符0", "切符1", "切符2", "切符3", "切符4"])

        model.select(tickets[3].id)
        model.select(tickets[1].id)
        model.placeCut(4)
        model.commitSequenceOrder(in: context)

        #expect(model.picks.isEmpty)
        #expect(model.cut == 4)
        #expect(model.rows.map(\.id) == [
            tickets[3].id, tickets[1].id, tickets[0].id, tickets[2].id, tickets[4].id,
        ])
        #expect(tickets.map(\.sortOrder) == [2, 1, 3, 0, 4])

        model.sync(tickets: tickets, sessions: [])
        #expect(model.rows.map(\.id).first == tickets[3].id)
        #expect(model.cut == 4)

        model.select(tickets[4].id)
        model.dropPicks()
        #expect(model.picks.isEmpty)
        #expect(model.rows.map(\.id).first == tickets[3].id)
        #expect(model.cut == 4)
    }

    @Test func slotNames_runFirstSecondThirdThenNumbers() {
        #expect(OpeningPanelTickets.slotName(index: 0) == "先発")
        #expect(OpeningPanelTickets.slotName(index: 1) == "次発")
        #expect(OpeningPanelTickets.slotName(index: 2) == "次々発")
        #expect(OpeningPanelTickets.slotName(index: 3) == "4")
        #expect(OpeningPanelTickets.slotName(index: 5) == "6")
    }
}
