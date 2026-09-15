//
//  TimetableGuardLogicTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

@MainActor
struct TimetableGuardLogicTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let sessionID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

    private func block(
        id: UUID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
        startOffset: TimeInterval,
        duration: TimeInterval = 1800,
        cancelled: Bool = false
    ) -> TimetableGuardBlock {
        TimetableGuardBlock(
            id: id,
            startsAt: now.addingTimeInterval(startOffset),
            endsAt: now.addingTimeInterval(startOffset + duration),
            isCancelled: cancelled
        )
    }

    @Test func pauseBeforeStart_doesNotArm() {
        let meeting = block(startOffset: 300)
        let effect = TimetableGuardLogic.evaluate(
            ride: .paused(sessionID: sessionID),
            blocks: [meeting],
            openGuard: nil,
            now: now
        )
        #expect(effect == .none)
    }

    @Test func overlapArmsFromSegmentStart() {
        let meeting = block(startOffset: 0)
        let effect = TimetableGuardLogic.evaluate(
            ride: .running(sessionID: sessionID, segmentStart: now.addingTimeInterval(-120)),
            blocks: [meeting],
            openGuard: nil,
            now: now
        )
        #expect(
            effect == .arm(
                blockID: meeting.id,
                notifiedAt: now,
                protectionBoundary: now.addingTimeInterval(60)
            )
        )
    }

    @Test func boardDuringMeeting_graceFromSegment() {
        let meeting = block(startOffset: -600)
        let segment = now
        let effect = TimetableGuardLogic.evaluate(
            ride: .running(sessionID: sessionID, segmentStart: segment),
            blocks: [meeting],
            openGuard: nil,
            now: now
        )
        #expect(
            effect == .arm(
                blockID: meeting.id,
                notifiedAt: now,
                protectionBoundary: segment.addingTimeInterval(60)
            )
        )
    }

    @Test func cancelledBlock_doesNotArm() {
        let meeting = block(startOffset: -60, cancelled: true)
        let effect = TimetableGuardLogic.evaluate(
            ride: .running(sessionID: sessionID, segmentStart: now.addingTimeInterval(-120)),
            blocks: [meeting],
            openGuard: nil,
            now: now
        )
        #expect(effect == .none)
    }

    @Test func afterGrace_pausesAtBoundary() {
        let meeting = block(startOffset: -60)
        let boundary = now
        let open = TimetableOpenGuard(
            id: UUID(),
            sessionID: sessionID,
            blockID: meeting.id,
            notifiedAt: now.addingTimeInterval(-60),
            protectionBoundary: boundary
        )
        let effect = TimetableGuardLogic.evaluate(
            ride: .running(sessionID: sessionID, segmentStart: now.addingTimeInterval(-120)),
            blocks: [meeting],
            openGuard: open,
            now: now.addingTimeInterval(1)
        )
        #expect(effect == .pauseAt(boundary))
    }

    @Test func noOpenGuardPastBoundary_stillPauses() {
        let meeting = block(startOffset: -120)
        let segment = now.addingTimeInterval(-180)
        let boundary = TimetableGuardLogic.protectionBoundary(
            blockStart: meeting.startsAt,
            segmentStart: segment
        )
        let effect = TimetableGuardLogic.evaluate(
            ride: .running(sessionID: sessionID, segmentStart: segment),
            blocks: [meeting],
            openGuard: nil,
            now: now
        )
        #expect(effect == .pauseAt(boundary))
    }

    @Test func paused_resolvesOpenGuard() {
        let open = TimetableOpenGuard(
            id: UUID(),
            sessionID: sessionID,
            blockID: UUID(),
            notifiedAt: now,
            protectionBoundary: now.addingTimeInterval(60)
        )
        let effect = TimetableGuardLogic.evaluate(
            ride: .paused(sessionID: sessionID),
            blocks: [block(startOffset: -10)],
            openGuard: open,
            now: now
        )
        #expect(effect == .resolve)
    }

    @Test func arrived_invalidates() {
        let open = TimetableOpenGuard(
            id: UUID(),
            sessionID: sessionID,
            blockID: UUID(),
            notifiedAt: now,
            protectionBoundary: now.addingTimeInterval(60)
        )
        let effect = TimetableGuardLogic.evaluate(
            ride: .arrived(sessionID: sessionID),
            blocks: [block(startOffset: -10)],
            openGuard: open,
            now: now
        )
        #expect(effect == .invalidate)
    }

    @Test func unadoptedOverlap_invalidatesGuard() {
        let meeting = block(startOffset: -10, cancelled: true)
        let open = TimetableOpenGuard(
            id: UUID(),
            sessionID: sessionID,
            blockID: meeting.id,
            notifiedAt: now.addingTimeInterval(-5),
            protectionBoundary: now.addingTimeInterval(55)
        )
        let effect = TimetableGuardLogic.evaluate(
            ride: .running(sessionID: sessionID, segmentStart: now.addingTimeInterval(-30)),
            blocks: [meeting],
            openGuard: open,
            now: now
        )
        #expect(effect == .invalidate)
    }
}
