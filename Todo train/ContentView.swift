//
//  ContentView.swift
//  Todo train
//
//  Temporary debug UI for Sprint 1 SessionManager + 運行コア.
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
                }

                Section("セッション") {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let _ = context.date
                        VStack(alignment: .leading, spacing: 8) {
                            Text("経過 \(format(sessionManager.elapsedSeconds))")
                            Text("残り \(format(sessionManager.remainingSeconds))")
                            if let title = sessionManager.activeSession?.ticket?.title {
                                Text("乗務中: \(title)")
                            } else {
                                Text("乗務なし")
                            }
                        }
                    }

                    Button("停車") { run { try sessionManager.pause() } }
                    Button("再開") { run { try sessionManager.resume() } }
                    Button("+5分延長") {
                        run { try sessionManager.extend(by: 5 * 60) }
                    }
                    Button("到着") { run { try sessionManager.arrive() } }
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
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    recover()
                }
            }
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
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let sign = total < 0 ? "-" : ""
        let absTotal = abs(total)
        let m = absTotal / 60
        let s = absTotal % 60
        return String(format: "%@%d:%02d", sign, m, s)
    }
}

#Preview {
    let container = try! AppModelContainer.make(inMemory: true)
    let manager = SessionManager(modelContext: container.mainContext)
    return ContentView()
        .environment(manager)
        .modelContainer(container)
}
