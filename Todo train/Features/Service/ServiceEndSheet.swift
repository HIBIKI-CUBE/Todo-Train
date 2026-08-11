//
//  ServiceEndSheet.swift
//  Todo train
//

import SwiftUI

struct ServiceEndSheet: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss

    var onError: (String) -> Void

    @State private var canvasLaunch: CanvasLaunch?

    private struct CanvasLaunch: Identifiable {
        let id = UUID()
        let parent: Ticket
        let sessionID: UUID?
    }

    private var pausedSessions: [WorkSession] {
        sessionManager.pausedSessions
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("停車中の切符の扱いを選んでから運行を終了します。何もしなければ持ち越し（翌日も停車中）です。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if pausedSessions.isEmpty {
                    Section {
                        Text("停車中の切符はありません。")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("停車中（\(pausedSessions.count)）") {
                        ForEach(pausedSessions, id: \.id) { session in
                            if let ticket = session.ticket {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(ticket.title)
                                            .font(.body.weight(.medium))
                                        Spacer()
                                        Text("持ち越し")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    HStack {
                                        Button("途中下車") {
                                            disembark(session, ticket: ticket)
                                        }
                                        .buttonStyle(.bordered)

                                        Button("放棄", role: .destructive) {
                                            abandon(session)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }

                Section {
                    Button("運行を終了する", role: .destructive) {
                        confirmEnd()
                    }
                }
            }
            .navigationTitle("運行終了")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .sheet(item: $canvasLaunch) { launch in
                RemainingTicketsCanvas(parent: launch.parent, fromSessionID: launch.sessionID)
            }
        }
    }

    private func disembark(_ session: WorkSession, ticket: Ticket) {
        let sessionID = session.id
        do {
            try sessionManager.partialDisembark(session: session)
            canvasLaunch = CanvasLaunch(parent: ticket, sessionID: sessionID)
        } catch {
            onError(error.localizedDescription)
        }
    }

    private func abandon(_ session: WorkSession) {
        do {
            try sessionManager.abandon(session: session)
        } catch {
            onError(error.localizedDescription)
        }
    }

    private func confirmEnd() {
        do {
            try sessionManager.endService()
            dismiss()
        } catch {
            onError(error.localizedDescription)
        }
    }
}
