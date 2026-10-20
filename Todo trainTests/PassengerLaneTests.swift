//
//  PassengerLaneTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

struct PassengerLaneTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func interval(
        id: String = "a",
        title: String = "週次",
        startOffset: TimeInterval = 0,
        duration: TimeInterval = 3600,
        source: PassengerRideSource = .manualInterval,
        cancelled: Bool = false
    ) -> PassengerInterval {
        PassengerInterval(
            id: id,
            title: title,
            startsAt: start.addingTimeInterval(startOffset),
            endsAt: start.addingTimeInterval(startOffset + duration),
            source: source,
            isCancelled: cancelled
        )
    }

    private func resolve(
        _ intervals: [PassengerInterval],
        at offset: TimeInterval,
        ride: PassengerRideSnapshot? = nil,
        memory: PassengerLaneMemory = .empty,
        ticketRunning: Bool = false
    ) -> PassengerLaneEffect {
        PassengerLane.resolve(
            intervals: intervals,
            openRide: ride,
            now: start.addingTimeInterval(offset),
            memory: memory,
            ticketRunning: ticketRunning
        )
    }

    @Test func eligibilityDropsCalendarWithoutPermissionAndKeepsManual() {
        let blocks = [
            PassengerBlockInput(
                id: "cal",
                title: "会議",
                startsAt: start,
                endsAt: start.addingTimeInterval(1800),
                source: .adoptedBlock,
                isCancelled: false
            ),
            PassengerBlockInput(
                id: "hand",
                title: "枠",
                startsAt: start,
                endsAt: start.addingTimeInterval(1800),
                source: .manualInterval,
                isCancelled: false
            ),
            PassengerBlockInput(
                id: "flat",
                title: "ゼロ",
                startsAt: start,
                endsAt: start,
                source: .manualInterval,
                isCancelled: false
            ),
        ]
        let hidden = PassengerEligibility.intervals(from: blocks, calendarAuthorized: false)
        #expect(hidden.map(\.id) == ["hand"])
        let shown = PassengerEligibility.intervals(from: blocks, calendarAuthorized: true)
        #expect(shown.map(\.id) == ["cal", "hand"])
    }

    @Test func noIntervalsMeansNoHubOfferChrome() {
        let effect = resolve([], at: 0)
        #expect(effect.chrome == .none)
        #expect(!effect.chrome.showsHubOffer)
    }

    @Test func showsHubOfferOnlyForSoonOrOffer() {
        let meeting = interval()
        let offer = resolve([meeting], at: 0)
        guard case .offer = offer.chrome else {
            Issue.record("expected offer")
            return
        }
        #expect(offer.chrome.showsHubOffer)

        let soon = resolve([interval(startOffset: 120)], at: 0)
        guard case .soon = soon.chrome else {
            Issue.record("expected soon")
            return
        }
        #expect(soon.chrome.showsHubOffer)
        #expect(!PassengerChrome.none.showsHubOffer)
    }

    @Test func oneOfferAtStartAndNoAutomaticAboard() {
        #expect(!PassengerLane.boardsAutomatically)
        let effect = resolve([interval()], at: 0)
        guard case .offer(let offered, let collapsed) = effect.chrome else {
            Issue.record("expected a single offer")
            return
        }
        #expect(offered.id == "a")
        #expect(!collapsed)
        #expect(effect.close == nil)
    }

    @Test func ignoreCreatesNoRideAndLateOpenStillBoardsUntilEnd() {
        let meeting = interval()
        let first = resolve([meeting], at: 0)
        let collapsed = resolve([meeting], at: PassengerLane.collapseDelay, memory: first.memory)
        guard case .offer(_, true) = collapsed.chrome else {
            Issue.record("expected the collapsed band")
            return
        }
        let late = resolve([meeting], at: 600)
        guard case .offer(let offered, false) = late.chrome else {
            Issue.record("a late open starts prominent")
            return
        }
        #expect(offered.id == "a")
        let after = resolve([meeting], at: 3600)
        #expect(after.chrome == .none)
    }

    @Test func overlappingKeepsTheEarlierDepartureOnly() {
        let effect = resolve(
            [
                interval(id: "later", startOffset: 60),
                interval(id: "earlier", startOffset: 0),
            ],
            at: 120
        )
        guard case .offer(let offered, _) = effect.chrome else {
            Issue.record("expected one offer")
            return
        }
        #expect(offered.id == "earlier")
    }

    @Test func soonBandHasNoBoardAndNotifiesOnce() {
        let meeting = interval(startOffset: 120)
        let first = resolve([meeting], at: 0)
        guard case .soon(let soon) = first.chrome else {
            Issue.record("expected まもなく")
            return
        }
        #expect(soon.id == "a")
        guard case .schedule(let id, _, let fireAt) = first.notify else {
            Issue.record("expected one notification")
            return
        }
        #expect(id == "a")
        #expect(fireAt == meeting.startsAt)
        let again = resolve([meeting], at: 30, memory: first.memory)
        #expect(again.notify == .none)
    }

    @Test func runningTicketFoldsTheNotificationIntoATS() {
        let meeting = interval(startOffset: 120)
        let effect = resolve([meeting], at: 0, ticketRunning: true)
        guard case .soon = effect.chrome else {
            Issue.record("expected the soon band")
            return
        }
        #expect(effect.notify == .none)
    }

    @Test func boardingStampsTapTimeAndEndReasonsStayDistinct() {
        let meeting = interval()
        let boarded = PassengerLane.ride(
            on: meeting,
            now: start.addingTimeInterval(90),
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            deviceID: "phone"
        )
        #expect(boarded.boardedAt == start.addingTimeInterval(90))
        #expect(boarded.endedAt == nil)
        #expect(boarded.source == .manualInterval)

        let riding = resolve([meeting], at: 90, ride: boarded)
        guard case .aboard(let ride, let phrase, _) = riding.chrome else {
            Issue.record("expected aboard")
            return
        }
        #expect(ride.id == boarded.id)
        #expect(phrase == .next)
        #expect(riding.close == nil)

        let nearEnd = resolve([meeting], at: 3600 - 60, ride: boarded)
        guard case .aboard(_, .soon, _) = nearEnd.chrome else {
            Issue.record("expected まもなく near the end")
            return
        }

        let arrived = resolve([meeting], at: 3600, ride: boarded)
        #expect(arrived.close?.reason == .arrived)
        guard case .arrived(let ended) = arrived.chrome else {
            Issue.record("expected the short ただいま")
            return
        }
        #expect(ended.endReason == .arrived)

        let stillGreeting = resolve(
            [meeting],
            at: 3600 + 1,
            memory: arrived.memory
        )
        guard case .arrived = stillGreeting.chrome else {
            Issue.record("greeting should hold")
            return
        }
        let done = resolve(
            [meeting],
            at: 3600 + PassengerLane.arrivedGreeting,
            memory: arrived.memory
        )
        #expect(done.chrome == .none)

        let opened = PassengerLane.emergency(ride: boarded, now: start.addingTimeInterval(200))
        #expect(opened.ride.endReason == .emergency)
        #expect(opened.ride.id == boarded.id)
    }

    @Test func emergencyThenReofferWhileTheIntervalContinues() {
        let meeting = interval()
        let boarded = PassengerLane.ride(on: meeting, now: start, id: UUID(), deviceID: nil)
        let opened = PassengerLane.emergency(ride: boarded, now: start.addingTimeInterval(30))
        var memory = PassengerLaneMemory.empty
        memory.greeting = opened.greeting
        let showing = resolve([meeting], at: 30, memory: memory)
        guard case .doorOpened(let ride) = showing.chrome else {
            Issue.record("expected the door line")
            return
        }
        #expect(ride.endReason == .emergency)
        let again = resolve(
            [meeting],
            at: 30 + PassengerLane.doorOpenedGreeting,
            memory: memory
        )
        guard case .offer(let offered, false) = again.chrome else {
            Issue.record("expected a fresh offer")
            return
        }
        #expect(offered.id == meeting.id)
    }

    @Test func cancellationClosesTheRideAndDropsTheOffer() {
        let meeting = interval(cancelled: true)
        let boarded = PassengerLane.ride(on: meeting, now: start, id: UUID(), deviceID: nil)
        let closed = resolve([meeting], at: 10, ride: boarded)
        #expect(closed.close?.reason == .cancelled)
        #expect(closed.chrome == .none)

        let ignored = resolve([meeting], at: 10)
        #expect(ignored.chrome == .none)
        #expect(ignored.close == nil)
    }

    @Test func followMovesTheEndAndDoesNotInventASecondRide() {
        var meeting = interval()
        let boarded = PassengerLane.ride(on: meeting, now: start, id: UUID(), deviceID: nil)
        meeting.endsAt = start.addingTimeInterval(1200)
        meeting.title = "延びた週次"
        let followed = resolve([meeting], at: 60, ride: boarded)
        #expect(followed.follow?.endsAt == meeting.endsAt)
        #expect(followed.follow?.title == "延びた週次")
        #expect(followed.close == nil)
        guard case .aboard(let ride, _, _) = followed.chrome else {
            Issue.record("still aboard")
            return
        }
        #expect(ride.id == boarded.id)
        #expect(ride.intervalEnd == meeting.endsAt)
    }

    @Test func surfaceCopyAvoidsTicketWords() {
        let forbidden = ["切符", "発車", "停車", "再乗車", "途中下車", "発券", "マルス"]
        for line in PassengerCopy.surfaceLines {
            for word in forbidden {
                #expect(!line.contains(word))
            }
        }
    }
}
