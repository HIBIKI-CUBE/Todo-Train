//
//  SessionPresentationTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

@MainActor
struct SessionPresentationTests {
    @Test func enqueueOnTimeService_ticksHaptic_consumeDoesNot() {
        let presentation = SessionPresentation()
        presentation.enqueuePunctualityMoment(PunctualityMoment(kind: .onTimeService))
        #expect(presentation.punctualityHapticTick == 1)
        #expect(presentation.punctualityMoment?.kind == .onTimeService)

        presentation.consumePunctualityMoment()
        #expect(presentation.punctualityMoment == nil)
        #expect(presentation.punctualityHapticTick == 1)
    }

    @Test func consumeArrivalCelebrations_keepsOnTimeService() {
        let presentation = SessionPresentation()
        let sessionID = UUID()
        presentation.enqueuePunctualityMoment(
            PunctualityMoment(
                kind: .arrival(
                    title: "A",
                    estimateSeconds: 600,
                    actualSeconds: 600,
                    punctuality: .onTime
                ),
                arrivedSessionID: sessionID
            )
        )
        presentation.enqueuePunctualityMoment(PunctualityMoment(kind: .onTimeService))
        presentation.consumeArrivalCelebrations()
        #expect(presentation.punctualityQueue.count == 1)
        #expect(presentation.punctualityMoment?.kind == .onTimeService)
    }

    @Test func managerPresentation_isSharedSurfaceForViews() throws {
        let (manager, _, _, _) = try SessionManagerFixtures.makeHarness()
        manager.presentation.timetableQuietMessage = TimetableCopy.quiet
        #expect(manager.timetableQuietMessage == TimetableCopy.quiet)
        manager.clearTimetableQuietMessage()
        #expect(manager.presentation.timetableQuietMessage == nil)
    }
}
