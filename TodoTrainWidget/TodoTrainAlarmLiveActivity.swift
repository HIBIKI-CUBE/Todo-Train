//
//  TodoTrainAlarmLiveActivity.swift
//  TodoTrainWidget
//
//  Dark cockpit for Lock Screen + StandBy (AlarmKit).
//  StandBy = isActivityFullscreen. Background: showsWidgetContainerBackground
//  for Lock Screen container; activityBackgroundTint for StandBy edge fill.
//  ActivityFamily.small is the Watch Smart Stack face, same shape as the session card.
//  Single essential control (停車 / 再乗車 / 停止). Arrive / extend via app deep link.
//

import AppIntents
import SwiftUI
import WidgetKit

#if canImport(AlarmKit) && canImport(ActivityKit)
import ActivityKit
import AlarmKit

struct TodoTrainAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<TodoTrainAlarmMetadata>.self) { context in
            AlarmCockpitRoot(context: context)
        } dynamicIsland: { context in
            let presentation = AlarmPresentationModel(context: context)
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
                    CockpitIslandExpandedCenter(presentation: presentation.display)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    CockpitAlarmControlRow(
                        alarmID: context.state.alarmID,
                        sessionID: presentation.sessionID,
                        mode: context.state.mode,
                        layout: .islandCompact
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                CockpitIslandMark(phase: presentation.phase)
            } compactTrailing: {
                AlarmCompactTrailingTimer(presentation: presentation)
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

private struct AlarmCompactTrailingTimer: View {
    let presentation: AlarmPresentationModel
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

// MARK: - Presentation model

private struct AlarmPresentationModel {
    let title: String
    let sessionID: UUID
    let clock: CockpitClockStyle
    let phase: FocusTimerPhase
    let headerState: String?
    let deadlineLabel: String
    let budgetSeconds: Int
    let pausedProgress: Double?
    let mode: AlarmPresentationState.Mode
    let display: CockpitDisplayModel

    init(context: ActivityViewContext<AlarmAttributes<TodoTrainAlarmMetadata>>) {
        let now = Date.now
        let budget = context.attributes.metadata?.budgetSeconds ?? 1
        let snapshot = CockpitInstrumentSnapshot.alarm(
            mode: context.state.mode,
            budgetSeconds: budget,
            now: now
        )
        title = context.attributes.metadata?.ticketTitle ?? "乗務中"
        sessionID = context.attributes.metadata?.sessionID ?? context.state.alarmID
        budgetSeconds = budget
        mode = context.state.mode
        phase = snapshot.phase
        deadlineLabel = CockpitPresentation.deadlineLabel(from: snapshot)

        let resolvedClock: CockpitClockStyle
        let resolvedHeader: String?
        let resolvedPaused: Double?
        switch context.state.mode {
        case .countdown(let countdown):
            resolvedClock = .countdown(end: countdown.fireDate)
            resolvedHeader = snapshot.phase.stateLabel
            resolvedPaused = nil
        case .paused(let paused):
            let remaining = max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration)
            resolvedClock = .paused(remaining: remaining)
            resolvedHeader = "停車中"
            resolvedPaused = CockpitFormat.progress(
                elapsed: paused.previouslyElapsedDuration,
                budget: TimeInterval(budget)
            )
        case .alert:
            resolvedClock = .alert
            resolvedHeader = "超過"
            resolvedPaused = 1
        @unknown default:
            resolvedClock = .paused(remaining: 0)
            resolvedHeader = nil
            resolvedPaused = 0
        }
        clock = resolvedClock
        headerState = resolvedHeader
        pausedProgress = resolvedPaused
        display = CockpitDisplayModel(
            title: title,
            clock: resolvedClock,
            phase: phase,
            headerState: resolvedHeader,
            deadlineLabel: deadlineLabel,
            budgetSeconds: budget,
            pausedProgress: resolvedPaused,
            isStale: context.isStale,
            accessibilityTimer: CockpitFormat.accessibilityTimerValue(
                remaining: snapshot.remaining,
                isStale: context.isStale,
                isOvertime: phase == .overtime
            )
        )
    }
}

private struct AlarmCockpitRoot: View {
    let context: ActivityViewContext<AlarmAttributes<TodoTrainAlarmMetadata>>

    @Environment(\.activityFamily) private var activityFamily

    var body: some View {
        if activityFamily == .small {
            AlarmSmallActivityView(context: context)
        } else {
            alarmLockScreen
        }
    }

    /// StandBy / fullscreen — Apple's documented signal only.
    @Environment(\.isActivityFullscreen) private var isFullscreen
    @Environment(\.showsWidgetContainerBackground) private var showsWidgetContainerBackground
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var alarmLockScreen: some View {
        let presentation = AlarmPresentationModel(context: context)

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
                    accessibilityTimer: presentation.display.accessibilityTimer
                ) {
                    CockpitAlarmControlRow(
                        alarmID: context.state.alarmID,
                        sessionID: presentation.sessionID,
                        mode: context.state.mode,
                        layout: .standByStack
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
                    accessibilityTimer: presentation.display.accessibilityTimer
                ) {
                    CockpitAlarmControlRow(
                        alarmID: context.state.alarmID,
                        sessionID: presentation.sessionID,
                        mode: context.state.mode,
                        layout: .horizontalRow
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

/// Smart Stack card for the end bell. Title and the same instrument as the session card. No buttons.
private struct AlarmSmallActivityView: View {
    let context: ActivityViewContext<AlarmAttributes<TodoTrainAlarmMetadata>>

    @Environment(\.showsWidgetContainerBackground) private var showsWidgetContainerBackground

    var body: some View {
        let presentation = AlarmPresentationModel(context: context)
        let face = SessionSmallFace(
            title: presentation.title,
            clock: smallClock(presentation.clock, isStale: context.isStale),
            phase: presentation.phase,
            holdLamp: SessionSmallHoldLamp(isLit: false, phase: presentation.phase),
            pausedLabel: pausedLabel(for: presentation.mode)
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

    private func smallClock(_ clock: CockpitClockStyle, isStale: Bool) -> CockpitClockStyle {
        if case .countdown = clock, isStale {
            return .stale
        }
        return clock
    }

    private func pausedLabel(for mode: AlarmPresentationState.Mode) -> String? {
        if case .paused = mode {
            return "停車中"
        }
        return nil
    }
}

// MARK: - Previews

#if DEBUG
private enum AlarmPreviewFixtures {
    static let sessionID = UUID()
    static let alarmID = sessionID
    static let budget: TimeInterval = 20 * 60

    static var attributes: AlarmAttributes<TodoTrainAlarmMetadata> {
        let pause = AlarmButton(text: "停車", textColor: .white, systemImageName: "pause.fill")
        let resume = AlarmButton(text: "再乗車", textColor: .white, systemImageName: "play.fill")
        return AlarmAttributes(
            presentation: AlarmPresentation(
                alert: AlarmPresentation.Alert(title: "見積もり終了"),
                countdown: AlarmPresentation.Countdown(
                    title: "仕様書を書く",
                    pauseButton: pause
                ),
                paused: AlarmPresentation.Paused(
                    title: "停車中",
                    resumeButton: resume
                )
            ),
            metadata: TodoTrainAlarmMetadata(
                sessionID: sessionID,
                ticketTitle: "仕様書を書く",
                budgetSeconds: Int(budget)
            ),
            tintColor: CockpitColors.amber
        )
    }

    static func countdownState(remaining: TimeInterval) -> AlarmPresentationState {
        let now = Date.now
        let fire = now.addingTimeInterval(remaining)
        let elapsed = budget - remaining
        return AlarmPresentationState(
            alarmID: alarmID,
            mode: .countdown(
                .init(
                    totalCountdownDuration: budget,
                    previouslyElapsedDuration: elapsed,
                    startDate: now.addingTimeInterval(-elapsed),
                    fireDate: fire
                )
            )
        )
    }

    static var alertState: AlarmPresentationState {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: .now)
        return AlarmPresentationState(
            alarmID: alarmID,
            mode: .alert(
                .init(time: Alarm.Schedule.Relative.Time(
                    hour: comps.hour ?? 0,
                    minute: comps.minute ?? 0
                ))
            )
        )
    }
}

#Preview("Alarm Lock Screen", as: .content, using: AlarmPreviewFixtures.attributes) {
    TodoTrainAlarmLiveActivity()
} contentStates: {
    AlarmPreviewFixtures.countdownState(remaining: 19 * 60)
    AlarmPreviewFixtures.countdownState(remaining: 5 * 60)
    AlarmPreviewFixtures.countdownState(remaining: 90)
    AlarmPreviewFixtures.alertState
}

#Preview("Alarm DI Compact", as: .dynamicIsland(.compact), using: AlarmPreviewFixtures.attributes) {
    TodoTrainAlarmLiveActivity()
} contentStates: {
    AlarmPreviewFixtures.countdownState(remaining: 5 * 60)
    AlarmPreviewFixtures.countdownState(remaining: 90)
    AlarmPreviewFixtures.alertState
}

#Preview("Alarm DI Minimal", as: .dynamicIsland(.minimal), using: AlarmPreviewFixtures.attributes) {
    TodoTrainAlarmLiveActivity()
} contentStates: {
    AlarmPreviewFixtures.countdownState(remaining: 5 * 60)
    AlarmPreviewFixtures.alertState
}

#Preview("Alarm DI Expanded", as: .dynamicIsland(.expanded), using: AlarmPreviewFixtures.attributes) {
    TodoTrainAlarmLiveActivity()
} contentStates: {
    AlarmPreviewFixtures.countdownState(remaining: 5 * 60)
    AlarmPreviewFixtures.countdownState(remaining: 90)
    AlarmPreviewFixtures.alertState
}

#Preview("Alarm Smart Stack") {
    let now = Date.now
    VStack(spacing: 8) {
        alarmSmallPreview(
            title: "仕様書を書く",
            clock: .countdown(end: now.addingTimeInterval(5 * 60)),
            phase: .cruise,
            pausedLabel: nil
        )
        alarmSmallPreview(
            title: "仕様書を書く",
            clock: .paused(remaining: 12 * 60),
            phase: .cruise,
            pausedLabel: "停車中"
        )
        alarmSmallPreview(
            title: "仕様書を書く",
            clock: .alert,
            phase: .overtime,
            pausedLabel: nil
        )
    }
    .padding()
    .background(Color.black)
}

private func alarmSmallPreview(
    title: String,
    clock: CockpitClockStyle,
    phase: FocusTimerPhase,
    pausedLabel: String?
) -> some View {
    SessionSmallInstrument(
        face: SessionSmallFace(
            title: title,
            clock: clock,
            phase: phase,
            holdLamp: SessionSmallHoldLamp(isLit: false, phase: phase),
            pausedLabel: pausedLabel
        )
    )
    .frame(width: 184, height: 72)
    .background(Color.black)
}
#endif
#endif
