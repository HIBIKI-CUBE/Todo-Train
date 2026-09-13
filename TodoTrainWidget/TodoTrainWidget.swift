//
//  TodoTrainWidget.swift
//  TodoTrainWidget
//
//  Home Screen Widget — reads App Group snapshot written by SessionManager.
//

import SwiftUI
import WidgetKit

struct TodoTrainEntry: TimelineEntry {
    let date: Date
    let isInService: Bool
    let pausedCount: Int
    let focusMinutesToday: Int
}

struct TodoTrainProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoTrainEntry {
        TodoTrainEntry(date: .now, isInService: true, pausedCount: 1, focusMinutesToday: 42)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodoTrainEntry) -> Void) {
        completion(entry(from: WidgetSnapshotStore.load()) ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoTrainEntry>) -> Void) {
        let entry = entry(from: WidgetSnapshotStore.load())
            ?? TodoTrainEntry(date: .now, isInService: false, pausedCount: 0, focusMinutesToday: 0)
        let timeline = Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60)))
        completion(timeline)
    }

    private func entry(from snapshot: WidgetSnapshotStore.Snapshot?) -> TodoTrainEntry? {
        guard let snapshot else { return nil }
        return TodoTrainEntry(
            date: snapshot.updatedAt,
            isInService: snapshot.isInService,
            pausedCount: snapshot.pausedCount,
            focusMinutesToday: snapshot.focusMinutesToday
        )
    }
}

struct TodoTrainWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: TodoTrainProvider.Entry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumBody
        default:
            smallBody
        }
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(entry.isInService ? "運行中" : "運休")
                    .font(.headline)
            } icon: {
                Image(systemName: "tram.fill")
                    .foregroundStyle(Color("AccentColor"))
            }
            Text("停車 \(entry.pausedCount) 件")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("今日 \(entry.focusMinutesToday) 分")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            Color("AccentColor").opacity(0.12)
        }
    }

    private var mediumBody: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text(entry.isInService ? "運行中" : "運休")
                        .font(.headline)
                } icon: {
                    Image(systemName: "tram.fill")
                        .foregroundStyle(Color("AccentColor"))
                }
                Text("停車 \(entry.pausedCount) 件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("今日")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(entry.focusMinutesToday) 分")
                    .font(.title3.weight(.semibold).monospacedDigit())
            }
        }
        .containerBackground(for: .widget) {
            Color("AccentColor").opacity(0.12)
        }
    }
}

struct TodoTrainHomeWidget: Widget {
    static let kind = WidgetSnapshotStore.homeWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: TodoTrainProvider()) { entry in
            TodoTrainWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Todo train")
        .description("運行と停車のざっくり状況")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
