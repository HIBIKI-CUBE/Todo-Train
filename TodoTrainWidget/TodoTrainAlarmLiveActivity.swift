//
//  TodoTrainAlarmLiveActivity.swift
//  TodoTrainWidget
//
//  Add to Widget Extension target alongside AlarmKit countdown support.
//

import SwiftUI
import WidgetKit

#if canImport(AlarmKit) && canImport(ActivityKit)
import ActivityKit
import AlarmKit

struct TodoTrainAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<TodoTrainAlarmMetadata>.self) { context in
            lockScreenCountdown(context: context)
                .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.metadata?.ticketTitle ?? "切符")
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdownLabel(context: context)
                }
            } compactLeading: {
                Image(systemName: "tram.fill")
            } compactTrailing: {
                countdownLabel(context: context)
            } minimal: {
                Image(systemName: "tram.fill")
            }
        }
    }

    @ViewBuilder
    private func lockScreenCountdown(
        context: ActivityViewContext<AlarmAttributes<TodoTrainAlarmMetadata>>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(context.attributes.metadata?.ticketTitle ?? "乗務中")
                .font(.headline)
            countdownLabel(context: context)
                .font(.title2.monospacedDigit())
        }
    }

    @ViewBuilder
    private func countdownLabel(
        context: ActivityViewContext<AlarmAttributes<TodoTrainAlarmMetadata>>
    ) -> some View {
        if let fireDate = context.state.timerEndDate {
            Text(timerInterval: Date.now...fireDate, countsDown: true)
                .monospacedDigit()
        } else {
            Text("—")
        }
    }
}
#endif
