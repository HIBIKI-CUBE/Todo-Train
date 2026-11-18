//
//  DepartStatusLine.swift
//  Todo train
//
//  DEPART 横の運転状況の行。ただいま板と同じ文言を 10pt の一行に詰める。
//

import SwiftUI

struct DepartStatusLine: View {
    var reading: RunStatusNow
    var isLit: Bool
    var calendar: Calendar = .current

    var body: some View {
        RunStatusNowReadingLine(
            model: reading.displayModel(calendar: calendar),
            layout: .departLine,
            isLit: isLit
        )
        .padding(.horizontal, 5)
    }
}

/// 分が変わるたびに nowReading を取り直して DEPART 横の行を更新する。
struct DepartStatusLineTimeline: View {
    var range: TimetableRange
    var bands: [RunStatusBand]
    var isLit: Bool
    var calendar: Calendar = .current

    var body: some View {
        TimelineView(.periodic(from: .distantPast, by: 60)) { context in
            DepartStatusLine(
                reading: RunStatusLogic.nowReading(now: context.date, range: range, bands: bands),
                isLit: isLit,
                calendar: calendar
            )
        }
    }
}

#if DEBUG
#Preview("DEPART 横 仕様の例") {
    let fixtures = OpeningPanelRunStatusPreviewFixtures.self
    let samples: [(String, RunStatusNow)] = [
        ("08:30", fixtures.reading(hour: 8, minute: 30)),
        ("09:50", fixtures.reading(hour: 9, minute: 50)),
        ("13:10", fixtures.reading(hour: 13, minute: 10)),
        ("17:00", fixtures.reading(hour: 17)),
        ("19:10", fixtures.reading(hour: 19, minute: 10)),
        ("09:30 朝詰", fixtures.reading(hour: 9, minute: 30, packed: true)),
    ]
    return VStack(alignment: .leading, spacing: 8) {
        ForEach(samples, id: \.0) { label, reading in
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                OpeningPanelWindow {
                    DepartStatusLine(reading: reading, isLit: true, calendar: fixtures.utc)
                        .frame(height: OpeningPanelTokens.Chrome.departLineHeight)
                }
                .frame(height: OpeningPanelTokens.Chrome.departLineHeight)
            }
        }
        VStack(alignment: .leading, spacing: 2) {
            Text("消灯")
                .font(.caption)
                .foregroundStyle(.secondary)
            OpeningPanelWindow {
                DepartStatusLine(reading: fixtures.reading(hour: 13, minute: 10), isLit: false, calendar: fixtures.utc)
                    .frame(height: OpeningPanelTokens.Chrome.departLineHeight)
            }
            .frame(height: OpeningPanelTokens.Chrome.departLineHeight)
        }
    }
    .padding()
    .background(OpeningPanelTokens.Palette.housing)
}
#endif