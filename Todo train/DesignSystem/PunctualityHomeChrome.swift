//
//  PunctualityHomeChrome.swift
//  Todo train
//

import SwiftUI
import TodoTrainSync

struct PunctualityHomeSignalLamp: View {
    var state: PunctualityJudgment.HomeSignalState

    var body: some View {
        Group {
            switch state {
            case .green:
                Circle()
                    .fill(TrainTheme.signalGreen.opacity(0.95))
            case .yellow:
                Capsule()
                    .fill(TrainTheme.signalAmber.opacity(0.95))
            case .off:
                Color.clear
            }
        }
        .frame(width: state == .yellow ? 14 : 8, height: 8)
        .accessibilityHidden(true)
    }
}

struct PunctualitySealSample: View {
    var tier: PunctualityJudgment.OnTimeSealTier

    var body: some View {
        OnTimeCornerSealGlyph(tier: tier, season: .spring, timeOfDay: .afternoon)
            .frame(width: 18, height: 18)
            .opacity(0.92)
            .accessibilityHidden(true)
    }
}

struct PunctualityHomeMeterRow: View {
    var judgment: PunctualityJudgment.Judgment
    var activeSeconds: TimeInterval
    var budgetSeconds: Int
    var sealTier: PunctualityJudgment.OnTimeSealTier?
    var showsFirstTimeTip: Bool

    private var band: (start: Double, end: Double)? {
        PunctualityPresentation.homeBandFractions(judgment: judgment, budgetSeconds: budgetSeconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                PunctualityHomeSignalLamp(state: judgment.signal)
                if let sealTier {
                    PunctualitySealSample(tier: sealTier)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)

            if showsFirstTimeTip {
                Text(PunctualityFirstTimeTips.homeLine)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FocusPanel.dim)
                    .padding(.horizontal, 14)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(combinedAccessibilityLabel)
    }

    private var combinedAccessibilityLabel: String {
        var parts = [PunctualityPresentation.signalAccessibilityLabel(
            judgment: judgment,
            activeSeconds: activeSeconds
        )]
        if let sealTier {
            parts.append(PunctualityPresentation.sealSampleAccessibilityLabel(tier: sealTier))
        }
        return parts.joined(separator: "、")
    }
}
