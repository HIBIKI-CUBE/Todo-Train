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
    var showsLogLines: Bool = true

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

    private var baseTicketSize: CGSize {
        let width: CGFloat = 300
        return CGSize(width: width, height: MarsTicketSpec.height(forWidth: width))
    }

    var body: some View {
        ZStack {
            MarsTicketView(content: content, density: .celebration)
            MarsTicketUsedMarks(
                punctuality: stamp.punctuality,
                stampSettled: settled.stampImpact,
                innerRingSolid: stamp.punctuality == .onTime,
                sealLuxury: stamp.sealLuxury,
                sealSeed: SealSeed.seed(rideID: stamp.sessionID),
                sealDateText: FukeiSealDate.text(from: stamp.stampedAt),
                sealSeason: stamp.stampSeason,
                sealTimeOfDay: stamp.stampTimeOfDay,
                sealSettled: settled.sealImpact
            )
            if showsLogLines {
                logLines
                    .padding(10)
                    .frame(width: baseTicketSize.width - 20, alignment: .leading)
                    .frame(maxHeight: 36, alignment: .bottomLeading)
                    .clipped()
                    .frame(width: baseTicketSize.width, height: baseTicketSize.height, alignment: .bottomLeading)
            }
        }
        .frame(width: baseTicketSize.width, height: baseTicketSize.height)
        .background(MarsTicketSpec.paper)
        .compositingGroup()
        .drawingGroup(opaque: true)
        .scaleEffect(scale, anchor: .bottom)
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
            includesCornerSeal: stamp.sealLuxury != nil
        ))
        parts.append("見積もり \(stamp.judgedEstimateMinutes)分、実際 \(stamp.actualMinutes)分")
        return parts.joined(separator: "、")
    }
}
