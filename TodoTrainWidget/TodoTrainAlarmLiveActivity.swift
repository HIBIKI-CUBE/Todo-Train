//
//  TodoTrainAlarmLiveActivity.swift
//  TodoTrainWidget
//
//  Dark cockpit instrument for StandBy / Lock Screen (AlarmKit).
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
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    phaseDot(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(ticketTitle(context))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CockpitColors.muted)
                        .lineLimit(1)
                        .frame(maxWidth: 88, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    islandTimer(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    CockpitAlarmControlRow(
                        alarmID: context.state.alarmID,
                        sessionID: context.attributes.metadata?.sessionID ?? context.state.alarmID,
                        mode: context.state.mode,
                        compact: true
                    )
                    .padding(.top, 4)
                }
            } compactLeading: {
                phaseDot(context: context)
            } compactTrailing: {
                compactTrailing(context: context)
            } minimal: {
                phaseDot(context: context)
            }
        }
    }

    // MARK: - Lock Screen / StandBy

    @ViewBuilder
    private func lockScreenView(
        context: ActivityViewContext<AlarmAttributes<TodoTrainAlarmMetadata>>
    ) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let budget = context.attributes.metadata?.budgetSeconds ?? 1
            let snapshot = CockpitInstrumentSnapshot.alarm(
                mode: context.state.mode,
                budgetSeconds: budget,
                now: timeline.date
            )
            VStack(spacing: 0) {
                CockpitInstrumentPanel(
                    title: ticketTitle(context),
                    snapshot: snapshot,
                    timerFontSize: 58
                )
                CockpitAlarmControlRow(
                    alarmID: context.state.alarmID,
                    sessionID: context.attributes.metadata?.sessionID ?? context.state.alarmID,
                    mode: context.state.mode
                )
            }
            .activityBackgroundTint(.black)
        }
    }

    // MARK: - Dynamic Island

    @ViewBuilder
    private func islandTimer(
        context: ActivityViewContext<AlarmAttributes<TodoTrainAlarmMetadata>>
    ) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let budget = context.attributes.metadata?.budgetSeconds ?? 1
            let snapshot = CockpitInstrumentSnapshot.alarm(
                mode: context.state.mode,
                budgetSeconds: budget,
                now: timeline.date
            )
            Text(CockpitFormat.timerLabel(remaining: snapshot.remaining))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(snapshot.phase.accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    @ViewBuilder
    private func phaseDot(
        context: ActivityViewContext<AlarmAttributes<TodoTrainAlarmMetadata>>
    ) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let budget = context.attributes.metadata?.budgetSeconds ?? 1
            let snapshot = CockpitInstrumentSnapshot.alarm(
                mode: context.state.mode,
                budgetSeconds: budget,
                now: timeline.date
            )
            Circle()
                .fill(snapshot.phase.accentColor)
                .frame(width: 10, height: 10)
        }
    }

    @ViewBuilder
    private func compactTrailing(
        context: ActivityViewContext<AlarmAttributes<TodoTrainAlarmMetadata>>
    ) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let budget = context.attributes.metadata?.budgetSeconds ?? 1
            let snapshot = CockpitInstrumentSnapshot.alarm(
                mode: context.state.mode,
                budgetSeconds: budget,
                now: timeline.date
            )
            switch context.state.mode {
            case .countdown:
                ZStack {
                    Circle()
                        .stroke(CockpitColors.track, lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: snapshot.progress)
                        .stroke(snapshot.phase.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 18, height: 18)
            case .paused:
                Text(CockpitFormat.timerLabel(remaining: snapshot.remaining))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(snapshot.phase.accentColor)
                    .frame(width: 36, alignment: .trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            case .alert:
                Image(systemName: "bell.fill")
                    .font(.caption2)
                    .foregroundStyle(CockpitColors.red)
            @unknown default:
                EmptyView()
            }
        }
    }

    private func ticketTitle(
        _ context: ActivityViewContext<AlarmAttributes<TodoTrainAlarmMetadata>>
    ) -> String {
        context.attributes.metadata?.ticketTitle ?? "乗務中"
    }
}
#endif
