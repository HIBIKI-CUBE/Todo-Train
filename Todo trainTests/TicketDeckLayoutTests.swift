//
//  TicketDeckLayoutTests.swift
//  Todo trainTests
//

import CoreGraphics
import Testing
@testable import Todo_train

struct TicketDeckLayoutTests {
    @Test func deckSize_followsProposalWidth() {
        let wide = TicketDeckLayout.deckSize(proposalWidth: 900, orderedCount: 3)
        let narrow = TicketDeckLayout.deckSize(proposalWidth: 390, orderedCount: 3)
        let wideFace = TrainLayout.ticketFaceSize(containerWidth: 900)
        let narrowFace = TrainLayout.ticketFaceSize(containerWidth: 390)
        #expect(wide.width == 900)
        #expect(narrow.width == 390)
        #expect(abs(wide.height - TicketStackLayout.totalHeight(orderedCount: 3, faceHeight: wideFace.height)) < 0.5)
        #expect(abs(narrow.height - TicketStackLayout.totalHeight(orderedCount: 3, faceHeight: narrowFace.height)) < 0.5)
        #expect(narrow.width < wide.width)
        #expect(narrow.height < wide.height)
    }

    @Test func deckSize_zeroProposalOrEmptyDeck() {
        #expect(TicketDeckLayout.deckSize(proposalWidth: 0, orderedCount: 3) == .zero)
        #expect(TicketDeckLayout.deckSize(proposalWidth: 390, orderedCount: 0) == .zero)
    }
}
