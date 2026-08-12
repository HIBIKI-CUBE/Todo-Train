//
//  HubView.swift
//  Todo train
//

import SwiftUI
import SwiftData

struct HubView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(DeletionUndoCenter.self) private var undoCenter

    @Query(sort: \Ticket.sortOrder) private var allTickets: [Ticket]

    @State private var showQuickAdd = false
    @State private var showServiceEndSheet = false
    @State private var hubDestination: HubDestination?
    @State private var errorMessage = ""
    @State private var showError = false
    /// Single-issue celebration playing on Hub (may overlap sheet dismiss).
    @State private var hubIssueEject: TicketIssueEjectEvent?
    @State private var hubIssueHaptic = 0

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

    private var isLandscapeSplit: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        Group {
            if isLandscapeSplit {
                landscapeSplitHub
            } else {
                portraitHubList
            }
        }
        .navigationTitle("Todo train")
        .navigationBarTitleDisplayMode(
            TrainLayout.navigationBarTitleDisplayMode(verticalSizeClass: verticalSizeClass)
        )
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
        .errorAlert(isPresented: $showError, message: errorMessage)
        .sheet(isPresented: $showQuickAdd) {
            QuickAddSheet { event in
                // Commit-instant celebration: haptic + overlay while sheet dismisses in parallel.
                hubIssueEject = event
                hubIssueHaptic += 1
            }
        }
        .overlay {
            if let hubIssueEject {
                TicketIssueEjectOverlay(event: hubIssueEject) {
                    if self.hubIssueEject?.id == hubIssueEject.id {
                        self.hubIssueEject = nil
                    }
                }
                .transition(.opacity)
            }
        }
        .sensoryFeedback(.success, trigger: hubIssueHaptic)
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

    // MARK: - Portrait (single List)

    private var portraitHubList: some View {
        List {
            serviceSummarySection

            if !sessionManager.pausedSessions.isEmpty {
                pausedSessionsSection
            }

            ticketsSection
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Landscape split (service | tickets)

    private var landscapeSplitHub: some View {
        HStack(alignment: .top, spacing: 0) {
            servicePane
                .frame(width: TrainLayout.hubServicePaneWidth)

            ticketsPane
        }
    }

    private var servicePane: some View {
        List {
            serviceSummarySection

            if !sessionManager.pausedSessions.isEmpty {
                pausedSessionsSection
            }
        }
        .listStyle(.insetGrouped)
    }

    private var ticketsPane: some View {
        List {
            ticketsSection
        }
        .listStyle(.insetGrouped)
    }

  // MARK: - Shared sections

    private var serviceSummarySection: some View {
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
    }

    private var pausedSessionsSection: some View {
        Section {
            ForEach(sessionManager.pausedSessions, id: \.id) { session in
                if let ticket = session.ticket {
                    pausedTicketRow(ticket: ticket, session: session)
                        .deleteSwipeAction(accessibilityName: ticket.title) {
                            deleteTicket(ticket)
                        }
                }
            }
        } header: {
            Text("停車中")
        }
    }

    private var ticketsSection: some View {
        Section {
            if openTickets.isEmpty {
                ContentUnavailableView {
                    Label("切符がありません", systemImage: "tram")
                } description: {
                    Text("右上の ＋ から掃き出しましょう。")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, isLandscapeSplit ? 8 : 24)
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
                    .deleteSwipeAction(accessibilityName: ticket.title) {
                        deleteTicket(ticket)
                    }
                }
                .onMove(perform: moveBacklogTickets)
            }
        } header: {
            Text("切符")
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

    @ViewBuilder
    private func pausedTicketRow(ticket: Ticket, session: WorkSession) -> some View {
        HStack(spacing: TrainTheme.Space.md) {
            NavigationLink {
                TicketDetailView(ticket: ticket)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ticket.title)
                        .font(TrainTheme.TypeScale.ticketTitle())
                        .lineLimit(isLandscapeSplit ? 2 : nil)
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
        let title = ticket.title
        let record = DeletionUndo.captureTicket(ticket)
        do {
            try sessionManager.deleteTicket(ticket)
            undoCenter.offer(message: DeletionUndo.bannerMessage(ticketTitle: title)) {
                withAnimation {
                    try? sessionManager.restoreDeletedTicket(record)
                }
            }
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
            .environment(DeletionUndoCenter())
            .modelContainer(container)
    }
}
