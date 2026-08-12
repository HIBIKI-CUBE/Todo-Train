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
    @State private var localError = ""
    @State private var showLocalError = false

    private struct CanvasLaunch: Identifiable {
        let id = UUID()
        let parent: Ticket
        let sessionID: UUID?
    }

    private var pausedSessions: [WorkSession] {
        sessionManager.pausedSessions
    }

    private var canConfirmEnd: Bool {
        pausedSessions.isEmpty
            && sessionManager.phase != .running
            && sessionManager.phase != .overtime
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(introCopy)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if pausedSessions.isEmpty {
                    Section {
                        Label("停車中の切符はありません", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(TrainTheme.signalGreen)
                    }
                } else {
                    Section {
                        ForEach(pausedSessions, id: \.id) { session in
                            if let ticket = session.ticket {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(ticket.title)
                                        .font(.body.weight(.medium))

                                    HStack(spacing: 8) {
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
                                .accessibilityElement(children: .contain)
                            }
                        }
                    } header: {
                        Text("停車中（\(pausedSessions.count)）— すべて解決してください")
                    } footer: {
                        Text("途中下車すると乗り継ぎ切符を掃き出せます。未解決の停車中は持ち越しできません。")
                    }
                }

                Section {
                    Button("運行を終了する", role: .destructive) {
                        confirmEnd()
                    }
                    .disabled(!canConfirmEnd)
                } footer: {
                    if !canConfirmEnd {
                        Text(sessionManager.phase == .running || sessionManager.phase == .overtime
                            ? "走行中は運行終了できません。"
                            : "停車中を途中下車または放棄してから終了できます。")
                    }
                }
            }
            .navigationTitle(sessionManager.needsServiceDayEndPrompt ? "昨日の運行終了" : "運行終了")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .sheet(item: $canvasLaunch) { launch in
                RemainingTicketsCanvas(parent: launch.parent, fromSessionID: launch.sessionID)
            }
            .alert("エラー", isPresented: $showLocalError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(localError)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var introCopy: String {
        if sessionManager.needsServiceDayEndPrompt {
            return "昨日の運行が続いています。停車中の切符を途中下車（乗り継ぎ）または放棄してから終了してください。"
        }
        return "停車中の切符を途中下車（乗り継ぎ）または放棄してから運行を終了します。"
    }

    private func disembark(_ session: WorkSession, ticket: Ticket) {
        let sessionID = session.id
        do {
            try sessionManager.partialDisembark(session: session)
            canvasLaunch = CanvasLaunch(parent: ticket, sessionID: sessionID)
        } catch {
            present(error)
        }
    }

    private func abandon(_ session: WorkSession) {
        do {
            try sessionManager.abandon(session: session)
        } catch {
            present(error)
        }
    }

    private func confirmEnd() {
        do {
            try sessionManager.endService()
            dismiss()
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        localError = error.localizedDescription
        showLocalError = true
        onError(error.localizedDescription)
    }
}
