//
//  PauseLimitSheet.swift
//  Todo train
//

import SwiftUI

struct PauseLimitSheet: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss

    /// Called after current ticket partial disembark so Focus can present the canvas.
    var onCurrentPartialDisembark: (Ticket, UUID?) -> Void
    /// After freeing a slot, try pausing the current ride again.
    var onSlotFreedTryPause: () -> Void

    @State private var canvasLaunch: CanvasLaunch?
    @State private var errorMessage = ""
    @State private var showError = false

    private struct CanvasLaunch: Identifiable {
        let id = UUID()
        let parent: Ticket
        let sessionID: UUID?
    }

    private var currentTitle: String {
        sessionManager.activeSession?.ticket?.title ?? "今の切符"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("停車枠がいっぱいです（\(sessionManager.pausedTicketCount)/\(sessionManager.pauseLimit)）")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(sessionManager.pausedSessions, id: \.id) { session in
                        if let ticket = session.ticket {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(ticket.title)
                                    .font(.body.weight(.medium))
                                ViewThatFits(in: .horizontal) {
                                    HStack {
                                        pauseActions(for: session, ticket: ticket)
                                    }
                                    VStack(alignment: .leading, spacing: 8) {
                                        pauseActions(for: session, ticket: ticket)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("先に停車中を解決")
                }

                Section("今の切符「\(currentTitle)」") {
                    Button("途中下車して整理") {
                        disembarkCurrent()
                    }
                    Button("放棄", role: .destructive) {
                        abandonCurrent()
                    }
                }

                if sessionManager.pausedTicketCount < sessionManager.pauseLimit,
                   sessionManager.phase == .running || sessionManager.phase == .overtime {
                    Section {
                        Button("このまま停車") {
                            onSlotFreedTryPause()
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if sessionManager.pausedTicketCount >= sessionManager.pauseLimit,
                   sessionManager.phase == .running || sessionManager.phase == .overtime {
                    Section("臨時停車") {
                        SafetyLockOverrideControl(
                            todayCount: sessionManager.todayOverrideCount
                        ) {
                            forcePauseCurrent()
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    }
                }
            }
            .navigationTitle("停車の整理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .sheet(item: $canvasLaunch) { launch in
                RemainingTicketsCanvas(parent: launch.parent, fromSessionID: launch.sessionID)
            }
            .alert("エラー", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    @ViewBuilder
    private func pauseActions(for session: WorkSession, ticket: Ticket) -> some View {
        Button("途中下車") {
            disembarkPaused(session, ticket: ticket)
        }
        .buttonStyle(.bordered)

        Button("再乗車") {
            resumePaused(ticket)
        }
        .buttonStyle(.borderedProminent)

        Button("放棄", role: .destructive) {
            abandonPaused(session)
        }
        .buttonStyle(.bordered)
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }

    private func disembarkPaused(_ session: WorkSession, ticket: Ticket) {
        let sessionID = session.id
        do {
            try sessionManager.partialDisembark(session: session)
            canvasLaunch = CanvasLaunch(parent: ticket, sessionID: sessionID)
        } catch {
            present(error)
        }
    }

    private func resumePaused(_ ticket: Ticket) {
        do {
            try sessionManager.board(ticket: ticket)
            dismiss()
        } catch {
            present(error)
        }
    }

    private func abandonPaused(_ session: WorkSession) {
        do {
            try sessionManager.abandon(session: session)
        } catch {
            present(error)
        }
    }

    private func disembarkCurrent() {
        guard let ticket = sessionManager.activeSession?.ticket else { return }
        let sessionID = sessionManager.activeSession?.id
        do {
            try sessionManager.partialDisembark()
            dismiss()
            onCurrentPartialDisembark(ticket, sessionID)
        } catch {
            present(error)
        }
    }

    private func abandonCurrent() {
        do {
            try sessionManager.abandon()
            dismiss()
        } catch {
            present(error)
        }
    }

    private func forcePauseCurrent() {
        do {
            _ = try sessionManager.forcePause()
            dismiss()
        } catch {
            present(error)
        }
    }
}
