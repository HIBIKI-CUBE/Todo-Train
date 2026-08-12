//
//  DailyStatsHeader.swift
//  Todo train
//

import SwiftUI

struct DailyStatsHeader: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let dayKey: String
    let aggregate: DayAggregate

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                compactHeader
            } else {
                portraitHeader
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, verticalSizeClass == .compact ? 0 : 2)
    }

    private var portraitHeader: some View {
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
    }

    private var compactHeader: some View {
        HStack(spacing: TrainTheme.Space.sm) {
            Text(displayDay)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 8)

            inlineMeta("集中 \(aggregate.focusMinutes)分")
            inlineMeta("到着 \(aggregate.arrived)")
            inlineMeta("途中下車 \(aggregate.partialDisembark)")
            if aggregate.abandoned > 0 {
                inlineMeta("放棄 \(aggregate.abandoned)", color: TrainTheme.signalRed)
            }
        }
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

    private func inlineMeta(_ text: String, color: Color = .secondary) -> some View {
        Text(text)
            .font(.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private var displayDay: String {
        DayKeyFormatting.displayDay(from: dayKey)
    }
}
