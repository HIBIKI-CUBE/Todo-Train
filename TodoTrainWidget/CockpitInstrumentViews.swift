//
//  CockpitInstrumentViews.swift
//  Compact Dynamic Island trailing timer.
//
//  Timers MUST use Text(timerInterval:) so the system drives second-by-second
//  updates. TimelineView does not tick inside Live Activities.
//

import SwiftUI

/// Compact Dynamic Island trailing — live seconds with hidden max-digit width template.
struct CockpitCompactTimer: View {
    let clock: CockpitClockStyle
    let phase: FocusTimerPhase
    var scheduledAt: Date? = nil
    var limitedWidth: Bool = false

    var body: some View {
        Group {
            switch clock {
            case .countdown(let end):
                liveCountdown(end: end)
            case .paused(let remaining):
                Text(CockpitFormat.shortTimerLabel(remaining: remaining, limitedWidth: limitedWidth))
                    .accessibilityValue(
                        CockpitFormat.accessibilityTimerValue(
                            remaining: remaining,
                            isStale: false,
                            isOvertime: false
                        )
                    )
            case .alert, .overtime:
                if let scheduledAt {
                    Text(
                        timerInterval: CockpitGaugeRange.countUp(since: scheduledAt),
                        countsDown: false,
                        showsHours: false
                    )
                } else {
                    Text("0:00")
                }
            case .stale:
                Text("…")
            }
        }
        .font(.caption.weight(.bold).monospacedDigit())
        .foregroundStyle(phase.accentColor)
        .minimumScaleFactor(0.7)
        .lineLimit(1)
        .multilineTextAlignment(.trailing)
    }

    /// `Text(timerInterval:)` takes every offered width. The hidden template is the width;
    /// the overlay cannot grow past it, so compact trailing stays as wide as the digits.
    private func liveCountdown(end: Date) -> some View {
        let remaining = end.timeIntervalSinceNow
        let template = limitedWidth && remaining >= 10 * 60
            ? "00分"
            : CockpitLayoutPolicy.islandTimerWidthTemplate(remaining: remaining)
        return Text(template)
            .hidden()
            .accessibilityHidden(true)
            .overlay(alignment: .trailing) {
                Text(
                    timerInterval: CockpitTimerInterval.countdown(to: end),
                    countsDown: true,
                    showsHours: false
                )
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
            }
    }
}
