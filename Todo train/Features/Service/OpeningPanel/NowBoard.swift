//
//  NowBoard.swift
//  Todo train
//
//  ただいま板。RunStatusLogic.nowReading の結果をそのまま見せる。
//

import SwiftUI

struct NowBoard: View {
    var reading: RunStatusNow
    var isLit: Bool
    var calendar: Calendar = .current

    var body: some View {
        RunStatusNowReadingLine(
            model: reading.displayModel(calendar: calendar),
            layout: .nowBoard,
            isLit: isLit
        )
        .padding(.horizontal, 8)
    }
}

/// 描画後だけ分で送る。格子そのものは描き直さない。
struct NowBoardClock: View {
    var stage: OpeningPanelTimetableStage
    var board: OpeningTimetableBoard
    var isLit: Bool
    var calendar: Calendar = .current

    var body: some View {
        if stage == .drawn {
            NowBoardTimeline(
                range: board.range,
                bands: board.bands,
                isLit: isLit,
                calendar: calendar
            )
        } else {
            NowBoard(reading: board.reading, isLit: false, calendar: calendar)
        }
    }
}

/// 分が変わるたびに nowReading を取り直してただいま板を更新する。
struct NowBoardTimeline: View {
    var range: TimetableRange
    var bands: [RunStatusBand]
    var isLit: Bool
    var calendar: Calendar = .current

    var body: some View {
        TimelineView(.periodic(from: .distantPast, by: 60)) { context in
            NowBoard(
                reading: RunStatusLogic.nowReading(now: context.date, range: range, bands: bands),
                isLit: isLit,
                calendar: calendar
            )
        }
    }
}

#if DEBUG
#Preview("ただいま板 仕様の例") {
    let fixtures = OpeningPanelRunStatusPreviewFixtures.self
    let samples: [(String, RunStatusNow)] = [
        ("08:30", fixtures.reading(hour: 8, minute: 30)),
        ("09:50", fixtures.reading(hour: 9, minute: 50)),
        ("13:10", fixtures.reading(hour: 13, minute: 10)),
        ("17:00", fixtures.reading(hour: 17)),
        ("19:10", fixtures.reading(hour: 19, minute: 10)),
        ("09:30 朝詰", fixtures.reading(hour: 9, minute: 30, packed: true)),
    ]
    return VStack(alignment: .leading, spacing: 10) {
        ForEach(samples, id: \.0) { label, reading in
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                OpeningPanelWindow {
                    NowBoard(reading: reading, isLit: true, calendar: fixtures.utc)
                        .frame(
                            width: OpeningPanelTokens.Chrome.nowWindow.width,
                            height: OpeningPanelTokens.Chrome.nowWindow.height
                        )
                }
                .frame(
                    width: OpeningPanelTokens.Chrome.nowWindow.width,
                    height: OpeningPanelTokens.Chrome.nowWindow.height
                )
            }
        }
        VStack(alignment: .leading, spacing: 2) {
            Text("消灯")
                .font(.caption)
                .foregroundStyle(.secondary)
            OpeningPanelWindow {
                NowBoard(reading: fixtures.reading(hour: 13, minute: 10), isLit: false, calendar: fixtures.utc)
                    .frame(
                        width: OpeningPanelTokens.Chrome.nowWindow.width,
                        height: OpeningPanelTokens.Chrome.nowWindow.height
                    )
            }
            .frame(
                width: OpeningPanelTokens.Chrome.nowWindow.width,
                height: OpeningPanelTokens.Chrome.nowWindow.height
            )
        }
    }
    .padding()
    .background(OpeningPanelTokens.Palette.housing)
}
#endif