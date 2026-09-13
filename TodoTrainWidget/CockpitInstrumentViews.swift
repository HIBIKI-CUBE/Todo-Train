//
//  CockpitInstrumentViews.swift
//  Shared Live Activity instrument chrome (Focus dashboard echo).
//
//  Timers MUST use TextInterval / ProgressView(timerInterval:) so the system
//  drives second-by-second updates. TimelineView does not tick inside LAs.
//
//  StandBy detection: EnvironmentValues.isActivityFullscreen (Apple docs).
//  Layout MUST fit the unscaled proposal (84…160 × ~408). StandBy scales ~200%.
//  Never invent a taller internal height than GeometryReader reports.
//

import SwiftUI
import WidgetKit

// MARK: - Lock Screen (ViewThatFits ≤ proposal; HIG outer margin 14pt)

struct CockpitLockScreenInstrument<Controls: View>: View {
    let title: String
    let clock: CockpitClockStyle
    let phase: FocusTimerPhase
    let headerState: String?
    let deadlineLabel: String
    let budgetSeconds: Int
    let pausedProgress: Double?
    let accessibilityTimer: String
    @ViewBuilder var controls: () -> Controls

    private var hasControls: Bool { Controls.self != EmptyView.self }

    init(
        title: String,
        clock: CockpitClockStyle,
        phase: FocusTimerPhase,
        headerState: String?,
        deadlineLabel: String,
        budgetSeconds: Int,
        pausedProgress: Double?,
        accessibilityTimer: String = "",
        @ViewBuilder controls: @escaping () -> Controls = { EmptyView() }
    ) {
        self.title = title
        self.clock = clock
        self.phase = phase
        self.headerState = headerState
        self.deadlineLabel = deadlineLabel
        self.budgetSeconds = budgetSeconds
        self.pausedProgress = pausedProgress
        self.accessibilityTimer = accessibilityTimer
        self.controls = controls
    }

    var body: some View {
        // Prefer richer chrome; fall back when the proposal is short.
        // Padding is inside each candidate so ViewThatFits measures total height.
        ViewThatFits(in: .vertical) {
            lockScreenStack(density: .regular)
            if hasControls {
                lockScreenRegularWithoutDeadline
            }
            lockScreenStack(density: .compact)
        }
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    @ViewBuilder
    private func lockScreenStack(density: CockpitDensity) -> some View {
        let margin = density == .regular
            ? CockpitSizeContract.outerMargin
            : CockpitSizeContract.compactOuterMargin
        let controlHeight = density == .regular
            ? CockpitSizeContract.controlHeight
            : CockpitSizeContract.compactControlHeight

        lockScreenChrome(
            density: density,
            showsTitle: density == .regular,
            showsDeadline: density == .regular,
            showsProgress: density == .regular || !hasControls,
            margin: margin,
            controlHeight: controlHeight
        )
    }

    /// Intermediate: keep title/progress, drop deadline so Alarm controls fit in 160pt.
    @ViewBuilder
    private var lockScreenRegularWithoutDeadline: some View {
        lockScreenChrome(
            density: .regular,
            showsTitle: true,
            showsDeadline: false,
            showsProgress: true,
            margin: CockpitSizeContract.outerMargin,
            controlHeight: CockpitSizeContract.controlHeight
        )
    }

    @ViewBuilder
    private func lockScreenChrome(
        density: CockpitDensity,
        showsTitle: Bool,
        showsDeadline: Bool,
        showsProgress: Bool,
        margin: CGFloat,
        controlHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CockpitLiveTimer(
                style: clock,
                phase: phase,
                fontSize: density == .regular ? 40 : 28
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: density == .regular ? 40 : 28)
            .accessibilityLabel("残り時間")

            if showsTitle {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CockpitColors.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .privacySensitive()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    CockpitHeaderBadge(text: headerState, color: phase.accentColor, size: 13)
                }
                .padding(.top, 4)
            }

            if showsProgress {
                CockpitLiveProgress(
                    clock: clock,
                    phase: phase,
                    budgetSeconds: budgetSeconds,
                    pausedProgress: pausedProgress,
                    barHeight: density == .regular ? 4 : 3
                )
                .padding(.top, density == .regular ? 6 : 4)
            }

            if showsDeadline {
                Text(deadlineLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(phase == .overtime ? CockpitColors.red : CockpitColors.muted)
                    .monospacedDigit()
                    .lineLimit(1)
                    .padding(.top, 2)
            }

            if hasControls {
                controls()
                    .frame(height: controlHeight)
                    .padding(.top, density == .regular ? 6 : 4)
            }
        }
        .padding(margin)
    }
}

// MARK: - StandBy (horizontal 2-pane; remaining-height fill; no black-box overlay)

struct CockpitStandByInstrument<Controls: View>: View {
    let title: String
    let clock: CockpitClockStyle
    let phase: FocusTimerPhase
    let headerState: String?
    let deadlineLabel: String
    let budgetSeconds: Int
    let pausedProgress: Double?
    let accessibilityTimer: String
    @ViewBuilder var controls: () -> Controls

    private var hasControls: Bool { Controls.self != EmptyView.self }

    init(
        title: String,
        clock: CockpitClockStyle,
        phase: FocusTimerPhase,
        headerState: String?,
        deadlineLabel: String,
        budgetSeconds: Int,
        pausedProgress: Double?,
        accessibilityTimer: String = "",
        @ViewBuilder controls: @escaping () -> Controls = { EmptyView() }
    ) {
        self.title = title
        self.clock = clock
        self.phase = phase
        self.headerState = headerState
        self.deadlineLabel = deadlineLabel
        self.budgetSeconds = budgetSeconds
        self.pausedProgress = pausedProgress
        self.accessibilityTimer = accessibilityTimer
        self.controls = controls
    }

    var body: some View {
        // No Color.black box — activityBackgroundTint extends to edges (WWDC26).
        GeometryReader { geo in
            let contract = CockpitSizeContract.standBy(
                width: geo.size.width,
                height: geo.size.height
            )
            let metrics = CockpitStandByMetrics(
                width: contract.width,
                height: contract.height
            )
            standByBand(contract: contract, metrics: metrics)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func standByBand(contract: CockpitSizeContract, metrics: CockpitStandByMetrics) -> some View {
        let density = metrics.density
        HStack(alignment: .center, spacing: 0) {
            standByInstrument(density: density, metrics: metrics)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            if hasControls {
                CockpitVerticalHairline()
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)

                controls()
                    .frame(width: max(88, contract.contentWidth * contract.standByControlFraction))
                    .frame(maxHeight: .infinity)
                    .environment(\.cockpitStandByMetrics, metrics)
            }
        }
        .padding(metrics.margin)
    }

    @ViewBuilder
    private func standByInstrument(density: CockpitDensity, metrics: CockpitStandByMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if density == .regular {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.system(size: metrics.titleSize, weight: .semibold))
                        .foregroundStyle(CockpitColors.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .privacySensitive()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    CockpitHeaderBadge(
                        text: headerState,
                        color: phase.accentColor,
                        size: metrics.badgeSize
                    )
                }
                .frame(height: CockpitStandByChrome.titleRowHeight, alignment: .bottom)
                .padding(.bottom, 4)
            }

            // Timer fills all remaining height after fixed chrome.
            CockpitLiveTimer(
                style: clock,
                phase: phase,
                fontSize: metrics.timerSize,
                fillHeight: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .layoutPriority(0)
            .accessibilityLabel("残り時間")

            CockpitLiveProgress(
                clock: clock,
                phase: phase,
                budgetSeconds: budgetSeconds,
                pausedProgress: pausedProgress,
                barHeight: metrics.progressHeight
            )
            .padding(.top, 4)

            if density == .regular {
                Text(deadlineLabel)
                    .font(.system(size: metrics.deadlineSize, weight: .semibold))
                    .foregroundStyle(phase == .overtime ? CockpitColors.red : CockpitColors.muted)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(height: CockpitStandByChrome.deadlineRowHeight, alignment: .top)
                    .padding(.top, 4)
            }
        }
    }
}

/// Always reserves width for the longest status word so pause/resume does not shift title.
struct CockpitHeaderBadge: View {
    let text: String?
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .trailing) {
            Text("まもなく")
                .font(.system(size: size, weight: .bold))
                .hidden()
            Text(text ?? "")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(color)
                .opacity(text == nil ? 0 : 1)
        }
        .lineLimit(1)
        .accessibilityHidden(text == nil)
    }
}

// MARK: - System-driven clock / progress

struct CockpitLiveTimer: View {
    let style: CockpitClockStyle
    let phase: FocusTimerPhase
    var fontSize: CGFloat = 44
    /// When true (StandBy instrument), size against both width and height.
    var fillHeight: Bool = false

    var body: some View {
        GeometryReader { geo in
            let widthCap = geo.size.width * (fillHeight ? 0.92 : 0.55)
            let heightCap = fillHeight ? geo.size.height * 0.98 : fontSize
            let fitted = min(fontSize, widthCap, max(28, heightCap))
            timerText
                .font(.system(size: fitted, weight: .bold, design: .default))
                .monospacedDigit()
                .foregroundStyle(phase.accentColor)
                .minimumScaleFactor(0.25)
                .lineLimit(1)
                .frame(
                    width: geo.size.width,
                    height: geo.size.height,
                    alignment: .leading
                )
                .accessibilityLabel("残り時間")
        }
    }

    @ViewBuilder
    private var timerText: some View {
        switch style {
        case .countdown(let end):
            Text(
                timerInterval: CockpitTimerInterval.countdown(to: end),
                pauseTime: nil,
                countsDown: true,
                showsHours: false
            )
        case .paused(let remaining):
            Text(CockpitFormat.timerLabel(remaining: remaining))
                .accessibilityValue(
                    CockpitFormat.accessibilityTimerValue(
                        remaining: remaining,
                        isStale: false,
                        isOvertime: false
                    )
                )
        case .alert:
            Text("終了")
        case .overtime:
            Text("超過")
        case .stale:
            Text("—:—")
        }
    }
}

/// Compact Dynamic Island trailing — live seconds with hidden max-digit width template.
struct CockpitCompactTimer: View {
    let clock: CockpitClockStyle
    let phase: FocusTimerPhase
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
            case .alert:
                Text("終了")
            case .overtime:
                Text("超過")
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

    /// `Text(timerInterval:)` keeps seconds; hidden template sets the ideal width.
    @ViewBuilder
    private func liveCountdown(end: Date) -> some View {
        let template = CockpitLayoutPolicy.islandTimerWidthTemplate(
            remaining: end.timeIntervalSinceNow
        )
        ZStack(alignment: .trailing) {
            Text(template)
                .hidden()
                .accessibilityHidden(true)
            Text(
                timerInterval: CockpitTimerInterval.countdown(to: end),
                countsDown: true,
                showsHours: false
            )
        }
    }
}

/// Compact leading / minimal mark — phase-tinted train glyph (not a bare dot).
struct CockpitIslandMark: View {
    let phase: FocusTimerPhase
    var size: CGFloat = 12

    var body: some View {
        Image(systemName: "tram.fill")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(phase.accentColor)
            .accessibilityHidden(true)
    }
}

/// Minimal Dynamic Island — remaining time primary, phase-tinted.
struct CockpitMinimalTimer: View {
    let clock: CockpitClockStyle
    let phase: FocusTimerPhase

    var body: some View {
        CockpitCompactTimer(clock: clock, phase: phase, limitedWidth: true)
            .font(.caption2.weight(.bold).monospacedDigit())
    }
}

struct CockpitLiveProgress: View {
    let clock: CockpitClockStyle
    let phase: FocusTimerPhase
    let budgetSeconds: Int
    let pausedProgress: Double?
    var barHeight: CGFloat = 4

    var body: some View {
        Group {
            switch clock {
            case .countdown(let end):
                ProgressView(
                    timerInterval: CockpitTimerInterval.progress(end: end, budgetSeconds: budgetSeconds),
                    countsDown: false
                ) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(phase.accentColor)
            case .paused:
                ProgressView(value: min(max(pausedProgress ?? 0, 0), 1), total: 1)
                    .progressViewStyle(.linear)
                    .tint(phase.accentColor)
            case .alert, .overtime:
                ProgressView(value: 1.0, total: 1)
                    .progressViewStyle(.linear)
                    .tint(CockpitColors.red)
            case .stale:
                ProgressView(value: 0, total: 1)
                    .progressViewStyle(.linear)
                    .tint(CockpitColors.muted)
            }
        }
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .frame(height: barHeight)
        .accessibilityHidden(true)
    }
}

struct CockpitHairline: View {
    var body: some View {
        Rectangle()
            .fill(CockpitColors.hairline)
            .frame(height: 1)
    }
}

struct CockpitVerticalHairline: View {
    var body: some View {
        Rectangle()
            .fill(CockpitColors.hairline)
            .frame(width: 1)
    }
}

private struct CockpitStandByMetricsKey: EnvironmentKey {
    static let defaultValue = CockpitStandByMetrics(
        width: CockpitSizeContract.proMaxWidth,
        height: CockpitSizeContract.lockScreenMaxHeight
    )
}

extension EnvironmentValues {
    var cockpitStandByMetrics: CockpitStandByMetrics {
        get { self[CockpitStandByMetricsKey.self] }
        set { self[CockpitStandByMetricsKey.self] = newValue }
    }
}

// MARK: - Alarm controls (single essential action)

#if canImport(AlarmKit) && canImport(ActivityKit)
import ActivityKit
import AlarmKit
import AppIntents

enum CockpitControlLayout {
    /// Lock Screen: one Capsule primary action (fixed 44pt tall).
    case horizontalRow
    /// StandBy: large instrument cell in the right pane.
    case standByStack
    /// Dynamic Island bottom: one Capsule chip (≤ 40pt total).
    case islandCompact
}

struct CockpitAlarmControlRow: View {
    let alarmID: UUID
    let sessionID: UUID
    let mode: AlarmPresentationState.Mode
    var layout: CockpitControlLayout = .horizontalRow

    var body: some View {
        switch layout {
        case .horizontalRow:
            primaryMotionButton(density: .lockScreen)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .standByStack:
            primaryMotionButton(density: .standBy)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .islandCompact:
            primaryIslandChip
                .frame(maxWidth: .infinity)
                .frame(height: CockpitSizeContract.islandExpandedControlHeight)
        }
    }

    @ViewBuilder
    private var primaryIslandChip: some View {
        switch mode {
        case .countdown:
            Button(intent: EndBellPauseIntent(alarmID: alarmID)) {
                islandChip(title: "停車", systemImage: "pause.fill", tint: CockpitColors.amber)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("停車")
        case .alert:
            Button(intent: EndBellStopIntent(alarmID: alarmID, sessionID: sessionID)) {
                islandChip(title: "停止", systemImage: "stop.fill", tint: CockpitColors.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("終了ベルを停止")
        case .paused:
            Button(intent: EndBellResumeIntent(alarmID: alarmID)) {
                islandChip(title: "再乗車", systemImage: "play.fill", tint: CockpitColors.green)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("再乗車")
        @unknown default:
            EmptyView()
        }
    }

    private func islandChip(title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CockpitColors.fillRaised, in: Capsule())
        .contentShape(Capsule())
    }

    @ViewBuilder
    private func primaryMotionButton(density: CockpitControlDensity) -> some View {
        switch mode {
        case .countdown:
            Button(intent: EndBellPauseIntent(alarmID: alarmID)) {
                CockpitControlCell(
                    title: "停車",
                    systemImage: "pause.fill",
                    foreground: CockpitColors.amber,
                    fill: CockpitColors.fillRaised,
                    density: density
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("停車")
        case .alert:
            Button(intent: EndBellStopIntent(alarmID: alarmID, sessionID: sessionID)) {
                CockpitControlCell(
                    title: "停止",
                    systemImage: "stop.fill",
                    foreground: CockpitColors.ink,
                    fill: CockpitColors.fillRaised,
                    density: density
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("終了ベルを停止")
        case .paused:
            Button(intent: EndBellResumeIntent(alarmID: alarmID)) {
                CockpitControlCell(
                    title: "再乗車",
                    systemImage: "play.fill",
                    foreground: CockpitColors.green,
                    fill: CockpitColors.fillRaised,
                    density: density
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("再乗車")
        @unknown default:
            EmptyView()
        }
    }
}

private enum CockpitControlDensity {
    case lockScreen
    case standBy
}

private struct CockpitControlCell: View {
    let title: String
    let systemImage: String
    let foreground: Color
    var fill: Color? = nil
    var density: CockpitControlDensity = .lockScreen

    @Environment(\.cockpitStandByMetrics) private var standByMetrics

    var body: some View {
        Group {
            if density == .standBy {
                VStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.system(size: standByMetrics.controlIconSize, weight: .bold))
                    Text(title)
                        .font(.system(size: standByMetrics.controlFontSize, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .bold))
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                }
            }
        }
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(fill ?? CockpitColors.fillRaised, in: RoundedRectangle(cornerRadius: density == .standBy ? 16 : 999, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: density == .standBy ? 16 : 999, style: .continuous))
    }
}
#endif

// MARK: - Dynamic Island shared builders

struct CockpitIslandExpandedCenter: View {
    let presentation: CockpitDisplayModel

    var body: some View {
        VStack(spacing: 2) {
            timerLabel
            Text(presentation.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .privacySensitive()
                .frame(maxWidth: 160)
        }
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private var timerLabel: some View {
        switch presentation.clock {
        case .countdown(let end):
            Text(
                timerInterval: CockpitTimerInterval.countdown(to: end),
                countsDown: true,
                showsHours: false
            )
            .font(.title2.weight(.bold).monospacedDigit())
            .foregroundStyle(presentation.phase.accentColor)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .frame(maxWidth: 140)
            .accessibilityLabel("残り時間")
        case .paused(let remaining):
            Text(CockpitFormat.timerLabel(remaining: remaining))
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(presentation.phase.accentColor)
                .lineLimit(1)
                .frame(maxWidth: 140)
        case .alert:
            Text("終了")
                .font(.headline.weight(.semibold))
                .foregroundStyle(CockpitColors.red)
        case .overtime:
            Text("超過")
                .font(.headline.weight(.semibold))
                .foregroundStyle(CockpitColors.red)
        case .stale:
            Text("更新待ち")
                .font(.headline.weight(.semibold))
                .foregroundStyle(CockpitColors.muted)
        }
    }
}

/// Trailing state word only — titles live under the center timer to avoid sensor-row clipping.
struct CockpitIslandExpandedTrailing: View {
    let phase: FocusTimerPhase
    let headerState: String?

    var body: some View {
        Group {
            if let headerState {
                Text(headerState)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(phase.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: CockpitSizeContract.islandExpandedTrailingMaxWidth, alignment: .trailing)
    }
}

// MARK: - Instrument previews (nominal HIG sizes)

#if DEBUG
private enum CockpitPreviewData {
    static let end = Date.now.addingTimeInterval(5 * 60)
    static let budget = 20 * 60

    static var countdownClock: CockpitClockStyle { .countdown(end: end) }
    static var phase: FocusTimerPhase { FocusTimerPhase(remaining: 5 * 60, budgetSeconds: TimeInterval(budget)) }
    static var deadline: String { CockpitFormat.deadlineLabel(remaining: 5 * 60, deadline: end) }
    static let longTitle = "とても長い切符タイトルでレイアウトを確認する"
}

private struct CockpitSizePreviewHost<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            content()
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
        }
    }
}

#Preview("LS matrix Pro Max") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach([84.0, 120.0, 160.0], id: \.self) { height in
                CockpitSizePreviewHost(
                    width: CockpitSizeContract.proMaxWidth,
                    height: height,
                    label: "LS \(Int(CockpitSizeContract.proMaxWidth))×\(Int(height))"
                ) {
                    CockpitLockScreenInstrument(
                        title: CockpitPreviewData.longTitle,
                        clock: CockpitPreviewData.countdownClock,
                        phase: CockpitPreviewData.phase,
                        headerState: "終盤",
                        deadlineLabel: CockpitPreviewData.deadline,
                        budgetSeconds: CockpitPreviewData.budget,
                        pausedProgress: nil,
                        accessibilityTimer: "残り5分"
                    )
                }
            }
        }
        .padding()
    }
    .background(Color.black)
}

#Preview("LS matrix Pro") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach([84.0, 120.0, 160.0], id: \.self) { height in
                CockpitSizePreviewHost(
                    width: CockpitSizeContract.proWidth,
                    height: height,
                    label: "LS \(Int(CockpitSizeContract.proWidth))×\(Int(height))"
                ) {
                    CockpitLockScreenInstrument(
                        title: "仕様書を書く",
                        clock: CockpitPreviewData.countdownClock,
                        phase: CockpitPreviewData.phase,
                        headerState: "まもなく",
                        deadlineLabel: CockpitPreviewData.deadline,
                        budgetSeconds: CockpitPreviewData.budget,
                        pausedProgress: nil
                    )
                }
            }
        }
        .padding()
    }
    .background(Color.black)
}

#Preview("StandBy matrix (input = LS size)") {
    ScrollView {
        VStack(spacing: 20) {
            ForEach([84.0, 120.0, 160.0, 240.0, 400.0], id: \.self) { height in
                CockpitSizePreviewHost(
                    width: CockpitSizeContract.proMaxWidth,
                    height: height,
                    label: "StandBy input \(Int(CockpitSizeContract.proMaxWidth))×\(Int(height))"
                ) {
                    CockpitStandByInstrument(
                        title: CockpitPreviewData.longTitle,
                        clock: CockpitPreviewData.countdownClock,
                        phase: CockpitPreviewData.phase,
                        headerState: "終盤",
                        deadlineLabel: CockpitPreviewData.deadline,
                        budgetSeconds: CockpitPreviewData.budget,
                        pausedProgress: nil,
                        accessibilityTimer: "残り5分"
                    ) {
                        VStack(spacing: 10) {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 22, weight: .bold))
                            Text("停車")
                                .font(.system(size: 18, weight: .bold))
                        }
                        .foregroundStyle(CockpitColors.amber)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            CockpitColors.fillRaised,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .environment(
                            \.cockpitStandByMetrics,
                            CockpitStandByMetrics(
                                width: CockpitSizeContract.proMaxWidth,
                                height: height
                            )
                        )
                    }
                }
            }
        }
        .padding()
    }
    .background(Color.black)
}

#Preview("DI compact / minimal sizes") {
    HStack(spacing: 24) {
        HStack(spacing: 8) {
            CockpitIslandMark(phase: CockpitPreviewData.phase)
                .frame(
                    width: CockpitSizeContract.islandCompactSide.width,
                    height: CockpitSizeContract.islandCompactSide.height
                )
            // Live timerInterval + hidden max-digit width (hugs tram).
            CockpitCompactTimer(
                clock: CockpitPreviewData.countdownClock,
                phase: CockpitPreviewData.phase
            )
            .fixedSize(horizontal: true, vertical: false)
            .frame(height: CockpitSizeContract.islandCompactSide.height)
        }
        CockpitMinimalTimer(
            clock: CockpitPreviewData.countdownClock,
            phase: CockpitPreviewData.phase
        )
        .frame(
            width: CockpitSizeContract.islandMinimalMaxWidth,
            height: CockpitSizeContract.islandMinimalMin.height
        )
    }
    .padding()
    .background(Color.black)
}
#endif
