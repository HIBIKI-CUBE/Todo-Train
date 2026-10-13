import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Mac PiP nudge")
struct MacNudgeTests {
    private let session = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let nudgeID = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!

    @Test func stageOneShowsTheQuestionAndFourChoices() throws {
        let view = RideOverlayPresentation.make(
            MenuBarInput(pairing: .paired, snap: snap(stage: .checkIn, surface: .none), now: 1_768_000_120)
        )
        #expect(view.showsNudgeChoices)
        #expect(view.holdLamp)
        #expect(view.nudgePrompt == CabinCopy.question(title: "週次レポート"))
        #expect(view.cabinPrompt == nil)
        #expect(view.nudgePrompt == CabinCopy.question(title: "週次レポート"))
    }

    @Test func laterStagesKeepTheSameQuestion() {
        let early = MacNudgeChrome.make(
            snap: snap(stage: .checkIn, surface: .none),
            now: 1_768_000_120,
            cabinEnabled: true,
            sendingExtendMinutes: nil,
            winnerLine: nil
        )
        let late = MacNudgeChrome.make(
            snap: snap(stage: .handoff2, surface: .mac),
            now: 1_768_001_600,
            cabinEnabled: true,
            sendingExtendMinutes: nil,
            winnerLine: nil
        )
        #expect(early.prompt == late.prompt)
        #expect(late.holdLamp)
        #expect(late.showsChoices)
    }

    @Test func iphoneTurnDoesNotLightTheLamp() {
        let chrome = MacNudgeChrome.make(
            snap: snap(stage: .handoff1, surface: .iphone),
            now: 1_768_001_600,
            cabinEnabled: true,
            sendingExtendMinutes: nil,
            winnerLine: nil
        )
        #expect(chrome.showsChoices)
        #expect(!chrome.holdLamp)
    }

    @Test func approachColorsTheInstrumentsWithoutAQuestion() {
        let chrome = MacNudgeChrome.make(
            snap: running,
            now: 1_768_001_380,
            cabinEnabled: true,
            sendingExtendMinutes: nil,
            winnerLine: nil
        )
        #expect(chrome.forcesApproach)
        #expect(!chrome.showsChoices)
        #expect(chrome.prompt == nil)
    }

    @Test func answeredNudgeDoesNotFallBackToTheCabinPrompt() {
        var snap = running
        snap.pendingCabin = .progress
        snap.checkInFiredCount = 0
        snap.nudge = nil
        snap.nudgePlan = [
            WireNudgePlanItem(stage: .estimate, fireAt: 1_768_001_600, surface: .mac, rings: true)
        ]
        let view = RideOverlayPresentation.make(
            MenuBarInput(pairing: .paired, snap: snap, now: 1_768_000_120)
        )
        #expect(!view.showsNudgeChoices)
        #expect(view.nudgePrompt == nil)
        #expect(view.cabinPrompt == nil)
    }

    @Test func olderSnapStaysOnTheCabinPrompt() {
        var snap = running
        snap.pendingCabin = .progress
        let view = RideOverlayPresentation.make(
            MenuBarInput(pairing: .paired, snap: snap, now: 1_768_000_120)
        )
        #expect(!view.showsNudgeChoices)
        #expect(view.nudgePrompt == nil)
        #expect(view.cabinPrompt == CabinCopy.prompt)
    }

    @Test func extendSendingNamesTheMinutes() {
        let view = RideOverlayPresentation.make(
            MenuBarInput(
                pairing: .paired,
                snap: snap(stage: .checkIn, surface: .none),
                now: 1_768_000_120,
                outgoingPause: .sending(cmdId: UUID()),
                sendingExtendMinutes: 10
            )
        )
        #expect(view.instrumentCaption == "延長 +10（送信中）")
        #expect(view.statusLine == SyncCopy.sentToIPhone)
    }

    @Test func staleAnswerShowsTheWinnerInsteadOfABlameLine() {
        var snap = running
        snap.phase = .paused
        snap.pausedAt = 1_768_000_100
        let view = RideOverlayPresentation.make(
            MenuBarInput(
                pairing: .paired,
                snap: snap,
                now: 1_768_000_200,
                outgoingPause: .failed(.nudgeStale),
                nudgeWinnerLine: MacNudgeReceipt.winnerLine(snap: snap, estimateBefore: 1500)
            )
        )
        #expect(view.instrumentCaption == "停車（iPhone）")
        #expect(view.failureLine == nil)
    }

    @Test func fifoFullReplacesTheDecryptLine() {
        let view = RideOverlayPresentation.make(
            MenuBarInput(
                pairing: .paired,
                snap: running,
                now: 1_768_000_120,
                transportNotice: SyncCopy.fifoFull
            )
        )
        #expect(view.failureLine == SyncCopy.fifoFull)
    }

    @Test func malformedNudgeStillShowsTheRide() throws {
        let present = try ContractFixtures.data("fixtures/snap-nudge.json")
        var object = try #require(JSONSerialization.jsonObject(with: present) as? [String: Any])
        object["nudge"] = ["id": "not-a-uuid"]
        object["nudgePlan"] = [["stage": 1]]
        object["reserved"] = "nope"
        let data = try JSONSerialization.data(withJSONObject: object)
        let snap = try WireJSON.decoder().decode(SnapPlaintext.self, from: data)
        let view = RideOverlayPresentation.make(
            MenuBarInput(pairing: .paired, snap: snap, now: 1_768_000_120)
        )
        #expect(view.isVisible)
        #expect(view.title == "週次レポート")
        #expect(!view.showsNudgeChoices)
        #expect(view.cabinPrompt == CabinCopy.prompt)
    }

    @Test func macRingsOnlyItsOwnTurns() {
        let plan = [
            WireNudgePlanItem(stage: .estimate, fireAt: 100, surface: .mac, rings: true),
            WireNudgePlanItem(stage: .handoff1, fireAt: 160, surface: .iphone, rings: true),
            WireNudgePlanItem(stage: .handoff2, fireAt: 220, surface: .mac, rings: true),
            WireNudgePlanItem(stage: .handoff3, fireAt: 280, surface: .iphone, rings: true),
            WireNudgePlanItem(stage: .estimate, fireAt: 100, surface: .none, rings: false),
        ]
        var seen = Set<String>()
        var sounded: [String] = []
        for now in [90, 100, 101, 160, 161, 220, 221, 280, 281] {
            let step = MacNudgeRinging.cues(
                sessionID: session,
                nudge: nil,
                plan: plan,
                now: now,
                seen: seen
            )
            seen = step.seen
            sounded.append(contentsOf: step.fresh.filter(\.sound).map(\.key))
        }
        #expect(sounded.count == 2)
        #expect(sounded.allSatisfy { $0.hasSuffix("|estimate") || $0.hasSuffix("|handoff2") })
        #expect(!sounded.contains { $0.contains("handoff1") || $0.contains("handoff3") })
    }

    @Test func aReturnFromSleepDoesNotReplay() {
        let plan = [
            WireNudgePlanItem(stage: .estimate, fireAt: 100, surface: .mac, rings: true),
            WireNudgePlanItem(stage: .handoff2, fireAt: 220, surface: .mac, rings: true),
        ]
        let step = MacNudgeRinging.cues(sessionID: session, nudge: nil, plan: plan, now: 400, seen: [])
        #expect(step.fresh.allSatisfy { !$0.sound })
        #expect(!MacNudgeRinging.audible(step.fresh, tucked: false))
    }

    @Test func tuckedPiPDoesNotChime() {
        let cue = MacNudgeRingCue(key: "x", sound: true)
        #expect(!MacNudgeRinging.audible([cue], tucked: true))
        #expect(MacNudgeRinging.audible([cue], tucked: false))
    }

    @Test func iphoneSurfaceOnTheCurrentNudgeDoesNotChime() {
        let nudge = WireNudge(
            id: nudgeID,
            kind: .overrun,
            stage: .estimate,
            ringSurface: .iphone,
            firedAt: 100
        )
        let step = MacNudgeRinging.cues(sessionID: session, nudge: nudge, plan: nil, now: 100, seen: [])
        #expect(step.fresh.isEmpty)
    }

    @Test func winnerLineNamesAnExtension() {
        var snap = running
        snap.estimatedSeconds = 2100
        let line = MacNudgeReceipt.winnerLine(snap: snap, estimateBefore: 1500)
        #expect(line == "延長 +10（iPhone）")
    }

    private var running: SnapPlaintext {
        let data = try! ContractFixtures.data("fixtures/snap.json")
        return try! WireJSON.decoder().decode(SnapPlaintext.self, from: data)
    }

    private func snap(stage: NudgeStageWire, surface: NudgeRingSurface) -> SnapPlaintext {
        var snap = running
        snap.nudge = WireNudge(
            id: nudgeID,
            kind: stage == .checkIn ? .progress : .overrun,
            stage: stage,
            ringSurface: surface,
            firedAt: 1_768_000_120
        )
        return snap
    }
}
