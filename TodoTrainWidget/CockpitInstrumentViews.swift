//
//  CockpitInstrumentViews.swift
//  Compact Dynamic Island trailing timer.
//
//  Timers MUST use Text(timerInterval:) so the system drives second-by-second
//  updates. TimelineView does not tick inside Live Activities.
//

import SwiftUI

/// Width of the compact trailing timer. `Text(timerInterval:)` reports the widest
/// string it might draw and then left-aligns inside that width, so a hidden template
/// with an overlay clips the right-hand digits against the pill. The frame below is
/// this wide, trailing-aligned, and does not scale.
enum CockpitCompactTimerWidth {
    /// SF Pro Bold 12pt tabular figures — SwiftUI `.caption` + `.monospacedDigit()`.
    /// Measured from the system face: a digit is 8.0566pt, a colon is 4.1719pt.
    /// Rounded up so the frame is never narrower than the glyphs.
    static let digitAdvance: CGFloat = 8.06
    static let colonAdvance: CGFloat = 4.18
    /// 「分」 in the same face. "00分" measured 28.70pt, so the mark is the remainder.
    static let markAdvance: CGFloat = 12.58

    /// `showsHours: false`, so an hour still draws as five characters (`75:00`),
    /// and one hundred minutes as six (`100:00`).
    static func template(remaining: TimeInterval, limitedWidth: Bool) -> String {
        let total = max(0, Int(remaining.rounded()))
        if limitedWidth, total >= 10 * 60 {
            return total >= 100 * 60 ? "000分" : "00分"
        }
        if total >= 100 * 60 { return "000:00" }
        if total >= 10 * 60 { return "00:00" }
        return "0:00"
    }

    /// `Text(timerInterval:)` is wider than the glyph run of the same digits.
    /// A frame that matches only the glyphs truncates to an ellipsis ("12:…").
    /// This slack is the extra the timer keeps around the current value.
    static let timerSlack: CGFloat = 8

    static func width(of template: String) -> CGFloat {
        var points: CGFloat = 0
        for character in template {
            if character == ":" {
                points += colonAdvance
            } else if character.isNumber {
                points += digitAdvance
            } else {
                points += markAdvance
            }
        }
        return points.rounded(.up)
    }

    static func frameWidth(of template: String) -> CGFloat {
        width(of: template) + timerSlack
    }
}

/// Compact Dynamic Island trailing. The width is the monospaced template, not the
/// timer text's own ideal width.
///
/// `Text(timerInterval:)` sizes itself wider than the digits it is showing.
/// A frame of only the glyph width truncates to an ellipsis (seen as "12:…"
/// on the iPhone 18 Pro Max Simulator). Clipping that view hides the timer
/// entirely inside the Live Activity, so the frame is the template plus
/// `timerSlack`, trailing-aligned, and not clipped.
struct CockpitCompactTimer: View {
    let clock: CockpitClockStyle
    let phase: FocusTimerPhase
    var scheduledAt: Date? = nil
    var limitedWidth: Bool = false

    var body: some View {
        timerLabel
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(phase.accentColor)
            .lineLimit(1)
            .multilineTextAlignment(.trailing)
            .frame(
                width: CockpitCompactTimerWidth.frameWidth(of: template),
                alignment: .trailing
            )
    }

    private var template: String {
        CockpitCompactTimerWidth.template(remaining: templateRemaining, limitedWidth: limitedWidth)
    }

    /// Count-up keeps growing between ActivityKit updates, so reserve the
    /// five-character `75:00` shape even while the elapsed time is still short.
    private var templateRemaining: TimeInterval {
        switch clock {
        case .countdown(let end):
            return max(0, end.timeIntervalSinceNow)
        case .paused(let remaining):
            return max(0, remaining)
        case .alert, .overtime:
            let elapsed = scheduledAt.map { max(0, Date().timeIntervalSince($0)) } ?? 0
            return max(elapsed, 75 * 60)
        case .stale:
            return 0
        }
    }

    @ViewBuilder
    private var timerLabel: some View {
        switch clock {
        case .countdown(let end):
            Text(
                timerInterval: CockpitTimerInterval.countdown(to: end),
                countsDown: true,
                showsHours: false
            )
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
}
