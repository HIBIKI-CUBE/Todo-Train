//
//  HubView.swift
//  Todo train
//

import SwiftUI
import SwiftData

struct HubView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Ticket.sortOrder) private var allTickets: [Ticket]

    @State private var showQuickAdd = false
    @State private var showServiceEndSheet = false
    @State private var errorMessage = ""
    @State private var showError = false

    private var openTickets: [Ticket] {
        allTickets.filter(\.isOpen)
    }

    private var canBoardGenerally: Bool {
        sessionManager.isInService
            && sessionManager.phase != .running
            && sessionManager.phase != .overtime
    }

    var body: some View {
        ZStack {
            List {
                Section {
                    ServiceSummaryBar(
                        onError: { message in
                            errorMessage = message
                            showError = true
                        },
                        onRequestEndService: {
                            requestEndService()
                        }
                    )
                }

                if !sessionManager.pausedSessions.isEmpty {
                    Section("停車中") {
                        ForEach(sessionManager.pausedSessions, id: \.id) { session in
                            if let ticket = session.ticket {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(ticket.title)
                                        Text("残り \(formatRemaining(session))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("再開") {
                                        board(ticket)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .disabled(!canBoardGenerally)
                                }
                            }
                        }
                    }
                }

                Section("切符") {
                    if openTickets.isEmpty {
                        Text("切符がありません。＋ から掃き出しましょう。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(openTickets, id: \.id) { ticket in
                            HStack(spacing: 8) {
                                NavigationLink {
                                    TicketDetailView(ticket: ticket)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(ticket.title)
                                            .font(.body.weight(.medium))
                                            .lineLimit(1)
                                        HStack(spacing: 8) {
                                            Text("\(ticket.estimatedSeconds / 60)分")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            if isPaused(ticket) {
                                                Text("停車中")
                                                    .font(.caption.weight(.semibold))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.orange.opacity(0.2), in: Capsule())
                                                    .foregroundStyle(.orange)
                                            }
                                        }
                                        if !ticket.tags.isEmpty {
                                            TagChipRow(tags: ticket.tags)
                                        }
                                    }
                                }

                                Button("発車") {
                                    board(ticket)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(!canBoardGenerally)
                            }
                        }
                        .onMove(perform: moveTickets)
                    }
                }
            }

            if !showQuickAdd {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            showQuickAdd = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.accentColor, in: Circle())
                                .shadow(radius: 4, y: 2)
                        }
                        .padding(20)
                    }
                }
            }

            if showQuickAdd {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showQuickAdd = false
                    }

                QuickAddBar(isPresented: $showQuickAdd)
            }
        }
        .navigationTitle("Todo train")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink("タグ") {
                    TagManagerView()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("履歴") {
                    HistoryView()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .alert("エラー", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showServiceEndSheet) {
            ServiceEndSheet { message in
                errorMessage = message
                showError = true
            }
        }
    }

    private func requestEndService() {
        if sessionManager.pausedTicketCount == 0 {
            do {
                try sessionManager.endService()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        } else {
            showServiceEndSheet = true
        }
    }

    private func isPaused(_ ticket: Ticket) -> Bool {
        sessionManager.pausedSessions.contains { $0.ticket?.id == ticket.id }
    }

    private func board(_ ticket: Ticket) {
        do {
            try sessionManager.board(ticket: ticket)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func moveTickets(from source: IndexSet, to destination: Int) {
        var ordered = openTickets
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, ticket) in ordered.enumerated() {
            ticket.sortOrder = index
        }
        try? modelContext.save()
    }

    private func formatRemaining(_ session: WorkSession) -> String {
        let remaining = Int(session.remainingSeconds(at: .now).rounded())
        let absTotal = abs(remaining)
        let prefix = remaining < 0 ? "超過 " : ""
        return "\(prefix)\(absTotal / 60):\(String(format: "%02d", absTotal % 60))"
    }
}

#Preview {
    let container = try! AppModelContainer.make(inMemory: true)
    let manager = SessionManager(modelContext: container.mainContext)
    return NavigationStack {
        HubView()
            .environment(manager)
            .modelContainer(container)
    }
}
