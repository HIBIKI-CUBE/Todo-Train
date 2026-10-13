//
//  CockpitActivityChrome.swift
//  Shared Live Activity face.
//
//  Left: ticket name and state. Right: remaining mm:ss.
//  Bottom: tick gauge and 「予定 HH:mm」, or the pause / check-in row.
//  The gauge is ProgressView(timerInterval:) with ticks and a train-head pointer.
//

import SwiftUI
import WidgetKit

struct CockpitFaceMetrics: Equatable {
    var timerSize: CGFloat
    var titleSize: CGFloat
    var stateSize: CGFloat
    var captionSize: CGFloat
    var gaugeHeight: CGFloat
    var trainMark: CGFloat
    var marginH: CGFloat
    var marginV: CGFloat
    var rowSpacing: CGFloat
    var fillsTimer: Bool

    static let expanded = CockpitFaceMetrics(
        timerSize: 34, titleSize: 15, stateSize: 12, captionSize: 11,
        gaugeHeight: 12, trainMark: 13, marginH: 12, marginV: 4,
        rowSpacing: 4, fillsTimer: false
    )

    static let expandedTight = CockpitFaceMetrics(
        timerSize: 26, titleSize: 13, stateSize: 11, captionSize: 10,
        gaugeHeight: 10, trainMark: 12, marginH: 8, marginV: 2,
        rowSpacing: 2, fillsTimer: false
    )

    static let lockScreen = CockpitFaceMetrics(
        timerSize: 40, titleSize: 16, stateSize: 13, captionSize: 12,
        gaugeHeight: 12, trainMark: 14, marginH: 14, marginV: 10,
        rowSpacing: 8, fillsTimer: false
    )

    static let lockScreenCompact = CockpitFaceMetrics(
        timerSize: 28, titleSize: 14, stateSize: 12, captionSize: 11,
        gaugeHeight: 10, trainMark: 12, marginH: 10, marginV: 6,
        rowSpacing: 4, fillsTimer: false
    )

    static let standBy = CockpitFaceMetrics(
        timerSize: 96, titleSize: 18, stateSize: 15, captionSize: 14,
        gaugeHeight: 14, trainMark: 16, marginH: 8, marginV: 8,
        rowSpacing: 8, fillsTimer: true
    )

    static let stackMedium = CockpitFaceMetrics(
        timerSize: 30, titleSize: 14, stateSize: 12, captionSize: 11,
        gaugeHeight: 10, trainMark: 12, marginH: 8, marginV: 6,
        rowSpacing: 6, fillsTimer: false
    )

    static let stackSmall = CockpitFaceMetrics(
        timerSize: 22, titleSize: 12, stateSize: 10, captionSize: 10,
        gaugeHeight: 8, trainMark: 10, marginH: 6, marginV: 4,
        rowSpacing: 3, fillsTimer: false
    )

    static func resolve(width: CGFloat, height: CGFloat, fullscreen: Bool) -> CockpitFaceMetrics {
        if fullscreen { return .standBy }
        let w = width.isFinite ? width : CockpitSizeContract.proMaxWidth
        let h = height.isFinite ? height : CockpitSizeContract.lockScreenMaxHeight
        if w >= 300 {
            return h >= 120 ? .lockScreen : .lockScreenCompact
        }
        if h >= 108 { return .stackMedium }
        return .stackSmall
    }
}

struct CockpitActivityChrome<RideButton: View, ResumeButton: View, PromptButtons: View>: View {
    let model: CockpitDisplayModel
    var metrics: CockpitFaceMetrics
    var showsTrainMark: Bool = true
    var limitedWidth: Bool = false
    @ViewBuilder var rideButton: () -> RideButton
    @ViewBuilder var resumeButton: () -> ResumeButton
    @ViewBuilder var promptButtons: () -> PromptButtons

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            HStack(alignment: .center, spacing: 4) {
                titleBlock
                Spacer(minLength: 4)
                CockpitFaceTimer(model: model, metrics: metrics, limitedWidth: limitedWidth)
                    .layoutPriority(1)
                trailingSlot
            }
            .frame(maxHeight: metrics.fillsTimer ? .infinity : nil)

            bottomSlot
        }
        .padding(.horizontal, metrics.marginH)
        .padding(.vertical, metrics.marginV)
        .frame(maxWidth: .infinity, maxHeight: metrics.fillsTimer ? .infinity : nil, alignment: .top)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if showsTrainMark {
                    Image(systemName: "tram.fill")
                        .font(.system(size: metrics.trainMark, weight: .bold))
                        .foregroundStyle(model.phase.accentColor)
                        .accessibilityHidden(true)
                }
                Text(model.title)
                    .font(.system(size: metrics.titleSize, weight: .semibold))
                    .foregroundStyle(CockpitColors.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .privacySensitive()
            }
            if model.showsOvertimeMark {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: metrics.stateSize, weight: .bold))
                    .foregroundStyle(CockpitColors.red)
                    .accessibilityLabel("予定の時刻を過ぎています")
            } else if let state = model.inlineState {
                Text(state)
                    .font(.system(size: metrics.stateSize, weight: .bold))
                    .foregroundStyle(model.phase.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var trailingSlot: some View {
        switch model.chromeMode {
        case .riding:
            rideButton()
        case .paused, .prompt:
            EmptyView()
        }
    }

    @ViewBuilder
    private var bottomSlot: some View {
        switch model.chromeMode {
        case .riding:
            CockpitGaugeBottom(model: model, metrics: metrics, limitedWidth: limitedWidth)
        case .paused:
            CockpitPausedBottom(metrics: metrics) {
                resumeButton()
            }
        case .prompt(let text):
            CockpitPromptBottom(prompt: text, metrics: metrics) {
                promptButtons()
            }
        }
    }
}

struct CockpitFittedChrome<RideButton: View, ResumeButton: View, PromptButtons: View>: View {
    let model: CockpitDisplayModel
    var fullscreen: Bool
    var showsTrainMark: Bool = true
    var limitedWidth: Bool = false
    @ViewBuilder var rideButton: () -> RideButton
    @ViewBuilder var resumeButton: () -> ResumeButton
    @ViewBuilder var promptButtons: () -> PromptButtons

    var body: some View {
        GeometryReader { geo in
            let metrics = CockpitFaceMetrics.resolve(
                width: geo.size.width,
                height: geo.size.height,
                fullscreen: fullscreen
            )
            CockpitActivityChrome(
                model: model,
                metrics: metrics,
                showsTrainMark: showsTrainMark,
                limitedWidth: limitedWidth,
                rideButton: rideButton,
                resumeButton: resumeButton,
                promptButtons: promptButtons
            )
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }
}

struct CockpitFaceTimer: View {
    let model: CockpitDisplayModel
    var metrics: CockpitFaceMetrics
    var limitedWidth: Bool = false

    var body: some View {
        Group {
            if metrics.fillsTimer {
                GeometryReader { geo in
                    let fitted = min(metrics.timerSize, geo.size.width * 0.92, max(28, geo.size.height * 0.92))
                    timerText
                        .font(.system(size: fitted, weight: .bold))
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .trailing)
                }
            } else {
                timerText
                    .font(.system(size: limitedWidth ? metrics.timerSize * 0.85 : metrics.timerSize, weight: .bold))
            }
        }
        .monospacedDigit()
        .foregroundStyle(model.phase.accentColor)
        .minimumScaleFactor(0.4)
        .lineLimit(1)
        .multilineTextAlignment(.trailing)
        .accessibilityLabel(accessibilityName)
    }

    @ViewBuilder
    private var timerText: some View {
        switch model.clock {
        case .countdown(let end):
            Text(
                timerInterval: CockpitTimerInterval.countdown(to: end),
                pauseTime: nil,
                countsDown: true,
                showsHours: false
            )
        case .paused(let remaining):
            Text(CockpitFormat.shortTimerLabel(remaining: remaining, limitedWidth: limitedWidth))
        case .overtime, .alert:
            if let start = model.scheduledAt {
                Text(
                    timerInterval: CockpitGaugeRange.countUp(since: start),
                    pauseTime: nil,
                    countsDown: false,
                    showsHours: false
                )
            } else {
                Text("0:00")
            }
        case .stale:
            Text("—:—")
        }
    }

    private var accessibilityName: String {
        if model.showsOvertimeMark { return "予定の時刻を過ぎています" }
        if case .paused = model.clock { return "停車中" }
        return "残り時間"
    }
}

struct CockpitGaugeBottom: View {
    let model: CockpitDisplayModel
    var metrics: CockpitFaceMetrics
    var limitedWidth: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            CockpitTickGauge(model: model, limitedWidth: limitedWidth)
                .frame(height: metrics.gaugeHeight)
            if let caption = model.gaugeCaption {
                Text(caption)
                    .font(.system(size: metrics.captionSize, weight: .semibold))
                    .foregroundStyle(CockpitColors.muted)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct CockpitPausedBottom<Resume: View>: View {
    var metrics: CockpitFaceMetrics
    @ViewBuilder var resume: () -> Resume

    var body: some View {
        HStack(spacing: 8) {
            Text("停車中")
                .font(.system(size: metrics.stateSize + 2, weight: .bold))
                .foregroundStyle(CockpitColors.amber)
                .lineLimit(1)
            Spacer(minLength: 4)
            resume()
        }
    }
}

struct CockpitPromptBottom<Replies: View>: View {
    let prompt: String
    var metrics: CockpitFaceMetrics
    @ViewBuilder var replies: () -> Replies

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(prompt)
                .font(.system(size: metrics.stateSize + 1, weight: .semibold))
                .foregroundStyle(CockpitColors.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, alignment: .leading)
            replies()
        }
    }
}

/// Visual circle is small. The 44pt frame is the tap area.
struct CockpitRoundButtonLabel: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(CockpitColors.fillRaised, in: Circle())
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

struct CockpitReplyLabel: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .frame(minWidth: 44, minHeight: 44)
        .background(CockpitColors.fillRaised, in: Capsule())
        .contentShape(Capsule())
    }
}

// MARK: - Gauge

struct TrainHeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let nose = rect.width * 0.38
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.maxX - nose, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - nose, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.18))
        path.closeSubpath()
        return path
    }
}

struct TrainHeadGaugeStyle: ProgressViewStyle {
    var phase: FocusTimerPhase
    var tickFractions: [Double]
    var showsTrain: Bool
    var muted: Bool

    func makeBody(configuration: Configuration) -> some View {
        let fraction = CGFloat(min(max(configuration.fractionCompleted ?? 0, 0), 1))
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let height = max(geo.size.height, 1)
            let planned = width * CGFloat(CockpitGaugeRange.plannedSpan)
            let barH = max(3, min(height * 0.42, 6))
            let barY = (height - barH) / 2
            let filled = width * fraction
            let pastFull = fraction > CGFloat(CockpitGaugeRange.plannedSpan) + 0.004
            let accent = muted ? CockpitColors.muted : (pastFull ? CockpitColors.red : phase.accentColor)
            let headW = min(14, max(7, height * 0.85))
            let headH = min(10, max(5, height * 0.62))

            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(CockpitColors.track)
                    .frame(width: width, height: barH)
                    .offset(y: barY)

                Capsule()
                    .fill(accent)
                    .frame(width: max(min(filled, planned), filled > 0 ? 2 : 0), height: barH)
                    .offset(y: barY)

                if filled > planned {
                    Capsule()
                        .fill(CockpitColors.red)
                        .frame(width: filled - planned, height: barH)
                        .offset(x: planned, y: barY)
                }

                ForEach(Array(tickFractions.enumerated()), id: \.offset) { _, tick in
                    let full = tick >= 0.999
                    let x = CGFloat(tick) * planned
                    Rectangle()
                        .fill(full ? Color.white.opacity(0.92) : Color.white.opacity(0.5))
                        .frame(width: full ? 1.5 : 1, height: full ? height : height * 0.72)
                        .offset(x: min(max(x - 0.5, 0), width - 1.5), y: full ? 0 : height * 0.14)
                }

                if showsTrain, !muted, filled > 0 {
                    TrainHeadShape()
                        .fill(accent)
                        .frame(width: headW, height: headH)
                        .offset(
                            x: min(max(filled - headW * 0.72, 0), width - headW),
                            y: (height - headH) / 2
                        )
                }
            }
        }
    }
}

struct RingGaugeStyle: ProgressViewStyle {
    var phase: FocusTimerPhase
    var muted: Bool

    func makeBody(configuration: Configuration) -> some View {
        let fraction = min(max(configuration.fractionCompleted ?? 0, 0), 1)
        let planned = CockpitGaugeRange.plannedSpan
        let ring = min(fraction / planned, 1)
        let pastFull = fraction > planned + 0.004
        let tint = muted ? CockpitColors.muted : (pastFull ? CockpitColors.red : phase.accentColor)
        ZStack {
            Circle()
                .stroke(CockpitColors.track, lineWidth: 3)
            Circle()
                .trim(from: 0, to: ring)
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if pastFull, !muted {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(CockpitColors.red)
            }
        }
        .padding(1.5)
    }
}

struct CockpitProgressHost<S: ProgressViewStyle>: View {
    let model: CockpitDisplayModel
    let style: S

    var body: some View {
        Group {
            switch model.clock {
            case .countdown(let end):
                live(CockpitGaugeRange.timerInterval(deadline: end, budgetSeconds: model.budgetSeconds))
            case .overtime, .alert:
                if let start = model.scheduledAt {
                    live(CockpitGaugeRange.timerInterval(deadline: start, budgetSeconds: model.budgetSeconds))
                } else {
                    ProgressView(value: 1.0)
                        .progressViewStyle(style)
                }
            case .paused:
                ProgressView(value: CockpitGaugeRange.trackFraction(progress: model.pausedProgress ?? 0))
                    .progressViewStyle(style)
            case .stale:
                ProgressView(value: 0)
                    .progressViewStyle(style)
            }
        }
        .labelsHidden()
    }

    private func live(_ range: ClosedRange<Date>) -> some View {
        ProgressView(timerInterval: range, countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(style)
    }
}

struct CockpitTickGauge: View {
    let model: CockpitDisplayModel
    var limitedWidth: Bool = false
    var showsTrain: Bool = true

    var body: some View {
        CockpitProgressHost(
            model: model,
            style: TrainHeadGaugeStyle(
                phase: model.phase,
                tickFractions: CockpitGaugeTicks.fractions(
                    budgetSeconds: model.budgetSeconds,
                    limited: limitedWidth
                ),
                showsTrain: showsTrain,
                muted: model.isStale
            )
        )
        .accessibilityHidden(true)
    }
}

struct CockpitRingGauge: View {
    let model: CockpitDisplayModel

    var body: some View {
        CockpitProgressHost(
            model: model,
            style: RingGaugeStyle(phase: model.phase, muted: model.isStale)
        )
        .accessibilityHidden(true)
    }
}

struct CockpitCompactLeadingGauge: View {
    let model: CockpitDisplayModel
    @Environment(\.isDynamicIslandLimitedInWidth) private var limitedWidth

    var body: some View {
        CockpitTickGauge(model: model, limitedWidth: limitedWidth, showsTrain: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, limitedWidth ? 1 : 3)
            .accessibilityLabel("進捗")
    }
}
