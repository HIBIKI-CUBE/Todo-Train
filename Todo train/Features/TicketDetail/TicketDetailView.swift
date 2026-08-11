//
//  TicketDetailView.swift
//  Todo train
//

import SwiftUI
import SwiftData

struct TicketDetailView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.modelContext) private var modelContext
    @Bindable var ticket: Ticket

    @State private var errorMessage = ""
    @State private var showError = false

    private var canBoard: Bool {
        sessionManager.isInService
            && sessionManager.phase != .running
            && sessionManager.phase != .overtime
            && ticket.isOpen
    }

    private var isPaused: Bool {
        sessionManager.pausedSessions.contains { $0.ticket?.id == ticket.id }
    }

    var body: some View {
        Form {
            Section("切符") {
                TextField("タイトル", text: $ticket.title)
                Stepper(
                    "見積もり \(ticket.estimatedSeconds / 60) 分",
                    value: Binding(
                        get: { ticket.estimatedSeconds / 60 },
                        set: { ticket.estimatedSeconds = min(max($0, 1), 60) * 60 }
                    ),
                    in: 1...60
                )
                if isPaused {
                    Text("停車中")
                        .foregroundStyle(.orange)
                }
            }

            Section("セッション") {
                Text("記録 \(ticket.sessions.count) 回")
                let total = ticket.sessions.reduce(0.0) { partial, session in
                    partial + session.accumulatedActiveSeconds
                }
                Text("累計アクティブ \(Int(total / 60)) 分")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(isPaused ? "再開" : "発車") {
                    board()
                }
                .disabled(!canBoard && !isPaused)
            }
        }
        .navigationTitle("切符の詳細")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            try? modelContext.save()
        }
        .alert("発車できません", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func board() {
        do {
            try sessionManager.board(ticket: ticket)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
