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
    }

    @Test func overtimeFillsProgress() {
        let view = RideOverlayPresentation.make(
            MenuBarInput(pairing: .paired, snap: running, now: 1_768_001_600)
        )
        #expect(view.isVisible)
        #expect(view.isOvertime)
        #expect(view.progress == 1)
        #expect(view.remainingLabel == "+1:40")
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

        let unpaired = RideOverlayPresentation.make(
            MenuBarInput(pairing: .unpaired, snap: running, now: 1_768_000_120)
        )
        #expect(!unpaired.isVisible)
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
        #expect(view.statusLine == "iPhone とつながっていない")
    }

    @Test func truncatesPeekTitle() {
        #expect(RideOverlayPresentation.truncatedPeekTitle("") == "乗務")
        #expect(RideOverlayPresentation.truncatedPeekTitle("短い") == "短い")
        let long = String(repeating: "あ", count: 8)
        #expect(RideOverlayPresentation.truncatedPeekTitle(long) == String(repeating: "あ", count: 6))
    }
}

@Suite("Ride overlay geometry")
struct RideOverlayGeometryTests {
    let screen = OverlayRect(x: 0, y: 34, width: 1440, height: 836)

    @Test func defaultParksBottomTrailing() {
        let frame = RideOverlayGeometry.frame(for: .default, screen: screen)
        #expect(frame.width == 320)
        #expect(frame.height == 120)
        #expect(frame.x == 1440 - 12 - 320)
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

    @Test func tuckFlushToTrailingEdge() {
        let state = OverlayLayoutState(corner: .bottomTrailing, isTucked: true)
        let frame = RideOverlayGeometry.frame(for: state, screen: screen)
        #expect(frame.width == RideOverlayGeometry.tuckedSize.width)
        #expect(frame.height == RideOverlayGeometry.tuckedSize.height)
        #expect(frame.x == screen.maxX - frame.width)
        #expect(frame.y == screen.minY + RideOverlayGeometry.screenInset)
    }

    @Test func tuckFlushToLeadingEdgeKeepsVerticalCorner() {
        let state = OverlayLayoutState(corner: .topLeading, isTucked: true)
        let frame = RideOverlayGeometry.frame(for: state, screen: screen)
        #expect(frame.x == screen.minX)
        #expect(frame.y == screen.maxY - RideOverlayGeometry.screenInset - frame.height)
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
            x: screen.minX - 80,
            y: screen.maxY - 140,
            width: 320,
            height: 120
        )
        let layout = RideOverlayGeometry.layout(afterDrag: dragged, screen: screen)
        #expect(layout.isTucked)
        #expect(layout.corner == .topLeading)
    }

    @Test func dragInsideSnapsNearestCorner() {
        let dragged = OverlayRect(x: 40, y: 80, width: 320, height: 120)
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
            x: peek.x - 80,
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
}
