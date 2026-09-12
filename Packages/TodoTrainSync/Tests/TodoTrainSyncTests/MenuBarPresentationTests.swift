import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Menu bar presentation")
struct MenuBarPresentationTests {
    let running: SnapPlaintext = {
        let data = try! ContractFixtures.data("fixtures/snap.json")
        return try! WireJSON.decoder().decode(SnapPlaintext.self, from: data)
    }()

    let idle: SnapPlaintext = {
        let data = try! ContractFixtures.data("fixtures/snap-idle.json")
        return try! WireJSON.decoder().decode(SnapPlaintext.self, from: data)
    }()

    @Test func remainingMatchesContractExample() {
        #expect(running.remainingSeconds(at: 1_768_000_120) == 1380)
        #expect(MenuBarPresentation.formatRemaining(1380) == "23:00")
    }

    @Test func runningShowsTitleRemainingAndPause() {
        let view = MenuBarPresentation.make(
            MenuBarInput(pairing: .paired, snap: running, now: 1_768_000_120)
        )
        #expect(view.barTitle?.contains("週次レポート") == true)
        #expect(view.barTitle?.contains("23:00") == true)
        #expect(view.remainingSeconds == 1380)
        #expect(!view.isOvertime)
        #expect(view.canPause)
        #expect(!view.canResume)
        #expect(!view.canReconnect)
        #expect(!view.isSending)
        #expect(view.popoverTitle == "週次レポート")
    }

    @Test func overtimeWhenRemainingNonPositive() {
        let view = MenuBarPresentation.make(
            MenuBarInput(pairing: .paired, snap: running, now: 1_768_001_600)
        )
        #expect(view.remainingSeconds == -100)
        #expect(view.isOvertime)
        #expect(view.canPause)
        #expect(view.popoverDetail.contains("超過"))
    }

    @Test func pausedForbidsPause() {
        var snap = running
        snap.phase = .paused
        snap.pausedAt = 1_768_000_100
        let view = MenuBarPresentation.make(
            MenuBarInput(pairing: .paired, snap: snap, now: 1_768_000_200)
        )
        #expect(view.barTitle == "停車中")
        #expect(!view.canPause)
        #expect(view.canResume)
        #expect(view.popoverDetail == "停車中")
        #expect(view.remainingSeconds == running.remainingSeconds(at: 1_768_000_100))
    }

    @Test func idleAndUnpairedAreIconOnly() {
        let idleView = MenuBarPresentation.make(
            MenuBarInput(pairing: .paired, snap: idle, now: 1_768_000_120)
        )
        #expect(idleView.barTitle == nil)
        #expect(!idleView.canPause)
        #expect(!idleView.canResume)
        #expect(!idleView.canReconnect)
        #expect(idleView.popoverTitle == "乗務なし")

        let unpaired = MenuBarPresentation.make(
            MenuBarInput(pairing: .unpaired, snap: nil, now: 0)
        )
        #expect(unpaired.barTitle == nil)
        #expect(!unpaired.canPause)
        #expect(!unpaired.canResume)
        #expect(!unpaired.canReconnect)
        #expect(unpaired.popoverTitle == "iPhone で QR を出す")
        #expect(unpaired.popoverDetail == "画面を Mac に向ける")
    }

    @Test func sendingBlocksResendUntilAck() {
        let sending = MenuBarPresentation.make(
            MenuBarInput(
                pairing: .paired,
                snap: running,
                now: 1_768_000_120,
                outgoingPause: .sending(cmdId: UUID())
            )
        )
        #expect(sending.isSending)
        #expect(sending.canPause)
        #expect(!sending.canResume)
        #expect(sending.popoverDetail == "iPhone に送った")

        let failed = MenuBarPresentation.make(
            MenuBarInput(
                pairing: .paired,
                snap: running,
                now: 1_768_000_120,
                outgoingPause: .failed(.pauseLimitReached)
            )
        )
        #expect(failed.canPause)
        #expect(failed.failureLine == "停車できません（停車上限）")
    }

    @Test func disconnectedKeepsDateBasedRemaining() {
        let view = MenuBarPresentation.make(
            MenuBarInput(
                pairing: .paired,
                snap: running,
                now: 1_768_000_120,
                connection: .disconnected
            )
        )
        #expect(view.remainingSeconds == 1380)
        #expect(view.canPause)
        #expect(!view.canResume)
        #expect(view.canReconnect)
        #expect(view.popoverDetail == "iPhone とつながっていない")
    }

    @Test func disconnectedIdleOffersReconnect() {
        let view = MenuBarPresentation.make(
            MenuBarInput(
                pairing: .paired,
                snap: idle,
                now: 1_768_000_120,
                connection: .disconnected
            )
        )
        #expect(view.canReconnect)
        #expect(view.popoverDetail == "iPhone とつながっていない")
        #expect(!view.canPause)
    }

    @Test func unknownPhaseIsConservative() {
        var snap = idle
        snap.phase = .unknown("boarding")
        let view = MenuBarPresentation.make(
            MenuBarInput(pairing: .paired, snap: snap, now: 0)
        )
        #expect(view.barTitle == nil)
        #expect(!view.canPause)
        #expect(!view.canResume)
    }

    @Test func truncatesLongTitle() {
        let long = String(repeating: "あ", count: 12)
        #expect(MenuBarPresentation.truncatedTitle(long)?.hasSuffix("…") == true)
        #expect(MenuBarPresentation.truncatedTitle(long)?.count == 11)
    }

    @Test func pausedShowsResumeAndSending() {
        var snap = running
        snap.phase = .paused
        snap.pausedAt = 1_768_000_100
        let sending = MenuBarPresentation.make(
            MenuBarInput(
                pairing: .paired,
                snap: snap,
                now: 1_768_000_200,
                outgoingPause: .sending(cmdId: UUID())
            )
        )
        #expect(sending.isSending)
        #expect(sending.canResume)
        #expect(sending.popoverDetail == "iPhone に送った")

        let failed = MenuBarPresentation.make(
            MenuBarInput(
                pairing: .paired,
                snap: snap,
                now: 1_768_000_200,
                outgoingPause: .failed(.notPaused)
            )
        )
        #expect(failed.canResume)
        #expect(failed.failureLine == "停車中ではない")
    }
}
