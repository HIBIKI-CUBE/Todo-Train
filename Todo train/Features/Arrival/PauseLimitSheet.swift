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
                    Text("停車枠がいっぱいです（\(sessionManager.pausedTicketCount)/\(PauseLimitGuard.defaultLimit)）")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("先に停車中を解決") {
                    ForEach(sessionManager.pausedSessions, id: \.id) { session in
                        if let ticket = session.ticket {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(ticket.title)
                                    .font(.body.weight(.medium))
                                HStack {
                                    Button("途中下車") {
                                        disembarkPaused(session, ticket: ticket)
                                    }
                                    .buttonStyle(.bordered)

                                    Button("再開") {
                                        resumePaused(ticket)
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button("放棄", role: .destructive) {
                                        abandonPaused(session)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("今の切符「\(currentTitle)」") {
                    Button("途中下車して整理") {
                        disembarkCurrent()
                    }
                    Button("放棄", role: .destructive) {
                        abandonCurrent()
                    }
                }

                if sessionManager.pausedTicketCount < PauseLimitGuard.defaultLimit,
                   sessionManager.phase == .running || sessionManager.phase == .overtime {
                    Section {
                        Button("このまま停車") {
                            onSlotFreedTryPause()
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if sessionManager.pausedTicketCount >= PauseLimitGuard.defaultLimit,
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
        }
    }

    private func disembarkPaused(_ session: WorkSession, ticket: Ticket) {
        let sessionID = session.id
        do {
            try sessionManager.partialDisembark(session: session)
            canvasLaunch = CanvasLaunch(parent: ticket, sessionID: sessionID)
        } catch {
            // Keep sheet open.
        }
    }

    private func resumePaused(_ ticket: Ticket) {
        do {
            try sessionManager.board(ticket: ticket)
            dismiss()
        } catch {
            // Keep sheet open.
        }
    }

    private func abandonPaused(_ session: WorkSession) {
        try? sessionManager.abandon(session: session)
    }

    private func disembarkCurrent() {
        guard let ticket = sessionManager.activeSession?.ticket else { return }
        let sessionID = sessionManager.activeSession?.id
        do {
            try sessionManager.partialDisembark()
            dismiss()
            onCurrentPartialDisembark(ticket, sessionID)
        } catch {
            // Keep sheet open.
        }
    }

    private func abandonCurrent() {
        do {
            try sessionManager.abandon()
            dismiss()
        } catch {
            // Keep sheet open.
        }
    }

    private func forcePauseCurrent() {
        do {
            _ = try sessionManager.forcePause()
            dismiss()
        } catch {
            // Keep sheet open.
        }
    }
}
