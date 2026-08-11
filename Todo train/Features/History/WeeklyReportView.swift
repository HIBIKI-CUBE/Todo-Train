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
        ZStack {
            PlatformBackground()
            List {
                if groups.isEmpty {
                    Text("週次データはまだありません。")
                        .foregroundStyle(TrainTheme.muted)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(groups, id: \.weekStart) { group in
                        Section {
                            let aggregate = WeeklyReport.aggregate(
                                sessions: group.sessions,
                                weekContaining: group.weekStart
                            )
                            LabeledContent("集中") {
                                Text("\(aggregate.focusMinutes) 分")
                                    .font(.body.monospacedDigit())
                            }
                            LabeledContent("到着") {
                                Text("\(aggregate.arrived) 件")
                            }
                            LabeledContent("途中下車") {
                                Text("\(aggregate.partialDisembark) 件")
                            }
                            LabeledContent("放棄") {
                                Text("\(aggregate.abandoned) 件")
                                    .foregroundStyle(aggregate.abandoned > 0 ? TrainTheme.signalRed : TrainTheme.ink)
                            }
                        } header: {
                            Text(WeeklyReport.weekTitle(for: group.weekStart))
                        }
                        .listRowBackground(Color.white.opacity(0.9))
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("週次レポート")
        .navigationBarTitleDisplayMode(.inline)
        .tint(TrainTheme.rail)
    }
}

#Preview {
    let container = try! AppModelContainer.make(inMemory: true)
    return NavigationStack {
        WeeklyReportView()
            .modelContainer(container)
    }
}
