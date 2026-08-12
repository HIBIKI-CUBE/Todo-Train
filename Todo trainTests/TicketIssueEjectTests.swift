//
//  TicketIssueEjectTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

struct TicketIssueEjectTests {
    @Test func presentation_isSnappyMicroInteraction() {
        // Micro-interaction band: readable but not a sit-and-wait celebration.
        #expect(TicketIssueEjectEvent.presentationMilliseconds <= 600)
        #expect(TicketIssueEjectEvent.presentationMilliseconds >= 400)
    }

    @Test func ejectEvent_storesTitleAndMinutes() {
        let event = TicketIssueEjectEvent(title: "メモ", minutes: 15)
        #expect(event.title == "メモ")
        #expect(event.minutes == 15)
    }
}
