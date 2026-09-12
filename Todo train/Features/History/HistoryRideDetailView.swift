//
//  HistoryRideDetailView.swift
//  Todo train
//
//  One ride from the day clock. Markers live here so the canvas stays readable.
//

import SwiftUI

struct HistoryRideDetailView: View {
    let session: WorkSession
    var onReissue: ((Ticket) -> Void)?
    var onDelete: (WorkSession) -> Void

    @Environment(\.dismiss) private var dismiss

    private var ride: TimelineRide? {
        SessionTimeline.rides(from: [session]).first
    }

    var body: some View {
        List {
            if let ride {
                Section {
                    LabeledContent("発車", value: Self.timeFormatter.string(from: ride.startedAt))
                    LabeledContent(terminalLabel(ride), value: Self.timeFormatter.string(from: ride.endedAt))
                    LabeledContent("元の予定", value: Self.timeFormatter.string(from: ride.originalScheduleAt))
                } header: {
                    HStack(spacing: TrainTheme.Space.sm) {
                        Text(ride.title)
                            .font(TrainTheme.TypeScale.ticketTitle())
                            .foregroundStyle(.primary)
                        HistoryOutcomeBadge(outcome: ride.outcome, punctuality: ride.punctuality)
                    }
                    .textCase(nil)
                }

                if !ride.extensions.isEmpty {
                    Section("延長") {
                        ForEach(Array(ride.extensions.enumerated()), id: \.element.id) { index, ext in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("延長\(index + 1) +\(max(0, ext.addedSeconds) / 60)分")
                                    .font(.body.weight(.medium))
                                Text(Self.timeFormatter.string(from: ext.createdAt))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                if let reason = ext.reason, !reason.isEmpty {
                                    Text(reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !ride.pauses.isEmpty {
                    Section("停車") {
                        ForEach(ride.pauses, id: \.id) { pause in
                            LabeledContent("停車 \(pauseMinutes(pause))分") {
                                Text(
                                    "\(Self.timeFormatter.string(from: pause.startedAt))–\(Self.timeFormatter.string(from: pause.endedAt))"
                                )
                                .font(.body.monospacedDigit())
                            }
                        }
                    }
                }

                if !ride.transfers.isEmpty {
                    Section("乗り継ぎ") {
                        ForEach(ride.transfers) { transfer in
                            if let child = childTicket(id: transfer.id) {
                                NavigationLink {
                                    TicketDetailView(ticket: child)
                                } label: {
                                    HStack {
                                        Text(transfer.title)
                                        if transfer.isOpen {
                                            Spacer()
                                            SignalBadge(kind: .inService, customLabel: "Hub")
                                        }
                                    }
                                }
                            } else {
                                Text(transfer.title)
                            }
                        }
                    }
                }
            }

            Section {
                if let ticket = session.ticket {
                    NavigationLink {
                        TicketDetailView(ticket: ticket)
                    } label: {
                        Label("切符の詳細", systemImage: "ticket")
                    }
                    if let onReissue {
                        Button("今日に追加") {
                            onReissue(ticket)
                            dismiss()
                        }
                    }
                }
                Button("削除", role: .destructive) {
                    onDelete(session)
                    dismiss()
                }
            }
        }
        .navigationTitle("乗車")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("閉じる") {
                    dismiss()
                }
            }
        }
    }

    private func terminalLabel(_ ride: TimelineRide) -> String {
        switch ride.outcome {
        case .partialDisembark: "途中下車"
        case .abandoned: "放棄"
        default: "到着"
        }
    }

    private func pauseMinutes(_ pause: TimelinePause) -> Int {
        Int((pause.duration / 60).rounded())
    }

    private func childTicket(id: UUID) -> Ticket? {
        session.ticket?.childLineages.compactMap(\.child).first { $0.id == id }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
