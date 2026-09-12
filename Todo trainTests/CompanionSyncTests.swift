import Foundation
import SwiftData
import Testing
import TodoTrainSync
@testable import Todo_train

@MainActor
struct CompanionSnapBuildingTests {
    @Test func idleWhenNoSession() {
        let snap = CompanionSnapBuilding.snap(rev: 1, phase: .idle, session: nil, now: Date())
        #expect(snap.phase == .idle)
        #expect(snap.sessionId == nil)
        #expect(snap.title == nil)
        #expect(snap.rev == 1)
    }

    @Test func runningExportsTitleAndDateBasedRemaining() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let ticket = Ticket(title: "週次レポート", estimatedSeconds: 1500)
        container.mainContext.insert(ticket)
        let started = Date(timeIntervalSince1970: 1_768_000_000)
        let session = WorkSession(
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            startedAt: started,
            estimatedSecondsAtStart: 1500,
            ticket: ticket,
            boardedDeviceID: "phone-a"
        )
        container.mainContext.insert(session)
        let now = Date(timeIntervalSince1970: 1_768_000_060)
        let snap = CompanionSnapBuilding.snap(rev: 7, phase: .running, session: session, now: now)
        #expect(snap.phase == .running)
        #expect(snap.title == "週次レポート")
        #expect(snap.startedAt == 1_768_000_000)
        #expect(snap.estimatedSeconds == 1500)
        #expect(snap.pausedAt == nil)
        #expect(snap.remainingSeconds(at: 1_768_000_060) == 1440)
        #expect(snap.boardedDeviceID == "phone-a")
    }

    @Test func pausedExportsPausedAt() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let ticket = Ticket(title: "停車中", estimatedSeconds: 600)
        container.mainContext.insert(ticket)
        let started = Date(timeIntervalSince1970: 100)
        let session = WorkSession(startedAt: started, estimatedSecondsAtStart: 600, ticket: ticket)
        session.pausedAt = Date(timeIntervalSince1970: 160)
        session.segmentStartedAt = nil
        session.accumulatedActiveSeconds = 60
        container.mainContext.insert(session)
        let snap = CompanionSnapBuilding.snap(
            rev: 2,
            phase: .paused,
            session: session,
            now: Date(timeIntervalSince1970: 180)
        )
        #expect(snap.phase == .paused)
        #expect(snap.pausedAt == 160)
        #expect(snap.pausedAccumulated == 0)
    }
}

struct CompanionCommandApplyingTests {
    @Test func onlyApplyCallsPause() {
        #expect(CompanionCommandApplying.shouldCallPause(.apply, op: .pause))
        #expect(!CompanionCommandApplying.shouldCallPause(.pauseLimitReached, op: .pause))
        #expect(!CompanionCommandApplying.shouldCallPause(.sessionMismatch, op: .pause))
        #expect(!CompanionCommandApplying.shouldCallPause(.noActiveService, op: .pause))
        #expect(!CompanionCommandApplying.shouldCallPause(.apply, op: .resume))
        #expect(CompanionCommandApplying.shouldCallResume(.apply, op: .resume))
        #expect(!CompanionCommandApplying.shouldCallResume(.notPaused, op: .resume))
        #expect(!CompanionCommandApplying.shouldCallResume(.apply, op: .pause))
    }
}

@MainActor
struct CloudKitGateStaysOffTests {
    @Test func companionDoesNotEnableCloudKit() {
        CloudKitSync.isConfiguredOverride = nil
        #expect(!CloudKitSync.isConfigured)
    }
}
