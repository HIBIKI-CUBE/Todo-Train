//
//  PauseLimitSheet.swift
//  Todo train
//
//  Shown when the user tries to 発車 a new ticket while paused rides
//  already sit at the WIP cap. Pause itself is always allowed.
//

import SwiftUI

struct PauseLimitSheet: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss

    /// Ticket the user tried to board. After a slot is freed, retry this ride.
    var pendingTicket: Ticket?
    var onSlotFreedTryBoard: () -> Void

    @State private var canvasLaunch: CanvasLaunch?
    @State private var errorMessage = ""
    @State private var showError = false

    private struct CanvasLaunch: Identifiable {
        let id = UUID()
        let parent: Ticket
        let sessionID: UUID?
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("停車が \(sessionManager.pauseLimit) 件あるので、新しい切符は発車できません。先に片付けるか、停車中から再乗車してください。")
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
                    Text("停車中を解決")
                }

                if let pendingTicket,
                   sessionManager.pausedTicketCount < sessionManager.pauseLimit {
                    Section {
                        Button("「\(pendingTicket.title)」を発車") {
                            onSlotFreedTryBoard()
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("発車の前に")
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
            if sessionManager.phase == .running || sessionManager.phase == .overtime {
                try sessionManager.switchBoard(ticket: ticket)
            } else {
                try sessionManager.board(ticket: ticket)
            }
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
}
