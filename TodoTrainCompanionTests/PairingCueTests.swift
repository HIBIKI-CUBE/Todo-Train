import Testing
@testable import TodoTrainCompanion

struct PairingCueTests {
    @Test func successAndFailureCopyAreDistinct() {
        #expect(PairingCue.scanning.message.contains("枠"))
        #expect(PairingCue.captured.message == "読めた")
        #expect(PairingCue.waitingPeer.message.contains("読めた"))
        #expect(PairingCue.established.message.contains("つながった"))
        #expect(PairingCue.failed("つなぎ直しが必要").isFailed)
        #expect(!PairingCue.scanning.isFailed)
    }
}
