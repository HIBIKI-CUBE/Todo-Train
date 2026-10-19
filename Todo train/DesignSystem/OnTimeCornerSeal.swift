//
//  OnTimeCornerSeal.swift
//  Todo train
//
//  中身は風景印。位置は束の上の帯に「定時」が収まるところ。
//

import SwiftUI
import TodoTrainSync

struct OnTimeCornerSealMark: View {
    var luxury: Double
    var season: PunctualityJudgment.StampSeason
    var timeOfDay: PunctualityJudgment.StampTimeOfDay
    var seed: UInt64
    var dateText: String
    var settled: CGFloat

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height) * TicketStampBundleLayout.cornerSealSideRatio
            FukeiSealView(
                input: FukeiSealInput(
                    luxury: luxury,
                    season: season,
                    timeOfDay: timeOfDay,
                    seed: seed,
                    dateText: dateText,
                    detail: .full
                )
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(TicketStampBundleLayout.cornerSealRotationDegrees))
            .scaleEffect(0.7 + 0.3 * settled)
            .opacity(Double(settled))
            .position(
                x: geo.size.width * TicketStampBundleLayout.cornerSealCenterXRatio,
                y: geo.size.height * TicketStampBundleLayout.cornerSealCenterYRatio
            )
        }
        .allowsHitTesting(false)
    }
}
