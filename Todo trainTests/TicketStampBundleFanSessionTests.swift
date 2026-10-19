//
//  TicketStampBundleFanSessionTests.swift
//  Todo trainTests
//

import Testing
@testable import Todo_train

@Suite("Ticket stamp bundle fan session")
struct TicketStampBundleFanSessionTests {
    @Test func leavingTheTouchClosesTheFan() {
        let open = TicketStampBundleFanSession.open(touching: true)
        let events: [TicketStampBundleFanSession.Event] = [
            .cancelled,
            .bundleChanged,
            .disappeared,
            .sceneInactive,
            .ended(.vertical),
        ]
        for event in events {
            let next = TicketStampBundleFanSession.reduce(open, event)
            #expect(next == .closed)
        }
    }

    @Test func endedAfterCancelStaysClosed() {
        let open = TicketStampBundleFanSession.open(touching: true)
        let cancelled = TicketStampBundleFanSession.reduce(open, .cancelled)
        #expect(cancelled == .closed)
        let ended = TicketStampBundleFanSession.reduce(cancelled, .ended(.vertical))
        #expect(ended == .closed)
        let again = TicketStampBundleFanSession.reduce(ended, .ended(.horizontal))
        #expect(again == .closed)
        let disappeared = TicketStampBundleFanSession.reduce(again, .disappeared)
        #expect(disappeared == .closed)
    }
}
