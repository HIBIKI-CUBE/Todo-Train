//
//  TodoTrainAlarmLiveActivity.swift
//  TodoTrainWidget
//
//  AlarmKit countdown / paused / alert Live Activity (Lock Screen, Dynamic Island, StandBy).
//

import SwiftUI
import WidgetKit

#if canImport(AlarmKit) && canImport(ActivityKit)
import ActivityKit
import AlarmKit

struct TodoTrainAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<TodoTrainAlarmMetadata>.self) { context in
            lockScreenView(context: context)
                .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(ticketTitle(context))
                            .font(.caption)
                            .lineLimit(2)
                    } icon: {
                        Image(systemName: "tram.fill")
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    modeTrailing(context: context)
                        .font(.title3.monospacedDigit())
                }
            } compactLeading: {
                Image(systemName: "tram.fill")
            } compactTrailing: {
                modeTrailing(context: context)
                    .font(.caption.monospacedDigit())
            } minimal: {
                Image(systemName: "tram.fill")
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(
        context: ActivityViewContext<AlarmAttributes<TodoTrainAlarmMetadata>>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(ticketTitle(context), systemImage: "tram.fill")
                .font(.headline)
                .lineLimit(2)

            switch context.state.mode {
            case .countdown(let countdown):
                Text(timerInterval: Date.now...countdown.fireDate, countsDown: true)
                    .font(.title2.monospacedDigit())
                    .multilineTextAlignment(.leading)
            case .paused(let paused):
                Text(pausedRemainingLabel(paused))
                    .font(.title2.monospacedDigit())
                Text("一時停止")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .alert:
                Text("見積もり終了")
                    .font(.title2)
            @unknown default:
                Text("—")
                    .font(.title2.monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .activityBackgroundTint(Color.orange.opacity(0.2))
    }

    @ViewBuilder
    private func modeTrailing(
        context: ActivityViewContext<AlarmAttributes<TodoTrainAlarmMetadata>>
    ) -> some View {
        switch context.state.mode {
        case .countdown(let countdown):
            Text(timerInterval: Date.now...countdown.fireDate, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        case .paused(let paused):
            Text(pausedRemainingLabel(paused))
                .monospacedDigit()
        case .alert:
            Image(systemName: "bell.fill")
        @unknown default:
            Text("—")
                .monospacedDigit()
        }
    }

    private func ticketTitle(
        _ context: ActivityViewContext<AlarmAttributes<TodoTrainAlarmMetadata>>
    ) -> String {
        context.attributes.metadata?.ticketTitle ?? "乗務中"
    }

    private func pausedRemainingLabel(_ paused: AlarmPresentationState.Mode.Paused) -> String {
        let remaining = max(0, Int(paused.totalCountdownDuration - paused.previouslyElapsedDuration))
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
#endif
