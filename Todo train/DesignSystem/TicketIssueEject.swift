//
//  TicketIssueEject.swift
//  Todo train
//
//  Single-issue: ticket slides up from the screen bottom (sheet exit edge),
//  90° CW and already printed, then uprights. Swipe down dismisses early.
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

/// Hub celebration: emerge from bottom edge → upright → hold → settle.
/// Downward swipe dismisses early (same path as settle).
struct TicketIssueEjectOverlay: View {
    let event: TicketIssueEjectEvent
    var onFinished: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase: Equatable {
        /// Fully below the bottom edge.
        case idle
        /// Sliding up from the bottom, still 90° CW.
        case ejecting
        /// On-screen, still 90° CW.
        case ejected
        /// Landscape upright.
        case upright
        case settling
        case gone
    }

    @State private var phase: Phase = .idle
    /// 0 = below bottom edge, 1 = fully on screen (slot orientation).
    @State private var ejectProgress: CGFloat = 0
    /// Interactive dismiss drag (down positive).
    @State private var dragY: CGFloat = 0
    @State private var runID = UUID()
    @State private var ejectHaptic = 0
    @State private var landHaptic = 0
    @State private var finishing = false

    private var canDismissInteractively: Bool {
        switch phase {
        case .ejected, .upright: true
        case .idle, .ejecting, .settling, .gone: false
        }
    }

    var body: some View {
        GeometryReader { geo in
            let ticketWidth = min(
                geo.size.width - MarsTicketSpec.horizontalMargin * 2,
                420
            )
            let ticketHeight = MarsTicketSpec.height(forWidth: ticketWidth)
            // 90° CW → long edge vertical.
            let verticalSpan = ticketWidth
            let bottom = geo.size.height
            // Resting place while still portrait-oriented (above the bottom edge).
            let emergedCenterY = bottom - verticalSpan * 0.52 - geo.safeAreaInsets.bottom - 12
            // Fully tucked under the bottom edge (sheet / machine mouth).
            let hiddenCenterY = bottom + verticalSpan * 0.55 + 8
            let uprightCenterY = geo.size.height * 0.42
            let centerY = ticketCenterY(
                hiddenCenterY: hiddenCenterY,
                emergedCenterY: emergedCenterY,
                uprightCenterY: uprightCenterY
            ) + dragY

            ZStack {
                Color.black
                    .opacity(scrimOpacity * Double(max(0, 1 - dragY / 220)))
                    .ignoresSafeArea()

                // Bottom-edge mouth only — never a floating mid-air lip.
                if showsBottomMouth {
                    Rectangle()
                        .fill(Color.primary.opacity(0.22))
                        .frame(height: 3)
                        .frame(maxWidth: .infinity)
                        .opacity(bottomMouthOpacity)
                        .position(x: geo.size.width / 2, y: bottom - 1.5)
                }

                MarsTicketView(content: event.ticketContent, titleReveal: 1)
                    .frame(width: ticketWidth, height: ticketHeight)
                    .rotationEffect(.degrees(slotOriented ? 90 : 0))
                    .position(x: geo.size.width / 2, y: centerY)
                    .opacity(cardOpacity)
                    // Clip to the screen: emerging from below reads as the sheet edge.
                    .mask(alignment: .top) {
                        Rectangle()
                            .frame(width: geo.size.width, height: bottom)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(dismissGesture)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("発券。\(event.title)。\(event.minutes)分")
        .accessibilityHint("下にスワイプではけます")
        .accessibilityAction(.escape) {
            dismissEarly()
        }
        .sensoryFeedback(.impact(weight: .medium, intensity: 1.0), trigger: ejectHaptic)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: landHaptic)
        .onAppear { startRun() }
        .onChange(of: event.id) { _, _ in startRun() }
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
                    dismissEarly()
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
        case .upright, .settling, .gone: false
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
        case .upright, .settling, .gone: 0
        }
    }

    private var scrimOpacity: Double {
        switch phase {
        case .idle: 0.06
        case .ejecting, .ejected, .upright: 0.2
        case .settling: 0.1
        case .gone: 0
        }
    }

    private var cardOpacity: Double {
        switch phase {
        case .gone: 0
        case .settling: 0.55
        case .idle, .ejecting, .ejected, .upright: 1
        }
    }

    private func ticketCenterY(
        hiddenCenterY: CGFloat,
        emergedCenterY: CGFloat,
        uprightCenterY: CGFloat
    ) -> CGFloat {
        switch phase {
        case .idle:
            hiddenCenterY
        case .ejecting, .ejected:
            hiddenCenterY + (emergedCenterY - hiddenCenterY) * ejectProgress
        case .upright:
            uprightCenterY
        case .settling:
            uprightCenterY + 16 + max(0, dragY)
        case .gone:
            uprightCenterY + 28 + max(0, dragY)
        }
    }

    private func dismissEarly() {
        guard !finishing else { return }
        finishing = true
        // Invalidate the auto-hold Task.
        runID = UUID()
        landHaptic += 1
        withAnimation(MarsTicketSpec.IssueMotion.settle) {
            phase = .settling
            dragY = max(dragY, 24)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(MarsTicketSpec.IssueMotion.settleMilliseconds))
            withAnimation(.easeIn(duration: 0.16)) {
                phase = .gone
                dragY += 40
            }
            try? await Task.sleep(for: .milliseconds(160))
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

        Task { @MainActor in
            if reduceMotion {
                ejectProgress = 1
                withAnimation(.easeOut(duration: 0.12)) {
                    phase = .upright
                }
                try? await Task.sleep(for: .milliseconds(1_800))
                guard runID == token, !finishing else { return }
                finishAutomatically(token: token)
                return
            }

            ejectHaptic += 1
            phase = .ejecting
            withAnimation(MarsTicketSpec.IssueMotion.eject) {
                ejectProgress = 1
            }

            try? await Task.sleep(for: .milliseconds(MarsTicketSpec.IssueMotion.ejectMilliseconds))
            guard runID == token, !finishing else { return }
            phase = .ejected

            try? await Task.sleep(for: .milliseconds(90))
            guard runID == token, !finishing else { return }

            withAnimation(MarsTicketSpec.IssueMotion.upright) {
                phase = .upright
            }

            try? await Task.sleep(
                for: .milliseconds(
                    MarsTicketSpec.IssueMotion.uprightMilliseconds
                        + MarsTicketSpec.IssueMotion.readableHoldMilliseconds
                )
            )
            guard runID == token, !finishing else { return }
            finishAutomatically(token: token)
        }
    }

    private func finishAutomatically(token: UUID) {
        guard runID == token, !finishing else { return }
        finishing = true
        landHaptic += 1
        withAnimation(MarsTicketSpec.IssueMotion.settle) {
            phase = .settling
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(MarsTicketSpec.IssueMotion.settleMilliseconds))
            guard runID == token else { return }
            withAnimation(.easeIn(duration: 0.16)) {
                phase = .gone
            }
            try? await Task.sleep(for: .milliseconds(160))
            guard runID == token else { return }
            onFinished?()
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
