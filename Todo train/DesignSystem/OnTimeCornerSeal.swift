//
//  OnTimeCornerSeal.swift
//  Todo train
//

import SwiftUI
import TodoTrainSync

struct OnTimeCornerSealGlyph: View {
    var tier: PunctualityJudgment.OnTimeSealTier
    var season: PunctualityJudgment.StampSeason
    var timeOfDay: PunctualityJudgment.StampTimeOfDay

    private var ink: Color {
        let base = Color(red: 0.78, green: 0.18, blue: 0.14)
        switch season {
        case .spring: return base
        case .summer: return base.opacity(0.94)
        case .autumn: return Color(red: 0.72, green: 0.16, blue: 0.12)
        case .winter: return Color(red: 0.68, green: 0.14, blue: 0.16)
        }
    }

    private var gold: Color {
        switch timeOfDay {
        case .morning: Color(red: 0.92, green: 0.78, blue: 0.38)
        case .afternoon: Color(red: 0.88, green: 0.72, blue: 0.28)
        case .evening: Color(red: 0.82, green: 0.62, blue: 0.22)
        case .night: Color(red: 0.72, green: 0.58, blue: 0.20)
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(ink, lineWidth: lineWidth)
            if tier == .ticketing {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .strokeBorder(ink, lineWidth: 1.2)
                    .padding(2.5)
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .strokeBorder(gold, lineWidth: 1)
                    .padding(0.5)
            } else if tier == .earlyReestimate {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .strokeBorder(ink, lineWidth: 1.4)
                    .padding(2)
            }
            Text("定時")
                .font(.system(size: fontSize, weight: .bold, design: .default))
                .foregroundStyle(ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .rotationEffect(.degrees(-8))
    }

    private var lineWidth: CGFloat {
        switch tier {
        case .ticketing: 2.2
        case .earlyReestimate: 1.8
        case .lateReestimate: 1
        }
    }

    private var fontSize: CGFloat {
        switch tier {
        case .ticketing: 9
        case .earlyReestimate: 8.5
        case .lateReestimate: 8
        }
    }
}

struct OnTimeCornerSealMark: View {
    var tier: PunctualityJudgment.OnTimeSealTier
    var season: PunctualityJudgment.StampSeason
    var timeOfDay: PunctualityJudgment.StampTimeOfDay
    var settled: CGFloat

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height) * 0.30
            OnTimeCornerSealGlyph(tier: tier, season: season, timeOfDay: timeOfDay)
                .frame(width: size, height: size)
                .scaleEffect(0.7 + 0.3 * settled)
                .opacity(Double(settled))
                .position(x: geo.size.width * 0.84, y: geo.size.height * 0.38)
        }
        .allowsHitTesting(false)
    }
}
