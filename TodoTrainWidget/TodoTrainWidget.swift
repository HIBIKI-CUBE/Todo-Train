//
//  TodoTrainWidget.swift
//  Todo trainWidget
//
//  Add this folder to a Widget Extension target in Xcode (see README.md).
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
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoTrainEntry>) -> Void) {
        let entry = placeholder(in: context)
        let timeline = Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60)))
        completion(timeline)
    }
}

struct TodoTrainWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
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
            Text(entry.isInService ? "運行中" : "運休")
                .font(.headline)
            Text("停車 \(entry.pausedCount) 件")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
    }

    private var mediumBody: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.isInService ? "運行中" : "運休")
                    .font(.headline)
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
                    .font(.title3.weight(.semibold))
            }
        }
        .padding()
    }
}

@main
struct TodoTrainWidget: Widget {
    let kind = "TodoTrainWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodoTrainProvider()) { entry in
            TodoTrainWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Todo train")
        .description("運行と停車のざっくり状況")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
