//
//  TicketIssueEject.swift
//  Todo train
//
//  Single-issue: ticket slides up from the screen bottom (sheet exit edge),
//  90° CW and already printed, then uprights. No mid-air clip.
//

import SwiftUI

struct TicketIssueEjectEvent: Identifiable, Equatable {
    let id: UUID
    let title: String
    let minutes: Int
    let tagNames: [String]
    let issuedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        minutes: Int,
        tagNames: [String] = [],
        issuedAt: Date = .now
    ) {
        self.id = id
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
    @State private var runID = UUID()
    @State private var ejectHaptic = 0
    @State private var landHaptic = 0

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
            )

            ZStack {
                Color.black
                    .opacity(scrimOpacity)
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
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .sensoryFeedback(.impact(weight: .medium, intensity: 1.0), trigger: ejectHaptic)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: landHaptic)
        .onAppear { startRun() }
        .onChange(of: event.id) { _, _ in startRun() }
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
            uprightCenterY + 16
        case .gone:
            uprightCenterY + 28
        }
    }

    private func startRun() {
        let token = UUID()
        runID = token
        phase = .idle
        ejectProgress = 0

        Task { @MainActor in
            if reduceMotion {
                ejectProgress = 1
                withAnimation(.easeOut(duration: 0.12)) {
                    phase = .upright
                }
                try? await Task.sleep(for: .milliseconds(1_800))
                guard runID == token else { return }
                withAnimation(.easeIn(duration: 0.2)) {
                    phase = .gone
                }
                try? await Task.sleep(for: .milliseconds(200))
                guard runID == token else { return }
                onFinished?()
                return
            }

            ejectHaptic += 1
            phase = .ejecting
            withAnimation(MarsTicketSpec.IssueMotion.eject) {
                ejectProgress = 1
            }

            try? await Task.sleep(for: .milliseconds(MarsTicketSpec.IssueMotion.ejectMilliseconds))
            guard runID == token else { return }
            phase = .ejected

            try? await Task.sleep(for: .milliseconds(90))
            guard runID == token else { return }

            withAnimation(MarsTicketSpec.IssueMotion.upright) {
                phase = .upright
            }

            try? await Task.sleep(
                for: .milliseconds(
                    MarsTicketSpec.IssueMotion.uprightMilliseconds
                        + MarsTicketSpec.IssueMotion.readableHoldMilliseconds
                )
            )
            guard runID == token else { return }

            landHaptic += 1
            withAnimation(MarsTicketSpec.IssueMotion.settle) {
                phase = .settling
            }

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
                title: "週次レビューの下書き",
                minutes: 25,
                tagNames: ["仕事"]
            )
        )
    }
}
