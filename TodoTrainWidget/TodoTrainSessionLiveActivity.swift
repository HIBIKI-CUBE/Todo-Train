//
//  TodoTrainSessionLiveActivity.swift
//  TodoTrainWidget
//
//  Dark cockpit for Lock Screen + StandBy (Session LA, 終了ベル OFF).
//  StandBy = isActivityFullscreen. Background: showsWidgetContainerBackground
//  for Lock Screen container; activityBackgroundTint for StandBy edge fill.
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
                checkInPrompt: context.state.checkInPrompt
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
        .supplementalActivityFamilies([.medium])
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

    @Environment(\.isActivityFullscreen) private var isFullscreen
    @Environment(\.showsWidgetContainerBackground) private var showsWidgetContainerBackground
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let presentation = CockpitDisplayModel.session(
            title: context.state.title,
            deadline: context.state.deadline,
            budgetSeconds: context.state.budgetSeconds,
            isOvertime: context.state.isOvertime,
            isStale: context.isStale,
            isPaused: context.state.isPaused,
            checkInPrompt: context.state.checkInPrompt
        )

        Group {
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
#endif
#endif
