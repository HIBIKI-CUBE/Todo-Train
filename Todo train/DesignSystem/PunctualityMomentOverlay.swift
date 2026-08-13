//
//  PunctualityMomentOverlay.swift
//  Todo train
//
//  Brief 定時運行 cue only. Arrivals use ArrivalInvalidateOverlay (gesture).
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
        case gone
    }

    @State private var phase: Phase = .idle
    @State private var runID = UUID()

    var body: some View {
        ZStack {
            Color.black
                .opacity(scrimOpacity)
                .ignoresSafeArea()

            Text("定時運行")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TrainTheme.signalGreen)
                .tracking(1)
                .padding(.horizontal, TrainTheme.Space.lg)
                .padding(.vertical, 14)
                .background(Color(uiColor: .systemBackground), in: Capsule())
                .overlay(Capsule().strokeBorder(TrainTheme.signalGreen.opacity(0.35), lineWidth: 1))
                .opacity(cardOpacity)
                .scaleEffect(phase == .held ? 1 : 0.96)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("本日、定時運行でした")
        .onAppear { startRun() }
        .onChange(of: moment.id) { _, _ in startRun() }
    }

    private var scrimOpacity: Double {
        switch phase {
        case .idle, .gone: 0
        case .held: 0.18
        }
    }

    private var cardOpacity: Double {
        switch phase {
        case .idle, .gone: 0
        case .held: 1
        }
    }

    private func startRun() {
        let token = UUID()
        runID = token
        phase = .idle

        Task { @MainActor in
            withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.22)) {
                phase = .held
            }
            announceIfNeeded()

            try? await Task.sleep(for: .milliseconds(reduceMotion ? 400 : 900))
            guard runID == token else { return }

            withAnimation(.easeIn(duration: 0.18)) {
                phase = .gone
            }

            try? await Task.sleep(for: .milliseconds(180))
            guard runID == token else { return }
            onFinished?()
        }
    }

    private func announceIfNeeded() {
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: "本日、定時運行でした")
        #endif
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
