//
//  OnTimeCornerSeal.swift
//  Todo train
//
//  位置と大きさは今のまま。中身は風景印。
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
            let size = min(geo.size.width, geo.size.height) * 0.30
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
            .rotationEffect(.degrees(-8))
            .scaleEffect(0.7 + 0.3 * settled)
            .opacity(Double(settled))
            .position(x: geo.size.width * 0.84, y: geo.size.height * 0.38)
        }
        .allowsHitTesting(false)
    }
}
