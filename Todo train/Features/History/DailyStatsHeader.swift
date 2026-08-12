//
//  DailyStatsHeader.swift
//  Todo train
//

import SwiftUI

struct DailyStatsHeader: View {
    let dayKey: String
    let aggregate: DayAggregate

    var body: some View {
        VStack(alignment: .leading, spacing: TrainTheme.Space.xs) {
            Text(displayDay)
                .font(.headline.weight(.semibold))

            HStack(spacing: TrainTheme.Space.md) {
                meta("集中", "\(aggregate.focusMinutes)分")
                meta("到着", "\(aggregate.arrived)")
                meta("途中下車", "\(aggregate.partialDisembark)")
                if aggregate.abandoned > 0 {
                    meta("放棄", "\(aggregate.abandoned)", color: TrainTheme.signalRed)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private func meta(_ label: String, _ value: String, color: Color = .secondary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    private var displayDay: String {
        DayKeyFormatting.displayDay(from: dayKey)
    }
}
