//
//  TimetableGuardLogicTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

struct TimetableGuardLogicTests {
    private let sessionID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let blockID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    @Test func userPauseBeforeStart_createsNothing() {
        let start = Date(timeIntervalSince1970: 1_800_014_000)
        let ride = running(from: start.addingTimeInterval(-2400), now: start.addingTimeInterval(-2))
        let effects = TimetableGuardLogic.effects(
            ride: ride,
            blocks: [meeting(start: start)],
            guards: [],
            now: start.addingTimeInterval(-2)
        )
        #expect(effects.isEmpty)
    }

    @Test func atStart_armsGuard() {
        let start = Date(timeIntervalSince1970: 1_800_014_000)
        let ride = running(from: start.addingTimeInterval(-2400), now: start)
        let effects = TimetableGuardLogic.effects(
            ride: ride,
            blocks: [meeting(start: start)],
            guards: [],
            now: start
        )
        #expect(effects == [
            .arm(
                blockID: blockID,
                notifiedAt: start,
                protectionBoundary: start.addingTimeInterval(60)
            )
        ])
    }

    @Test func alreadyArmed_staysQuietUntilGrace() {
        let start = Date(timeIntervalSince1970: 1_800_014_000)
        let ride = running(from: start.addingTimeInterval(-2400), now: start.addingTimeInterval(35))
        let guardRecord = stored(notifiedAt: start)
        let effects = TimetableGuardLogic.effects(
            ride: ride,
            blocks: [meeting(start: start)],
            guards: [guardRecord],
            now: start.addingTimeInterval(35)
        )
        #expect(effects.isEmpty)
    }

    @Test func afterGrace_pausesAtBoundary() {
        let start = Date(timeIntervalSince1970: 1_800_014_000)
        let ride = running(from: start.addingTimeInterval(-2400), now: start.addingTimeInterval(90))
        let guardRecord = stored(notifiedAt: start)
        let effects = TimetableGuardLogic.effects(
            ride: ride,
            blocks: [meeting(start: start)],
            guards: [guardRecord],
            now: start.addingTimeInterval(90)
        )
        #expect(effects == [
            .pause(at: start.addingTimeInterval(60), guardID: guardRecord.id, blockID: blockID)
        ])
    }

    @Test func lateReturnWithoutGuard_stillPausesAtBoundary() {
        let start = Date(timeIntervalSince1970: 1_800_014_000)
        let ride = running(from: start.addingTimeInterval(-2400), now: start.addingTimeInterval(30 * 60))
        let effects = TimetableGuardLogic.effects(
            ride: ride,
            blocks: [meeting(start: start)],
            guards: [],
            now: start.addingTimeInterval(30 * 60)
        )
        #expect(effects == [
            .pause(at: start.addingTimeInterval(60), guardID: nil, blockID: blockID)
        ])
    }

    @Test func userPaused_resolvesOpenGuard() {
        let start = Date(timeIntervalSince1970: 1_800_014_000)
        var ride = running(from: start.addingTimeInterval(-2400), now: start.addingTimeInterval(35))
        ride.isPaused = true
        let guardRecord = stored(notifiedAt: start)
        let effects = TimetableGuardLogic.effects(
            ride: ride,
            blocks: [meeting(start: start)],
            guards: [guardRecord],
            now: start.addingTimeInterval(35)
        )
        #expect(effects == [.resolve(guardID: guardRecord.id)])
    }

    @Test func arrived_invalidatesGuard() {
        let start = Date(timeIntervalSince1970: 1_800_014_000)
        var ride = running(from: start.addingTimeInterval(-2400), now: start.addingTimeInterval(10))
        ride.isOpen = false
        ride.endedAt = start.addingTimeInterval(10)
        let guardRecord = stored(notifiedAt: start)
        let effects = TimetableGuardLogic.effects(
            ride: ride,
            blocks: [meeting(start: start)],
            guards: [guardRecord],
            now: start.addingTimeInterval(90)
        )
        #expect(effects == [.invalidate(guardID: guardRecord.id)])
    }

    @Test func boardedDuringBlock_doesNotArm() {
        let start = Date(timeIntervalSince1970: 1_800_014_000)
        let ride = running(from: start.addingTimeInterval(120), now: start.addingTimeInterval(180))
        let effects = TimetableGuardLogic.effects(
            ride: ride,
            blocks: [meeting(start: start)],
            guards: [],
            now: start.addingTimeInterval(180)
        )
        #expect(effects.isEmpty)
    }

    @Test func cancelledBlock_doesNotArm() {
        let start = Date(timeIntervalSince1970: 1_800_014_000)
        let ride = running(from: start.addingTimeInterval(-2400), now: start.addingTimeInterval(90))
        let effects = TimetableGuardLogic.effects(
            ride: ride,
            blocks: [meeting(start: start, cancelled: true)],
            guards: [],
            now: start.addingTimeInterval(90)
        )
        #expect(effects.isEmpty)
    }

    @Test func consecutiveBlocks_doNotStackWhilePaused() {
        let first = Date(timeIntervalSince1970: 1_800_014_000)
        let second = first.addingTimeInterval(30 * 60)
        var ride = running(from: first.addingTimeInterval(-2400), now: first.addingTimeInterval(90))
        ride.isPaused = true
        let effects = TimetableGuardLogic.effects(
            ride: ride,
            blocks: [meeting(start: first), meeting(id: blockID, start: second)],
            guards: [stored(notifiedAt: first)],
            now: second
        )
        #expect(effects == [.resolve(guardID: stored(notifiedAt: first).id)])
    }

    @Test func suppressAway_nearAdoptedBlock() {
        let start = Date(timeIntervalSince1970: 1_800_014_000)
        let blocks = [meeting(start: start)]
        #expect(TimetableGuardLogic.shouldSuppressAway(blocks: blocks, now: start.addingTimeInterval(-90)))
        #expect(!TimetableGuardLogic.shouldSuppressAway(blocks: blocks, now: start.addingTimeInterval(-8 * 60)))
        #expect(!TimetableGuardLogic.shouldSuppressAway(blocks: blocks, now: start.addingTimeInterval(31 * 60)))
    }

    private func running(from startedAt: Date, now: Date) -> TimetableGuardLogic.Ride {
        TimetableGuardLogic.Ride(
            sessionID: sessionID,
            startedAt: startedAt,
            segmentStartedAt: startedAt,
            isOpen: true,
            isPaused: false,
            endedAt: nil
        )
    }

    private func meeting(
        id: UUID? = nil,
        start: Date,
        cancelled: Bool = false
    ) -> TimetableFit.Block {
        TimetableFit.Block(
            id: id ?? blockID,
            title: "1on1",
            startsAt: start,
            endsAt: start.addingTimeInterval(30 * 60),
            isCancelled: cancelled
        )
    }

    private func stored(notifiedAt: Date) -> TimetableGuardLogic.StoredGuard {
        TimetableGuardLogic.StoredGuard(
            id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            sessionID: sessionID,
            blockID: blockID,
            notifiedAt: notifiedAt,
            protectionBoundary: notifiedAt.addingTimeInterval(60),
            resolvedAt: nil,
            invalidatedAt: nil
        )
    }
}
