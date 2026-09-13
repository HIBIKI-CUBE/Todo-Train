//
//  TicketIssueEject.swift
//  Todo train
//
//  Single-issue: paper comes out of the sheet lip, uprights, then lands on the
//  deck slot (the real Hub card was hidden — no fade-clone). Swipe skips the hold.
//

import SwiftUI

struct TicketIssueEjectEvent: Identifiable, Equatable {
    let id: UUID
    let ticketID: UUID
    let title: String
    let minutes: Int
    let tagNames: [String]
    let issuedAt: Date

    init(
        id: UUID = UUID(),
        ticketID: UUID,
        title: String,
        minutes: Int,
        tagNames: [String] = [],
        issuedAt: Date = .now
    ) {
        self.id = id
        self.ticketID = ticketID
        self.title = title
        self.minutes = minutes
        self.tagNames = tagNames
        self.issuedAt = issuedAt
    }

    init(ticket: Ticket) {
        self.init(
            ticketID: ticket.id,
            title: ticket.title,
            minutes: max(1, ticket.estimatedSeconds / 60),
            tagNames: ticket.tags
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(\.name),
            issuedAt: ticket.createdAt
        )
    }

    var ticketContent: MarsTicketContent {
        MarsTicketContent(
            title: title,
            minutes: minutes,
            tagNames: tagNames,
            issuedAt: issuedAt
        )
    }

    static var presentationMilliseconds: Int {
        MarsTicketSpec.IssueMotion.presentationMilliseconds
    }
}

enum TicketIssueEjectFinish: Equatable {
    /// Hub: hold, then seat in the deck slot.
    case landInDeck
    /// Focus interrupt: after the ticket is readable, zoom into Focus.
    case zoomIntoFocus
}

/// Hub celebration: emerge from bottom edge → upright → hold → land in deck slot.
/// Interrupt: same eject, then the upright ticket becomes the Focus zoom source.
struct TicketIssueEjectOverlay: View {
    let event: TicketIssueEjectEvent
    /// Resting frame of the real deck card, in `HubTicketCanvas` space.
    var landingRect: CGRect?
    var finish: TicketIssueEjectFinish = .landInDeck
    var onFinished: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.focusZoomNamespace) private var focusZoomNamespace

    private enum Phase: Equatable {
        case idle
        case ejecting
        case ejected
        case upright
        case landing
    }

    @State private var phase: Phase = .idle
    @State private var ejectProgress: CGFloat = 0
    @State private var dragY: CGFloat = 0
    @State private var runID = UUID()
    @State private var ejectHaptic = 0
    @State private var landHaptic = 0
    @State private var finishing = false

    private var canDismissInteractively: Bool {
        switch phase {
        case .ejected, .upright: true
        case .idle, .ejecting, .landing: false
        }
    }

    var body: some View {
        GeometryReader { geo in
            scene(in: geo)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("発券。\(event.title)。\(event.minutes)分")
        .accessibilityHint(
            finish == .zoomIntoFocus
                ? "表示のあと自動で発車します。下にスワイプですぐ発車"
                : "下にスワイプでデッキに収めます"
        )
        .accessibilityAction(.escape) {
            finishSequence()
        }
        .sensoryFeedback(.impact(weight: .medium, intensity: 1.0), trigger: ejectHaptic)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: landHaptic)
        .onAppear { startRun() }
        .onChange(of: event.id) { _, _ in startRun() }
    }

    private func scene(in geo: GeometryProxy) -> some View {
        let layout = layoutMetrics(in: geo)
        return ZStack {
            Color.black
                .opacity(scrimOpacity * Double(max(0, 1 - dragY / 220)))
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if showsBottomMouth {
                Rectangle()
                    .fill(Color.primary.opacity(0.22))
                    .frame(height: 3)
                    .frame(maxWidth: .infinity)
                    .opacity(bottomMouthOpacity)
                    .position(x: geo.size.width / 2, y: layout.bottom - 1.5)
            }

            ticketFace
                .frame(width: layout.ticketWidth, height: layout.ticketHeight)
                .rotation3DEffect(
                    .degrees(slotOriented ? MarsTicketSpec.IssueMotion.slotRotationDegrees : 0),
                    axis: (x: 0.12, y: 0, z: 1),
                    perspective: 0.65
                )
                .position(x: layout.center.x, y: layout.center.y)
                .mask(alignment: .top) {
                    Rectangle()
                        .frame(width: geo.size.width, height: layout.bottom)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
        }
        .frame(width: geo.size.width, height: geo.size.height)
        .contentShape(Rectangle())
        .gesture(dismissGesture)
    }

    private struct LayoutMetrics {
        var ticketWidth: CGFloat
        var ticketHeight: CGFloat
        var bottom: CGFloat
        var center: CGPoint
    }

    @ViewBuilder
    private var ticketFace: some View {
        let face = MarsTicketView(content: event.ticketContent, titleReveal: 1)
        if finish == .zoomIntoFocus, let focusZoomNamespace {
            face.matchedTransitionSource(id: event.ticketID, in: focusZoomNamespace)
        } else {
            face
        }
    }

    private func layoutMetrics(in geo: GeometryProxy) -> LayoutMetrics {
        let defaultWidth = min(geo.size.width - MarsTicketSpec.horizontalMargin * 2, 420)
        let defaultHeight = MarsTicketSpec.height(forWidth: defaultWidth)
        let landing = landingRect
        let ticketWidth: CGFloat
        let ticketHeight: CGFloat
        if phase == .landing, let landing, landing.width > 8 {
            let clamped = TrainLayout.clampedLandingRect(landing, containerSize: geo.size)
            ticketWidth = clamped.width
            ticketHeight = clamped.height
        } else {
            ticketWidth = defaultWidth
            ticketHeight = defaultHeight
        }
        let bottom = geo.size.height
        let emergedCenterY = bottom - ticketWidth * 0.52 - geo.safeAreaInsets.bottom - 12
        let hiddenCenterY = bottom + ticketWidth * 0.55 + 8
        let uprightCenterY = geo.size.height * 0.42
        let center = ticketCenter(
            size: geo.size,
            hiddenCenterY: hiddenCenterY,
            emergedCenterY: emergedCenterY,
            uprightCenterY: uprightCenterY,
            landing: landing
        )
        return LayoutMetrics(
            ticketWidth: ticketWidth,
            ticketHeight: ticketHeight,
            bottom: bottom,
            center: center
        )
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard canDismissInteractively, !finishing else { return }
                dragY = max(0, value.translation.height)
            }
            .onEnded { value in
                guard canDismissInteractively, !finishing else { return }
                let dy = max(0, value.translation.height)
                let predicted = max(dy, value.predictedEndTranslation.height)
                if predicted > 90 || dy > 70 {
                    finishSequence()
                } else {
                    withAnimation(MarsTicketSpec.IssueMotion.upright) {
                        dragY = 0
                    }
                }
            }
    }

    private var slotOriented: Bool {
        switch phase {
        case .idle, .ejecting, .ejected: true
        case .upright, .landing: false
        }
    }

    private var showsBottomMouth: Bool {
        slotOriented
    }

    private var bottomMouthOpacity: Double {
        switch phase {
        case .idle: 0.15
        case .ejecting: 0.45
        case .ejected: 0.2
        case .upright, .landing: 0
        }
    }

    private var scrimOpacity: Double {
        switch phase {
        case .idle: 0.06
        case .ejecting, .ejected, .upright: 0.2
        case .landing: 0
        }
    }

    private func ticketCenter(
        size: CGSize,
        hiddenCenterY: CGFloat,
        emergedCenterY: CGFloat,
        uprightCenterY: CGFloat,
        landing: CGRect?
    ) -> CGPoint {
        switch phase {
        case .idle:
            return CGPoint(x: size.width / 2, y: hiddenCenterY)
        case .ejecting, .ejected:
            return CGPoint(
                x: size.width / 2,
                y: hiddenCenterY + (emergedCenterY - hiddenCenterY) * ejectProgress + dragY
            )
        case .upright:
            return CGPoint(x: size.width / 2, y: uprightCenterY + dragY)
        case .landing:
            if let landing, landing.width > 8 {
                let clamped = TrainLayout.clampedLandingRect(landing, containerSize: size)
                return CGPoint(x: clamped.midX, y: clamped.midY)
            }
            return CGPoint(x: size.width / 2, y: uprightCenterY)
        }
    }

    private func finishSequence() {
        switch finish {
        case .landInDeck:
            landIntoDeck()
        case .zoomIntoFocus:
            commitZoom()
        }
    }

    private func commitZoom() {
        guard !finishing else { return }
        finishing = true
        runID = UUID()
        landHaptic += 1
        dragY = 0
        onFinished?()
    }

    private func landIntoDeck() {
        guard !finishing else { return }
        finishing = true
        runID = UUID()
        landHaptic += 1
        dragY = 0
        withAnimation(MarsTicketSpec.IssueMotion.settle) {
            phase = .landing
        } completion: {
            onFinished?()
        }
    }

    private func startRun() {
        let token = UUID()
        runID = token
        phase = .idle
        ejectProgress = 0
        dragY = 0
        finishing = false

        if reduceMotion {
            ejectProgress = 1
            withAnimation(.easeOut(duration: 0.12)) {
                phase = .upright
            } completion: {
                guard runID == token, !finishing else { return }
                finishSequence()
            }
            return
        }

        ejectHaptic += 1
        phase = .ejecting
        withAnimation(MarsTicketSpec.IssueMotion.eject) {
            ejectProgress = 1
        } completion: {
            guard runID == token, !finishing else { return }
            phase = .ejected
            withAnimation(MarsTicketSpec.IssueMotion.upright) {
                phase = .upright
            } completion: {
                guard runID == token, !finishing else { return }
                holdThenFinish(token: token)
            }
        }
    }

    private func holdThenFinish(token: UUID) {
        let hold = finish == .zoomIntoFocus
            ? MarsTicketSpec.IssueMotion.interruptZoomHoldMilliseconds
            : MarsTicketSpec.IssueMotion.readableHoldMilliseconds
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(hold))
            guard runID == token, !finishing else { return }
            finishSequence()
        }
    }
}

#Preview("Issue eject") {
    ZStack {
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        TicketIssueEjectOverlay(
            event: TicketIssueEjectEvent(
                ticketID: UUID(),
                title: "週次レビューの下書き",
                minutes: 25,
                tagNames: ["仕事"]
            )
        )
    }
}
