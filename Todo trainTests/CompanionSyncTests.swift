import Foundation
import SwiftData
import Testing
import TodoTrainSync
@testable import Todo_train

@MainActor
struct CompanionSnapBuildingTests {
    @Test func idleWhenNoSession() {
        let snap = CompanionSnapBuilding.snap(
            rev: 1,
            phase: .idle,
            session: nil,
            now: Date(),
            serviceActive: false,
            cabinEnabled: true
        )
        #expect(snap.phase == .idle)
        #expect(snap.sessionId == nil)
        #expect(snap.title == nil)
        #expect(snap.rev == 1)
        #expect(snap.serviceActive == false)
        #expect(snap.cabinEnabled == true)
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
        let snap = CompanionSnapBuilding.snap(
            rev: 7,
            phase: .running,
            session: session,
            now: now,
            serviceActive: true,
            cabinEnabled: true
        )
        #expect(snap.phase == .running)
        #expect(snap.title == "週次レポート")
        #expect(snap.startedAt == 1_768_000_000)
        #expect(snap.estimatedSeconds == 1500)
        #expect(snap.pausedAt == nil)
        #expect(snap.remainingSeconds(at: 1_768_000_060) == 1440)
        #expect(snap.boardedDeviceID == "phone-a")
        #expect(snap.serviceActive == true)
        #expect(snap.checkInFiredCount == 0)
        #expect(snap.pendingCabin == nil)
    }

    @Test func idleExportsPendingCabin() {
        let snap = CompanionSnapBuilding.idle(
            rev: 4,
            serviceActive: true,
            cabinEnabled: true,
            pendingCabin: .idle
        )
        #expect(snap.phase == .idle)
        #expect(snap.sessionId == nil)
        #expect(snap.pendingCabin == .idle)
        #expect(snap.checkInFiredCount == 0)
        #expect(snap.serviceActive == true)
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
            now: Date(timeIntervalSince1970: 180),
            serviceActive: true,
            cabinEnabled: true
        )
        #expect(snap.phase == .paused)
        #expect(snap.pausedAt == 160)
        #expect(snap.pausedAccumulated == 0)
        #expect(snap.pauseHeldBy == nil)
        let bare = try JSONSerialization.jsonObject(with: try jsonData(snap)) as! [String: Any]
        #expect(bare["pauseHeldBy"] == nil)

        let record = SessionPause(startedAt: Date(timeIntervalSince1970: 160), session: session)
        record.heldBy = .user
        record.pausedOn = .iphone
        container.mainContext.insert(record)
        try container.mainContext.save()
        let withReason = CompanionSnapBuilding.snap(
            rev: 3,
            phase: .paused,
            session: session,
            now: Date(timeIntervalSince1970: 180),
            serviceActive: true,
            cabinEnabled: true
        )
        #expect(withReason.pauseHeldBy == .user)
        let object = try JSONSerialization.jsonObject(with: try jsonData(withReason)) as! [String: Any]
        #expect(object["pauseHeldBy"] as? String == "user")

        let running = CompanionSnapBuilding.snap(
            rev: 4,
            phase: .running,
            session: session,
            now: Date(timeIntervalSince1970: 180),
            serviceActive: true,
            cabinEnabled: true
        )
        #expect(running.pauseHeldBy == nil)
        let runningObject = try JSONSerialization.jsonObject(with: try jsonData(running)) as! [String: Any]
        #expect(runningObject["pauseHeldBy"] == nil)
    }

    private func jsonData(_ snap: SnapPlaintext) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snap)
    }
}

@MainActor
struct CloudKitGateStaysOffTests {
    @Test func companionDoesNotEnableCloudKit() {
        CloudKitSync.isConfiguredOverride = nil
        #expect(!CloudKitSync.isConfigured)
    }
}
