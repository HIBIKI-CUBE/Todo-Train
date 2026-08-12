//
//  TodoTrainAlarmLiveActivity.swift
//  TodoTrainWidget
//
//  Custom LA = vision + interactive controls (LiveActivityIntent).
//  AlarmPresentation buttons only cover the system templated fallback UI.
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
                    Text(ticketTitle(context))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: 90, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    primaryTimer(context: context, style: .island)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    controlRow(context: context, compact: true)
                        .padding(.top, 6)
                }
            } compactLeading: {
                Image(systemName: "tram.fill")
                    .font(.caption2)
                    .foregroundStyle(Color("AccentColor"))
            } compactTrailing: {
                compactTrailing(context: context)
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

    // MARK: - Lock Screen / StandBy

    @ViewBuilder
    private func lockScreenView(
        context: ActivityViewContext<AlarmAttributes<TodoTrainAlarmMetadata>>
    ) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "tram.fill")
                    .foregroundStyle(Color("AccentColor"))
                Text(ticketTitle(context))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                modeCaption(context: context)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            primaryTimer(context: context, style: .lockScreen)
                .frame(maxWidth: .infinity)

            progressBar(context: context)
                .frame(height: 6)
                .padding(.horizontal, 4)

            controlRow(context: context, compact: false)
                .padding(.top, 2)
        }
        .activityBackgroundTint(Color("AccentColor").opacity(0.14))
    }

    // MARK: - Timer

    @ViewBuilder
    private func primaryTimer(
        context: ActivityViewContext<AlarmAttributes<TodoTrainAlarmMetadata>>,
        style: TimerStyle
    ) -> some View {
        let font: Font = style == .lockScreen
            ? .system(size: 48, weight: .medium, design: .rounded)
            : .title2.weight(.semibold)

        switch context.state.mode {
        case .countdown(let countdown):
            Text(timerInterval: Date.now...countdown.fireDate, countsDown: true)
                .font(font)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(maxWidth: style == .lockScreen ? 220 : 120)
        case .paused(let paused):
            Text(pausedRemainingLabel(paused))
                .font(font)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .frame(maxWidth: style == .lockScreen ? 220 : 120)
        case .alert:
            Label("見積もり終了", systemImage: "bell.fill")
                .font(style == .lockScreen ? .title2.weight(.semibold) : .headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        @unknown default:
            Text("—")
                .font(font)
                .monospacedDigit()
        }
    }

    // MARK: - Compact DI (keep narrow)

    @ViewBuilder
    private func compactTrailing(
        context: ActivityViewContext<AlarmAttributes<TodoTrainAlarmMetadata>>
    ) -> some View {
        switch context.state.mode {
        case .countdown(let countdown):
            ProgressView(
                timerInterval: Date.now...countdown.fireDate,
                countsDown: true,
                label: { EmptyView() },
                currentValueLabel: { EmptyView() }
            )
            .progressViewStyle(.circular)
            .tint(Color("AccentColor"))
            .frame(width: 18, height: 18)
        case .paused(let paused):
            Text(pausedRemainingLabel(paused))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .frame(width: 36, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        case .alert:
            Image(systemName: "bell.fill")
                .font(.caption2)
        @unknown default:
            EmptyView()
        }
    }

    // MARK: - Progress

    @ViewBuilder
    private func progressBar(
        context: ActivityViewContext<AlarmAttributes<TodoTrainAlarmMetadata>>
    ) -> some View {
        switch context.state.mode {
        case .countdown(let countdown):
            ProgressView(
                timerInterval: Date.now...countdown.fireDate,
                countsDown: true,
                label: { EmptyView() },
                currentValueLabel: { EmptyView() }
            )
            .tint(Color("AccentColor"))
        case .paused(let paused):
            let remaining = max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration)
            let total = max(paused.totalCountdownDuration, 0.001)
            ProgressView(value: remaining, total: total)
                .tint(Color("AccentColor"))
        case .alert:
            ProgressView(value: 0, total: 1)
                .tint(Color("AccentColor"))
        @unknown default:
            EmptyView()
        }
    }

    // MARK: - Controls (required for custom LA)

    @ViewBuilder
    private func controlRow(
        context: ActivityViewContext<AlarmAttributes<TodoTrainAlarmMetadata>>,
        compact: Bool
    ) -> some View {
        let alarmID = context.state.alarmID
        let iconSize: CGFloat = compact ? 28 : 36

        HStack(spacing: compact ? 28 : 40) {
            Button(intent: EndBellCancelIntent(alarmID: alarmID)) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: iconSize))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            switch context.state.mode {
            case .countdown:
                Button(intent: EndBellPauseIntent(alarmID: alarmID)) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: iconSize + (compact ? 4 : 8)))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color("AccentColor"))
                }
                .buttonStyle(.plain)
            case .paused:
                Button(intent: EndBellResumeIntent(alarmID: alarmID)) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: iconSize + (compact ? 4 : 8)))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color("AccentColor"))
                }
                .buttonStyle(.plain)
            case .alert:
                Button(intent: EndBellStopIntent(alarmID: alarmID, sessionID: context.attributes.metadata?.sessionID ?? alarmID)) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: iconSize + (compact ? 4 : 8)))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color("AccentColor"))
                }
                .buttonStyle(.plain)
            @unknown default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func modeCaption(
        context: ActivityViewContext<AlarmAttributes<TodoTrainAlarmMetadata>>
    ) -> some View {
        switch context.state.mode {
        case .paused:
            Text("停車中")
        case .alert:
            Text("終了ベル")
        case .countdown:
            EmptyView()
        @unknown default:
            EmptyView()
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
