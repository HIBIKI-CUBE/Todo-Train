//
//  TodoTrainSessionLiveActivity.swift
//  TodoTrainWidget
//
//  Dark cockpit instrument for StandBy / Lock Screen (Session LA, 終了ベル OFF).
//

import SwiftUI
import WidgetKit

#if canImport(ActivityKit)
import ActivityKit

struct TodoTrainSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TodoTrainActivityAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    phaseDot(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CockpitColors.muted)
                        .lineLimit(1)
                        .frame(maxWidth: 88, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    islandTimer(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let label = headerState(context) {
                        Text(label)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(snapshot(context).phase.accentColor)
                            .padding(.top, 4)
                    }
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
        context: ActivityViewContext<TodoTrainActivityAttributes>
    ) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let snap = snapshot(context, now: timeline.date)
            CockpitInstrumentPanel(
                title: context.state.title,
                snapshot: snap,
                timerFontSize: 56
            )
            .activityBackgroundTint(.black)
        }
    }

    // MARK: - Dynamic Island

    private func snapshot(
        _ context: ActivityViewContext<TodoTrainActivityAttributes>,
        now: Date = .now
    ) -> CockpitInstrumentSnapshot {
        CockpitInstrumentSnapshot.session(
            deadline: context.state.deadline,
            budgetSeconds: context.state.budgetSeconds,
            isOvertime: context.state.isOvertime,
            now: now
        )
    }

    @ViewBuilder
    private func islandTimer(
        context: ActivityViewContext<TodoTrainActivityAttributes>
    ) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let snap = snapshot(context, now: timeline.date)
            Text(CockpitFormat.timerLabel(remaining: snap.remaining))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(snap.phase.accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    @ViewBuilder
    private func phaseDot(
        context: ActivityViewContext<TodoTrainActivityAttributes>
    ) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            Circle()
                .fill(snapshot(context, now: timeline.date).phase.accentColor)
                .frame(width: 10, height: 10)
        }
    }

    @ViewBuilder
    private func compactTrailing(
        context: ActivityViewContext<TodoTrainActivityAttributes>
    ) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let snap = snapshot(context, now: timeline.date)
            if context.state.isOvertime {
                Text("超過")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(CockpitColors.red)
            } else {
                ZStack {
                    Circle()
                        .stroke(CockpitColors.track, lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: snap.progress)
                        .stroke(snap.phase.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 18, height: 18)
            }
        }
    }

    private func headerState(_ context: ActivityViewContext<TodoTrainActivityAttributes>) -> String? {
        snapshot(context).headerState
    }
}
#endif
