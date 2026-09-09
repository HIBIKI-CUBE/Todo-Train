import Foundation
import Testing
import TodoTrainSync
@testable import TodoTrainCompanion

struct OutgoingPauseApplyingTests {
    @Test func beginSending_blocksResendWhileInFlight() {
        let id = UUID()
        let first = OutgoingPauseApplying.beginSending(cmdId: id, current: .idle)
        #expect(first == .sending(cmdId: id))
        #expect(OutgoingPauseApplying.beginSending(cmdId: UUID(), current: first!) == nil)
    }

    @Test func applyAck_okClearsSending() {
        let id = UUID()
        let sending = OutgoingPauseState.sending(cmdId: id)
        let next = OutgoingPauseApplying.applyAck(
            AckPlaintext(cmdId: id, ok: true),
            current: sending
        )
        #expect(next == .idle)
    }

    @Test func applyAck_failureUsesWireError() {
        let id = UUID()
        let sending = OutgoingPauseState.sending(cmdId: id)
        let next = OutgoingPauseApplying.applyAck(
            AckPlaintext(cmdId: id, ok: false, error: .pauseLimitReached),
            current: sending
        )
        #expect(next == .failed(.pauseLimitReached))
    }

    @Test func applyAck_ignoresOtherCommand() {
        let sending = OutgoingPauseState.sending(cmdId: UUID())
        let next = OutgoingPauseApplying.applyAck(
            AckPlaintext(cmdId: UUID(), ok: true),
            current: sending
        )
        #expect(next == sending)
    }

    @Test func presentation_usesPackageDefaults() {
        let view = MenuBarPresentation.make(
            MenuBarInput(pairing: .unpaired, snap: nil, now: 0)
        )
        #expect(view.barTitle == nil)
        #expect(view.popoverTitle == "iPhone で QR を出す")
        #expect(!view.canPause)
    }
}
