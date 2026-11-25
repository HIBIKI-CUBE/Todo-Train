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
    private let scrollBridge = ImaYaruScrollBridge()
    private var scrollMonitor: Any?
    private var alive = false

    init(runtime: CompanionMacRuntime, revealRide: @escaping () -> Void) {
        self.runtime = runtime
        self.revealRide = revealRide
        formPanel = ImaYaruFormPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 260),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configure(formPanel)
    }

    func present() {
        alive = true
        runtime.issueBoardTrack = .idle
        runtime.issueOnlyFailure = nil
        runtime.suppressRideOverlay = false
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        showForm(on: screen, mouse: mouse, notice: nil)
    }

    func close() {
        alive = false
        runtime.suppressRideOverlay = false
        runtime.issueBoardTrack = .idle
        removeScrollMonitor()
        formPanel.orderOut(nil)
    }

    private func showForm(on screen: NSScreen, mouse: NSPoint, notice: String?, title: String = "", minutes: Int = 30, prior: UUID? = nil) {
        let ticket = ImaYaruTicketMetrics.points(on: screen)
        let anchor = CGPoint(
            x: mouse.x - screen.frame.minX,
            y: screen.frame.maxY - mouse.y
        )
        let root = ImaYaruFormView(
            initialNotice: notice,
            seededTitle: title,
            seededMinutes: minutes,
            seededPrior: prior,
            anchor: clamped(anchor, on: screen, ticket: ticket),
            stageSize: screen.frame.size,
            ticketSize: ticket,
            menuAnchor: menuAnchor(on: screen),
            scrollBridge: scrollBridge,
            onDispense: { [weak self] _, _, _ in
                self?.completeDepart()
            },
            onClose: { [weak self] in
                self?.close()
            }
        )
        .environment(runtime)
        install(root, in: formPanel, screen: screen)
        formPanel.setFrame(screen.frame, display: true)
        installScrollMonitor()
        NSApp.activate(ignoringOtherApps: true)
        formPanel.orderFrontRegardless()
        formPanel.makeKey()
    }

    private func completeDepart() {
        guard alive else { return }
        runtime.suppressRideOverlay = false
        revealRide()
        close()
    }

    private func install<V: View>(_ root: V, in panel: NSPanel, screen: NSScreen) {
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        host.frame = NSRect(origin: .zero, size: screen.frame.size)
        panel.contentView = host
    }

    private func configure(_ panel: NSPanel) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .none
        panel.isExcludedFromWindowsMenu = true
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.isMovable = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.tabbingMode = .disallowed
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
    }

    private func clamped(_ anchor: CGPoint, on screen: NSScreen, ticket: CGSize) -> CGPoint {
        let margin: CGFloat = 24
        let halfCard = ImaYaruMachineMetrics.fitted(ticket: ticket).body.width / 2 + margin
        let halfTicket = ticket.height / 2 + margin
        let size = screen.frame.size
        return CGPoint(
            x: min(max(anchor.x, halfCard), max(halfCard, size.width - halfCard)),
            y: min(max(anchor.y, halfTicket), max(halfTicket, size.height - halfTicket))
        )
    }

    /// Menu-bar train icon, in the panel's top-left coordinates. Falls back to the clock side.
    private func menuAnchor(on screen: NSScreen) -> CGPoint {
        for window in NSApp.windows {
            guard let button = window.contentView?.subviews.first(where: { $0 is NSStatusBarButton }) else { continue }
            let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
            guard screen.frame.intersects(frame) else { continue }
            return CGPoint(
                x: frame.midX - screen.frame.minX,
                y: screen.frame.maxY - frame.midY
            )
        }
        let visible = screen.visibleFrame
        return CGPoint(
            x: visible.maxX - screen.frame.minX - 28,
            y: screen.frame.maxY - visible.maxY + 8
        )
    }

    private func installScrollMonitor() {
        removeScrollMonitor()
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.formPanel else { return event }
            guard event.hasPreciseScrollingDeltas else { return event }
            if event.momentumPhase != [] { return nil }
            let deltas = event.imaYaruStrokeDeltas()
            self.scrollBridge.onScroll?(deltas.dx, deltas.dy, event.phase)
            return nil
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
        scrollMonitor = nil
    }
}

final class ImaYaruFormPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
