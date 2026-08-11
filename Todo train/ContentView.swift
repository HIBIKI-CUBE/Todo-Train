//
//  ContentView.swift
//  Todo train
//
//  Debug Hub + Focus fullScreenCover (Sprint 2).
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var ticketTitle = "デバッグ切符"
    @State private var estimateMinutes = 30
    @State private var statusMessage = ""
    @State private var isFocusPresented = false

    var body: some View {
        NavigationStack {
            List {
                Section("運行") {
                    LabeledContent("phase", value: sessionManager.phase.rawValue)
                    LabeledContent(
                        "運行",
                        value: sessionManager.isInService
                            ? (sessionManager.activeServiceDay?.calendarDayKey ?? "中")
                            : "なし"
                    )
                    if sessionManager.needsServiceDayEndPrompt {
                        Text("昨日の運行が未終了です")
                            .foregroundStyle(.orange)
                    }
                    LabeledContent("停車中", value: "\(sessionManager.pausedTicketCount)")

                    Button("運行開始") { run { try sessionManager.startService() } }
                    Button("運行終了", role: .destructive) {
                        run { try sessionManager.endService() }
                    }
                }

                Section("切符を作って発車") {
                    TextField("タイトル", text: $ticketTitle)
                    Stepper("見積もり \(estimateMinutes) 分", value: $estimateMinutes, in: 1...60)
                    Button("作成して発車") {
                        run {
                            let seconds = estimateMinutes * 60
                            let ticket = Ticket(
                                title: ticketTitle.isEmpty ? "無題" : ticketTitle,
                                estimatedSeconds: seconds,
                                sortOrder: 0
                            )
                            modelContext.insert(ticket)
                            try modelContext.save()
                            try sessionManager.board(ticket: ticket)
                        }
                    }
                    .disabled(!sessionManager.isInService || sessionManager.phase == .running || sessionManager.phase == .overtime)
                }

                Section("停車中セッション") {
                    if sessionManager.phase == .paused, let title = sessionManager.activeSession?.ticket?.title {
                        Text(title)
                        Button("再開") {
                            run { try sessionManager.resume() }
                        }
                    } else {
                        Text("なし")
                            .foregroundStyle(.secondary)
                    }
                }

                if !statusMessage.isEmpty {
                    Section("ログ") {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Todo train Debug")
            .onAppear {
                recover()
                syncFocusPresentation()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    recover()
                    syncFocusPresentation()
                }
            }
            .onChange(of: sessionManager.phase) { _, _ in
                syncFocusPresentation()
            }
            .fullScreenCover(isPresented: $isFocusPresented) {
                FocusView()
                    .environment(sessionManager)
                    .interactiveDismissDisabled()
            }
        }
    }

    private func syncFocusPresentation() {
        let shouldShow = sessionManager.phase == .running || sessionManager.phase == .overtime
        if isFocusPresented != shouldShow {
            isFocusPresented = shouldShow
        }
    }

    private func recover() {
        do {
            try sessionManager.recoverOnLaunch()
            statusMessage = "recover OK / phase=\(sessionManager.phase.rawValue)"
        } catch {
            sessionManager.reconcile()
            statusMessage = "recover: \(error.localizedDescription)"
        }
    }

    private func run(_ body: () throws -> Void) {
        do {
            try body()
            statusMessage = "OK / phase=\(sessionManager.phase.rawValue)"
            syncFocusPresentation()
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

#Preview {
    let container = try! AppModelContainer.make(inMemory: true)
    let manager = SessionManager(modelContext: container.mainContext)
    return ContentView()
        .environment(manager)
        .modelContainer(container)
}
