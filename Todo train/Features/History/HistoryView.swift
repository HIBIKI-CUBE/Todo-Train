//
//  HistoryView.swift
//  Todo train
//

import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \WorkSession.endedAt, order: .reverse)
    private var sessions: [WorkSession]

    private var groups: [(dayKey: String, sessions: [WorkSession])] {
        HistoryStats.groupByDay(sessions: Array(sessions))
    }

    var body: some View {
        List {
            if groups.isEmpty {
                Text("まだ履歴がありません。発車して到着・途中下車するとここに残ります。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groups, id: \.dayKey) { group in
                    Section {
                        ForEach(group.sessions, id: \.id) { session in
                            HistorySessionRow(session: session)
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
        .navigationTitle("履歴")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    let container = try! AppModelContainer.make(inMemory: true)
    return NavigationStack {
        HistoryView()
            .modelContainer(container)
    }
}
