//
//  ServiceSummaryBar.swift
//  Todo train
//

import SwiftUI

struct ServiceSummaryBar: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let onRequestStartService: () -> Void
    let onRequestEndService: () -> Void

    private var canEndOpenService: Bool {
        sessionManager.isInService || sessionManager.needsServiceDayEndPrompt
    }

    private var usesTightVerticalLayout: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: usesTightVerticalLayout ? TrainTheme.Space.sm : TrainTheme.Space.md) {
            if sessionManager.needsServiceDayEndPrompt {
                Label {
                    Text("昨日の運行が未終了です。終了してから今日の運行を開始してください。")
                        .font(.footnote)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(TrainTheme.signalAmber)
                }
                .foregroundStyle(.primary)
            }

            statusPauseRow

            if canEndOpenService {
                ServiceCabinKey(
                    title: sessionManager.needsServiceDayEndPrompt ? "昨日を終了" : "運行終了",
                    kind: .power,
                    compact: usesTightVerticalLayout,
                    action: onRequestEndService
                )
            } else {
                ServiceCabinKey(
                    title: "運行開始",
                    kind: .stand,
                    compact: usesTightVerticalLayout,
                    action: onRequestStartService
                )
            }
        }
        .padding(.vertical, usesTightVerticalLayout ? 2 : 4)
    }

    private var statusPauseRow: some View {
        HStack(alignment: .center, spacing: TrainTheme.Space.md) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: TrainTheme.Space.sm) {
                    Circle()
                        .fill(statusDot)
                        .frame(width: 8, height: 8)
                    Text(statusTitle)
                        .font(TrainTheme.TypeScale.status())
                        .lineLimit(1)
                }

                if let key = sessionManager.activeServiceDay?.calendarDayKey,
                   sessionManager.activeServiceDay?.isOpen == true {
                    Text(Self.displayDay(from: key))
                        .font(TrainTheme.TypeScale.meta())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                TimelineView(.periodic(from: .now, by: 15)) { context in
                    let fit = sessionManager.timetableFit(at: context.date)
                    TimetableOccupancyMeter(
                        rows: TimetableFit.occupancyRows(
                            fit: fit,
                            now: context.date,
                            calendar: sessionManager.calendar
                        ),
                        marks: TimetableFit.occupancyMarks(fit: fit, now: context.date),
                        chrome: .grouped
                    )
                    .opacity(
                        sessionManager.isInService || sessionManager.needsServiceDayEndPrompt
                            ? 1
                            : 0.32
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text("停車")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(sessionManager.pausedCountTowardLimit)/\(sessionManager.pauseLimit)")
                    .font(
                        usesTightVerticalLayout
                            ? .body.weight(.semibold).monospacedDigit()
                            : .title3.weight(.semibold).monospacedDigit()
                    )
                    .foregroundStyle(
                        sessionManager.pausedCountTowardLimit >= sessionManager.pauseLimit
                            ? TrainTheme.signalAmber
                            : .primary
                    )
            }
        }
    }

    private var statusTitle: String {
        if sessionManager.needsServiceDayEndPrompt {
            return "前日の運行が未終了"
        }
        return sessionManager.isInService ? "運行中" : "運休"
    }

    private var statusDot: Color {
        if sessionManager.needsServiceDayEndPrompt { return TrainTheme.signalAmber }
        return sessionManager.isInService ? TrainTheme.signalGreen : TrainTheme.muted
    }

    private static func displayDay(from dayKey: String) -> String {
        DayKeyFormatting.displayDay(from: dayKey)
    }
}
