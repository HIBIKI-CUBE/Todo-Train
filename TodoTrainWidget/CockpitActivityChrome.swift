//
//  CockpitActivityChrome.swift
//  Shared Live Activity face.
//
//  Left: ticket name and state. Right: remaining mm:ss, with 「予定 HH:mm」 under it.
//  Bottom: tick gauge, or the pause / check-in row. The bottom row is reserved first.
//  The gauge is ProgressView(timerInterval:) with ticks and a train-head pointer.
//  Outer inset and corner radius belong to CockpitSafeChrome. Do not pad the face.
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
    var rowSpacing: CGFloat
    var fillsTimer: Bool

    /// The caption's line box. Point size alone clips 「予定 HH:mm」 out of the band.
    var captionLine: CGFloat { captionSize + 4 }

    /// Timer row (at least the 44pt control) plus 「予定 HH:mm」 under it.
    var scheduleBand: CGFloat {
        max(timerSize, CockpitSafeChrome.controlSide) + 2 + captionLine
    }

    static let expanded = CockpitFaceMetrics(
        timerSize: 34, titleSize: 15, stateSize: 12, captionSize: 11,
        gaugeHeight: 12, trainMark: 13,
        rowSpacing: 4, fillsTimer: false
    )

    static let expandedTight = CockpitFaceMetrics(
        timerSize: 26, titleSize: 13, stateSize: 11, captionSize: 10,
        gaugeHeight: 10, trainMark: 12,
        rowSpacing: 2, fillsTimer: false
    )

    static let lockScreen = CockpitFaceMetrics(
        timerSize: 40, titleSize: 16, stateSize: 13, captionSize: 12,
        gaugeHeight: 12, trainMark: 14,
        rowSpacing: 8, fillsTimer: false
    )

    static let lockScreenCompact = CockpitFaceMetrics(
        timerSize: 28, titleSize: 14, stateSize: 12, captionSize: 11,
        gaugeHeight: 10, trainMark: 12,
        rowSpacing: 4, fillsTimer: false
    )

    static let standBy = CockpitFaceMetrics(
        timerSize: 96, titleSize: 18, stateSize: 15, captionSize: 14,
        gaugeHeight: 14, trainMark: 16,
        rowSpacing: 8, fillsTimer: true
    )

    static let stackMedium = CockpitFaceMetrics(
        timerSize: 30, titleSize: 14, stateSize: 12, captionSize: 11,
        gaugeHeight: 10, trainMark: 12,
        rowSpacing: 6, fillsTimer: false
    )

    static let stackSmall = CockpitFaceMetrics(
        timerSize: 22, titleSize: 12, stateSize: 10, captionSize: 10,
        gaugeHeight: 8, trainMark: 10,
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

/// Vertical stack that fits the height the system actually proposed.
/// The bottom row (gauge, or 停車中 / 再乗車) is reserved first and is never the piece that overflows.
struct CockpitFaceBudget: Equatable, Sendable {
    var top: CGFloat
    var bottom: CGFloat
    var spacing: CGFloat
    var timerHeight: CGFloat
    var showsSchedule: Bool
    var showsStateLine: Bool

    var idealHeight: CGFloat { top + spacing + bottom }

    static func bottomHeight(mode: CockpitChromeMode, metrics: CockpitFaceMetrics) -> CGFloat {
        switch mode {
        case .riding:
            return metrics.gaugeHeight
        case .paused, .prompt:
            return CockpitSafeChrome.controlSide
        }
    }

    /// Uncompressed stack. StandBy's timer does not grow here; `resolve` fills leftover space.
    static func preferred(
        mode: CockpitChromeMode,
        metrics: CockpitFaceMetrics,
        showsOvertimeMark: Bool,
        showsInlineState: Bool
    ) -> CockpitFaceBudget {
        resolve(
            mode: mode,
            metrics: metrics,
            contentHeight: .greatestFiniteMagnitude,
            showsOvertimeMark: showsOvertimeMark,
            showsInlineState: showsInlineState
        )
    }

    /// Canvas height of an expanded island that keeps the top band and the bottom row under the 160pt cap.
    /// The chrome reserves a 44pt bottom before it gives the top band its height, so the canvas
    /// includes that reserve even when the gauge itself is shorter.
    static func expandedCanvasHeight(
        mode: CockpitChromeMode,
        metrics: CockpitFaceMetrics = .expanded
    ) -> CGFloat {
        let inset = CockpitSafeChrome.expandedEdgeInset
        let topBand = max(metrics.scheduleBand, CockpitSafeChrome.cameraHousing.height)
        let bottom = max(bottomHeight(mode: mode, metrics: metrics), CockpitSafeChrome.controlSide)
        let height = inset + topBand + CockpitSafeChrome.bandGap + bottom + inset
        return min(
            CockpitSizeContract.lockScreenMaxHeight,
            max(CockpitSizeContract.lockScreenMinHeight, height)
        )
    }

    static func resolve(
        mode: CockpitChromeMode,
        metrics: CockpitFaceMetrics,
        contentHeight: CGFloat,
        showsOvertimeMark: Bool,
        showsInlineState: Bool
    ) -> CockpitFaceBudget {
        let fullBottom = bottomHeight(mode: mode, metrics: metrics)
        let bottom = min(fullBottom, max(0, contentHeight))
        let room = max(0, contentHeight - bottom)
        let preferredSpacing = metrics.rowSpacing
        let tightSpacing = min(2, preferredSpacing)
        let control: CGFloat = {
            if case .riding = mode { return CockpitSafeChrome.controlSide }
            return 0
        }()
        let stateWanted = showsOvertimeMark || showsInlineState

        func pack(spacing: CGFloat, state: Bool, schedule: Bool, timer: CGFloat) -> CockpitFaceBudget? {
            let title = metrics.titleSize + (state ? (1 + metrics.stateSize) : 0)
            let row = max(timer, control)
            let column = row + (schedule ? (2 + metrics.captionLine) : 0)
            let top = max(title, column)
            guard top + spacing + bottom <= contentHeight + 0.5 else { return nil }
            var budget = CockpitFaceBudget(
                top: top,
                bottom: bottom,
                spacing: spacing,
                timerHeight: timer,
                showsSchedule: schedule,
                showsStateLine: state
            )
            if metrics.fillsTimer, contentHeight.isFinite {
                let extra = max(0, contentHeight - budget.idealHeight)
                budget.top += extra
                budget.timerHeight = max(timer, budget.top - (schedule ? (2 + metrics.captionLine) : 0))
            }
            return budget
        }

        if let hit = pack(spacing: preferredSpacing, state: stateWanted, schedule: true, timer: metrics.timerSize) {
            return hit
        }
        if let hit = pack(spacing: tightSpacing, state: stateWanted, schedule: true, timer: metrics.timerSize) {
            return hit
        }
        if let hit = pack(spacing: tightSpacing, state: false, schedule: true, timer: metrics.timerSize) {
            return hit
        }
        let spacing = tightSpacing
        let topRoom = max(0, room - spacing)
        let scheduleExtra = 2 + metrics.captionLine
        let timerRoom = max(0, topRoom - scheduleExtra)
        let shrunk = min(metrics.timerSize, timerRoom)
        if shrunk >= 12,
           let hit = pack(spacing: spacing, state: false, schedule: true, timer: shrunk) {
            return hit
        }
        let timerOnly = min(metrics.timerSize, topRoom)
        if let hit = pack(spacing: spacing, state: false, schedule: false, timer: timerOnly) {
            return hit
        }
        let fallbackTop = max(0, contentHeight - bottom - spacing)
        return CockpitFaceBudget(
            top: fallbackTop,
            bottom: bottom,
            spacing: fallbackTop > 0 ? spacing : 0,
            timerHeight: min(metrics.timerSize, fallbackTop),
            showsSchedule: false,
            showsStateLine: false
        )
    }
}

struct CockpitActivityChrome<RideButton: View, ResumeButton: View, PromptButtons: View>: View {
    let model: CockpitDisplayModel
    var metrics: CockpitFaceMetrics
    var surface: CockpitSafeSurface
    var slot: CockpitSafeSlot = .all
    var showsTrainMark: Bool = true
    var limitedWidth: Bool = false
    @ViewBuilder var rideButton: () -> RideButton
    @ViewBuilder var resumeButton: () -> ResumeButton
    @ViewBuilder var promptButtons: () -> PromptButtons

    var body: some View {
        switch slot {
        case .all:
            CockpitSafeHost(surface: surface) {
                fittedFace
            } leading: {
                titleBlock(showsStateLine: true)
            } trailing: {
                fittedTrailing
            } bottom: {
                fittedBottom
            }
        case .leading:
            titleBlock(showsStateLine: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .dynamicIsland(verticalPlacement: .belowIfTooWide)
                .environment(\.cockpitConcentricRadius, surfaceConcentricRadius)
        case .trailing:
            fittedTrailing
                .dynamicIsland(verticalPlacement: .belowIfTooWide)
                .environment(\.cockpitConcentricRadius, surfaceConcentricRadius)
        case .bottom:
            fittedBottom
                .environment(\.cockpitConcentricRadius, surfaceConcentricRadius)
        }
    }

    private var surfaceConcentricRadius: CGFloat {
        CockpitSafeChrome.expandedOuterRadius - CockpitSafeChrome.expandedEdgeInset
    }

    /// Lock screen, StandBy, and the stack. The first stack that fits the proposal wins.
    /// Explicit heights keep `Text(timerInterval:)` from reporting an ideal taller than the card.
    private var fittedFace: some View {
        GeometryReader { geo in
            let resolved = budget(fitting: geo.size.height)
            let preferred = CockpitFaceBudget.preferred(
                mode: model.chromeMode,
                metrics: metrics,
                showsOvertimeMark: model.showsOvertimeMark,
                showsInlineState: model.inlineState != nil
            )
            ViewThatFits(in: .vertical) {
                if !metrics.fillsTimer {
                    arranged(preferred)
                }
                arranged(resolved)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }

    private func arranged(_ budget: CockpitFaceBudget) -> some View {
        VStack(alignment: .leading, spacing: budget.spacing) {
            HStack(alignment: .center, spacing: 4) {
                titleBlock(showsStateLine: budget.showsStateLine)
                Spacer(minLength: 4)
                trailingStack(budget)
            }
            .frame(height: budget.top, alignment: .center)
            .layoutPriority(0)
            bottomSlot
                .frame(height: budget.bottom, alignment: .center)
                .layoutPriority(1)
        }
    }

    /// Expanded trailing region. 予定 sits under the remaining time, off the bottom corner.
    /// Ideal height is the stack itself, so the island grows to it instead of collapsing.
    private var fittedTrailing: some View {
        let withSchedule = CockpitFaceBudget(
            top: metrics.scheduleBand,
            bottom: 0,
            spacing: 0,
            timerHeight: metrics.timerSize,
            showsSchedule: true,
            showsStateLine: false
        )
        let timerOnly = CockpitFaceBudget(
            top: max(metrics.timerSize, CockpitSafeChrome.controlSide),
            bottom: 0,
            spacing: 0,
            timerHeight: metrics.timerSize,
            showsSchedule: false,
            showsStateLine: false
        )
        return ViewThatFits(in: .vertical) {
            trailingStack(withSchedule)
            trailingStack(timerOnly)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    /// Gauge or action row. Its own height is the ideal, so the system keeps the row
    /// and the chord inset (content margins) keeps it off the bottom corners.
    private var fittedBottom: some View {
        bottomSlot
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func budget(fitting height: CGFloat) -> CockpitFaceBudget {
        CockpitFaceBudget.resolve(
            mode: model.chromeMode,
            metrics: metrics,
            contentHeight: height,
            showsOvertimeMark: model.showsOvertimeMark,
            showsInlineState: model.inlineState != nil
        )
    }

    private func trailingStack(_ budget: CockpitFaceBudget) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                CockpitFaceTimer(
                    model: model,
                    metrics: metrics,
                    limitedWidth: limitedWidth,
                    height: budget.timerHeight
                )
                trailingControl
            }
            if budget.showsSchedule {
                scheduleLabel
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private var scheduleLabel: some View {
        if let caption = model.gaugeCaption {
            Text(caption)
                .font(.system(size: metrics.captionSize, weight: .semibold))
                .foregroundStyle(CockpitColors.muted)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func titleBlock(showsStateLine: Bool) -> some View {
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
                    .minimumScaleFactor(0.5)
                    .privacySensitive()
            }
            if showsStateLine, model.showsOvertimeMark {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: metrics.stateSize, weight: .bold))
                    .foregroundStyle(CockpitColors.red)
                    .accessibilityLabel("予定の時刻を過ぎています")
            } else if showsStateLine, let state = model.inlineState {
                Text(state)
                    .font(.system(size: metrics.stateSize, weight: .bold))
                    .foregroundStyle(model.phase.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var trailingControl: some View {
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
            let surface = CockpitSafeSurface.fitting(
                width: geo.size.width,
                height: geo.size.height,
                fullscreen: fullscreen
            )
            CockpitActivityChrome(
                model: model,
                metrics: metrics,
                surface: surface,
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
    /// Explicit height so `Text(timerInterval:)` cannot report an ideal taller than the card.
    var height: CGFloat? = nil

    var body: some View {
        Group {
            if metrics.fillsTimer {
                GeometryReader { geo in
                    // "12:00" is about three ems wide. Fit the point size to the slot.
                    let fitted = min(
                        metrics.timerSize,
                        geo.size.width / 3.15,
                        max(22, geo.size.height * 0.9)
                    )
                    timerText
                        .font(.system(size: fitted, weight: .bold))
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .trailing)
                }
                .clipped()
            } else {
                timerText
                    .font(.system(size: limitedWidth ? metrics.timerSize * 0.85 : metrics.timerSize, weight: .bold))
                    .frame(height: height, alignment: .trailing)
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
        CockpitTickGauge(model: model, limitedWidth: limitedWidth)
            .frame(height: metrics.gaugeHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
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
                .layoutPriority(1)
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
                .layoutPriority(1)
        }
    }
}

/// Visual circle is small. The 44pt frame is the tap area.
struct CockpitRoundButtonLabel: View {
    let systemImage: String
    let tint: Color
    @Environment(\.cockpitConcentricRadius) private var concentricRadius

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(CockpitColors.fillRaised, in: CockpitConcentricCorner(radius: concentricRadius))
            .frame(width: CockpitSafeChrome.controlSide, height: CockpitSafeChrome.controlSide)
            .contentShape(CockpitConcentricCorner(radius: concentricRadius))
    }
}

struct CockpitReplyLabel: View {
    let title: String
    let systemImage: String
    let tint: Color
    @Environment(\.cockpitConcentricRadius) private var concentricRadius

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .frame(minWidth: CockpitSafeChrome.controlSide, minHeight: CockpitSafeChrome.controlSide)
        .background(CockpitColors.fillRaised, in: CockpitConcentricCorner(radius: concentricRadius))
        .contentShape(CockpitConcentricCorner(radius: concentricRadius))
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
    var trackColor: Color = CockpitColors.track
    var lineWidth: CGFloat = 3

    func makeBody(configuration: Configuration) -> some View {
        let fraction = min(max(configuration.fractionCompleted ?? 0, 0), 1)
        let planned = CockpitGaugeRange.plannedSpan
        let ring = min(fraction / planned, 1)
        let pastFull = fraction > planned + 0.004
        let tint = muted ? CockpitColors.muted : (pastFull ? CockpitColors.red : phase.accentColor)
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: ring)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if pastFull, !muted {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(CockpitColors.red)
            }
        }
        .padding(lineWidth / 2)
    }
}

private struct CockpitFrozenGaugeKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

extension EnvironmentValues {
    /// When set, the gauge draws this track fraction instead of `ProgressView(timerInterval:)`.
    /// ImageRenderer does not tick a timer interval, so previews freeze the train head here.
    var cockpitFrozenGaugeFraction: Double? {
        get { self[CockpitFrozenGaugeKey.self] }
        set { self[CockpitFrozenGaugeKey.self] = newValue }
    }
}

struct CockpitProgressHost<S: ProgressViewStyle>: View {
    let model: CockpitDisplayModel
    let style: S
    @Environment(\.cockpitFrozenGaugeFraction) private var frozenFraction

    var body: some View {
        Group {
            if let frozenFraction {
                ProgressView(value: min(max(frozenFraction, 0), 1))
                    .progressViewStyle(style)
            } else {
                liveGauge
            }
        }
        .labelsHidden()
    }

    @ViewBuilder
    private var liveGauge: some View {
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

/// Diameter of the compact-leading mark. It is the slot's shorter side, never a squeezed bar.
enum CockpitCompactMark {
    /// Below this, a ring with a train mark does not read as a gauge.
    static let legibleSide: CGFloat = 18
    /// The old horizontal bar never drew thicker than this, which is why it was a sliver.
    static let barThickness: CGFloat = 6

    static func side(fitting size: CGSize) -> CGFloat {
        min(max(0, size.width), max(0, size.height))
    }

    /// Square that fills the HIG compact pill after the cap inset.
    /// A fixed side keeps the region from collapsing to the old bar's height.
    static var slotSide: CGFloat {
        let chrome = CockpitSafeChrome.resolve(
            surface: .islandCompact,
            canvas: CockpitSizeContract.islandCompactSide
        )
        return side(fitting: chrome.content.size)
    }

    /// Stroke that stays a ring on `side`, not a hairline.
    static func stroke(for side: CGFloat) -> CGFloat {
        max(2.5, side * 0.14)
    }
}

struct CockpitCompactLeadingGauge: View {
    let model: CockpitDisplayModel

    var body: some View {
        let side = CockpitCompactMark.slotSide
        let stroke = CockpitCompactMark.stroke(for: side)
        ZStack {
            CockpitProgressHost(
                model: model,
                style: RingGaugeStyle(
                    phase: model.phase,
                    muted: model.isStale,
                    trackColor: CockpitColors.ringTrack,
                    lineWidth: stroke
                )
            )
            Image(systemName: "tram.fill")
                .font(.system(size: max(9, side * 0.38), weight: .bold))
                .foregroundStyle(model.phase.accentColor)
                .accessibilityHidden(true)
        }
        .frame(width: side, height: side)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("進捗")
    }
}
