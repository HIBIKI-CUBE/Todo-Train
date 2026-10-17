//
//  FocusReestimatePanel.swift
//  Todo train
//

import SwiftUI
import TodoTrainTicketUI

private let progressStops = [10, 20, 30, 40, 50, 60, 70, 80, 90]

struct FocusReestimatePanel: View {
    let activeSeconds: TimeInterval
    let onCommit: (ReestimateMode, Double?, Int, Int?, Int?, Bool) -> Void
    let onArriveAtFullProgress: () -> Void
    let onClose: () -> Void

    @State private var stage: Stage = .progress
    @State private var progressValue = 0
    @State private var remainingMinutes = 0
    @State private var detailsOpen = false
    @State private var inputsLocked = false

    private enum Stage {
        case progress
        case remaining
    }

    private var progressAnswer: Double? {
        guard progressValue > 0, progressValue < 100 else { return nil }
        return Double(progressValue) / 100.0
    }

    private var band: ReestimateBand.ShownBand? {
        guard let progressAnswer else { return nil }
        return ReestimateBand.shown(activeSeconds: activeSeconds, progress: progressAnswer)
    }

    private var bandRangeMinutes: ClosedRange<Int>? {
        guard let band, let span = ReestimateBand.remainingSpan(activeSeconds: activeSeconds, band: band) else {
            return nil
        }
        return span.lowRemainingMinutes...span.highRemainingMinutes
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            FocusControlDivider()
            stageBody
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .opacity(inputsLocked ? 0.55 : 1)
                .allowsHitTesting(!inputsLocked)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FocusPanel.fill)
        .onAppear {
            lockInputsBriefly()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(stage == .progress ? "今、進捗は何割くらい？" : "あとどのくらい？")
                .font(.system(size: 16, weight: .bold))
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if stage == .progress {
                Button("分で決める") {
                    beginRemaining(minutesOnly: true)
                }
                .font(.system(size: 15, weight: .semibold))
                .buttonStyle(.plain)
            }
            Button("閉じる", action: onClose)
                .font(.system(size: 15, weight: .semibold))
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .foregroundStyle(FocusPanel.ink)
        .background(FocusPanel.fill)
    }

    @ViewBuilder
    private var stageBody: some View {
        switch stage {
        case .progress:
            VStack(alignment: .leading, spacing: 10) {
                if progressValue == 100 {
                    Text("到着済み")
                        .font(.title3.weight(.semibold))
                } else if progressValue > 0 {
                    Text("\(progressValue / 10)割")
                        .font(.system(size: 40, weight: .medium, design: .rounded))
                        .monospacedDigit()
                } else {
                    Text("なぞって答える")
                        .font(.subheadline)
                        .foregroundStyle(FocusPanel.muted)
                }
                EstimateSnapGauge(
                    minutes: $progressValue,
                    stopMinutes: progressStops + [100],
                    maxMinutes: 100,
                    startsAtLeftUnselected: true,
                    minimumCommitTranslation: 24,
                    requiresDragToCommit: true,
                    accessibilityLabelText: "進捗",
                    onCommit: {
                        if progressValue == 100 {
                            onArriveAtFullProgress()
                        } else if progressValue > 0 {
                            beginRemaining(minutesOnly: false)
                        }
                    }
                )
            }
        case .remaining:
            VStack(alignment: .leading, spacing: 10) {
                bandHeader
                if remainingMinutes > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(remainingMinutes)")
                            .font(.system(size: 40, weight: .medium, design: .rounded))
                            .monospacedDigit()
                        Text("分")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(FocusPanel.muted)
                    }
                } else {
                    Text("左端からなぞって残りを決める")
                        .font(.subheadline)
                        .foregroundStyle(FocusPanel.muted)
                }
                EstimateSnapGauge(
                    minutes: $remainingMinutes,
                    startsAtLeftUnselected: true,
                    bandRangeMinutes: bandRangeMinutes,
                    minimumCommitTranslation: 24,
                    requiresDragToCommit: true,
                    accessibilityLabelText: "残り時間",
                    onCommit: {
                        guard remainingMinutes > 0 else { return }
                        let low = band?.lowTotalSeconds
                        let high = band?.highTotalSeconds
                        onCommit(
                            progressAnswer == nil ? .minutesOnly : .progress,
                            progressAnswer,
                            remainingMinutes * 60,
                            low,
                            high,
                            detailsOpen
                        )
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var bandHeader: some View {
        if let band {
            Button {
                detailsOpen.toggle()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(band.headline)
                        .font(.subheadline.weight(.semibold))
                    if detailsOpen {
                        Text(
                            "走行 \(Int(activeSeconds) / 60) 分 · 目安 \(band.lowTotalSeconds / 60)〜\(band.highTotalSeconds / 60) 分"
                        )
                        .font(.caption)
                        .foregroundStyle(FocusPanel.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        } else if activeSeconds < 180 {
            Text("走行が短いときは、分で決めるのが確かです。")
                .font(.caption)
                .foregroundStyle(FocusPanel.muted)
        }
    }

    private func beginRemaining(minutesOnly: Bool) {
        if minutesOnly {
            progressValue = 0
        }
        inputsLocked = true
        withAnimation(TrainTheme.Motion.soft) {
            stage = .remaining
            remainingMinutes = 0
        }
        lockInputsBriefly()
    }

    private func lockInputsBriefly() {
        inputsLocked = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            inputsLocked = false
        }
    }
}
