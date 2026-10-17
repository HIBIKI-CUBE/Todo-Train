//
//  StampedMarsTicketFace.swift
//  Todo train
//
//  検札済み券面。到着オーバーレイと同じ印・角判。
//

import SwiftUI
import TodoTrainTicketUI
import TodoTrainSync

struct StampedMarsTicketFace: View {
    var stamp: TicketStampBundleAssembly.Stamp
    var scale: CGFloat = 1

    private var settled: (stampImpact: CGFloat, sealImpact: CGFloat) {
        ArrivalStampCommitEffects.settledVisuals(punctuality: stamp.punctuality)
    }

    private var content: MarsTicketContent {
        MarsTicketContent(
            title: stamp.title,
            minutes: stamp.judgedEstimateMinutes,
            issuedAt: stamp.stampedAt
        )
    }

    var body: some View {
        MarsTicketView(content: content, density: .celebration)
            .scaleEffect(scale)
            .overlay {
                MarsTicketUsedMarks(
                    punctuality: stamp.punctuality,
                    stampSettled: settled.stampImpact,
                    innerRingSolid: stamp.punctuality == .onTime,
                    sealTier: stamp.sealTier,
                    sealSeason: stamp.stampSeason,
                    sealTimeOfDay: stamp.stampTimeOfDay,
                    sealSettled: settled.sealImpact
                )
            }
            .overlay(alignment: .bottomLeading) {
                logLines
                    .padding(8 * max(scale, 0.65))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
    }

    private var logLines: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("最初 \(stamp.originalEstimateMinutes)分")
                .font(.system(size: 8, weight: .medium))
            if let re = stamp.reestimateTotalMinutes {
                Text("見積もり直し \(re)分")
                    .font(.system(size: 8, weight: .medium))
            }
            Text("実際 \(stamp.actualMinutes)分")
                .font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(MarsTicketSpec.printInk.opacity(0.88))
        .allowsHitTesting(false)
    }

    private var accessibilityLabel: String {
        var parts = [stamp.title]
        parts.append(PunctualityPresentation.stampAccessibilityLabel(
            punctuality: stamp.punctuality,
            includesCornerSeal: stamp.sealTier != nil
        ))
        parts.append("見積もり \(stamp.judgedEstimateMinutes)分、実際 \(stamp.actualMinutes)分")
        return parts.joined(separator: "、")
    }
}
