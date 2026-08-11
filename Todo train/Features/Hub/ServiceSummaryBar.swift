//
//  ServiceSummaryBar.swift
//  Todo train
//

import SwiftUI

struct ServiceSummaryBar: View {
    @Environment(SessionManager.self) private var sessionManager
    let onError: (String) -> Void
    let onRequestEndService: () -> Void

    private var canEndOpenService: Bool {
        sessionManager.isInService || sessionManager.needsServiceDayEndPrompt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TrainTheme.Space.sm) {
            if sessionManager.needsServiceDayEndPrompt {
                HStack(alignment: .top, spacing: TrainTheme.Space.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(TrainTheme.signalAmber)
                    Text("昨日の運行が未終了です。終了してから今日の運行を開始してください。")
                        .font(.footnote)
                        .foregroundStyle(TrainTheme.ink)
                }
                .padding(TrainTheme.Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: TrainTheme.Radius.control)
                        .fill(TrainTheme.signalAmber.opacity(0.12))
                )
            }

            HStack(alignment: .center, spacing: TrainTheme.Space.md) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: TrainTheme.Space.sm) {
                        Circle()
                            .fill(statusDot)
                            .frame(width: 8, height: 8)
                        Text(statusTitle)
                            .font(TrainTheme.TypeScale.status())
                            .foregroundStyle(TrainTheme.ink)
                    }

                    if let key = sessionManager.activeServiceDay?.calendarDayKey,
                       sessionManager.activeServiceDay?.isOpen == true {
                        Text(key)
                            .font(TrainTheme.TypeScale.meta())
                            .foregroundStyle(TrainTheme.muted)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("停車")
                        .font(.caption2)
                        .foregroundStyle(TrainTheme.muted)
                    Text("\(sessionManager.pausedTicketCount)/\(sessionManager.pauseLimit)")
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(
                            sessionManager.pausedTicketCount >= sessionManager.pauseLimit
                                ? TrainTheme.signalAmber
                                : TrainTheme.ink
                        )
                }

                if canEndOpenService {
                    Button(
                        sessionManager.needsServiceDayEndPrompt ? "昨日を終了" : "運行終了"
                    ) {
                        onRequestEndService()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TrainTheme.signalRed)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: TrainTheme.Radius.control)
                            .strokeBorder(TrainTheme.signalRed.opacity(0.4), lineWidth: 1)
                    )
                } else {
                    Button("運行開始") {
                        do {
                            try sessionManager.startService()
                        } catch {
                            onError(error.localizedDescription)
                        }
                    }
                    .buttonStyle(DepartButtonStyle(enabled: true))
                }
            }
            .padding(TrainTheme.Space.md)
            .background(
                RoundedRectangle(cornerRadius: TrainTheme.Radius.ticket)
                    .fill(Color.white.opacity(0.92))
                    .overlay {
                        RoundedRectangle(cornerRadius: TrainTheme.Radius.ticket)
                            .strokeBorder(TrainTheme.track.opacity(0.8), lineWidth: 1)
                    }
            )
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
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
}
