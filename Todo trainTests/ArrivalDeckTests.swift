//
//  ArrivalDeckTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

struct ArrivalDeckTests {
    private let reserved = ArrivalTicketFace(id: UUID(), title: "予約", minutes: 25)
    private let other = ArrivalTicketFace(id: UUID(), title: "別", minutes: 10)
    private let instant = ArrivalTicketFace(id: UUID(), title: "即時", minutes: 15)

    @Test func reservedArrival_canStampImmediately() {
        let deck = ArrivalDeck(reserved: reserved)
        #expect(deck.canStamp)
        #expect(deck.destination?.action == .nextRide)
        #expect(deck.destination?.face.id == reserved.id)
        #expect(deck.stampedFace == nil)
    }

    @Test func missingReservation_isEmptyAndCannotStamp() {
        let deck = ArrivalDeck(reserved: nil)
        #expect(deck.reserved == nil)
        #expect(deck.destination == nil)
        #expect(!deck.canStamp)
        #expect(deck.stampSelection() == nil)
    }

    @Test func otherAndInstant_enableStamp_andPickerDismissKeepsArrival() {
        var deck = ArrivalDeck(reserved: nil)
        deck.showOtherTickets()
        #expect(deck.picker == .otherTickets)
        #expect(!deck.canStamp)
        deck.dismissPicker()
        #expect(deck.picker == nil)
        #expect(deck.destination == nil)
        #expect(!deck.canStamp)

        deck.selectOther(other)
        #expect(deck.canStamp)
        #expect(deck.stampSelection()?.action == .otherTicket)
        #expect(deck.stampSelection()?.face.id == other.id)

        deck.showInstant()
        #expect(!deck.canStamp)
        deck.dismissPicker()
        #expect(deck.destination?.face.id == other.id)
        #expect(deck.canStamp)

        deck.selectInstant(instant)
        #expect(deck.stampSelection()?.action == .instantTicket)
    }

    @Test func stamp_recordsTheChoice_andDoesNotClearItIntoARide() {
        var deck = ArrivalDeck(reserved: reserved)
        let selection = deck.stampSelection()
        #expect(selection?.action == .nextRide)
        deck.markStamped()
        #expect(deck.stampedFace?.id == reserved.id)
        #expect(!deck.canStamp)
        #expect(deck.stampSelection() == nil)
    }

    @Test func otherTicket_cannotBeTheReservedTicket() {
        var deck = ArrivalDeck(reserved: reserved)
        deck.selectOther(reserved)
        #expect(deck.destination?.action == .nextRide)
        #expect(deck.destination?.face.id == reserved.id)
    }

    @Test func leadingSwipe_afterStamp_isTheOnlyBoard() {
        var deck = ArrivalDeck(reserved: reserved)
        #expect(deck.boardTicketID(
            translation: CGSize(width: 180, height: 0),
            predictedEnd: CGSize(width: 200, height: 0),
            leadingIsPositiveX: true
        ) == nil)

        deck.markStamped()
        #expect(deck.boardTicketID(
            translation: CGSize(width: 180, height: 10),
            predictedEnd: CGSize(width: 220, height: 10),
            leadingIsPositiveX: true
        ) == reserved.id)
        #expect(deck.boardTicketID(
            translation: CGSize(width: 40, height: 0),
            predictedEnd: CGSize(width: 40, height: 0),
            leadingIsPositiveX: true
        ) == nil)
        #expect(deck.boardTicketID(
            translation: CGSize(width: -180, height: 0),
            predictedEnd: CGSize(width: -200, height: 0),
            leadingIsPositiveX: true
        ) == nil)
        #expect(deck.boardTicketID(
            translation: CGSize(width: -180, height: 0),
            predictedEnd: CGSize(width: -220, height: 0),
            leadingIsPositiveX: false
        ) == reserved.id)
    }

    @Test func choosingAnother_thenReturningToNextRide() {
        var deck = ArrivalDeck(reserved: reserved)
        deck.selectOther(other)
        #expect(deck.destination?.action == .otherTicket)
        deck.selectNextRide()
        #expect(deck.destination?.action == .nextRide)
        #expect(deck.destination?.face.id == reserved.id)
    }
}
