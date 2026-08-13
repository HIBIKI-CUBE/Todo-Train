//
//  TicketIssueEjectTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

struct TicketIssueEjectTests {
    @Test func presentation_allowsReadableHold() {
        // Issue must be long enough to read the Mars ticket title (~2.5s+).
        #expect(TicketIssueEjectEvent.presentationMilliseconds >= 2_400)
        #expect(TicketIssueEjectEvent.presentationMilliseconds <= 3_600)
        #expect(MarsTicketSpec.IssueMotion.readableHoldMilliseconds >= 1_600)
        #expect(MarsTicketSpec.IssueMotion.slotRotationDegrees == 90)
        #expect(MarsTicketSpec.IssueMotion.ejectMilliseconds >= 400)
    }

    @Test func ejectEvent_storesTitleMinutesAndTags() {
        let event = TicketIssueEjectEvent(title: "メモ", minutes: 15, tagNames: ["仕事"])
        #expect(event.title == "メモ")
        #expect(event.minutes == 15)
        #expect(event.tagNames == ["仕事"])
        #expect(event.ticketContent.title == "メモ")
    }
}
