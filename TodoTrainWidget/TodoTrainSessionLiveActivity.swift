//
//  TodoTrainSessionLiveActivity.swift
//  TodoTrainWidget
//
//  Dark cockpit for Lock Screen + StandBy (Session LA, 終了ベル OFF).
//  StandBy = isActivityFullscreen. Background: showsWidgetContainerBackground
//  for Lock Screen container; activityBackgroundTint for StandBy edge fill.
//  ActivityFamily.small is the Watch Smart Stack face. Lock Screen and the
//  Dynamic Island stay on the medium / island presentations.
//

import AppIntents
import SwiftUI
import WidgetKit

#if canImport(ActivityKit)
import ActivityKit

struct TodoTrainSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TodoTrainActivityAttributes.self) { context in
            SessionCockpitRoot(context: context)
        } dynamicIsland: { context in
            let presentation = CockpitDisplayModel.session(
                title: context.state.title,
                deadline: context.state.deadline,
                budgetSeconds: context.state.budgetSeconds,
                isOvertime: context.state.isOvertime,
                isStale: context.isStale,
                isPaused: context.state.isPaused,
                checkInPrompt: context.state.checkInPrompt,
                instrumentPhaseRaw: context.state.instrumentPhaseRaw,
                promptKeepsTimerColor: context.state.promptKeepsTimerColor == true
            )
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    CockpitIslandMark(phase: presentation.phase, size: 14)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CockpitIslandExpandedTrailing(
                        phase: presentation.phase,
                        headerState: presentation.headerState
                    )
                }
                DynamicIslandExpandedRegion(.center) {
                    CockpitIslandExpandedCenter(presentation: presentation)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    SessionRideChip(
                        sessionID: context.attributes.sessionID,
                        isPaused: context.state.isPaused
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                CockpitIslandMark(phase: presentation.phase)
            } compactTrailing: {
                CompactTrailingTimer(presentation: presentation)
            } minimal: {
                CockpitMinimalTimer(clock: presentation.clock, phase: presentation.phase)
                    .accessibilityLabel("残り時間")
            }
            .keylineTint(presentation.phase.accentColor)
            .widgetURL(URL(string: "todotrain://focus"))
        }
        .supplementalActivityFamilies([.medium, .small])
    }
}

private struct SessionRideControl: View {
    let sessionID: UUID
    let isPaused: Bool
    var standBy: Bool = false

    var body: some View {
        if isPaused {
            Button(intent: SessionResumeIntent(sessionID: sessionID)) {
                motionLabel(title: "再乗車", systemImage: "play.fill", tint: CockpitColors.green)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("再乗車")
        } else {
            Button(intent: SessionPauseIntent(sessionID: sessionID)) {
                motionLabel(title: "停車", systemImage: "pause.fill", tint: CockpitColors.amber)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("停車")
        }
    }

    @ViewBuilder
    private func motionLabel(title: String, systemImage: String, tint: Color) -> some View {
        if standBy {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .bold))
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                CockpitColors.fillRaised,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        } else {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CockpitColors.fillRaised, in: Capsule())
        }
    }
}

private struct SessionRideChip: View {
    let sessionID: UUID
    let isPaused: Bool

    var body: some View {
        Group {
            if isPaused {
                Button(intent: SessionResumeIntent(sessionID: sessionID)) {
                    chip(title: "再乗車", systemImage: "play.fill", tint: CockpitColors.green)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("再乗車")
            } else {
                Button(intent: SessionPauseIntent(sessionID: sessionID)) {
                    chip(title: "停車", systemImage: "pause.fill", tint: CockpitColors.amber)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("停車")
            }
        }
        .frame(height: CockpitSizeContract.islandExpandedControlHeight)
    }

    private func chip(title: String, systemImage: String, tint: Color) -> some View {
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
    }
}

private struct CompactTrailingTimer: View {
    let presentation: CockpitDisplayModel
    @Environment(\.isDynamicIslandLimitedInWidth) private var limitedWidth

    var body: some View {
        CockpitCompactTimer(
            clock: presentation.clock,
            phase: presentation.phase,
            limitedWidth: limitedWidth
        )
        .accessibilityLabel("残り時間")
    }
}

private struct SessionCockpitRoot: View {
    let context: ActivityViewContext<TodoTrainActivityAttributes>

    @Environment(\.activityFamily) private var activityFamily
    @Environment(\.isActivityFullscreen) private var isFullscreen
    @Environment(\.showsWidgetContainerBackground) private var showsWidgetContainerBackground
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        if activityFamily == .small {
            SessionSmallActivityView(context: context)
        } else {
            sessionLockScreen
        }
    }

    private var sessionLockScreen: some View {
        let presentation = CockpitDisplayModel.session(
            title: context.state.title,
            deadline: context.state.deadline,
            budgetSeconds: context.state.budgetSeconds,
            isOvertime: context.state.isOvertime,
            isStale: context.isStale,
            isPaused: context.state.isPaused,
            checkInPrompt: context.state.checkInPrompt,
            instrumentPhaseRaw: context.state.instrumentPhaseRaw,
            promptKeepsTimerColor: context.state.promptKeepsTimerColor == true
        )

        return Group {
            if isFullscreen {
                CockpitStandByInstrument(
                    title: presentation.title,
                    clock: presentation.clock,
                    phase: presentation.phase,
                    headerState: presentation.headerState,
                    deadlineLabel: presentation.deadlineLabel,
                    budgetSeconds: presentation.budgetSeconds,
                    pausedProgress: presentation.pausedProgress,
                    accessibilityTimer: presentation.accessibilityTimer
                ) {
                    SessionRideControl(
                        sessionID: context.attributes.sessionID,
                        isPaused: context.state.isPaused,
                        standBy: true
                    )
                }
            } else {
                CockpitLockScreenInstrument(
                    title: presentation.title,
                    clock: presentation.clock,
                    phase: presentation.phase,
                    headerState: presentation.headerState,
                    deadlineLabel: presentation.deadlineLabel,
                    budgetSeconds: presentation.budgetSeconds,
                    pausedProgress: presentation.pausedProgress,
                    accessibilityTimer: presentation.accessibilityTimer
                ) {
                    SessionRideControl(
                        sessionID: context.attributes.sessionID,
                        isPaused: context.state.isPaused
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: isFullscreen ? .infinity : nil)
        .opacity(isLuminanceReduced ? 0.92 : 1)
        // LS: container black. StandBy: tint only — avoid boxed Color.black (WWDC26).
        .background {
            if showsWidgetContainerBackground {
                Color.black
            }
        }
        .activityBackgroundTint(.black)
        .activitySystemActionForegroundColor(.white)
        .widgetURL(URL(string: "todotrain://focus"))
    }
}

/// Smart Stack card. Title, large instrument, one hold-lamp dot. No buttons.
private struct SessionSmallActivityView: View {
    let context: ActivityViewContext<TodoTrainActivityAttributes>

    @Environment(\.showsWidgetContainerBackground) private var showsWidgetContainerBackground

    var body: some View {
        let face = SessionSmallFace.make(
            title: context.state.title,
            deadline: context.state.deadline,
            budgetSeconds: context.state.budgetSeconds,
            isOvertime: context.state.isOvertime,
            isStale: context.isStale,
            isPaused: context.state.isPaused,
            checkInPrompt: context.state.checkInPrompt
        )
        SessionSmallInstrument(face: face)
            .background {
                if showsWidgetContainerBackground {
                    Color.black
                }
            }
            .activityBackgroundTint(.black)
            .widgetURL(URL(string: "todotrain://focus"))
    }
}

struct SessionSmallInstrument: View {
    let face: SessionSmallFace

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let tone = SessionSmallLuminance.resolve(reduced: isLuminanceReduced)
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(face.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CockpitColors.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .privacySensitive()
                    .opacity(tone.title)
                    .frame(maxWidth: .infinity, alignment: .leading)

                readout
                    .opacity(tone.instrument)
            }
            SessionSmallHoldLampMark(lamp: face.holdLamp)
                .opacity(tone.lamp)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var readout: some View {
        switch face.readout {
        case .countdown(let end):
            Text(
                timerInterval: CockpitTimerInterval.countdown(to: end),
                pauseTime: nil,
                countsDown: true,
                showsHours: false
            )
            .font(instrumentFont)
            .monospacedDigit()
            .foregroundStyle(face.phase.accentColor)
            .minimumScaleFactor(0.4)
            .lineLimit(1)
            .accessibilityLabel("残り時間")
        case .paused(let remaining):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(CockpitFormat.timerLabel(remaining: remaining))
                    .font(instrumentFont)
                    .monospacedDigit()
                    .foregroundStyle(CockpitColors.amber)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .accessibilityLabel("停車中")
                    .accessibilityValue(
                        CockpitFormat.accessibilityTimerValue(
                            remaining: remaining,
                            isStale: false,
                            isOvertime: false
                        )
                    )
                if let caption = face.pausedLabel {
                    Text(caption)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CockpitColors.amber)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                }
            }
        case .overtime:
            Text("超過")
                .font(instrumentFont)
                .foregroundStyle(face.phase.accentColor)
                .lineLimit(1)
                .accessibilityLabel("超過")
        case .ended:
            Text("終了")
                .font(instrumentFont)
                .foregroundStyle(CockpitColors.ink)
                .lineLimit(1)
                .accessibilityLabel("終了")
        case .stale:
            Text("—:—")
                .font(instrumentFont)
                .monospacedDigit()
                .foregroundStyle(CockpitColors.muted)
                .lineLimit(1)
                .accessibilityLabel(
                    CockpitFormat.accessibilityTimerValue(
                        remaining: 0,
                        isStale: true,
                        isOvertime: false
                    )
                )
        }
    }

    private var instrumentFont: Font {
        .system(size: 32, weight: .semibold, design: .default)
    }
}

private struct SessionSmallHoldLampMark: View {
    let lamp: SessionSmallHoldLamp

    var body: some View {
        Circle()
            .fill(lamp.isLit ? lamp.phase.accentColor : CockpitColors.hairline)
            .frame(width: 8, height: 8)
            .accessibilityLabel("保留灯が点灯しています")
            .accessibilityHidden(!lamp.isLit)
    }
}

// MARK: - Previews

#if DEBUG
private enum SessionPreviewFixtures {
    static let attributes = TodoTrainActivityAttributes(sessionID: UUID())

    static func running(remaining: TimeInterval, budget: Int = 20 * 60) -> TodoTrainActivityAttributes.ContentState {
        .init(
            title: "仕様書を書く",
            deadline: .now.addingTimeInterval(remaining),
            isOvertime: false,
            budgetSeconds: budget
        )
    }

    static var overtime: TodoTrainActivityAttributes.ContentState {
        .init(
            title: "仕様書を書く",
            deadline: .now.addingTimeInterval(-90),
            isOvertime: true,
            budgetSeconds: 20 * 60
        )
    }

    static var longTitle: TodoTrainActivityAttributes.ContentState {
        .init(
            title: "とても長い切符タイトルでレイアウトを確認する",
            deadline: .now.addingTimeInterval(12 * 60),
            isOvertime: false,
            budgetSeconds: 20 * 60
        )
    }

    static var awayInterrupt: TodoTrainActivityAttributes.ContentState {
        .init(
            title: "仕様書を書く",
            deadline: .now.addingTimeInterval(12 * 60),
            isOvertime: false,
            budgetSeconds: 20 * 60,
            checkInPrompt: "まだ乗ってる？"
        )
    }
}

#Preview("Session Lock Screen", as: .content, using: SessionPreviewFixtures.attributes) {
    TodoTrainSessionLiveActivity()
} contentStates: {
    SessionPreviewFixtures.running(remaining: 19 * 60)
    SessionPreviewFixtures.running(remaining: 5 * 60)
    SessionPreviewFixtures.running(remaining: 90)
    SessionPreviewFixtures.overtime
    SessionPreviewFixtures.longTitle
    SessionPreviewFixtures.awayInterrupt
}

#Preview("Session DI Compact", as: .dynamicIsland(.compact), using: SessionPreviewFixtures.attributes) {
    TodoTrainSessionLiveActivity()
} contentStates: {
    SessionPreviewFixtures.running(remaining: 5 * 60)
    SessionPreviewFixtures.running(remaining: 90)
    SessionPreviewFixtures.overtime
    SessionPreviewFixtures.longTitle
}

#Preview("Session DI Minimal", as: .dynamicIsland(.minimal), using: SessionPreviewFixtures.attributes) {
    TodoTrainSessionLiveActivity()
} contentStates: {
    SessionPreviewFixtures.running(remaining: 5 * 60)
    SessionPreviewFixtures.running(remaining: 90)
    SessionPreviewFixtures.overtime
}

#Preview("Session DI Expanded", as: .dynamicIsland(.expanded), using: SessionPreviewFixtures.attributes) {
    TodoTrainSessionLiveActivity()
} contentStates: {
    SessionPreviewFixtures.running(remaining: 5 * 60)
    SessionPreviewFixtures.running(remaining: 90)
    SessionPreviewFixtures.overtime
    SessionPreviewFixtures.longTitle
    SessionPreviewFixtures.awayInterrupt
}

#Preview("Session Smart Stack") {
    let now = Date.now
    VStack(spacing: 8) {
        smallPreview(SessionSmallFace.make(
            title: "仕様書を書く",
            deadline: now.addingTimeInterval(5 * 60),
            budgetSeconds: 20 * 60,
            isOvertime: false,
            isStale: false,
            now: now
        ))
        smallPreview(SessionSmallFace.make(
            title: "仕様書を書く",
            deadline: now.addingTimeInterval(90),
            budgetSeconds: 20 * 60,
            isOvertime: false,
            isStale: false,
            checkInPrompt: "まだ乗ってる？",
            now: now
        ))
        smallPreview(SessionSmallFace.make(
            title: "とても長い切符タイトルでレイアウトを確認する",
            deadline: now.addingTimeInterval(-90),
            budgetSeconds: 20 * 60,
            isOvertime: true,
            isStale: false,
            now: now
        ))
        smallPreview(SessionSmallFace.make(
            title: "仕様書を書く",
            deadline: now.addingTimeInterval(12 * 60),
            budgetSeconds: 20 * 60,
            isOvertime: false,
            isStale: false,
            isPaused: true,
            now: now
        ))
        smallPreview(
            SessionSmallFace.make(
                title: "仕様書を書く",
                deadline: now.addingTimeInterval(5 * 60),
                budgetSeconds: 20 * 60,
                isOvertime: false,
                isStale: false,
                now: now
            ),
            reduced: true
        )
    }
    .padding()
    .background(Color.black)
}

private func smallPreview(_ face: SessionSmallFace, reduced: Bool = false) -> some View {
    SessionSmallInstrument(face: face)
        .environment(\.isLuminanceReduced, reduced)
        .frame(width: 184, height: 72)
        .background(Color.black)
}
#endif
#endif
