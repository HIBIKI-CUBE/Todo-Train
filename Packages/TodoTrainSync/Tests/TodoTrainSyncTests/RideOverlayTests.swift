import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Ride overlay presentation")
struct RideOverlayPresentationTests {
    let running: SnapPlaintext = {
        let data = try! ContractFixtures.data("fixtures/snap.json")
        return try! WireJSON.decoder().decode(SnapPlaintext.self, from: data)
    }()

    let idle: SnapPlaintext = {
        let data = try! ContractFixtures.data("fixtures/snap-idle.json")
        return try! WireJSON.decoder().decode(SnapPlaintext.self, from: data)
    }()

    @Test func runningIsVisibleWithProgress() {
        let view = RideOverlayPresentation.make(
            MenuBarInput(pairing: .paired, snap: running, now: 1_768_000_120)
        )
        #expect(view.isVisible)
        #expect(view.title == "週次レポート")
        #expect(view.remainingLabel == "23:00")
        #expect(view.progress == 120.0 / 1500.0)
        #expect(!view.isOvertime)
        #expect(!view.isPaused)
        #expect(view.canPause)
        #expect(!view.canResume)
        #expect(view.peekTitle == "週次レポート")
        #expect(view.timerPhase == .cruise)
        #expect(view.cabinPrompt == nil)
    }

    @Test func overtimeFillsProgress() {
        let view = RideOverlayPresentation.make(
            MenuBarInput(pairing: .paired, snap: running, now: 1_768_001_600)
        )
        #expect(view.isVisible)
        #expect(view.isOvertime)
        #expect(view.progress == 1)
        #expect(view.remainingLabel == "+1:40")
        #expect(view.timerPhase == .overtime)
        #expect(view.canPause)
    }

    @Test func pausedShowsResumeAndFreezesProgress() {
        var snap = running
        snap.phase = .paused
        snap.pausedAt = 1_768_000_100
        let view = RideOverlayPresentation.make(
            MenuBarInput(pairing: .paired, snap: snap, now: 1_768_000_200)
        )
        #expect(view.isVisible)
        #expect(view.isPaused)
        #expect(!view.canPause)
        #expect(view.canResume)
        #expect(view.progress == 100.0 / 1500.0)
        #expect(view.remainingLabel == MenuBarPresentation.formatRemaining(1400))
    }

    @Test func idleAndUnpairedAreHidden() {
        let idleView = RideOverlayPresentation.make(
            MenuBarInput(pairing: .paired, snap: idle, now: 1_768_000_120)
        )
        #expect(!idleView.isVisible)
        #expect(idleView.cabinPrompt == nil)

        let unpaired = RideOverlayPresentation.make(
            MenuBarInput(pairing: .unpaired, snap: running, now: 1_768_000_120)
        )
        #expect(!unpaired.isVisible)
    }

    @Test func idlePendingDoesNotShowPip() {
        var snap = idle
        snap.serviceActive = true
        snap.pendingCabin = .idle
        let view = RideOverlayPresentation.make(
            MenuBarInput(pairing: .paired, snap: snap, now: 1_768_000_120)
        )
        #expect(!view.isVisible)
        #expect(view.cabinPrompt == nil)
    }

    @Test func sendingAndFailureCopy() {
        let sending = RideOverlayPresentation.make(
            MenuBarInput(
                pairing: .paired,
                snap: running,
                now: 1_768_000_120,
                outgoingPause: .sending(cmdId: UUID())
            )
        )
        #expect(sending.isSending)
        #expect(sending.canPause)
        #expect(sending.statusLine == "iPhone に送った")

        let failed = RideOverlayPresentation.make(
            MenuBarInput(
                pairing: .paired,
                snap: running,
                now: 1_768_000_120,
                outgoingPause: .failed(.pauseLimitReached)
            )
        )
        #expect(failed.failureLine == "停車できません（停車上限）")
    }

    @Test func cabinPromptWhenPendingProgress() {
        var snap = running
        snap.pendingCabin = .progress
        let view = RideOverlayPresentation.make(
            MenuBarInput(pairing: .paired, snap: snap, now: 1_768_000_120)
        )
        #expect(view.cabinPrompt == CabinCopy.prompt)

        let sending = RideOverlayPresentation.make(
            MenuBarInput(
                pairing: .paired,
                snap: snap,
                now: 1_768_000_120,
                outgoingPause: .sending(cmdId: UUID())
            )
        )
        #expect(sending.cabinPrompt == nil)

        let localOff = RideOverlayPresentation.make(
            MenuBarInput(
                pairing: .paired,
                snap: snap,
                now: 1_768_000_120,
                cabinEnabledLocal: false
            )
        )
        #expect(localOff.cabinPrompt == nil)
    }

    @Test func disconnectedKeepsProgress() {
        let view = RideOverlayPresentation.make(
            MenuBarInput(
                pairing: .paired,
                snap: running,
                now: 1_768_000_120,
                connection: .disconnected
            )
        )
        #expect(view.isVisible)
        #expect(view.progress == 120.0 / 1500.0)
        #expect(view.statusLine == "リレーが切れた")
    }

    @Test func nextBlockLineFromSnap() {
        var snap = running
        snap.nextBlockTitle = "1on1"
        snap.nextBlockStartsAt = 1_768_000_000 + 3600
        snap.timetablePauseAt = 1_768_000_000 + 3660
        let view = RideOverlayPresentation.make(
            MenuBarInput(pairing: .paired, snap: snap, now: 1_768_000_120)
        )
        #expect(view.nextBlockLine?.contains("1on1") == true)
        #expect(view.timetablePauseAt == snap.timetablePauseAt)
    }

    @Test func truncatesPeekTitle() {
        #expect(RideOverlayPresentation.truncatedPeekTitle("") == "乗務")
        #expect(RideOverlayPresentation.truncatedPeekTitle("短い") == "短い")
        let long = String(repeating: "あ", count: 8)
        #expect(RideOverlayPresentation.truncatedPeekTitle(long) == String(repeating: "あ", count: 6))
    }

    @Test func timerPhaseMatchesFocusBudgetRatio() {
        let budget = 5 * 60
        #expect(RideOverlayPresentation.timerPhase(remaining: 300, estimated: budget, overtime: false) == .cruise)
        #expect(RideOverlayPresentation.timerPhase(remaining: 91, estimated: budget, overtime: false) == .cruise)
        #expect(RideOverlayPresentation.timerPhase(remaining: 90, estimated: budget, overtime: false) == .approach)
        #expect(RideOverlayPresentation.timerPhase(remaining: 31, estimated: budget, overtime: false) == .approach)
        #expect(RideOverlayPresentation.timerPhase(remaining: 30, estimated: budget, overtime: false) == .final)
        #expect(RideOverlayPresentation.timerPhase(remaining: -1, estimated: budget, overtime: false) == .overtime)
        #expect(RideOverlayPresentation.timerPhase(remaining: 120, estimated: budget, overtime: true) == .overtime)
    }
}

@Suite("Ride overlay geometry")
struct RideOverlayGeometryTests {
    let screen = OverlayRect(x: 0, y: 34, width: 1440, height: 836)

    @Test func defaultParksBottomTrailing() {
        let frame = RideOverlayGeometry.frame(for: .default, screen: screen)
        #expect(frame.width == RideOverlayGeometry.cardSize.width)
        #expect(frame.height == RideOverlayGeometry.cardSize.height)
        #expect(frame.x == 1440 - 12 - RideOverlayGeometry.cardSize.width)
        #expect(frame.y == 34 + 12)
    }

    @Test func fourCorners() {
        let size = RideOverlayGeometry.cardSize
        let inset = RideOverlayGeometry.screenInset
        let topLeading = RideOverlayGeometry.frame(
            for: OverlayLayoutState(corner: .topLeading, isTucked: false),
            screen: screen
        )
        #expect(topLeading.x == inset)
        #expect(topLeading.y == screen.maxY - inset - size.height)

        let topTrailing = RideOverlayGeometry.frame(
            for: OverlayLayoutState(corner: .topTrailing, isTucked: false),
            screen: screen
        )
        #expect(topTrailing.x == screen.maxX - inset - size.width)
        #expect(topTrailing.y == screen.maxY - inset - size.height)

        let bottomLeading = RideOverlayGeometry.frame(
            for: OverlayLayoutState(corner: .bottomLeading, isTucked: false),
            screen: screen
        )
        #expect(bottomLeading.x == inset)
        #expect(bottomLeading.y == screen.minY + inset)
    }

    @Test func tuckKeepsCardSizeAndSlidesOffTrailing() {
        let state = OverlayLayoutState(corner: .bottomTrailing, isTucked: true)
        let frame = RideOverlayGeometry.frame(for: state, screen: screen)
        #expect(frame.width == RideOverlayGeometry.cardSize.width)
        #expect(frame.height == RideOverlayGeometry.cardSize.height)
        #expect(frame.x == screen.maxX - RideOverlayGeometry.peekReveal)
        #expect(frame.y == screen.minY + RideOverlayGeometry.screenInset)
    }

    @Test func tuckSlidesOffLeadingAndKeepsVerticalCorner() {
        let state = OverlayLayoutState(corner: .topLeading, isTucked: true)
        let frame = RideOverlayGeometry.frame(for: state, screen: screen)
        #expect(frame.width == RideOverlayGeometry.cardSize.width)
        #expect(frame.x == screen.minX + RideOverlayGeometry.peekReveal - frame.width)
        #expect(frame.y == screen.maxY - RideOverlayGeometry.screenInset - frame.height)
    }

    @Test func tuckUsesDisplayEdgeNotVisibleFrame() {
        let display = OverlayRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = OverlayRect(x: 0, y: 34, width: 1400, height: 841)
        let screen = OverlayScreen(display: display, visible: visible)
        let frame = RideOverlayGeometry.frame(
            for: OverlayLayoutState(corner: .bottomTrailing, isTucked: true),
            screen: screen
        )
        #expect(frame.x == display.maxX - RideOverlayGeometry.peekReveal)
        #expect(frame.y == visible.minY + RideOverlayGeometry.screenInset)
    }

    @Test func dragPastTrailingTucks() {
        let card = RideOverlayGeometry.frame(for: .default, screen: screen)
        let dragged = OverlayRect(
            x: screen.maxX - 20,
            y: card.y,
            width: card.width,
            height: card.height
        )
        let layout = RideOverlayGeometry.layout(afterDrag: dragged, screen: screen)
        #expect(layout.isTucked)
        #expect(layout.corner == .bottomTrailing)
    }

    @Test func dragPastLeadingTucksTopWhenHigh() {
        let dragged = OverlayRect(
            x: screen.minX - 160,
            y: screen.maxY - 140,
            width: RideOverlayGeometry.cardSize.width,
            height: RideOverlayGeometry.cardSize.height
        )
        let layout = RideOverlayGeometry.layout(afterDrag: dragged, screen: screen)
        #expect(layout.isTucked)
        #expect(layout.corner == .topLeading)
    }

    @Test func dragInsideSnapsNearestCorner() {
        let dragged = OverlayRect(
            x: 40,
            y: 80,
            width: RideOverlayGeometry.cardSize.width,
            height: RideOverlayGeometry.cardSize.height
        )
        let layout = RideOverlayGeometry.layout(afterDrag: dragged, screen: screen)
        #expect(!layout.isTucked)
        #expect(layout.corner == .bottomLeading)
    }

    @Test func peekDragInwardRestores() {
        let peek = RideOverlayGeometry.frame(
            for: OverlayLayoutState(corner: .bottomTrailing, isTucked: true),
            screen: screen
        )
        let inward = OverlayRect(
            x: peek.x - 250,
            y: peek.y,
            width: peek.width,
            height: peek.height
        )
        let layout = RideOverlayGeometry.layout(afterDrag: inward, screen: screen)
        #expect(!layout.isTucked)
        #expect(layout.corner == .bottomTrailing)
    }

    @Test func belowTuckThresholdDoesNotHide() {
        let card = RideOverlayGeometry.frame(for: .default, screen: screen)
        let nudged = OverlayRect(
            x: card.x + 20,
            y: card.y,
            width: card.width,
            height: card.height
        )
        let layout = RideOverlayGeometry.layout(afterDrag: nudged, screen: screen)
        #expect(!layout.isTucked)
        #expect(layout.corner == .bottomTrailing)
    }

    @Test func slightOvershootStillParksAtCorner() {
        let card = RideOverlayGeometry.frame(for: .default, screen: screen)
        let nudged = OverlayRect(
            x: card.x + 40,
            y: card.y,
            width: card.width,
            height: card.height
        )
        let layout = RideOverlayGeometry.layout(afterDrag: nudged, screen: screen)
        #expect(!layout.isTucked)
        #expect(layout.corner == .bottomTrailing)
    }

    @Test func doesNotTuckTowardAdjacentDisplay() {
        let left = OverlayRect(x: 0, y: 0, width: 1440, height: 900)
        let right = OverlayRect(x: 1440, y: 0, width: 800, height: 900)
        let dragged = OverlayRect(
            x: 1260,
            y: 40,
            width: RideOverlayGeometry.cardSize.width,
            height: RideOverlayGeometry.cardSize.height
        )
        let placement = RideOverlayGeometry.layout(
            afterDrag: dragged,
            screens: [OverlayScreen(left), OverlayScreen(right)]
        )
        #expect(!placement.state.isTucked)
        #expect(placement.screenIndex == 0)
        #expect(placement.state.corner == .bottomTrailing)
    }

    @Test func crossingSeamParksOnTheDestinationDisplay() {
        let left = OverlayRect(x: 0, y: 0, width: 1440, height: 900)
        let right = OverlayRect(x: 1440, y: 0, width: 1920, height: 1080)
        let dragged = OverlayRect(
            x: 1300,
            y: 40,
            width: RideOverlayGeometry.cardSize.width,
            height: RideOverlayGeometry.cardSize.height
        )
        let placement = RideOverlayGeometry.layout(
            afterDrag: dragged,
            screens: [OverlayScreen(left), OverlayScreen(right)]
        )
        #expect(!placement.state.isTucked)
        #expect(placement.screenIndex == 1)
        #expect(placement.state.corner == .bottomLeading)
    }

    @Test func outerEdgeStillTucksWhenNeighborIsOnTheOtherSide() {
        let left = OverlayRect(x: 0, y: 0, width: 1440, height: 900)
        let right = OverlayRect(x: 1440, y: 0, width: 800, height: 900)
        let dragged = OverlayRect(
            x: 2100,
            y: 40,
            width: RideOverlayGeometry.cardSize.width,
            height: RideOverlayGeometry.cardSize.height
        )
        let placement = RideOverlayGeometry.layout(
            afterDrag: dragged,
            screens: [OverlayScreen(left), OverlayScreen(right)]
        )
        #expect(placement.state.isTucked)
        #expect(placement.screenIndex == 1)
        #expect(placement.state.corner == .bottomTrailing)
    }

    @Test func fillLengthKeepsASliverUntilEmpty() {
        #expect(RideOverlayGeometry.fillLength(progress: 0, total: 280) == 0)
        #expect(RideOverlayGeometry.fillLength(progress: 0.5, total: 280) == 140)
        #expect(RideOverlayGeometry.fillLength(progress: 1, total: 280) == 280)
        #expect(RideOverlayGeometry.fillLength(progress: 0.01, total: 280) == RideOverlayGeometry.minimumFill)
        #expect(RideOverlayGeometry.fillLength(progress: -0.2, total: 280) == 0)
        #expect(RideOverlayGeometry.fillLength(progress: 1.4, total: 280) == 280)
        #expect(RideOverlayGeometry.fillLength(progress: 0.5, total: 0) == 0)
    }

    @Test func tuckedWindowPicksIntersectingScreenWhenCenterIsOffDisplay() {
        let peek = RideOverlayGeometry.frame(
            for: OverlayLayoutState(corner: .bottomTrailing, isTucked: true),
            screen: screen
        )
        #expect(!screen.contains(x: peek.midX, y: peek.midY))
        let index = RideOverlayGeometry.pickScreen(for: peek, screens: [OverlayScreen(screen)])
        #expect(index == 0)
    }
}
