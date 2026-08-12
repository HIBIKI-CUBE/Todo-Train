//
//  TicketIssueEject.swift
//  Todo train
//
//  Single-issue celebration on Hub — snappy (~550ms), overlaps sheet dismiss.
//

import SwiftUI

struct TicketIssueEjectEvent: Identifiable, Equatable {
    let id: UUID
    let title: String
    let minutes: Int

    init(id: UUID = UUID(), title: String, minutes: Int) {
        self.id = id
        self.title = title
        self.minutes = minutes
    }

    /// Full presentation budget (ms). Keep in sync with `TicketIssueEjectOverlay` phases.
    static let presentationMilliseconds = 550
}

/// Full-screen Hub celebration: light scrim + readable ticket, then short settle.
struct TicketIssueEjectOverlay: View {
    let event: TicketIssueEjectEvent
    var onFinished: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase: Equatable {
        case idle
        case held
        case settling
        case gone
    }

    @State private var phase: Phase = .idle
    @State private var runID = UUID()

    var body: some View {
        ZStack {
            Color.black
                .opacity(scrimOpacity)
                .ignoresSafeArea()

            ticketCard
                .padding(.horizontal, TrainTheme.Space.lg)
                .scaleEffect(cardScale)
                .opacity(cardOpacity)
                .offset(y: cardOffsetY)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { startRun() }
        .onChange(of: event.id) { _, _ in startRun() }
    }

    private var scrimOpacity: Double {
        switch phase {
        case .idle: 0
        case .held: 0.28
        case .settling: 0.12
        case .gone: 0
        }
    }

    private var cardOpacity: Double {
        switch phase {
        case .idle, .gone: 0
        case .held: 1
        case .settling: 0.5
        }
    }

    private var cardScale: CGFloat {
        switch phase {
        case .idle: 0.92
        case .held: 1
        case .settling: 0.96
        case .gone: 0.94
        }
    }

    private var cardOffsetY: CGFloat {
        switch phase {
        case .idle: 16
        case .held: 0
        case .settling: 36
        case .gone: 52
        }
    }

    private var ticketCard: some View {
        IssuedTicketCard(title: event.title, minutes: event.minutes)
    }

    private func startRun() {
        let token = UUID()
        runID = token
        phase = .idle

        Task { @MainActor in
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.12)) {
                    phase = .held
                }
                try? await Task.sleep(for: .milliseconds(200))
                guard runID == token else { return }
                withAnimation(.easeIn(duration: 0.12)) {
                    phase = .gone
                }
                try? await Task.sleep(for: .milliseconds(120))
                guard runID == token else { return }
                onFinished?()
                return
            }

            // Bloom immediately — no idle wait (sheet dismiss runs in parallel).
            withAnimation(TrainTheme.Motion.issueEject) {
                phase = .held
            }

            try? await Task.sleep(for: .milliseconds(320))
            guard runID == token else { return }

            withAnimation(TrainTheme.Motion.issueEject) {
                phase = .settling
            }

            try? await Task.sleep(for: .milliseconds(160))
            guard runID == token else { return }

            withAnimation(.easeIn(duration: 0.16)) {
                phase = .gone
            }

            try? await Task.sleep(for: .milliseconds(180))
            guard runID == token else { return }
            onFinished?()
        }
    }
}

/// Paper-ticket motif used by the Hub celebration overlay.
struct IssuedTicketCard: View {
    let title: String
    let minutes: Int

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "tram.fill")
                    .font(.title2.weight(.semibold))
                Text("\(minutes)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("分")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(width: 76)
            .padding(.vertical, 22)

            ticketPerforation
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 8) {
                Text("発券")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TrainTheme.rail)
                    .tracking(2)

                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Todo train")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, TrainTheme.Space.lg)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background {
            HStack(spacing: 0) {
                TrainTheme.rail
                    .frame(width: 76)
                Color(uiColor: .systemBackground)
                    .frame(width: 14)
                Color(uiColor: .systemBackground)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(TrainTheme.rail.opacity(0.45), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.28), radius: 24, y: 12)
        .frame(maxWidth: 420)
    }

    private var ticketPerforation: some View {
        VStack(spacing: 7) {
            ForEach(0..<7, id: \.self) { _ in
                Circle()
                    .fill(TrainTheme.platform)
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.vertical, 10)
    }
}

#Preview("Ticket card") {
    ZStack {
        Color.black.opacity(0.28).ignoresSafeArea()
        IssuedTicketCard(title: "週次レビューの下書き", minutes: 25)
            .padding(.horizontal, TrainTheme.Space.lg)
    }
}

#Preview("Issue eject") {
    ZStack {
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        TicketIssueEjectOverlay(
            event: TicketIssueEjectEvent(title: "週次レビューの下書き", minutes: 25)
        )
    }
}
