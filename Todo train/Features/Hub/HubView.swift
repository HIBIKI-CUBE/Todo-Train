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
    @State private var hubDestination: HubDestination?
    @State private var errorMessage = ""
    @State private var showError = false

    private enum HubDestination: Hashable, Identifiable {
        case tags
        case reorder

        var id: Self { self }
    }

    private var openTickets: [Ticket] {
        allTickets.filter(\.isOpen)
    }

    private var canBoardGenerally: Bool {
        sessionManager.isInService
            && sessionManager.phase != .running
            && sessionManager.phase != .overtime
    }

    var body: some View {
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
                Section {
                    ForEach(sessionManager.pausedSessions, id: \.id) { session in
                        if let ticket = session.ticket {
                            HStack(spacing: TrainTheme.Space.md) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(ticket.title)
                                        .font(TrainTheme.TypeScale.ticketTitle())
                                    Text("残り \(formatRemaining(session))")
                                        .font(TrainTheme.TypeScale.meta())
                                        .foregroundStyle(TrainTheme.signalAmber)
                                        .monospacedDigit()
                                }
                                Spacer(minLength: 8)
                                Button("再開") {
                                    board(ticket)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(TrainTheme.rail)
                                .disabled(!canBoardGenerally)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                } header: {
                    Text("停車中")
                }
            }

            Section {
                if openTickets.isEmpty {
                    ContentUnavailableView {
                        Label("切符がありません", systemImage: "tram")
                    } description: {
                        Text("右上の ＋ から掃き出しましょう。")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    ForEach(openTickets, id: \.id) { ticket in
                        TicketCardView(
                            ticket: ticket,
                            isPaused: isPaused(ticket),
                            canBoard: canBoardGenerally,
                            onBoard: { board(ticket) }
                        )
                    }
                    .onMove(perform: moveTickets)
                }
            } header: {
                Text("切符")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Todo train")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        hubDestination = .tags
                    } label: {
                        Label("タグ", systemImage: "tag")
                    }
                    Button {
                        hubDestination = .reorder
                    } label: {
                        Label("並べ替え", systemImage: "arrow.up.arrow.down")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("その他")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showQuickAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("切符を追加")
            }
        }
        .navigationDestination(item: $hubDestination) { destination in
            switch destination {
            case .tags:
                TagManagerView()
            case .reorder:
                ReorderView()
            }
        }
        .alert("エラー", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showQuickAdd) {
            QuickAddSheet()
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
            .environment(AppSettings.shared)
            .modelContainer(container)
    }
}
