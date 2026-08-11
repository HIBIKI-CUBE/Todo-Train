//
//  HistoryView.swift
//  Todo train
//

import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \WorkSession.endedAt, order: .reverse)
    private var sessions: [WorkSession]

    @State private var searchText = ""

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
        ZStack {
            PlatformBackground()
            List {
                if filteredSessions.isEmpty {
                    Text(isSearching
                        ? "一致する履歴がありません。"
                        : "まだ履歴がありません。発車して到着・途中下車するとここに残ります。")
                        .foregroundStyle(TrainTheme.muted)
                        .listRowBackground(Color.clear)
                } else if isSearching {
                    ForEach(filteredSessions, id: \.id) { session in
                        HistorySessionRow(session: session, onReissue: reissue)
                            .listRowBackground(Color.white.opacity(0.88))
                    }
                } else {
                    ForEach(groups, id: \.dayKey) { group in
                        Section {
                            ForEach(group.sessions, id: \.id) { session in
                                HistorySessionRow(session: session, onReissue: reissue)
                                    .listRowBackground(Color.white.opacity(0.88))
                            }
                        } header: {
                            DailyStatsHeader(
                                dayKey: group.dayKey,
                                aggregate: HistoryStats.aggregate(sessions: group.sessions)
                            )
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("履歴")
        .navigationBarTitleDisplayMode(.inline)
        .tint(TrainTheme.rail)
        .searchable(text: $searchText, prompt: "切符名で検索")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("週次") {
                    WeeklyReportView()
                }
            }
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
    return NavigationStack {
        HistoryView()
            .modelContainer(container)
    }
}
