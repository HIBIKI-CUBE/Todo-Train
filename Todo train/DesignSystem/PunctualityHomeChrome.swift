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
    var luxury: Double

    var body: some View {
        FukeiSealView(
            input: FukeiSealInput(
                luxury: luxury,
                season: .spring,
                timeOfDay: .afternoon,
                seed: Self.sampleSeed,
                dateText: "",
                detail: .compact
            )
        )
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }

    /// 見本は乗車を持たない。同じ豪華さなら同じかすれになる。
    private static let sampleSeed = SealSeed.seed(
        rideID: UUID(uuidString: "00000000-0000-4000-8000-000000000170")!
    )
}

struct PunctualityHomeMeterRow: View {
    var judgment: PunctualityJudgment.Judgment
    var activeSeconds: TimeInterval
    var budgetSeconds: Int
    var sealLuxury: Double?
    var showsFirstTimeTip: Bool

    private var band: (start: Double, end: Double)? {
        PunctualityPresentation.homeBandFractions(judgment: judgment, budgetSeconds: budgetSeconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                PunctualityHomeSignalLamp(state: judgment.signal)
                if let sealLuxury {
                    PunctualitySealSample(luxury: sealLuxury)
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
        PunctualityPresentation.homeMeterAccessibilityLabel(
            judgment: judgment,
            activeSeconds: activeSeconds,
            sealLuxury: sealLuxury
        )
    }
}
