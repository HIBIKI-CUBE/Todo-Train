//
//  TodoTrainAlarmLiveActivity.swift
//  TodoTrainWidget
//
//  End-bell Live Activity. Same cockpit face as the session activity.
//  Countdown: round 停車. Paused: 「停車中」 and 再乗車. Alert: warning mark and 停止.
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
                DynamicIslandExpandedRegion(.bottom) {
                    AlarmExpandedFace(model: presentation)
                }
            } compactLeading: {
                CockpitCompactLeadingGauge(model: presentation.display)
            } compactTrailing: {
                AlarmCompactTrailingTimer(presentation: presentation)
            } minimal: {
                CockpitRingGauge(model: presentation.display)
                    .accessibilityLabel(presentation.display.showsOvertimeMark ? "予定の時刻を過ぎています" : "残り時間")
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
            scheduledAt: presentation.display.scheduledAt,
            limitedWidth: limitedWidth
        )
        .accessibilityLabel(presentation.display.showsOvertimeMark ? "予定の時刻を過ぎています" : "残り時間")
    }
}

// MARK: - Presentation model

private struct AlarmPresentationModel {
    let sessionID: UUID
    let alarmID: UUID
    let clock: CockpitClockStyle
    let phase: FocusTimerPhase
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
        let ticketTitle = context.attributes.metadata?.ticketTitle ?? "乗務中"
        sessionID = context.attributes.metadata?.sessionID ?? context.state.alarmID
        alarmID = context.state.alarmID
        mode = context.state.mode
        phase = snapshot.phase

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
            resolvedHeader = nil
            resolvedPaused = 1
        @unknown default:
            resolvedClock = .paused(remaining: 0)
            resolvedHeader = nil
            resolvedPaused = 0
        }
        clock = resolvedClock
        let caption = context.isStale
            ? "予定の確認中"
            : (CockpitFormat.scheduledLabel(deadline: snapshot.deadline) ?? "予定 —")
        display = CockpitDisplayModel(
            title: ticketTitle,
            clock: resolvedClock,
            phase: phase,
            headerState: resolvedHeader,
            deadlineLabel: caption,
            budgetSeconds: budget,
            pausedProgress: resolvedPaused,
            isStale: context.isStale,
            accessibilityTimer: CockpitFormat.accessibilityTimerValue(
                remaining: snapshot.remaining,
                isStale: context.isStale,
                isOvertime: phase == .overtime
            ),
            scheduledAt: snapshot.deadline,
            checkInPrompt: nil
        )
    }
}

private struct AlarmCockpitFace: View {
    let model: AlarmPresentationModel
    var metrics: CockpitFaceMetrics
    var showsTrainMark: Bool = true
    var limitedWidth: Bool = false

    var body: some View {
        CockpitActivityChrome(
            model: model.display,
            metrics: metrics,
            showsTrainMark: showsTrainMark,
            limitedWidth: limitedWidth,
            rideButton: { rideButton },
            resumeButton: { resumeButton },
            promptButtons: { EmptyView() }
        )
    }

    @ViewBuilder
    private var rideButton: some View {
        if case .alert = model.mode {
            Button(intent: EndBellStopIntent(alarmID: model.alarmID, sessionID: model.sessionID)) {
                CockpitRoundButtonLabel(systemImage: "stop.fill", tint: CockpitColors.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("終了ベルを停止")
        } else {
            Button(intent: EndBellPauseIntent(alarmID: model.alarmID)) {
                CockpitRoundButtonLabel(systemImage: "pause.fill", tint: CockpitColors.amber)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("停車")
        }
    }

    private var resumeButton: some View {
        Button(intent: EndBellResumeIntent(alarmID: model.alarmID)) {
            CockpitReplyLabel(title: "再乗車", systemImage: "play.fill", tint: CockpitColors.green)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("再乗車")
    }
}

private struct AlarmExpandedFace: View {
    let model: AlarmPresentationModel
    @Environment(\.isDynamicIslandLimitedInWidth) private var limitedWidth

    var body: some View {
        AlarmCockpitFace(
            model: model,
            metrics: limitedWidth ? .expandedTight : .expanded,
            showsTrainMark: true,
            limitedWidth: limitedWidth
        )
    }
}

private struct AlarmCockpitRoot: View {
    let context: ActivityViewContext<AlarmAttributes<TodoTrainAlarmMetadata>>

    @Environment(\.activityFamily) private var activityFamily
    @Environment(\.isActivityFullscreen) private var isFullscreen
    @Environment(\.showsWidgetContainerBackground) private var showsWidgetContainerBackground
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let presentation = AlarmPresentationModel(context: context)
        Group {
            if activityFamily == .small {
                AlarmCockpitFace(model: presentation, metrics: .stackSmall)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .opacity(SessionSmallLuminance.resolve(reduced: isLuminanceReduced).instrument)
            } else {
                AlarmFittedFace(model: presentation, fullscreen: isFullscreen)
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

private struct AlarmFittedFace: View {
    let model: AlarmPresentationModel
    var fullscreen: Bool

    var body: some View {
        CockpitFittedChrome(
            model: model.display,
            fullscreen: fullscreen,
            showsTrainMark: true,
            rideButton: { AlarmRideButton(model: model) },
            resumeButton: { AlarmResumeButton(alarmID: model.alarmID) },
            promptButtons: { EmptyView() }
        )
    }
}

private struct AlarmRideButton: View {
    let model: AlarmPresentationModel

    var body: some View {
        if case .alert = model.mode {
            Button(intent: EndBellStopIntent(alarmID: model.alarmID, sessionID: model.sessionID)) {
                CockpitRoundButtonLabel(systemImage: "stop.fill", tint: CockpitColors.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("終了ベルを停止")
        } else {
            Button(intent: EndBellPauseIntent(alarmID: model.alarmID)) {
                CockpitRoundButtonLabel(systemImage: "pause.fill", tint: CockpitColors.amber)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("停車")
        }
    }
}

private struct AlarmResumeButton: View {
    let alarmID: UUID

    var body: some View {
        Button(intent: EndBellResumeIntent(alarmID: alarmID)) {
            CockpitReplyLabel(title: "再乗車", systemImage: "play.fill", tint: CockpitColors.green)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("再乗車")
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

    static var pausedState: AlarmPresentationState {
        AlarmPresentationState(
            alarmID: alarmID,
            mode: .paused(
                .init(
                    totalCountdownDuration: budget,
                    previouslyElapsedDuration: budget - 12 * 60
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
    AlarmPreviewFixtures.countdownState(remaining: 12 * 60)
    AlarmPreviewFixtures.countdownState(remaining: 90)
    AlarmPreviewFixtures.pausedState
    AlarmPreviewFixtures.alertState
}

#Preview("Alarm DI Compact", as: .dynamicIsland(.compact), using: AlarmPreviewFixtures.attributes) {
    TodoTrainAlarmLiveActivity()
} contentStates: {
    AlarmPreviewFixtures.countdownState(remaining: 12 * 60)
    AlarmPreviewFixtures.countdownState(remaining: 90)
    AlarmPreviewFixtures.alertState
}

#Preview("Alarm DI Minimal", as: .dynamicIsland(.minimal), using: AlarmPreviewFixtures.attributes) {
    TodoTrainAlarmLiveActivity()
} contentStates: {
    AlarmPreviewFixtures.countdownState(remaining: 12 * 60)
    AlarmPreviewFixtures.alertState
}

#Preview("Alarm DI Expanded", as: .dynamicIsland(.expanded), using: AlarmPreviewFixtures.attributes) {
    TodoTrainAlarmLiveActivity()
} contentStates: {
    AlarmPreviewFixtures.countdownState(remaining: 12 * 60)
    AlarmPreviewFixtures.countdownState(remaining: 90)
    AlarmPreviewFixtures.pausedState
    AlarmPreviewFixtures.alertState
}

#Preview("Alarm Smart Stack Small") {
    alarmStack(metrics: .stackSmall, width: 184, height: 72)
}

#Preview("Alarm Smart Stack Medium") {
    alarmStack(metrics: .stackMedium, width: 198, height: 140)
}

private func alarmStack(metrics: CockpitFaceMetrics, width: CGFloat, height: CGFloat) -> some View {
    let now = Date.now
    let running = CockpitDisplayModel(
        title: "仕様書を書く",
        clock: .countdown(end: now.addingTimeInterval(12 * 60)),
        phase: .cruise,
        headerState: nil,
        deadlineLabel: CockpitFormat.scheduledLabel(deadline: now.addingTimeInterval(12 * 60)) ?? "予定 —",
        budgetSeconds: Int(AlarmPreviewFixtures.budget),
        pausedProgress: nil,
        isStale: false,
        accessibilityTimer: "残り12分",
        scheduledAt: now.addingTimeInterval(12 * 60)
    )
    let paused = CockpitDisplayModel(
        title: "仕様書を書く",
        clock: .paused(remaining: 12 * 60),
        phase: .cruise,
        headerState: "停車中",
        deadlineLabel: "予定 —",
        budgetSeconds: Int(AlarmPreviewFixtures.budget),
        pausedProgress: 0.4,
        isStale: false,
        accessibilityTimer: "停車中",
        scheduledAt: now.addingTimeInterval(12 * 60)
    )
    let alert = CockpitDisplayModel(
        title: "仕様書を書く",
        clock: .alert,
        phase: .overtime,
        headerState: nil,
        deadlineLabel: "予定 —",
        budgetSeconds: Int(AlarmPreviewFixtures.budget),
        pausedProgress: 1,
        isStale: false,
        accessibilityTimer: "予定の時刻を過ぎています"
    )
    return VStack(spacing: 8) {
        alarmCard(running, metrics: metrics, width: width, height: height, alert: false)
        alarmCard(paused, metrics: metrics, width: width, height: height, alert: false)
        alarmCard(alert, metrics: metrics, width: width, height: height, alert: true)
    }
    .padding()
    .background(Color.black)
}

private func alarmCard(
    _ model: CockpitDisplayModel,
    metrics: CockpitFaceMetrics,
    width: CGFloat,
    height: CGFloat,
    alert: Bool
) -> some View {
    CockpitActivityChrome(
        model: model,
        metrics: metrics,
        rideButton: {
            CockpitRoundButtonLabel(
                systemImage: alert ? "stop.fill" : "pause.fill",
                tint: alert ? CockpitColors.ink : CockpitColors.amber
            )
        },
        resumeButton: {
            CockpitReplyLabel(title: "再乗車", systemImage: "play.fill", tint: CockpitColors.green)
        },
        promptButtons: { EmptyView() }
    )
    .frame(width: width, height: height)
    .background(Color.black)
}
#endif
#endif
