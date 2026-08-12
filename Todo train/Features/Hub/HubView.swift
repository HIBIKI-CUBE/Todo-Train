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
    @State private var ticketPendingDelete: Ticket?
    @State private var showDeleteConfirm = false

    private enum HubDestination: Hashable, Identifiable {
        case tags
        case reorder

        var id: Self { self }
    }

    private var openTickets: [Ticket] {
        allTickets.filter(\.isOpen)
    }

    /// Open tickets that are not currently paused (paused live in their own section).
    private var backlogTickets: [Ticket] {
        openTickets.filter { !isPaused($0) }
    }

    private var canBoardGenerally: Bool {
        sessionManager.isInService
            && sessionManager.phase != .running
            && sessionManager.phase != .overtime
    }

    private var boardDisabledReason: String {
        if sessionManager.needsServiceDayEndPrompt {
            return "昨日の運行を終了してください"
        }
        if !sessionManager.isInService {
            return "運行開始が必要です"
        }
        if sessionManager.phase == .running || sessionManager.phase == .overtime {
            return "すでに走行中の切符があります"
        }
        return "発車できません"
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
                                NavigationLink {
                                    TicketDetailView(ticket: ticket)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(ticket.title)
                                            .font(TrainTheme.TypeScale.ticketTitle())
                                        Text("残り \(formatRemaining(session))")
                                            .font(TrainTheme.TypeScale.meta())
                                            .foregroundStyle(TrainTheme.signalAmber)
                                            .monospacedDigit()
                                        SignalBadge(kind: .paused)
                                    }
                                }
                                Spacer(minLength: 8)
                                Button("再乗車") {
                                    board(ticket)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(TrainTheme.rail)
                                .disabled(!canBoardGenerally)
                                .accessibilityHint(canBoardGenerally ? "停車中の切符を再開" : boardDisabledReason)
                            }
                            .accessibilityElement(children: .contain)
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
                } else if backlogTickets.isEmpty {
                    Text("未乗車の切符はありません。停車中から再乗車するか、＋ で追加してください。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(backlogTickets, id: \.id) { ticket in
                        TicketCardView(
                            ticket: ticket,
                            canBoard: canBoardGenerally,
                            boardDisabledReason: boardDisabledReason,
                            onBoard: { board(ticket) }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("削除", role: .destructive) {
                                ticketPendingDelete = ticket
                                showDeleteConfirm = true
                            }
                        }
                    }
                    .onMove(perform: moveBacklogTickets)
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
        .confirmationDialog(
            "この切符を削除しますか？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                if let ticket = ticketPendingDelete {
                    deleteTicket(ticket)
                }
                ticketPendingDelete = nil
            }
            Button("キャンセル", role: .cancel) {
                ticketPendingDelete = nil
            }
        } message: {
            if let ticket = ticketPendingDelete, !ticket.sessions.isEmpty {
                Text("「\(ticket.title)」と関連する履歴も削除されます。")
            } else if let ticket = ticketPendingDelete {
                Text("「\(ticket.title)」を削除します。この操作は取り消せません。")
            }
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
        .onAppear {
            presentServiceEndIfNeeded()
        }
        .onChange(of: sessionManager.needsServiceDayEndPrompt) { _, needs in
            if needs {
                presentServiceEndIfNeeded()
            }
        }
        .onChange(of: sessionManager.phase) { _, _ in
            presentServiceEndIfNeeded()
        }
    }

    /// S-03: after a day change, surface the end-of-service flow (once Focus is not blocking).
    private func presentServiceEndIfNeeded() {
        guard sessionManager.needsServiceDayEndPrompt else { return }
        guard sessionManager.phase != .running, sessionManager.phase != .overtime else { return }
        if !showServiceEndSheet {
            showServiceEndSheet = true
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

    private func deleteTicket(_ ticket: Ticket) {
        do {
            try sessionManager.deleteTicket(ticket)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func moveBacklogTickets(from source: IndexSet, to destination: Int) {
        var ordered = backlogTickets
        ordered.move(fromOffsets: source, toOffset: destination)
        // Preserve paused tickets' relative order; rebuild full open order as paused first then backlog.
        let paused = sessionManager.pausedSessions.compactMap(\.ticket)
        let full = paused + ordered
        let orders = TicketSortOrdering.normalizedOrders(forOrderedIDs: full.map(\.id))
        for ticket in openTickets {
            if let order = orders[ticket.id] {
                ticket.sortOrder = order
            }
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
