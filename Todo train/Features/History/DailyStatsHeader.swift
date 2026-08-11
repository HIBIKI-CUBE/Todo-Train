//
//  DailyStatsHeader.swift
//  Todo train
//

import SwiftUI

struct DailyStatsHeader: View {
    let dayKey: String
    let aggregate: DayAggregate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayDay)
                .font(.headline)
            HStack(spacing: 12) {
                Text("集中 \(aggregate.focusMinutes)分")
                Text("到着 \(aggregate.arrived)")
                Text("途中下車 \(aggregate.partialDisembark)")
                if aggregate.abandoned > 0 {
                    Text("放棄 \(aggregate.abandoned)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var displayDay: String {
        // dayKey is "yyyy-MM-dd"
        dayKey
    }
}
