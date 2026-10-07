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
    private let ticketPanel: NSPanel
    private var alive = false
    private var dispensing = false
    private var dispenseModel: ImaYaruDispenseModel?
    private var attemptTitle = ""
    private var attemptMinutes = 30
    private var attemptPrior: UUID?

    init(runtime: CompanionMacRuntime, revealRide: @escaping () -> Void) {
        self.runtime = runtime
        self.revealRide = revealRide
        formPanel = ImaYaruFormPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 240),
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
        runtime.issueBoardTrack = .idle
        runtime.suppressRideOverlay = false
        ticketPanel.orderOut(nil)
        showForm(notice: nil)
    }

    func close() {
        alive = false
        dispensing = false
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
        let model = ImaYaruDispenseModel()
        dispenseModel = model
        let root = ImaYaruDispenseView(
            model: model,
            title: title,
            minutes: minutes,
            priorSessionId: prior,
            onReveal: { [weak self] in self?.reveal() },
            onGiveUp: { [weak self] in self?.giveUp() },
            onClose: { [weak self] in self?.close() }
        )
        .environment(runtime)
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
        install(root, in: ticketPanel, fillTicket: true)
        ticketPanel.alphaValue = 1
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let start = reduce ? anchor.rest : anchor.entry
        ticketPanel.setFrame(start, display: true)
        ticketPanel.orderFrontRegardless()
        ticketPanel.makeKey()
        if reduce {
            model.seated = true
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.48
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ticketPanel.animator().setFrame(anchor.rest, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.markTicketSeated()
            }
        }
    }

    private func markTicketSeated() {
        guard alive else { return }
        dispenseModel?.seated = true
    }

    private func reveal() {
        guard alive, dispensing else { return }
        dispensing = false
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

    private func install<V: View>(_ root: V, in panel: NSPanel, fillTicket: Bool = false) {
        let host = NSHostingView(rootView: root)
        if fillTicket {
            host.safeAreaRegions = []
        }
        host.sizingOptions = [.standardBounds]
        panel.contentView = host
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

/// Frame is not pinned, so the ticket can start off-screen.
final class ImaYaruTicketPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
