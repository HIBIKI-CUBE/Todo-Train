//
//  TodoTrainSessionLiveActivity.swift
//  TodoTrainWidget
//
//  Session (発車中) Live Activity — used when AlarmKit 終了ベル is off.
//

import SwiftUI
import WidgetKit

#if canImport(ActivityKit)
import ActivityKit

struct TodoTrainSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TodoTrainActivityAttributes.self) { context in
            lockScreenView(context: context)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "tram.fill")
                        .font(.title3)
                        .foregroundStyle(Color("AccentColor"))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: 90, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    timerText(context: context, style: .island)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.isOvertime ? "超過中" : "発車中")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(context.state.isOvertime ? .orange : .secondary)
                        .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "tram.fill")
                    .font(.caption2)
                    .foregroundStyle(Color("AccentColor"))
            } compactTrailing: {
                if context.state.isOvertime {
                    Text("超過")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                } else {
                    Text(timerInterval: Date.now...context.state.deadline, countsDown: true)
                        .font(.caption2.monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 52)
                        .minimumScaleFactor(0.6)
                }
            } minimal: {
                Image(systemName: "tram.fill")
                    .font(.caption2)
            }
        }
    }

    private enum TimerStyle {
        case lockScreen
        case island
    }

    @ViewBuilder
    private func lockScreenView(
        context: ActivityViewContext<TodoTrainActivityAttributes>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "tram.fill")
                    .foregroundStyle(Color("AccentColor"))
                Text(context.state.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(context.state.isOvertime ? "超過中" : "発車中")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(context.state.isOvertime ? .orange : .secondary)
            }

            timerText(context: context, style: .lockScreen)
                .frame(maxWidth: .infinity)
        }
        .activityBackgroundTint(Color("AccentColor").opacity(0.14))
    }

    @ViewBuilder
    private func timerText(
        context: ActivityViewContext<TodoTrainActivityAttributes>,
        style: TimerStyle
    ) -> some View {
        let font: Font = style == .lockScreen
            ? .system(size: 44, weight: .medium, design: .rounded)
            : .title2.weight(.semibold)

        if context.state.isOvertime {
            Text("超過")
                .font(font)
                .foregroundStyle(.orange)
                .frame(maxWidth: style == .lockScreen ? 220 : 120)
        } else {
            Text(timerInterval: Date.now...context.state.deadline, countsDown: true)
                .font(font)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(maxWidth: style == .lockScreen ? 220 : 120)
        }
    }
}
#endif
