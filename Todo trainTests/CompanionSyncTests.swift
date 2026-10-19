import Foundation
import SwiftData
import SwiftUI
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
        record.macSampledSeconds = 300
        record.macActiveSeconds = 270
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
        #expect(withReason.pauseId == record.id)
        let object = try JSONSerialization.jsonObject(with: try jsonData(withReason)) as! [String: Any]
        #expect(withReason.macSampledSeconds == 300)
        #expect(withReason.macActiveSeconds == 270)
        #expect(object["pauseHeldBy"] as? String == "user")
        #expect(object["pauseId"] as? String == record.id.uuidString.lowercased())
        #expect(object["macSampledSeconds"] as? Int == 300)
        #expect(object["macActiveSeconds"] as? Int == 270)

        let running = CompanionSnapBuilding.snap(
            rev: 4,
            phase: .running,
            session: session,
            now: Date(timeIntervalSince1970: 180),
            serviceActive: true,
            cabinEnabled: true
        )
        #expect(running.pauseHeldBy == nil)
        #expect(running.pauseId == nil)
        #expect(running.macSampledSeconds == nil)
        let runningObject = try JSONSerialization.jsonObject(with: try jsonData(running)) as! [String: Any]
        #expect(runningObject["pauseHeldBy"] == nil)
        #expect(runningObject["pauseId"] == nil)
        #expect(runningObject["macSampledSeconds"] == nil)
    }

    private func jsonData(_ snap: SnapPlaintext) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snap)
    }

    @Test func idleOmitsHomeEvenWhenAClosedSessionIsPassed() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let ticket = Ticket(title: "閉じた", estimatedSeconds: 1500)
        container.mainContext.insert(ticket)
        let session = WorkSession(startedAt: Date(timeIntervalSince1970: 100), estimatedSecondsAtStart: 1500, ticket: ticket)
        session.endedAt = Date(timeIntervalSince1970: 200)
        container.mainContext.insert(session)
        let idle = CompanionSnapBuilding.snap(
            rev: 1,
            phase: .idle,
            session: session,
            now: Date(timeIntervalSince1970: 200),
            serviceActive: true,
            cabinEnabled: true
        )
        #expect(idle.home == nil)
        let object = try JSONSerialization.jsonObject(with: try jsonData(idle)) as! [String: Any]
        #expect(object["home"] == nil)
    }

    @Test func homeBandBeforeInsideAndPastTheEstimate() throws {
        let before = try ridingSnap(estimate: 1800, active: 500)
        let inside = try ridingSnap(estimate: 1800, active: 1700)
        let past = try ridingSnap(estimate: 1800, active: 2100)

        #expect(before.home?.signal == .green)
        #expect(inside.home?.signal == .yellow)
        #expect(past.home?.signal == .off)
        #expect(before.home?.judgedEstimate.kind == .original)
        #expect(before.home?.sealLuxury == 1)
        #expect(inside.home?.sealLuxury == 1)
        #expect(past.home?.sealLuxury == nil)

        let band = judgment(estimate: 1800, active: 500)
        #expect(before.home?.startSeconds == band.lowerBound)
        #expect(inside.home?.endSeconds == band.upperBound)
        #expect(before.home?.startSeconds == 1530)
        #expect(before.home?.endSeconds == 2070)

        let pastObject = try JSONSerialization.jsonObject(with: try jsonData(past)) as! [String: Any]
        let pastHome = try #require(pastObject["home"] as? [String: Any])
        #expect(pastHome["sealLuxury"] == nil)
        #expect(pastHome["signal"] as? String == "off")
    }

    @Test func homeAfterReestimateUsesThatCommit() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let ticket = Ticket(title: "見積もり直し", estimatedSeconds: 1800)
        container.mainContext.insert(ticket)
        let session = WorkSession(
            startedAt: Date(timeIntervalSince1970: 1_000),
            estimatedSecondsAtStart: 1800,
            ticket: ticket
        )
        session.segmentStartedAt = nil
        session.accumulatedActiveSeconds = 900
        session.reestimateEvents = [
            ReestimateEventRecord(
                reestimateIndex: 2,
                trigger: .manual,
                surface: .macPip,
                input: .click,
                promptId: ReestimatePromptID.progressV1,
                mode: .progress,
                committedAt: Date(timeIntervalSince1970: 1_800),
                activeSeconds: 800,
                overrunSeconds: 0,
                progressAnswer: 0.5,
                committedRemainingSeconds: 1000,
                shownBandLowSeconds: nil,
                shownBandHighSeconds: nil,
                detailsOpened: false
            ),
        ]
        container.mainContext.insert(session)
        let now = Date(timeIntervalSince1970: 2_000)
        let snap = CompanionSnapBuilding.snap(
            rev: 8,
            phase: .running,
            session: session,
            now: now,
            serviceActive: true,
            cabinEnabled: true
        )
        let judgment = PunctualityJudgment.judge(
            PunctualityJudgment.RideInput(
                arrived: false,
                activeSeconds: 900,
                estimatedSecondsAtStart: 1800,
                reestimates: [
                    PunctualityJudgment.ReestimateCommit(
                        reestimateIndex: 2,
                        activeSeconds: 800,
                        committedRemainingSeconds: 1000
                    ),
                ]
            )
        )
        let home = try #require(snap.home)
        #expect(home.signal == judgment.signal)
        #expect(home.signal == .green)
        #expect(home.startSeconds == judgment.lowerBound)
        #expect(home.endSeconds == judgment.upperBound)
        #expect(home.judgedEstimate.kind == .reestimate)
        #expect(home.judgedEstimate.reestimateIndex == 2)
        #expect(home.judgedEstimate.activeSeconds == 800)
        #expect(home.sealLuxury == PunctualityJudgment.sealLuxury(
            source: .reestimate(index: 2),
            reestimates: [
                PunctualityJudgment.ReestimateCommit(
                    reestimateIndex: 2,
                    activeSeconds: 800,
                    committedRemainingSeconds: 1000
                ),
            ]
        ))
        let object = try JSONSerialization.jsonObject(with: try jsonData(snap)) as! [String: Any]
        let judged = try #require((object["home"] as? [String: Any])?["judgedEstimate"] as? [String: Any])
        #expect(judged["kind"] as? String == "reestimate")
        #expect(judged["reestimateIndex"] as? Int == 2)
        #expect(judged["activeSeconds"] as? Int == 800)
    }

    private func ridingSnap(estimate: Int, active: TimeInterval) throws -> SnapPlaintext {
        let container = try AppModelContainer.make(inMemory: true)
        let ticket = Ticket(title: "走行", estimatedSeconds: estimate)
        container.mainContext.insert(ticket)
        let session = WorkSession(
            startedAt: Date(timeIntervalSince1970: 1_000),
            estimatedSecondsAtStart: estimate,
            ticket: ticket
        )
        session.segmentStartedAt = nil
        session.accumulatedActiveSeconds = active
        container.mainContext.insert(session)
        return CompanionSnapBuilding.snap(
            rev: 1,
            phase: .running,
            session: session,
            now: Date(timeIntervalSince1970: 2_000),
            serviceActive: true,
            cabinEnabled: true
        )
    }

    private func judgment(estimate: Int, active: TimeInterval) -> PunctualityJudgment.Judgment {
        PunctualityJudgment.judge(
            PunctualityJudgment.RideInput(
                arrived: false,
                activeSeconds: active,
                estimatedSecondsAtStart: estimate
            )
        )
    }
}

@MainActor
struct CompanionSyncPolicyTests {
    @Test func pairingAndScenePhaseDecideNotificationsAndTheForegroundLoop() {
        let phases: [ScenePhase] = [.active, .inactive, .background]
        let pairedStates = [false, true]
        for paired in pairedStates {
            for phase in phases {
                #expect(
                    CompanionSyncRuntime.Policy.suppressProgressNotifications(isPaired: paired) == paired
                )
                let loop = CompanionSyncRuntime.Policy.foregroundLoop(for: phase)
                switch phase {
                case .active:
                    #expect(loop == .start)
                case .inactive:
                    #expect(loop == .keep)
                case .background:
                    #expect(loop == .stop)
                default:
                    Issue.record("unexpected scene phase")
                }
            }
        }
    }
}

@MainActor
struct CloudKitGateStaysOffTests {
    @Test func companionDoesNotEnableCloudKit() {
        CloudKitSync.isConfiguredOverride = nil
        #expect(!CloudKitSync.isConfigured)
    }
}
