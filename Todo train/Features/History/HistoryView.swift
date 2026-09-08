//
//  HistoryView.swift
//  Todo train
//

import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionManager.self) private var sessionManager
    @Environment(DeletionUndoCenter.self) private var undoCenter
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @Query(sort: \WorkSession.endedAt, order: .reverse)
    private var sessions: [WorkSession]

    @State private var searchText = ""
    @State private var errorMessage = ""
    @State private var showError = false

    private var endedSessions: [WorkSession] {
        sessions.filter { $0.endedAt != nil }
    }

    private var filteredSessions: [WorkSession] {
        HistorySearch.filter(sessions: endedSessions, query: searchText)
    }

    private var groups: [(dayKey: String, sessions: [WorkSession])] {
        HistoryStats.groupByDay(sessions: filteredSessions)
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if filteredSessions.isEmpty {
                ContentUnavailableView {
                    Label(
                        isSearching ? "一致する履歴がありません" : "まだ履歴がありません",
                        systemImage: isSearching ? "magnifyingglass" : "clock"
                    )
                } description: {
                    Text(
                        isSearching
                            ? "別の切符名で検索してみてください。"
                            : "発車して到着・途中下車するとここに残ります。"
                    )
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups, id: \.dayKey) { group in
                            Section {
                                HistoryDayClockView(
                                    sessions: group.sessions,
                                    onReissue: reissue,
                                    onDelete: deleteSession
                                )
                                .padding(.horizontal, TrainTheme.Space.md)
                                .padding(.bottom, TrainTheme.Space.xl)
                            } header: {
                                DailyStatsHeader(
                                    dayKey: group.dayKey,
                                    aggregate: HistoryStats.aggregate(sessions: group.sessions)
                                )
                                .textCase(nil)
                                .padding(.horizontal, TrainTheme.Space.md)
                                .padding(.vertical, TrainTheme.Space.sm)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(TrainTheme.platform)
                            }
                        }
                    }
                }
                .background(TrainTheme.platform)
            }
        }
        .navigationTitle("履歴")
        .navigationBarTitleDisplayMode(
            TrainLayout.navigationBarTitleDisplayMode(verticalSizeClass: verticalSizeClass)
        )
        .searchable(text: $searchText, prompt: "切符名で検索")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    WeeklyReportView()
                } label: {
                    Text("週次")
                }
            }
        }
        .errorAlert(isPresented: $showError, message: errorMessage)
    }

    private func deleteSession(_ session: WorkSession) {
        let title = session.ticket?.title ?? "不明な切符"
        let remainingIDs = session.ticket?.sessions.map(\.id) ?? [session.id]
        let deletesTicket = TicketDeletion.shouldDeleteOrphanTicket(
            remainingSessionIDs: remainingIDs,
            removing: session.id
        )
        do {
            if deletesTicket, let ticket = session.ticket {
                let record = DeletionUndo.captureTicket(ticket)
                try sessionManager.deleteEndedSession(session)
                undoCenter.offer(
                    message: DeletionUndo.bannerMessage(
                        historyTicketTitle: title,
                        deletedTicketToo: true
                    )
                ) {
                    withAnimation {
                        try? sessionManager.restoreDeletedTicket(record)
                    }
                }
            } else {
                let record = DeletionUndo.captureSession(session)
                try sessionManager.deleteEndedSession(session)
                undoCenter.offer(
                    message: DeletionUndo.bannerMessage(
                        historyTicketTitle: title,
                        deletedTicketToo: false
                    )
                ) {
                    withAnimation {
                        try? sessionManager.restoreDeletedSession(record)
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func reissue(from ticket: Ticket) {
        let nextOrder = nextSortOrder()
        let copy = TicketReissue.makeTodayCopy(from: ticket, sortOrder: nextOrder)
        modelContext.insert(copy)
        try? modelContext.save()
    }

    private func nextSortOrder() -> Int {
        let descriptor = FetchDescriptor<Ticket>(
            predicate: #Predicate { $0.closedAt == nil },
            sortBy: [SortDescriptor(\.sortOrder, order: .reverse)]
        )
        let maxOrder = (try? modelContext.fetch(descriptor).first?.sortOrder) ?? -1
        return maxOrder + 1
    }
}

#Preview {
    let container = try! AppModelContainer.make(inMemory: true)
    HistoryPreviewSeed.insertSampleDay(into: container.mainContext)
    let manager = SessionManager(modelContext: container.mainContext)
    return NavigationStack {
        HistoryView()
            .environment(manager)
            .environment(DeletionUndoCenter())
            .modelContainer(container)
    }
}
