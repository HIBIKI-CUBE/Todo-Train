import Foundation
import Testing
import TodoTrainSync
@testable import TodoTrainCompanion

@Suite("Mac offscreen notifications")
struct CompanionOffscreenNotifyTests {
    @Test func pipAndIphoneTurnsDoNotAskMacToPost() {
        var snap = SnapPlaintext(
            rev: 1,
            sessionId: UUID(uuidString: "11111111-1111-4111-8111-111111111111"),
            ticketId: nil,
            title: "週次レポート",
            phase: .running,
            startedAt: 1_768_000_000,
            estimatedSeconds: 1500,
            pausedAccumulated: 0,
            pausedAt: nil,
            boardedDeviceID: "phone-a",
            notifyOn: .mac,
            notifyTurn: 0
        )
        let now = Date(timeIntervalSince1970: TimeInterval(1_768_000_000))
        #expect(CompanionOffscreenNotify.requests(snap: snap, pipVisible: true, now: now).isEmpty)
        snap.notifyOn = .none
        #expect(CompanionOffscreenNotify.requests(snap: snap, pipVisible: false, now: now).isEmpty)
        snap.notifyOn = nil
        #expect(CompanionOffscreenNotify.requests(snap: snap, pipVisible: false, now: now).isEmpty)
        snap.notifyOn = .iphone
        #expect(CompanionOffscreenNotify.requests(snap: snap, pipVisible: false, now: now).isEmpty)
    }
}
