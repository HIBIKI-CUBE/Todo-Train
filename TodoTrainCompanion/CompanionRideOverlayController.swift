import AppKit
import Observation
import QuartzCore
import SwiftUI
import TodoTrainSync

@MainActor
final class CompanionRideOverlayController: NSObject {
    static let actionStripHeight: CGFloat = 44
    static let handleWidth: CGFloat = 22

    private let runtime: CompanionMacRuntime
    private let defaults: UserDefaults
    private let panel = CompanionRideOverlayPanel()
    private let model = CompanionRideOverlayModel()
    private let rootView = OverlayRootView()
    private var layout: OverlayLayoutState
    private var screenID: UInt32
    private var dragStart: NSRect?
    private var lastVisible = false
    private var lastCabinPrompt: String?
    private var seenNudgeKeys: Set<String> = []
    private var lastNudgeID: UUID?

    init(runtime: CompanionMacRuntime, defaults: UserDefaults = .standard) {
        self.runtime = runtime
        self.defaults = defaults
        self.layout = OverlayLayoutPersisting.load(defaults)
        self.screenID = OverlayLayoutPersisting.screenID(defaults)
        super.init()
        let hosting = PassThroughHostingView(
            rootView:             CompanionRideOverlayView(
                model: model,
                onPause: { [weak self] in
                    guard let self else { return }
                    Task { await self.runtime.sendPause() }
                },
                onResume: { [weak self] in
                    guard let self else { return }
                    Task { await self.runtime.sendResume() }
                },
                onStill: { [weak self] in
                    guard let self else { return }
                    Task { await self.runtime.sendStill() }
                },
                onRestore: { [weak self] in self?.restoreFromPeek() },
                onNudgeChoice: { [weak self] choice in
                    self?.handleNudgeChoice(choice)
                },
                onExtendPreset: { [weak self] seconds in
                    self?.sendExtend(seconds)
                },
                onCancelExtend: { [weak self] in
                    self?.model.extendPicker = false
                },
                onBoardReserved: { [weak self] in
                    guard let self else { return }
                    Task { await self.runtime.sendBoardReserved() }
                },
                onCloseGap: { [weak self] in
                    guard let self else { return }
                    Task { await self.runtime.sendStill() }
                }
            )
        )
        hosting.safeAreaRegions = []
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.frame = rootView.bounds
        hosting.autoresizingMask = [.width, .height]
        rootView.addSubview(hosting)
        rootView.onHover = { [weak self] hovering in
            self?.model.hovering = hovering
        }
        rootView.onDragChanged = { [weak self] mouse, startFrame, startMouse in
            self?.dragChanged(mouse: mouse, startFrame: startFrame, startMouse: startMouse)
        }
        rootView.onDragEnded = { [weak self] _ in
            self?.dragEnded()
        }
        rootView.onClick = { [weak self] point in
            self?.handleClick(at: point)
        }
        rootView.boardGestureEnabled = { [weak self] in
            guard let self else { return false }
            return self.model.presentation.canBoardReserved && !self.model.isTucked
        }
        rootView.onBoardGesture = { [weak self] in
            guard let self, !self.model.presentation.isSending else { return }
            Task { await self.runtime.sendBoardReserved() }
        }
        panel.contentView = rootView
        panel.orderOut(nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        observeRuntime()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func observeRuntime() {
        let presentation = runtime.overlayPresentation
        applyPresentation(presentation)
        withObservationTracking {
            _ = self.runtime.overlayPresentation
            _ = self.runtime.suppressRideOverlay
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeRuntime()
            }
        }
    }

    private func applyLayoutToChrome() {
        model.isTucked = layout.isTucked
        model.edge = layout.edge
        rootView.isTucked = layout.isTucked
        rootView.edge = layout.edge
        rootView.updateTrackingAreas()
    }

    /// Park the card fully on screen and show it. Used when the dispensed ticket hands off.
    func revealParkedRide() {
        if layout.isTucked {
            layout.isTucked = false
            persist()
        }
        applyLayoutToChrome()
        let presentation = runtime.overlayPresentation
        model.presentation = presentation
        guard presentation.isVisible else { return }
        applyFrame(animated: false)
        panel.orderFrontRegardless()
        lastVisible = true
        lastCabinPrompt = presentation.cabinPrompt
    }

    private func applyPresentation(_ presentation: RideOverlayPresentation) {
        if runtime.suppressRideOverlay {
            model.presentation = presentation
            panel.orderOut(nil)
            lastVisible = false
            lastCabinPrompt = presentation.cabinPrompt
            return
        }
        let cabinAppeared = presentation.cabinPrompt != nil && lastCabinPrompt == nil
        let nudgeID = runtime.snap?.nudge?.id
        if nudgeID != lastNudgeID {
            model.extendPicker = false
            lastNudgeID = nudgeID
        }
        model.presentation = presentation
        applyLayoutToChrome()
        let ringing: (fresh: [MacNudgeRingCue], seen: Set<String>)
        if runtime.cabinAnnouncementsEnabled, runtime.snap?.cabinEnabled != false {
            ringing = MacNudgeRinging.cues(
                sessionID: runtime.snap?.sessionId,
                nudge: runtime.snap?.nudge,
                plan: runtime.snap?.nudgePlan,
                now: runtime.now,
                seen: seenNudgeKeys
            )
        } else {
            ringing = ([], seenNudgeKeys)
        }
        seenNudgeKeys = ringing.seen
        model.edgeLamp = layout.isTucked && presentation.holdLamp
        let visible = presentation.isVisible
        if visible {
            if presentation.showsArrivalGap, layout.isTucked {
                layout.isTucked = false
                persist()
                applyLayoutToChrome()
            }
            if !lastVisible {
                applyFrame(animated: false)
            }
            // orderOut のときだけ出す。前面化せず、作業中の窓のキーも取らない。
            if !panel.isVisible {
                panel.orderFrontRegardless()
            }
            if cabinAppeared {
                model.hovering = false
            }
            let chime = MacNudgeRinging.audible(ringing.fresh, tucked: layout.isTucked)
                || (cabinAppeared && !layout.isTucked && runtime.snap?.nudge == nil)
            if chime, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                NSSound(named: "Tink")?.play()
            }
        } else {
            panel.orderOut(nil)
            model.edgeLamp = false
        }
        lastVisible = visible
        lastCabinPrompt = presentation.cabinPrompt
    }

    private func dragChanged(mouse: NSPoint, startFrame: NSRect, startMouse: NSPoint) {
        dragStart = startFrame
        var frame = startFrame
        frame.origin.x += mouse.x - startMouse.x
        frame.origin.y += mouse.y - startMouse.y
        frame.size = RideOverlayGeometry.cardSize.nsSize
        panel.setFrame(frame, display: true)
    }

    private func dragEnded() {
        dragStart = nil
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let overlayScreens = screens.map(OverlayScreen.init)
        let placement = RideOverlayGeometry.layout(
            afterDrag: OverlayRect(panel.frame),
            screens: overlayScreens
        )
        let index = min(max(placement.screenIndex, 0), screens.count - 1)
        screenID = screens[index].overlayDisplayID
        layout = placement.state
        persist()
        applyLayoutToChrome()
        model.hovering = false
        applyFrame(animated: true)
    }

    private func handleClick(at point: NSPoint) {
        if layout.isTucked {
            restoreFromPeek()
            return
        }
        guard point.y <= Self.actionStripHeight,
              point.x >= Self.handleWidth else { return }
        let presentation = model.presentation
        if presentation.isSending { return }
        if model.extendPicker {
            switch choiceIndex(at: point) {
            case 0: sendExtend(300)
            case 1: sendExtend(600)
            case 2: sendExtend(900)
            case 3: model.extendPicker = false
            default: break
            }
            return
        }
        if presentation.showsArrivalGap {
            let contentWidth = panel.frame.width - Self.handleWidth
            let x = point.x - Self.handleWidth
            guard x >= 0 else { return }
            if presentation.canBoardReserved {
                if x < contentWidth / 2 {
                    Task { await runtime.sendBoardReserved() }
                } else {
                    Task { await runtime.sendStill() }
                }
            } else {
                Task { await runtime.sendStill() }
            }
            return
        }
        if presentation.showsNudgeChoices {
            switch choiceIndex(at: point) {
            case 0: handleNudgeChoice(.stillOnIt)
            case 1: handleNudgeChoice(.willExtend)
            case 2: handleNudgeChoice(.alreadyDone)
            case 3: handleNudgeChoice(.paused)
            default: break
            }
            return
        }
        if presentation.cabinPrompt != nil {
            let contentWidth = panel.frame.width - Self.handleWidth
            let x = point.x - Self.handleWidth
            if x < contentWidth / 2 {
                Task { await runtime.sendStill() }
            } else if presentation.canPause {
                Task { await runtime.sendPause() }
            }
            return
        }
        guard model.hovering else { return }
        if presentation.canResume {
            Task { await runtime.sendResume() }
        } else if presentation.canPause {
            Task { await runtime.sendPause() }
        }
    }

    private func choiceIndex(at point: NSPoint) -> Int? {
        let contentWidth = panel.frame.width - Self.handleWidth
        guard contentWidth > 0 else { return nil }
        let x = point.x - Self.handleWidth
        guard x >= 0 else { return nil }
        let index = Int(x / (contentWidth / 4))
        return min(index, 3)
    }

    private func handleNudgeChoice(_ choice: NudgeChoice) {
        guard !model.presentation.isSending else { return }
        if choice == .willExtend {
            model.extendPicker = true
            return
        }
        model.extendPicker = false
        Task { await runtime.sendNudgeAnswer(choice) }
    }

    private func sendExtend(_ seconds: Int) {
        guard !model.presentation.isSending else { return }
        model.extendPicker = false
        Task { await runtime.sendNudgeAnswer(.willExtend, addSeconds: seconds) }
    }

    private func restoreFromPeek() {
        guard layout.isTucked else { return }
        layout.isTucked = false
        persist()
        applyLayoutToChrome()
        applyFrame(animated: true)
    }

    private func applyFrame(animated: Bool) {
        guard let screen = targetScreen() else { return }
        let rect = RideOverlayGeometry.frame(
            for: layout,
            screen: OverlayScreen(screen)
        ).nsRect
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.hasShadow = !layout.isTucked
        if animated, !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(rect, display: true)
            }
        } else {
            panel.setFrame(rect, display: true)
        }
        panel.invalidateShadow()
    }

    private func persist() {
        OverlayLayoutPersisting.save(layout, screenID: screenID, to: defaults)
    }

    private func targetScreen() -> NSScreen? {
        if screenID != 0, let match = NSScreen.screens.first(where: { $0.overlayDisplayID == screenID }) {
            return match
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    @objc private func screensChanged() {
        guard dragStart == nil else { return }
        if targetScreen() == nil {
            screenID = NSScreen.main?.overlayDisplayID ?? 0
        }
        if lastVisible {
            applyFrame(animated: false)
        }
    }
}
