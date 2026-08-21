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
    @State private var detailTicket: Ticket?
    @State private var errorMessage = ""
    @State private var showError = false
    /// Single-issue celebration playing on Hub (may overlap sheet dismiss).
    @State private var hubIssueEject: TicketIssueEjectEvent?
    @State private var focusedTicketID: UUID?
    /// Full-cabin black beat before Focus cover.
    @State private var cabinIngress = false
    @Namespace private var ticketNamespace

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

    /// Cabin ingress paints full-screen black; ticket focus uses dim overlay (no toolbar hide —
    /// toolbar(.hidden) mid-flight caused layout がくつき).
    private var isTicketFocusChromeActive: Bool {
        cabinIngress
    }

    var body: some View {
        Group {
            if isLandscapeSplit {
                landscapeSplitHub
            } else {
                portraitHub
            }
        }
        // Only hide chrome during cabin ingress (full black). Focus dim covers content without
        // resizing the tab/nav layout.
        .toolbar(isTicketFocusChromeActive ? .hidden : .automatic, for: .tabBar)
        .toolbar(isTicketFocusChromeActive ? .hidden : .automatic, for: .navigationBar)
        .toolbar {
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
        .navigationTitle("Todo train")
        .navigationBarTitleDisplayMode(
            TrainLayout.navigationBarTitleDisplayMode(verticalSizeClass: verticalSizeClass)
        )
        .navigationDestination(item: $hubDestination) { destination in
            switch destination {
            case .tags:
                TagManagerView()
            case .reorder:
                ReorderView()
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { detailTicket != nil },
            set: { if !$0 { detailTicket = nil } }
        )) {
            if let detailTicket {
                TicketDetailView(ticket: detailTicket)
            }
        }
        .errorAlert(isPresented: $showError, message: errorMessage)
        .sheet(isPresented: $showQuickAdd) {
            QuickAddSheet { event in
                hubIssueEject = event
                // Stay on the list so the issue celebration can play; do not auto-enter focus.
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
        .overlay {
            ticketFocusLayer
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

    // MARK: - Portrait

    private var portraitHub: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TrainTheme.Space.lg) {
                serviceBlock
                if !sessionManager.pausedSessions.isEmpty {
                    pausedBlock
                }
                ticketsBlock
            }
            .padding(.bottom, TrainTheme.Space.xl)
        }
        .scrollClipDisabled()
        .background(TrainTheme.platform)
    }

    // MARK: - Landscape split

    private var landscapeSplitHub: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: TrainTheme.Space.md) {
                    serviceBlock
                    if !sessionManager.pausedSessions.isEmpty {
                        pausedBlock
                    }
                }
                .padding(.bottom, TrainTheme.Space.lg)
            }
            .frame(width: TrainLayout.hubServicePaneWidth)
            .background(TrainTheme.platform)

            ScrollView {
                ticketsBlock
                    .padding(.bottom, TrainTheme.Space.lg)
            }
            .scrollClipDisabled()
            .background(TrainTheme.platform)
        }
    }

    // MARK: - Blocks

    private var serviceBlock: some View {
        VStack(alignment: .leading, spacing: TrainTheme.Space.sm) {
            Text("運行")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, TrainTheme.Space.lg)
            ServiceSummaryBar(
                onError: { message in
                    errorMessage = message
                    showError = true
                },
                onRequestEndService: {
                    requestEndService()
                }
            )
            .padding(.horizontal, TrainTheme.Space.md)
        }
        .padding(.top, TrainTheme.Space.sm)
    }

    private var pausedBlock: some View {
        VStack(alignment: .leading, spacing: TrainTheme.Space.sm) {
            Text("停車中")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, TrainTheme.Space.lg)

            VStack(spacing: TrainTheme.Space.sm) {
                ForEach(sessionManager.pausedSessions, id: \.id) { session in
                    if let ticket = session.ticket {
                        pausedTicketRow(ticket: ticket, session: session)
                            .padding(.horizontal, TrainTheme.Space.md)
                            .contextMenu {
                                Button("削除", role: .destructive) {
                                    deleteTicket(ticket)
                                }
                            }
                    }
                }
            }
        }
    }

    private var ticketsBlock: some View {
        VStack(alignment: .leading, spacing: TrainTheme.Space.sm) {
            Text("切符")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, TrainTheme.Space.lg)

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
                    .padding(.horizontal, TrainTheme.Space.lg)
            } else {
                TicketStackView(
                    tickets: backlogTickets,
                    canBoard: canBoardGenerally,
                    boardDisabledReason: boardDisabledReason,
                    focusedTicketID: $focusedTicketID,
                    ticketNamespace: ticketNamespace,
                    onFocusTicket: { focusTicket($0) },
                    onBoard: { board($0) },
                    onOpenDetail: { detailTicket = $0 },
                    onDelete: { deleteTicket($0) }
                )
            }
        }
        .padding(.top, TrainTheme.Space.sm)
    }

    private var focusedBacklogTicket: Ticket? {
        guard let focusedTicketID else { return nil }
        return backlogTickets.first(where: { $0.id == focusedTicketID })
    }

    @ViewBuilder
    private var ticketFocusLayer: some View {
        let inset = MarsTicketSpec.HubStack.horizontalInset
        let isFocusing = focusedTicketID != nil
        let consoleVisible = isFocusing && !cabinIngress

        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(MarsTicketSpec.HubStack.focusDimOpacity))
                .ignoresSafeArea()
                .opacity(isFocusing && !cabinIngress ? 1 : 0)
                .allowsHitTesting(isFocusing && !cabinIngress)
                .onTapGesture(perform: dismissTicketFocus)

            Color.black
                .ignoresSafeArea()
                .opacity(cabinIngress ? 1 : 0)
                .allowsHitTesting(cabinIngress)

            if let ticket = focusedBacklogTicket {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HubMarsTicketCard(ticket: ticket, onSelect: {})
                        .matchedGeometryEffect(
                            id: ticket.id,
                            in: ticketNamespace,
                            properties: .frame,
                            anchor: .center,
                            isSource: true
                        )
                        .padding(.horizontal, inset)
                    Spacer(minLength: MarsTicketSpec.HubStack.focusConsoleLayoutReserve)
                }
                .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HubTicketFocusActions(
                    canBoard: canBoardGenerally,
                    disabledReason: boardDisabledReason,
                    revealed: consoleVisible,
                    onBoard: {
                        if let ticket = focusedBacklogTicket {
                            boardFromFocus(ticket)
                        }
                    },
                    onOpenDetail: {
                        if let ticket = focusedBacklogTicket {
                            openDetailFromFocus(ticket)
                        }
                    }
                )
            }
            .allowsHitTesting(consoleVisible)
        }
    }

    private func focusTicket(_ id: UUID) {
        guard focusedTicketID != id else { return }
        withAnimation(MarsTicketSpec.HubStack.focus) {
            focusedTicketID = id
        }
    }

    private func openDetailFromFocus(_ ticket: Ticket) {
        let id = ticket.id
        withAnimation(MarsTicketSpec.HubStack.focus) {
            focusedTicketID = nil
        }
        let wait = MarsTicketSpec.HubStack.focusMilliseconds
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(wait))
            detailTicket = backlogTickets.first(where: { $0.id == id })
                ?? allTickets.first(where: { $0.id == id })
                ?? ticket
        }
    }

    private func boardFromFocus(_ ticket: Ticket) {
        guard canBoardGenerally else { return }
        withAnimation(MarsTicketSpec.HubStack.cabinIngress) {
            cabinIngress = true
        }
        let ingressMs = MarsTicketSpec.HubStack.cabinIngressMilliseconds
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(ingressMs))
            board(ticket)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                focusedTicketID = nil
                cabinIngress = false
            }
        }
    }

    private func dismissTicketFocus() {
        guard !cabinIngress else { return }
        withAnimation(MarsTicketSpec.HubStack.focus) {
            focusedTicketID = nil
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
            Button {
                detailTicket = ticket
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ticket.title)
                        .font(TrainTheme.TypeScale.ticketTitle())
                        .lineLimit(isLandscapeSplit ? 2 : nil)
                        .foregroundStyle(.primary)
                    Text("残り \(formatRemaining(session))")
                        .font(TrainTheme.TypeScale.meta())
                        .foregroundStyle(TrainTheme.signalAmber)
                        .monospacedDigit()
                    SignalBadge(kind: .paused)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button("再乗車") {
                board(ticket)
            }
            .buttonStyle(.borderedProminent)
            .tint(TrainTheme.rail)
            .disabled(!canBoardGenerally)
            .accessibilityHint(canBoardGenerally ? "停車中の切符を再開" : boardDisabledReason)
        }
        .padding(TrainTheme.Space.md)
        .background(TrainTheme.surface, in: RoundedRectangle(cornerRadius: TrainTheme.Radius.control, style: .continuous))
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
