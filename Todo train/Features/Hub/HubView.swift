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
            PlatformBackground()

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
                                            .foregroundStyle(TrainTheme.ink)
                                        Text("残り \(formatRemaining(session))")
                                            .font(TrainTheme.TypeScale.meta())
                                            .foregroundStyle(TrainTheme.signalAmber)
                                            .monospacedDigit()
                                    }
                                    Spacer()
                                    Button("再開") {
                                        board(ticket)
                                    }
                                    .buttonStyle(DepartButtonStyle(enabled: canBoardGenerally))
                                    .disabled(!canBoardGenerally)
                                }
                                .ticketSurface(emphasized: true)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowBackground(Color.clear)
                            }
                        }
                    } header: {
                        sectionHeader("停車中", accent: TrainTheme.signalAmber)
                    }
                }

                Section {
                    if openTickets.isEmpty {
                        VStack(alignment: .leading, spacing: TrainTheme.Space.sm) {
                            Text("切符がありません")
                                .font(TrainTheme.TypeScale.ticketTitle())
                                .foregroundStyle(TrainTheme.ink)
                            Text("右下の ＋ から掃き出しましょう。")
                                .font(.subheadline)
                                .foregroundStyle(TrainTheme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .ticketSurface()
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(openTickets, id: \.id) { ticket in
                            TicketCardView(
                                ticket: ticket,
                                isPaused: isPaused(ticket),
                                canBoard: canBoardGenerally,
                                onBoard: { board(ticket) }
                            )
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                        }
                        .onMove(perform: moveTickets)
                    }
                } header: {
                    sectionHeader("切符", accent: TrainTheme.rail)
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)

            if !showQuickAdd {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        TrainFAB {
                            withAnimation(TrainTheme.Motion.spring) {
                                showQuickAdd = true
                            }
                        }
                        .padding(20)
                    }
                }
            }

            if showQuickAdd {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(TrainTheme.Motion.soft) {
                            showQuickAdd = false
                        }
                    }

                QuickAddBar(isPresented: $showQuickAdd)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle("Todo train")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(TrainTheme.platform.opacity(0.92), for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink("タグ") {
                    TagManagerView()
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink("並べ替え") {
                    ReorderView()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
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
        .tint(TrainTheme.rail)
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

    private func sectionHeader(_ title: String, accent: Color) -> some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(accent)
                .frame(width: 3, height: 12)
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(TrainTheme.muted)
                .textCase(nil)
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
