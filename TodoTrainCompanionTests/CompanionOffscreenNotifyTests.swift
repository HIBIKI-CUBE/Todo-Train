import Foundation
import Testing
import TodoTrainSync
@testable import TodoTrainCompanion

@Suite("Mac offscreen notifications")
struct CompanionOffscreenNotifyTests {
    @Test func pipAndIphoneTurnsDoNotAskMacToPost() throws {
        var snap = try WireJSON.decoder().decode(
            SnapPlaintext.self,
            from: ContractFixtures.data("fixtures/snap.json")
        )
        snap.notifyOn = .mac
        let now = Date(timeIntervalSince1970: TimeInterval(1_768_000_000))
        #expect(CompanionOffscreenNotify.requests(snap: snap, pipVisible: true, now: now).isEmpty)
        snap.notifyOn = .none
        #expect(CompanionOffscreenNotify.requests(snap: snap, pipVisible: false, now: now).isEmpty)
        snap.notifyOn = nil
        #expect(CompanionOffscreenNotify.requests(snap: snap, pipVisible: false, now: now).isEmpty)
    }
}
