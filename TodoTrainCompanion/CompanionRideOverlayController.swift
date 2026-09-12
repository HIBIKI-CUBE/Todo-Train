import AppKit
import Observation
import QuartzCore
import SwiftUI
import TodoTrainSync

@MainActor
final class CompanionRideOverlayController: NSObject {
    private let runtime: CompanionMacRuntime
    private let defaults: UserDefaults
    private let panel = CompanionRideOverlayPanel()
    private let model = CompanionRideOverlayModel()
    private var layout: OverlayLayoutState
    private var screenID: UInt32
    private var dragStart: NSRect?
    private var lastVisible = false

    init(runtime: CompanionMacRuntime, defaults: UserDefaults = .standard) {
        self.runtime = runtime
        self.defaults = defaults
        self.layout = OverlayLayoutPersisting.load(defaults)
        self.screenID = OverlayLayoutPersisting.screenID(defaults)
        super.init()
        let root = CompanionRideOverlayView(
            model: model,
            onPause: { [weak self] in
                guard let self else { return }
                Task { await self.runtime.sendPause() }
            },
            onResume: { [weak self] in
                guard let self else { return }
                Task { await self.runtime.sendResume() }
            },
            onPeekClick: { [weak self] in self?.restoreFromPeek() },
            onDragChanged: { [weak self] translation in self?.dragChanged(translation) },
            onDragEnded: { [weak self] translation in self?.dragEnded(translation) }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.safeAreaRegions = []
        panel.contentView = hosting
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

    private func applyPresentation(_ presentation: RideOverlayPresentation) {
        model.presentation = presentation
        model.isTucked = layout.isTucked
        model.edge = layout.edge
        let visible = presentation.isVisible
        if visible {
            if !lastVisible {
                applyFrame(animated: false)
                panel.orderFrontRegardless()
            }
        } else {
            panel.orderOut(nil)
        }
        lastVisible = visible
    }

    private func dragChanged(_ translation: CGSize) {
        if dragStart == nil {
            dragStart = panel.frame
        }
        guard var frame = dragStart else { return }
        frame.origin.x += translation.width
        frame.origin.y += translation.height
        panel.setFrame(frame, display: true)
    }

    private func dragEnded(_ translation: CGSize) {
        let distance = hypot(translation.width, translation.height)
        dragStart = nil
        if layout.isTucked, distance < 6 {
            restoreFromPeek()
            return
        }
        guard let screen = screenContaining(panel.frame) ?? targetScreen() else { return }
        screenID = screen.overlayDisplayID
        layout = RideOverlayGeometry.layout(
            afterDrag: OverlayRect(panel.frame),
            screen: OverlayRect(screen.visibleFrame)
        )
        persist()
        model.isTucked = layout.isTucked
        model.edge = layout.edge
        applyFrame(animated: true)
    }

    private func restoreFromPeek() {
        guard layout.isTucked else { return }
        layout.isTucked = false
        persist()
        model.isTucked = false
        applyFrame(animated: true)
    }

    private func applyFrame(animated: Bool) {
        guard let screen = targetScreen() else { return }
        let rect = RideOverlayGeometry.frame(
            for: layout,
            screen: OverlayRect(screen.visibleFrame)
        ).nsRect
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
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

    private func screenContaining(_ frame: NSRect) -> NSScreen? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { NSMouseInRect(center, $0.frame, false) }
            ?? NSScreen.screens.first { $0.frame.intersects(frame) }
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
