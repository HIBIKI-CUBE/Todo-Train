//
//  PunctualityMomentOverlay.swift
//  Todo train
//
//  Brief station-style announcement. Not a score, streak, or unlock.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PunctualityMomentOverlay: View {
    let moment: PunctualityMoment
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

            announcementCard
                .padding(.horizontal, TrainTheme.Space.xl)
                .scaleEffect(cardScale)
                .opacity(cardOpacity)
                .offset(y: cardOffsetY)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .onAppear { startRun() }
        .onChange(of: moment.id) { _, _ in startRun() }
    }

    private var scrimOpacity: Double {
        switch phase {
        case .idle: 0
        case .held: 0.28
        case .settling: 0.1
        case .gone: 0
        }
    }

    private var cardOpacity: Double {
        switch phase {
        case .idle, .gone: 0
        case .held: 1
        case .settling: 0.55
        }
    }

    private var cardScale: CGFloat {
        switch phase {
        case .idle: 0.94
        case .held: 1
        case .settling: 0.98
        case .gone: 0.96
        }
    }

    private var cardOffsetY: CGFloat {
        switch phase {
        case .idle: 10
        case .held: 0
        case .settling: 8
        case .gone: 16
        }
    }

    private var announcementCard: some View {
        VStack(alignment: .leading, spacing: TrainTheme.Space.sm) {
            Text(headline)
                .font(.title2.weight(.semibold))
                .foregroundStyle(TrainTheme.signalGreen)
                .tracking(1)

            if let title {
                Text(title)
                    .font(TrainTheme.TypeScale.ticketTitle())
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            if let caption {
                Text(caption)
                    .font(TrainTheme.TypeScale.meta())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, TrainTheme.Space.lg)
        .padding(.vertical, 22)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(TrainTheme.signalGreen)
                .frame(width: 4)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(TrainTheme.signalGreen.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 20, y: 10)
    }

    private var headline: String {
        switch moment.kind {
        case .arrival(_, _, _, let punctuality):
            Punctuality.arrivalHeadline(punctuality)
        case .onTimeService:
            "定時運行"
        }
    }

    private var title: String? {
        switch moment.kind {
        case .arrival(let title, _, _, _): title
        case .onTimeService: nil
        }
    }

    private var caption: String? {
        switch moment.kind {
        case .arrival(_, let estimate, let actual, let punctuality):
            Punctuality.arrivalCaption(
                punctuality: punctuality,
                estimateSeconds: estimate,
                actualSeconds: actual
            )
        case .onTimeService:
            "本日、ダイヤどおり"
        }
    }

    private var accessibilityText: String {
        switch moment.kind {
        case .arrival(let title, let estimate, let actual, let punctuality):
            let head = Punctuality.arrivalHeadline(punctuality)
            if let caption = Punctuality.arrivalCaption(
                punctuality: punctuality,
                estimateSeconds: estimate,
                actualSeconds: actual
            ) {
                return "\(head)。\(title)。\(caption)"
            }
            return "\(head)。\(title)"
        case .onTimeService:
            "本日、定時運行でした"
        }
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
                announceIfNeeded()
                try? await Task.sleep(for: .milliseconds(240))
                guard runID == token else { return }
                withAnimation(.easeIn(duration: 0.12)) {
                    phase = .gone
                }
                try? await Task.sleep(for: .milliseconds(120))
                guard runID == token else { return }
                onFinished?()
                return
            }

            withAnimation(TrainTheme.Motion.onTimeArrival) {
                phase = .held
            }
            announceIfNeeded()

            try? await Task.sleep(for: .milliseconds(480))
            guard runID == token else { return }

            withAnimation(TrainTheme.Motion.onTimeArrival) {
                phase = .settling
            }

            try? await Task.sleep(for: .milliseconds(180))
            guard runID == token else { return }

            withAnimation(.easeIn(duration: 0.16)) {
                phase = .gone
            }

            try? await Task.sleep(for: .milliseconds(140))
            guard runID == token else { return }
            onFinished?()
        }
    }

    private func announceIfNeeded() {
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: accessibilityText)
        #endif
    }
}

#Preview("定時到着") {
    ZStack {
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        PunctualityMomentOverlay(
            moment: PunctualityMoment(
                kind: .arrival(
                    title: "週次レビューの下書き",
                    estimateSeconds: 1_500,
                    actualSeconds: 1_440,
                    punctuality: .onTime
                )
            )
        )
    }
}

#Preview("早着") {
    ZStack {
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        PunctualityMomentOverlay(
            moment: PunctualityMoment(
                kind: .arrival(
                    title: "週次レビューの下書き",
                    estimateSeconds: 1_500,
                    actualSeconds: 900,
                    punctuality: .early
                )
            )
        )
    }
}

#Preview("到着（超過後）") {
    ZStack {
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        PunctualityMomentOverlay(
            moment: PunctualityMoment(
                kind: .arrival(
                    title: "週次レビューの下書き",
                    estimateSeconds: 1_500,
                    actualSeconds: 2_100,
                    punctuality: .late
                )
            )
        )
    }
}

#Preview("定時運行") {
    ZStack {
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        PunctualityMomentOverlay(
            moment: PunctualityMoment(kind: .onTimeService)
        )
    }
}
