import AppKit
import SwiftUI
import TodoTrainSync

enum ImaYaruOpener {
    static var present: (() -> Void)?
}

@MainActor
final class ImaYaruPanelController {
    private let runtime: CompanionMacRuntime
    private let revealRide: () -> Void
    private let formPanel: NSPanel
    private let ticketPanel: ImaYaruTicketPanel
    private var alive = false
    private var dispensing = false
    private var dispenseModel: ImaYaruDispenseModel?
    private var attemptTitle = ""
    private var attemptMinutes = 30
    private var attemptPrior: UUID?
    private var slideTimer: Timer?

    init(runtime: CompanionMacRuntime, revealRide: @escaping () -> Void) {
        self.runtime = runtime
        self.revealRide = revealRide
        formPanel = ImaYaruFormPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 260),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        ticketPanel = ImaYaruTicketPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configure(formPanel, titled: true)
        configure(ticketPanel, titled: false)
        ticketPanel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        ticketPanel.hasShadow = true
        ticketPanel.isMovable = false
        formPanel.isMovable = true
        formPanel.title = "いまやる"
    }

    func present() {
        alive = true
        dispensing = false
        stopSlide()
        runtime.issueBoardTrack = .idle
        runtime.suppressRideOverlay = false
        ticketPanel.orderOut(nil)
        showForm(notice: nil)
    }

    func close() {
        alive = false
        dispensing = false
        stopSlide()
        runtime.suppressRideOverlay = false
        runtime.issueBoardTrack = .idle
        formPanel.orderOut(nil)
        ticketPanel.orderOut(nil)
    }

    private func showForm(notice: String?, title: String = "", minutes: Int = 30, prior: UUID? = nil) {
        let root = ImaYaruFormView(
            initialNotice: notice,
            seededTitle: title,
            seededMinutes: minutes,
            seededPrior: prior,
            onDispense: { [weak self] title, minutes, prior in
                self?.beginDispense(title: title, minutes: minutes, prior: prior)
            },
            onClose: { [weak self] in
                self?.close()
            }
        )
        .environment(runtime)
        install(root, in: formPanel)
        formPanel.alphaValue = 1
        formPanel.setFrame(centeredFormFrame(), display: true)
        NSApp.activate(ignoringOtherApps: true)
        formPanel.orderFrontRegardless()
        formPanel.makeKey()
    }

    private func beginDispense(title: String, minutes: Int, prior: UUID?) {
        guard alive, !dispensing else { return }
        dispensing = true
        attemptTitle = title
        attemptMinutes = minutes
        attemptPrior = prior
        formPanel.orderOut(nil)
        guard let anchor = anchorFrames() else {
            runtime.suppressRideOverlay = false
            dispensing = false
            showForm(
                notice: SyncCopy.iphoneNoReply,
                title: title,
                minutes: minutes,
                prior: prior
            )
            return
        }
        let model = ImaYaruDispenseModel()
        dispenseModel = model
        let root = ImaYaruDispenseView(
            model: model,
            title: title,
            minutes: minutes,
            ticketSize: anchor.rest.size,
            priorSessionId: prior,
            onReveal: { [weak self] in self?.reveal() },
            onGiveUp: { [weak self] in self?.giveUp() },
            onClose: { [weak self] in self?.close() }
        )
        .environment(runtime)
        installTicket(root, size: anchor.rest.size)
        ticketPanel.alphaValue = 1
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let start = reduce ? anchor.rest : anchor.entry
        ticketPanel.setFrame(start, display: false)
        ticketPanel.contentView?.layoutSubtreeIfNeeded()
        ticketPanel.orderFrontRegardless()
        ticketPanel.makeKey()
        if reduce {
            model.seated = true
            return
        }
        slideTicket(from: start, to: anchor.rest)
    }

    /// `animator().setFrame` can leave a borderless panel off-screen. Step the origin ourselves.
    private func slideTicket(from start: NSRect, to rest: NSRect) {
        stopSlide()
        let duration = 0.48
        let started = Date()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            let raw = min(1, Date().timeIntervalSince(started) / duration)
            let eased = 1 - pow(1 - raw, 3)
            let frame = NSRect(
                x: start.origin.x + (rest.origin.x - start.origin.x) * eased,
                y: start.origin.y + (rest.origin.y - start.origin.y) * eased,
                width: rest.width,
                height: rest.height
            )
            let finished = raw >= 1
            Task { @MainActor [weak self] in
                guard let self, self.alive, self.dispensing else {
                    self?.stopSlide()
                    return
                }
                self.ticketPanel.setFrame(finished ? rest : frame, display: true)
                if finished {
                    self.stopSlide()
                    self.ticketPanel.invalidateShadow()
                    self.markTicketSeated()
                }
            }
        }
        slideTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopSlide() {
        slideTimer?.invalidate()
        slideTimer = nil
    }

    private func markTicketSeated() {
        guard alive else { return }
        dispenseModel?.seated = true
    }

    private func reveal() {
        guard alive, dispensing else { return }
        dispensing = false
        stopSlide()
        runtime.suppressRideOverlay = false
        revealRide()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            guard self.alive else { return }
            self.ticketPanel.orderOut(nil)
            self.dispensing = false
            self.runtime.issueBoardTrack = .idle
        }
    }

    private func giveUp() {
        guard alive, dispensing else { return }
        dispensing = false
        stopSlide()
        runtime.suppressRideOverlay = false
        ticketPanel.orderOut(nil)
        dispensing = false
        runtime.issueBoardTrack = .idle
        showForm(
            notice: SyncCopy.iphoneNoReply,
            title: attemptTitle,
            minutes: attemptMinutes,
            prior: attemptPrior
        )
    }

    private func install<V: View>(_ root: V, in panel: NSPanel) {
        let host = NSHostingView(rootView: root)
        host.sizingOptions = [.standardBounds]
        panel.contentView = host
    }

    /// GeometryReader's ideal size is ~0. Letting the hosting view size the window hides the face.
    private func installTicket<V: View>(_ root: V, size: NSSize) {
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]

        let container = TicketDispenseRootView(frame: NSRect(origin: .zero, size: size))
        host.frame = container.bounds
        container.addSubview(host)

        ticketPanel.lockedSize = size
        ticketPanel.contentMinSize = size
        ticketPanel.contentMaxSize = size
        ticketPanel.minSize = size
        ticketPanel.maxSize = size
        ticketPanel.contentView = container
        container.layoutSubtreeIfNeeded()
    }

    private func configure(_ panel: NSPanel, titled: Bool) {
        panel.isOpaque = titled
        panel.backgroundColor = titled ? .windowBackgroundColor : .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .none
        panel.isExcludedFromWindowsMenu = true
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.tabbingMode = .disallowed
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        if !titled {
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
        }
    }

    private func centeredFormFrame() -> NSRect {
        let size = formPanel.frame.size
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        return NSRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func anchorFrames() -> (entry: NSRect, rest: NSRect)? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        let layout = OverlayLayoutPersisting.load(runtime.defaults)
        let savedID = OverlayLayoutPersisting.screenID(runtime.defaults)
        let screen = screens.first { $0.overlayDisplayID == savedID } ?? NSScreen.main ?? screens[0]
        var parked = layout
        parked.isTucked = false
        let pip = RideOverlayGeometry.frame(
            for: parked,
            screen: OverlayScreen(screen)
        ).nsRect
        let rest = TicketDispenseGeometry.restingFrame(pip: pip)
        let entry = TicketDispenseGeometry.entryFrame(resting: rest, display: screen.frame)
        return (entry, rest)
    }
}

final class ImaYaruFormPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Origin may start off-screen. Size stays the Mars face, so the window cannot collapse.
final class ImaYaruTicketPanel: NSPanel {
    var lockedSize: NSSize = .zero

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        var rect = frameRect
        if lockedSize.width > 1, lockedSize.height > 1 {
            rect.size = lockedSize
        }
        return rect
    }
}

private final class TicketDispenseRootView: NSView {
    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        for subview in subviews {
            subview.frame = bounds
        }
    }
}
