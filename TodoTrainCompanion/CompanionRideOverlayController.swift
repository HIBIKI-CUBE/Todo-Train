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
                onRestore: { [weak self] in self?.restoreFromPeek() }
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

    private func applyPresentation(_ presentation: RideOverlayPresentation) {
        let cabinAppeared = presentation.cabinPrompt != nil && lastCabinPrompt == nil
        model.presentation = presentation
        applyLayoutToChrome()
        let visible = presentation.isVisible
        if visible {
            if !lastVisible {
                applyFrame(animated: false)
                panel.orderFrontRegardless()
            }
            if cabinAppeared {
                model.hovering = false
                if layout.isTucked {
                    restoreFromPeek()
                }
                if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    NSSound(named: "Tink")?.play()
                }
            }
        } else {
            panel.orderOut(nil)
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
