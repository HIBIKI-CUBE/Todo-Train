import AppKit

enum ImaYaruOpener {
    static var present: (() -> Void)?
}
import SwiftUI
import TodoTrainSync

@MainActor
final class ImaYaruPanelController {
    private let runtime: CompanionMacRuntime
    private let panel: NSPanel
    private var didHandOff = false

    init(runtime: CompanionMacRuntime) {
        self.runtime = runtime
        let size = ImaYaruCanvas.size
        panel = ImaYaruPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.isExcludedFromWindowsMenu = true
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.tabbingMode = .disallowed
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        panel.minSize = size
        panel.maxSize = size
        panel.contentMinSize = size
        panel.contentMaxSize = size
    }

    func present() {
        didHandOff = false
        runtime.issueBoardTrack = .idle
        let size = ImaYaruCanvas.size
        panel.minSize = size
        panel.maxSize = size
        panel.contentMinSize = size
        panel.contentMaxSize = size
        let root = ImaYaruFlowView(
            onHandOff: { [weak self] in self?.handOff() },
            onClose: { [weak self] in self?.close() }
        )
        .environment(runtime)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: ImaYaruCanvas.size)
        panel.contentView = host
        panel.alphaValue = 1
        panel.setFrame(centeredFrame(), display: true)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func close() {
        panel.orderOut(nil)
        runtime.issueBoardTrack = .idle
    }

    private func handOff() {
        guard !didHandOff else { return }
        didHandOff = true
        let target = pipFrame() ?? panel.frame
        let unlocked = NSSize(width: 4_000, height: 4_000)
        panel.minSize = NSSize(width: 1, height: 1)
        panel.maxSize = unlocked
        panel.contentMinSize = panel.minSize
        panel.contentMaxSize = unlocked
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduce {
            panel.setFrame(target, display: true)
            panel.alphaValue = 1
            close()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.38
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 0.01
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.close()
            }
        }
    }

    private func centeredFrame() -> NSRect {
        let size = ImaYaruCanvas.size
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        return NSRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func pipFrame() -> NSRect? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        let layout = OverlayLayoutPersisting.load(runtime.defaults)
        let savedID = OverlayLayoutPersisting.screenID(runtime.defaults)
        let screen = screens.first { $0.overlayDisplayID == savedID } ?? NSScreen.main ?? screens[0]
        return RideOverlayGeometry.frame(
            for: layout,
            screen: OverlayScreen(screen)
        ).nsRect
    }
}

/// Borderless panel that can take keyboard focus. Frame is not pinned, so handoff can fly to the PiP.
final class ImaYaruPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
