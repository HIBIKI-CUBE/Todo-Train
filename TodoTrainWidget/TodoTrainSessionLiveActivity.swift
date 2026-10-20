//
//  TodoTrainSessionLiveActivity.swift
//  TodoTrainWidget
//
//  One cockpit face for Lock Screen, StandBy, expanded Dynamic Island,
//  and the Watch Smart Stack (.small and narrow .medium).
//  Compact leading is the mini gauge. Minimal is a ring.
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
            let presentation = sessionPresentation(context)
            let sessionID = context.attributes.sessionID
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SessionExpandedFace(model: presentation, sessionID: sessionID, slot: .leading)
                }
                .safeLeadingChrome()
                DynamicIslandExpandedRegion(.trailing) {
                    SessionExpandedFace(model: presentation, sessionID: sessionID, slot: .trailing)
                }
                .safeTrailingChrome()
                DynamicIslandExpandedRegion(.bottom) {
                    SessionExpandedFace(model: presentation, sessionID: sessionID, slot: .bottom)
                }
                .safeBottomChrome()
            } compactLeading: {
                CockpitCompactLeadingGauge(model: presentation)
            } compactTrailing: {
                CompactTrailingTimer(presentation: presentation)
            } minimal: {
                CockpitRingGauge(model: presentation)
                    .accessibilityLabel(presentation.showsOvertimeMark ? "予定の時刻を過ぎています" : "残り時間")
            }
            .safeCompactChrome()
            .keylineTint(presentation.phase.accentColor)
            .widgetURL(URL(string: "todotrain://focus"))
        }
        .supplementalActivityFamilies([.medium, .small])
    }
}

private func sessionPresentation(
    _ context: ActivityViewContext<TodoTrainActivityAttributes>
) -> CockpitDisplayModel {
    CockpitDisplayModel.session(
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
}

struct SessionCockpitFace: View {
    let model: CockpitDisplayModel
    let sessionID: UUID
    var metrics: CockpitFaceMetrics
    var surface: CockpitSafeSurface
    var slot: CockpitSafeSlot = .all
    var showsTrainMark: Bool = true
    var limitedWidth: Bool = false

    var body: some View {
        CockpitActivityChrome(
            model: model,
            metrics: metrics,
            surface: surface,
            slot: slot,
            showsTrainMark: showsTrainMark,
            limitedWidth: limitedWidth,
            rideButton: { pauseButton },
            resumeButton: { resumeButton },
            promptButtons: { promptButtons }
        )
    }

    private var pauseButton: some View {
        Button(intent: SessionPauseIntent(sessionID: sessionID)) {
            CockpitRoundButtonLabel(systemImage: "pause.fill", tint: CockpitColors.amber)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("停車")
    }

    private var resumeButton: some View {
        Button(intent: SessionResumeIntent(sessionID: sessionID)) {
            CockpitReplyLabel(title: "再乗車", systemImage: "play.fill", tint: CockpitColors.green)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("再乗車")
    }

    private var promptButtons: some View {
        HStack(spacing: 4) {
            Button(intent: SessionStillIntent(sessionID: sessionID)) {
                CockpitReplyLabel(title: "続行", systemImage: "arrow.forward", tint: CockpitColors.green)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("続行")
            Button(intent: SessionPauseIntent(sessionID: sessionID)) {
                CockpitReplyLabel(title: "停車", systemImage: "pause.fill", tint: CockpitColors.amber)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("停車")
        }
    }
}

private struct SessionExpandedFace: View {
    let model: CockpitDisplayModel
    let sessionID: UUID
    var slot: CockpitSafeSlot = .all
    @Environment(\.isDynamicIslandLimitedInWidth) private var limitedWidth

    var body: some View {
        SessionCockpitFace(
            model: model,
            sessionID: sessionID,
            metrics: limitedWidth ? .expandedTight : .expanded,
            surface: .islandExpanded,
            slot: slot,
            showsTrainMark: true,
            limitedWidth: limitedWidth
        )
    }
}

private struct CompactTrailingTimer: View {
    let presentation: CockpitDisplayModel
    @Environment(\.isDynamicIslandLimitedInWidth) private var limitedWidth

    var body: some View {
        CockpitCompactTimer(
            clock: presentation.clock,
            phase: presentation.phase,
            scheduledAt: presentation.scheduledAt,
            limitedWidth: limitedWidth
        )
        .accessibilityLabel(presentation.showsOvertimeMark ? "予定の時刻を過ぎています" : "残り時間")
    }
}

private struct SessionCockpitRoot: View {
    let context: ActivityViewContext<TodoTrainActivityAttributes>

    @Environment(\.activityFamily) private var activityFamily
    @Environment(\.isActivityFullscreen) private var isFullscreen
    @Environment(\.showsWidgetContainerBackground) private var showsWidgetContainerBackground
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let presentation = sessionPresentation(context)
        Group {
            if activityFamily == .small {
                SessionCockpitFace(
                    model: presentation,
                    sessionID: context.attributes.sessionID,
                    metrics: .stackSmall,
                    surface: .stack
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .opacity(SessionSmallLuminance.resolve(reduced: isLuminanceReduced).instrument)
            } else {
                CockpitFittedChrome(
                    model: presentation,
                    fullscreen: isFullscreen,
                    showsTrainMark: true,
                    rideButton: {
                        SessionPauseButton(sessionID: context.attributes.sessionID)
                    },
                    resumeButton: {
                        SessionResumeButton(sessionID: context.attributes.sessionID)
                    },
                    promptButtons: {
                        SessionPromptButtons(sessionID: context.attributes.sessionID)
                    }
                )
                .opacity(isLuminanceReduced ? 0.92 : 1)
            }
        }
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

private struct SessionPauseButton: View {
    let sessionID: UUID

    var body: some View {
        Button(intent: SessionPauseIntent(sessionID: sessionID)) {
            CockpitRoundButtonLabel(systemImage: "pause.fill", tint: CockpitColors.amber)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("停車")
    }
}

private struct SessionResumeButton: View {
    let sessionID: UUID

    var body: some View {
        Button(intent: SessionResumeIntent(sessionID: sessionID)) {
            CockpitReplyLabel(title: "再乗車", systemImage: "play.fill", tint: CockpitColors.green)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("再乗車")
    }
}

private struct SessionPromptButtons: View {
    let sessionID: UUID

    var body: some View {
        HStack(spacing: 4) {
            Button(intent: SessionStillIntent(sessionID: sessionID)) {
                CockpitReplyLabel(title: "続行", systemImage: "arrow.forward", tint: CockpitColors.green)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("続行")
            Button(intent: SessionPauseIntent(sessionID: sessionID)) {
                CockpitReplyLabel(title: "停車", systemImage: "pause.fill", tint: CockpitColors.amber)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("停車")
        }
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

    static var paused: TodoTrainActivityAttributes.ContentState {
        .init(
            title: "仕様書を書く",
            deadline: .now.addingTimeInterval(12 * 60),
            isOvertime: false,
            budgetSeconds: 20 * 60,
            isPaused: true
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
            title: "とても長い切符の題名でレイアウトを確認する",
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

    static func model(
        _ state: TodoTrainActivityAttributes.ContentState,
        now: Date = .now
    ) -> CockpitDisplayModel {
        CockpitDisplayModel.session(
            title: state.title,
            deadline: state.deadline,
            budgetSeconds: state.budgetSeconds,
            isOvertime: state.isOvertime,
            isStale: false,
            isPaused: state.isPaused,
            checkInPrompt: state.checkInPrompt,
            now: now
        )
    }
}

#Preview("Session Lock Screen", as: .content, using: SessionPreviewFixtures.attributes) {
    TodoTrainSessionLiveActivity()
} contentStates: {
    SessionPreviewFixtures.running(remaining: 12 * 60)
    SessionPreviewFixtures.running(remaining: 90)
    SessionPreviewFixtures.overtime
    SessionPreviewFixtures.paused
    SessionPreviewFixtures.longTitle
    SessionPreviewFixtures.awayInterrupt
}

#Preview("Session DI Compact", as: .dynamicIsland(.compact), using: SessionPreviewFixtures.attributes) {
    TodoTrainSessionLiveActivity()
} contentStates: {
    SessionPreviewFixtures.running(remaining: 12 * 60)
    SessionPreviewFixtures.running(remaining: 90)
    SessionPreviewFixtures.overtime
    SessionPreviewFixtures.paused
}

#Preview("Session DI Minimal", as: .dynamicIsland(.minimal), using: SessionPreviewFixtures.attributes) {
    TodoTrainSessionLiveActivity()
} contentStates: {
    SessionPreviewFixtures.running(remaining: 12 * 60)
    SessionPreviewFixtures.running(remaining: 90)
    SessionPreviewFixtures.overtime
}

#Preview("Session DI Expanded", as: .dynamicIsland(.expanded), using: SessionPreviewFixtures.attributes) {
    TodoTrainSessionLiveActivity()
} contentStates: {
    SessionPreviewFixtures.running(remaining: 12 * 60)
    SessionPreviewFixtures.running(remaining: 90)
    SessionPreviewFixtures.overtime
    SessionPreviewFixtures.paused
    SessionPreviewFixtures.longTitle
    SessionPreviewFixtures.awayInterrupt
}

#Preview("Session Smart Stack Small") {
    stackGallery(metrics: .stackSmall, width: 184, height: 72)
}

#Preview("Session Smart Stack Medium") {
    stackGallery(metrics: .stackMedium, width: 198, height: 140)
}

#Preview("Session StandBy") {
    let now = Date.now
        SessionCockpitFace(
            model: SessionPreviewFixtures.model(SessionPreviewFixtures.running(remaining: 12 * 60), now: now),
            sessionID: UUID(),
            metrics: .standBy,
            surface: .standBy
        )
    .frame(width: 408, height: 160)
    .background(Color.black)
}

private func stackGallery(metrics: CockpitFaceMetrics, width: CGFloat, height: CGFloat) -> some View {
    let now = Date.now
    let states = [
        SessionPreviewFixtures.running(remaining: 12 * 60),
        SessionPreviewFixtures.paused,
        SessionPreviewFixtures.overtime,
        SessionPreviewFixtures.awayInterrupt
    ]
    return VStack(spacing: 8) {
        ForEach(Array(states.enumerated()), id: \.offset) { _, state in
            SessionCockpitFace(
                model: SessionPreviewFixtures.model(state, now: now),
                sessionID: UUID(),
                metrics: metrics,
                surface: .stack
            )
            .frame(width: width, height: height)
            .background(Color.black)
        }
    }
    .padding()
    .background(Color.black)
}
#endif
#endif
