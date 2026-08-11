//
//  WeeklyReportView.swift
//  Todo train
//

import SwiftUI
import SwiftData

struct WeeklyReportView: View {
    @Query(sort: \WorkSession.endedAt, order: .reverse)
    private var sessions: [WorkSession]

    private var groups: [(weekStart: Date, sessions: [WorkSession])] {
        WeeklyReport.groupByWeek(sessions: Array(sessions))
    }

    var body: some View {
        List {
            if groups.isEmpty {
                Text("週次データはまだありません。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groups, id: \.weekStart) { group in
                    Section {
                        let aggregate = WeeklyReport.aggregate(
                            sessions: group.sessions,
                            weekContaining: group.weekStart
                        )
                        LabeledContent("集中") {
                            Text("\(aggregate.focusMinutes) 分")
                        }
                        LabeledContent("到着") {
                            Text("\(aggregate.arrived) 件")
                        }
                        LabeledContent("途中下車") {
                            Text("\(aggregate.partialDisembark) 件")
                        }
                        LabeledContent("放棄") {
                            Text("\(aggregate.abandoned) 件")
                        }
                    } header: {
                        Text(WeeklyReport.weekTitle(for: group.weekStart))
                    }
                }
            }
        }
        .navigationTitle("週次レポート")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    let container = try! AppModelContainer.make(inMemory: true)
    return NavigationStack {
        WeeklyReportView()
            .modelContainer(container)
    }
}
