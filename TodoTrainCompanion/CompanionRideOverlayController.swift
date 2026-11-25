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
                onToggleHold: { [weak self] in
                    guard let self else { return }
                    Task { await self.runtime.sendPauseOrResume() }
                },
                onStill: { [weak self] in
                    guard let self else { return }
                    Task { await self.runtime.sendStill() }
                },
                onRestore: { [weak self] in self?.restoreFromPeek() },
                onNudgeChoice: { [weak self] choice in
                    self?.handleNudgeChoice(choice)
                },
                onOpenProgress: { [weak self] in
                    self?.openProgressBand()
                },
                onSelectProgress: { [weak self] progress in
                    self?.selectProgress(progress)
                },
                onCommitReestimate: { [weak self] choice in
                    self?.commitReestimate(choice)
                },
                onUndoReestimate: { [weak self] in
                    self?.undoReestimate()
                },
                onBoardReserved: { [weak self] in
                    guard let self else { return }
                    Task { await self.runtime.sendBoardReserved() }
                },
                onCloseGap: { [weak self] in
                    guard let self else { return }
                    Task { await self.runtime.sendStill() }
                },
                onPausePrompt: { [weak self] choice in
                    self?.runtime.answerPausePrompt(choice)
                },
                onAcknowledgeRadio: { [weak self] in
                    self?.runtime.acknowledgeRadio()
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

    private func syncReestimateChrome() {
        let nudgeID = runtime.snap?.nudge?.id
        if nudgeID != lastNudgeID {
            lastNudgeID = nudgeID
            if model.reestimateUndoUntil == nil {
                model.settledNudgeID = nil
                model.reestimateBand = nil
                model.reestimateProgress = nil
            } else {
                model.settledNudgeID = nil
            }
        }
        syncPositionCheckContext()
        let previousUndo = model.reestimateUndoUntil
        model.reestimateUndoUntil = runtime.reestimateUndoUntil
        if let previousUndo, runtime.reestimateUndoUntil == nil, runtime.now < previousUndo {
            if case .failed = runtime.outgoingPause {
                model.settledNudgeID = nil
                model.reestimateBand = nil
                model.reestimateProgress = nil
            }
        }
    }

    private func syncPositionCheckContext() {
        guard let snap = runtime.snap else {
            model.positionActiveSeconds = 0
            model.positionPlannedBudgetSeconds = 0
            model.positionRemainingSeconds = 0
            model.positionNowUnix = runtime.now
            return
        }
        model.positionNowUnix = runtime.now
        model.positionActiveSeconds = TimeInterval(snap.elapsedActiveSeconds(at: runtime.now) ?? 0)
        model.positionPlannedBudgetSeconds = snap.estimatedSeconds ?? 0
        model.positionRemainingSeconds = max(0, snap.remainingSeconds(at: runtime.now) ?? 0)
    }

    private func applyPresentation(_ presentation: RideOverlayPresentation) {
        syncReestimateChrome()
        if runtime.suppressRideOverlay {
            model.presentation = presentation
            panel.orderOut(nil)
            lastVisible = false
            lastCabinPrompt = presentation.cabinPrompt
            return
        }
        let cabinAppeared = presentation.cabinPrompt != nil && lastCabinPrompt == nil
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
        if model.reestimateUndoUntil != nil {
            let contentWidth = panel.frame.width - Self.handleWidth
            let x = point.x - Self.handleWidth
            if PipHoverStrip.action(x: x, contentWidth: contentWidth, undoVisible: true) == .undo {
                undoReestimate()
            }
            return
        }
        if presentation.isSending { return }
        if let band = model.activeReestimateBand(showsNudgeChoices: presentation.showsNudgeChoices) {
            handleBandClick(band, at: point)
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
        if presentation.pausePrompt != nil {
            let contentWidth = panel.frame.width - Self.handleWidth
            let x = point.x - Self.handleWidth
            guard x >= 0 else { return }
            if x < contentWidth / 2 {
                runtime.answerPausePrompt(.resume)
            } else {
                runtime.answerPausePrompt(.keepPaused)
            }
            return
        }
        if presentation.cabinPrompt != nil {
            let contentWidth = panel.frame.width - Self.handleWidth
            let x = point.x - Self.handleWidth
            if x < contentWidth / 2 {
                Task { await runtime.sendStill() }
            } else {
                Task { await runtime.sendPauseOrResume() }
            }
            return
        }
        guard model.hovering, presentation.canPause || presentation.canResume else { return }
        let contentWidth = panel.frame.width - Self.handleWidth
        let x = point.x - Self.handleWidth
        switch PipHoverStrip.action(x: x, contentWidth: contentWidth, undoVisible: false) {
        case .positionCheck:
            openProgressBand()
        case .pauseOrResume:
            Task { await runtime.sendPauseOrResume() }
        case .undo, nil:
            break
        }
    }

    /// Hover の「位置確認」。声掛けの四択は経由しない。
    private func openProgressBand() {
        model.reestimateBand = .progress
        model.reestimateProgress = nil
    }

    private func handleBandClick(_ band: PipReestimateBand, at point: NSPoint) {
        switch band {
        case .answers:
            switch choiceIndex(at: point) {
            case 0: handleNudgeChoice(.stillOnIt)
            case 1: openProgressBand()
            case 2: handleNudgeChoice(.alreadyDone)
            case 3: handleNudgeChoice(.paused)
            default: break
            }
        case .progress:
            let ratios = MacPipReestimate.progressAnswers
            guard let index = choiceIndex(at: point, segments: ratios.count),
                  ratios.indices.contains(index) else { return }
            selectProgress(ratios[index])
        case .declare:
            guard let progress = model.reestimateProgress,
                  let labels = MacPipReestimate.declareLabels(
                    progress: progress,
                    activeSeconds: model.positionActiveSeconds,
                    plannedBudgetSeconds: model.positionPlannedBudgetSeconds,
                    remainingSeconds: model.positionRemainingSeconds,
                    now: Date(timeIntervalSince1970: TimeInterval(model.positionNowUnix))
                  ) else { return }
            let segments = labels.showsRecovery ? 2 : 1
            guard let index = choiceIndex(at: point, segments: segments) else { return }
            if labels.showsRecovery {
                switch index {
                case 0:
                    commitReestimate(.recovery(
                        progress: progress,
                        committedRemainingSeconds: model.positionRemainingSeconds
                    ))
                case 1:
                    commitReestimate(.adjust(progress: progress))
                default:
                    break
                }
            } else if index == 0 {
                commitReestimate(.adjust(progress: progress))
            }
        }
    }

    private func selectProgress(_ progress: Double) {
        model.reestimateProgress = progress
        syncPositionCheckContext()
        model.reestimateBand = .declare
    }

    private func commitReestimate(_ choice: MacPipReestimateChoice) {
        guard !model.presentation.isSending else { return }
        let nudgeID = runtime.snap?.nudge?.id
        Task { @MainActor in
            let sent = await runtime.sendReestimate(choice)
            guard sent else { return }
            model.reestimateBand = nil
            model.reestimateProgress = nil
            model.settledNudgeID = nudgeID
            model.reestimateUndoUntil = runtime.reestimateUndoUntil
        }
    }

    private func undoReestimate() {
        model.settledNudgeID = nil
        model.reestimateBand = nil
        model.reestimateProgress = nil
        Task { await runtime.sendUndoReestimate() }
    }

    private func choiceIndex(at point: NSPoint, segments: Int = 4) -> Int? {
        guard segments > 0 else { return nil }
        let contentWidth = panel.frame.width - Self.handleWidth
        guard contentWidth > 0 else { return nil }
        let x = point.x - Self.handleWidth
        guard x >= 0 else { return nil }
        let index = Int(x / (contentWidth / CGFloat(segments)))
        return min(max(index, 0), segments - 1)
    }

    private func handleNudgeChoice(_ choice: NudgeChoice) {
        guard choice == .stillOnIt || choice == .alreadyDone || choice == .paused else { return }
        guard !model.presentation.isSending else { return }
        model.reestimateBand = nil
        model.reestimateProgress = nil
        Task { await runtime.sendNudgeAnswer(choice) }
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
