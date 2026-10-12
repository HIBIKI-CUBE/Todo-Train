import Foundation
import Testing
import TodoTrainSync
@testable import Todo_train

@MainActor
struct WatchRideCopyTests {
    @Test func contextFollowsTheRideTitleAndRemaining() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(
            now: Date(timeIntervalSince1970: 1_768_000_060)
        )
        let ticket = try SessionManagerFixtures.makeTicket(context, title: "週次レポート", seconds: 1500)
        let session = WorkSession(
            startedAt: Date(timeIntervalSince1970: 1_768_000_000),
            estimatedSecondsAtStart: 1500,
            ticket: ticket
        )
        context.insert(session)
        manager.activeSession = session
        manager.phase = .running

        let snap = RideWireSnap.make(
            sessionManager: manager,
            settings: manager.settings,
            rev: 1,
            now: clock.now
        )
        #expect(snap.contract == ContractVersion.contract)
        #expect(snap.minReadable == ContractVersion.minReadable)
        #expect(snap.title == "週次レポート")
        #expect(snap.remainingSeconds(at: 1_768_000_060) == 1440)

        var mirror = WatchMirror()
        mirror.receive(try WatchLink.context(for: snap))
        #expect(mirror.title == "週次レポート")
        #expect(mirror.remainingSeconds(at: 1_768_000_060) == 1440)
        #expect(mirror.replyGate == .open)

        ticket.title = "続きのメモ"
        let next = RideWireSnap.make(
            sessionManager: manager,
            settings: manager.settings,
            rev: 2,
            now: clock.now
        )
        mirror.receive(try WatchLink.context(for: next))
        #expect(mirror.title == "続きのメモ")
        #expect(mirror.remainingSeconds(at: 1_768_000_060) == 1440)
    }
}
