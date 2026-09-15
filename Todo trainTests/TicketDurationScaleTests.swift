//
//  TicketDurationScaleTests.swift
//  Todo trainTests
//

import Testing
@testable import Todo_train

struct TicketDurationScaleTests {
    @Test func fiveMinutes_fillsOneCell() {
        let fill = TicketDurationScale.filled(minutes: 5)
        #expect(fill.fullCells == 1)
        #expect(fill.lastFraction == 0)
        #expect(TicketDurationScale.cellFillAmount(index: 0, fill: fill) == 1)
        #expect(TicketDurationScale.cellFillAmount(index: 1, fill: fill) == 0)
    }

    @Test func twentyThreeMinutes_fillsFourCellsAndThreeFifths() {
        let fill = TicketDurationScale.filled(minutes: 23)
        #expect(fill.fullCells == 4)
        #expect(abs(fill.lastFraction - 0.6) < 0.000_1)
        #expect(TicketDurationScale.cellFillAmount(index: 3, fill: fill) == 1)
        #expect(abs(TicketDurationScale.cellFillAmount(index: 4, fill: fill) - 0.6) < 0.000_1)
        #expect(TicketDurationScale.cellFillAmount(index: 5, fill: fill) == 0)
    }

    @Test func sixtyMinutes_fillsEveryCell() {
        let fill = TicketDurationScale.filled(minutes: 60)
        #expect(fill.fullCells == TicketDurationScale.cellCount)
        #expect(fill.lastFraction == 0)
        #expect(TicketDurationScale.cellFillAmount(index: 11, fill: fill) == 1)
    }

    @Test func oneMinute_isPartialFirstCell() {
        let fill = TicketDurationScale.filled(minutes: 1)
        #expect(fill.fullCells == 0)
        #expect(abs(fill.lastFraction - 0.2) < 0.000_1)
        #expect(abs(TicketDurationScale.cellFillAmount(index: 0, fill: fill) - 0.2) < 0.000_1)
    }

    @Test func clampsToOneThroughSixty() {
        #expect(TicketDurationScale.filled(minutes: 0) == TicketDurationScale.filled(minutes: 1))
        #expect(TicketDurationScale.filled(minutes: 90).fullCells == 12)
        #expect(TicketDurationScale.filled(minutes: 90).lastFraction == 0)
        #expect(TicketDurationScale.clampedMinutes(0) == 1)
        #expect(TicketDurationScale.clampedMinutes(90) == 60)
        #expect(TicketDurationScale.unitFraction(minutes: 30) == 0.5)
        #expect(TicketDurationScale.unitFraction(minutes: 0) == TicketDurationScale.unitFraction(minutes: 1))
    }

    @Test func filledExactMinutes_canStartEmptyForReveal() {
        let empty = TicketDurationScale.filled(exactMinutes: 0)
        #expect(empty.fullCells == 0)
        #expect(empty.lastFraction == 0)
        let half = TicketDurationScale.filled(exactMinutes: 2.5)
        #expect(half.fullCells == 0)
        #expect(abs(half.lastFraction - 0.5) < 0.000_1)
    }
}
