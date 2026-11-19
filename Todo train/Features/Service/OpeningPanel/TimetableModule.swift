//
//  TimetableModule.swift
//  Todo train
//
//  TIMETABLE。縦の時間割、範囲、AUTO/24H、いまの帯、NEXT。
//  盤の格子への組み込みは後続。このビューが計器一式。
//

import SwiftUI

struct TimetableHourMark: Equatable {
    var hour: Int
    var y: CGFloat
}

struct TimetableRowFrame: Equatable, Identifiable {
    var id: String
    var top: CGFloat
    var bandTop: CGFloat
    var bandHeight: CGFloat

    var rowCenter: CGFloat { top + TimetableColumnLayout.rowHeight / 2 }
    var bandCenter: CGFloat { bandTop + bandHeight / 2 }
}

struct TimetableNowSpan: Equatable {
    var startsAt: Date
    var endsAt: Date
    var insideStop: Bool
}

struct TimetableNextReadout: Equatable {
    var stopText: String
    var rideText: String
    var stopLit: Bool
    var rideLit: Bool

    static let idle = "--:--:--"

    static func make(now: Date, next: RunStatusNext) -> TimetableNextReadout {
        if let target = next.nextRideInTarget {
            return TimetableNextReadout(
                stopText: idle,
                rideText: formatHMS(secondsUntil(target, now: now)),
                stopLit: false,
                rideLit: true
            )
        }
        if let target = next.nextStopInTarget {
            return TimetableNextReadout(
                stopText: formatHMS(secondsUntil(target, now: now)),
                rideText: idle,
                stopLit: true,
                rideLit: false
            )
        }
        return TimetableNextReadout(stopText: idle, rideText: idle, stopLit: false, rideLit: false)
    }

    static func formatHMS(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }

    private static func secondsUntil(_ target: Date, now: Date) -> Int {
        let interval = target.timeIntervalSince(now)
        guard interval > 0 else { return 0 }
        return Int(interval)
    }
}

enum TimetableColumnLayout {
    static let rowHeight: CGFloat = 34
    static let rowGap: CGFloat = 2
    static let overviewWidth: CGFloat = 10
    static let hourWidth: CGFloat = 18
    static let barWidth: CGFloat = 20
    static let leaderWidth: CGFloat = 14

    static var barOrigin: CGFloat { overviewWidth + hourWidth }
    static var rowOrigin: CGFloat { barOrigin + barWidth + leaderWidth }

    static func y(of date: Date, range: TimetableRange, height: CGFloat) -> CGFloat {
        let span = range.endsAt.timeIntervalSince(range.startsAt)
        guard span > 0, height > 0 else { return 0 }
        let fraction = date.timeIntervalSince(range.startsAt) / span
        return CGFloat(fraction) * height
    }

    static func dayFraction(_ date: Date, referenceDay: Date, calendar: Calendar) -> CGFloat {
        let start = calendar.startOfDay(for: referenceDay)
        let elapsed = date.timeIntervalSince(start)
        return CGFloat(min(86_400, max(0, elapsed)) / 86_400)
    }

    static func hourMarks(range: TimetableRange, height: CGFloat, calendar: Calendar) -> [TimetableHourMark] {
        let day = calendar.startOfDay(for: range.startsAt)
        let lower = Int((range.startsAt.timeIntervalSince(day) / 3600).rounded())
        let upper = Int((range.endsAt.timeIntervalSince(day) / 3600).rounded())
        let span = max(upper - lower, 1)
        let step = height / CGFloat(span) < 18 ? 2 : 1
        var marks: [TimetableHourMark] = []
        var hour = lower
        while hour <= upper {
            let date = calendar.date(byAdding: .hour, value: hour, to: day) ?? range.startsAt
            marks.append(TimetableHourMark(hour: hour, y: y(of: date, range: range, height: height)))
            hour += step
        }
        if marks.last?.hour != upper {
            let date = calendar.date(byAdding: .hour, value: upper, to: day) ?? range.endsAt
            marks.append(TimetableHourMark(hour: upper, y: y(of: date, range: range, height: height)))
        }
        return marks
    }

    static func clock(_ date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }

    /// 行は帯の中央。重なるときは下へ押し、下端から上へ戻して間隔を空ける。
    static func rowFrames(
        entries: [OpeningTimetableEntry],
        range: TimetableRange,
        height: CGFloat
    ) -> [TimetableRowFrame] {
        let sorted = entries.sorted { lhs, rhs in
            if lhs.startsAt != rhs.startsAt { return lhs.startsAt < rhs.startsAt }
            if lhs.endsAt != rhs.endsAt { return lhs.endsAt < rhs.endsAt }
            return lhs.id < rhs.id
        }
        let maxTop = max(0, height - rowHeight)
        let stride = rowHeight + rowGap
        var tops: [CGFloat] = sorted.map { entry in
            let center = bandCenter(of: entry, range: range, height: height)
            return min(maxTop, max(0, center - rowHeight / 2))
        }
        if tops.count > 1 {
            for index in 1..<tops.count {
                tops[index] = max(tops[index], tops[index - 1] + stride)
            }
            for index in tops.indices.reversed() {
                let limit = index == tops.count - 1 ? maxTop : tops[index + 1] - stride
                tops[index] = min(tops[index], limit)
            }
        }
        return zip(sorted, tops).map { entry, top in
            let start = y(of: entry.startsAt, range: range, height: height)
            let end = y(of: entry.endsAt, range: range, height: height)
            return TimetableRowFrame(
                id: entry.id,
                top: top,
                bandTop: min(start, end),
                bandHeight: max(2, abs(end - start))
            )
        }
    }

    static func nowSpan(now: Date, range: TimetableRange, next: RunStatusNext) -> TimetableNowSpan? {
        guard range.endsAt > range.startsAt, now < range.endsAt else { return nil }
        let visibleStart = max(now, range.startsAt)
        let rawEnd: Date
        let inside: Bool
        if let rideEnd = next.nextRideInTarget {
            rawEnd = rideEnd
            inside = true
        } else if let stopStart = next.nextStopInTarget {
            rawEnd = stopStart
            inside = false
        } else {
            rawEnd = range.endsAt
            inside = false
        }
        let visibleEnd = min(range.endsAt, max(rawEnd, visibleStart))
        guard visibleEnd > visibleStart else { return nil }
        return TimetableNowSpan(startsAt: visibleStart, endsAt: visibleEnd, insideStop: inside)
    }

    private static func bandCenter(
        of entry: OpeningTimetableEntry,
        range: TimetableRange,
        height: CGFloat
    ) -> CGFloat {
        let start = y(of: entry.startsAt, range: range, height: height)
        let end = y(of: entry.endsAt, range: range, height: height)
        return (start + end) / 2
    }
}

/// 運行開始の盤の TIMETABLE。起動の段番号で充填・IN TEST・描画を分ける。
struct TimetableModule: View {
    var stage: OpeningPanelTimetableStage
    var board: OpeningTimetableBoard
    var now: Date
    var calendar: Calendar = .current
    var onScaleToggle: () -> Void = {}
    var onToggleEntry: (OpeningTimetableEntry) -> Void = { _ in }

    private var stageNumber: Int { stage.stageNumber }

    private var isDrawn: Bool {
        stageNumber == OpeningPanelTiming.timetableFillCount + 2
    }

    var body: some View {
        VStack(spacing: 3) {
            header
            chartRow
            footer
        }
        .padding(EdgeInsets(top: 6, leading: 8, bottom: 5, trailing: 6))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("TIMETABLE")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("TIMETABLE")
                .font(OpeningPanelFaceFont.legend(8))
                .tracking(0.4)
                .foregroundStyle(OpeningPanelTokens.Palette.legend)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(OpeningPanelTokens.Palette.strip, in: RoundedRectangle(cornerRadius: 1))
            TimetableScaleToggle(isTwentyFourHour: board.isTwentyFourHour, action: onScaleToggle)
            Spacer(minLength: 0)
            OpeningPanelWindow(label: isDrawn ? board.range.windowLabel : "範囲") {
                Text(isDrawn ? board.range.windowLabel : "")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(OpeningPanelTokens.TimetableChrome.amberSolid)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(
                width: OpeningPanelTokens.Chrome.rangeWindow.width,
                height: OpeningPanelTokens.Chrome.rangeWindow.height
            )
            Text("運転状況")
                .font(OpeningPanelFaceFont.legend(8))
                .tracking(0.4)
                .foregroundStyle(OpeningPanelTokens.Palette.legend)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(OpeningPanelTokens.Palette.strip, in: RoundedRectangle(cornerRadius: 1))
                .frame(width: OpeningPanelTokens.RunStatus.width)
        }
        .frame(height: 22)
    }

    /// 充填は時刻表の窓だけ。運転状況の列は描画まで空のままにする。
    private var chartRow: some View {
        GeometryReader { geo in
            let statusWidth = OpeningPanelTokens.RunStatus.width
            let gap = OpeningPanelTokens.RunStatus.columnGap
            let timetableWidth = max(0, geo.size.width - gap - statusWidth)
            HStack(alignment: .top, spacing: gap) {
                TimetableWell {
                    timetableFace
                }
                .frame(width: timetableWidth, height: geo.size.height)
                .clipped()
                TimetableWell {
                    if isDrawn {
                        RunStatusColumn(
                            bands: board.bands,
                            range: board.range,
                            now: now,
                            reading: board.reading
                        )
                        .padding(.horizontal, OpeningPanelTokens.RunStatus.horizontalInset)
                        .padding(.vertical, OpeningPanelTokens.RunStatus.verticalInset)
                    }
                }
                .frame(width: statusWidth, height: geo.size.height)
                .clipped()
            }
        }
    }

    @ViewBuilder
    private var timetableFace: some View {
        if stageNumber >= 1 && stageNumber <= OpeningPanelTiming.timetableFillCount {
            TimetableFill(fraction: CGFloat(stageNumber) / CGFloat(OpeningPanelTiming.timetableFillCount))
        } else if stageNumber == OpeningPanelTiming.timetableFillCount + 1 {
            Text("IN TEST")
                .font(.system(size: 11, weight: .medium))
                .tracking(2.2)
                .foregroundStyle(OpeningPanelTokens.TimetableChrome.amberSolid)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isDrawn {
            TimetableTape(
                entries: board.entries,
                range: board.range,
                next: board.next,
                now: now,
                calendar: calendar,
                onToggleEntry: onToggleEntry
            )
            .padding(.vertical, OpeningPanelTokens.RunStatus.verticalInset)
        } else {
            Color.clear
        }
    }

    private var footer: some View {
        let readout = TimetableNextReadout.make(now: now, next: board.next)
        return HStack(spacing: 10) {
            TimetableNextWindow(
                title: "NEXT STOP IN",
                text: isDrawn ? readout.stopText : TimetableNextReadout.idle,
                lit: isDrawn && readout.stopLit
            )
            TimetableNextWindow(
                title: "NEXT RIDE IN",
                text: isDrawn ? readout.rideText : TimetableNextReadout.idle,
                lit: isDrawn && readout.rideLit
            )
            Spacer(minLength: 0)
        }
        .frame(height: OpeningPanelTokens.Chrome.timetableKeySize.height)
    }
}

private struct TimetableWell<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: OpeningPanelTokens.Chrome.windowRadius)
                .fill(OpeningPanelTokens.Palette.window)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay {
            RoundedRectangle(cornerRadius: OpeningPanelTokens.Chrome.windowRadius)
                .strokeBorder(OpeningPanelTokens.Palette.windowEdge, lineWidth: 1)
        }
    }
}

private struct TimetableScaleToggle: View {
    var isTwentyFourHour: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(OpeningPanelTokens.Palette.hex(0x2E3033))
                    Rectangle()
                        .fill(OpeningPanelTokens.Palette.hex(0x1D1E20))
                        .frame(height: 1)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(OpeningPanelTokens.Palette.hex(0x8A8E92))
                        .frame(width: 6, height: 9)
                        .offset(x: 3, y: isTwentyFourHour ? 11 : 2)
                }
                .frame(width: 12, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text("AUTO")
                        .foregroundStyle(label(active: !isTwentyFourHour))
                    Text("24H")
                        .foregroundStyle(label(active: isTwentyFourHour))
                }
                .font(OpeningPanelFaceFont.legend(8))
                .tracking(0.4)
            }
        }
        .buttonStyle(.plain)
        .openingPanelAction(.scaleToggle, perform: action)
        .contentShape(Rectangle())
        .accessibilityLabel(isTwentyFourHour ? "24時間" : "自動")
        .accessibilityHint("表示範囲を切り替えます")
    }

    private func label(active: Bool) -> Color {
        active ? OpeningPanelTokens.TimetableChrome.amberSolid : OpeningPanelTokens.TimetableChrome.nextIdle
    }
}

private struct TimetableFill: View {
    var fraction: CGFloat

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(OpeningPanelTokens.TimetableChrome.fill)
                .frame(width: geo.size.width, height: geo.size.height * fraction)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .accessibilityHidden(true)
    }
}

private struct TimetableNextWindow: View {
    var title: String
    var text: String
    var lit: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(lit ? OpeningPanelTokens.TimetableChrome.amberSolid : OpeningPanelTokens.TimetableChrome.nextIdle)
                .lineLimit(1)
            OpeningPanelWindow(label: "\(title) \(text)") {
                Text(text)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(lit ? OpeningPanelTokens.TimetableChrome.amberSolid : OpeningPanelTokens.TimetableChrome.nextIdle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(
                width: OpeningPanelTokens.Chrome.nextWindow.width,
                height: OpeningPanelTokens.Chrome.nextWindow.height
            )
        }
    }
}

private struct TimetableTape: View {
    @Environment(\.openingPanelHitMinimum) private var hitMinimum
    var entries: [OpeningTimetableEntry]
    var range: TimetableRange
    var next: RunStatusNext
    var now: Date
    var calendar: Calendar
    var onToggleEntry: (OpeningTimetableEntry) -> Void

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let width = geo.size.width
            let frames = TimetableColumnLayout.rowFrames(entries: entries, range: range, height: height)
            let framesByID = Dictionary(uniqueKeysWithValues: frames.map { ($0.id, $0) })
            let hits = OpeningPanelHitLayout.timetable(
                entries: entries,
                range: range,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                minimum: hitMinimum
            )
            ZStack(alignment: .topLeading) {
                DayOverview(entries: entries, range: range, calendar: calendar)
                    .frame(width: TimetableColumnLayout.overviewWidth, height: height)
                hourRail(height: height)
                timeBar(frames: frames, height: height)
                nowBand(height: height, width: width)
                leaders(frames: frames, width: width, height: height)
                rows(framesByID: framesByID, width: width, height: height)
                timetableHits(hits)
            }
            .frame(width: width, height: height)
            .clipped()
        }
    }

    private func timetableHits(_ hits: [OpeningPanelHitLayout.Target]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(hits) { hit in
                Color.clear
                    .frame(width: hit.hit.width, height: hit.hit.height)
                    .contentShape(Rectangle())
                    .position(x: hit.hit.midX, y: hit.hit.midY)
                    .onTapGesture {
                        guard let entry = entries.first(where: { $0.id == hit.id.entryID }) else { return }
                        onToggleEntry(entry)
                    }
                    .accessibilityHidden(true)
            }
        }
    }

    private func hourRail(height: CGFloat) -> some View {
        let marks = TimetableColumnLayout.hourMarks(range: range, height: height, calendar: calendar)
        return ZStack(alignment: .topLeading) {
            ForEach(marks, id: \.hour) { mark in
                Text(String(format: "%02d", mark.hour))
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(OpeningPanelTokens.TimetableChrome.hourLabel)
                    .position(
                        x: TimetableColumnLayout.overviewWidth + TimetableColumnLayout.hourWidth / 2,
                        y: min(height - 4, max(4, mark.y))
                    )
            }
        }
        .frame(width: TimetableColumnLayout.barOrigin, height: height)
        .accessibilityHidden(true)
    }

    private func timeBar(frames: [TimetableRowFrame], height: CGFloat) -> some View {
        let marks = TimetableColumnLayout.hourMarks(range: range, height: height, calendar: calendar)
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0x22 / 255, green: 0x23 / 255, blue: 0x24 / 255))
            ForEach(marks, id: \.hour) { mark in
                Rectangle()
                    .fill(OpeningPanelTokens.TimetableChrome.hourLine)
                    .frame(height: 1)
                    .offset(y: mark.y)
            }
            ForEach(entries) { entry in
                if let frame = frames.first(where: { $0.id == entry.id }) {
                    Button {
                        onToggleEntry(entry)
                    } label: {
                        entryBand(entry)
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(false)
                    .frame(width: TimetableColumnLayout.barWidth, height: frame.bandHeight)
                    .position(
                        x: TimetableColumnLayout.barWidth / 2,
                        y: frame.bandCenter
                    )
                    .accessibilityLabel(rowSpoken(entry))
                    .accessibilityHint("この予定の着発と通過を切り替えます")
                }
            }
        }
        .frame(width: TimetableColumnLayout.barWidth, height: height)
        .offset(x: TimetableColumnLayout.barOrigin)
    }

    private func entryBand(_ entry: OpeningTimetableEntry) -> some View {
        Rectangle()
            .fill(entry.stops ? OpeningPanelTokens.TimetableChrome.adoptedBand : Color.clear)
            .overlay {
                if !entry.stops {
                    Rectangle()
                        .strokeBorder(OpeningPanelTokens.TimetableChrome.passingEdge, lineWidth: 1)
                }
            }
    }

    private func nowBand(height: CGFloat, width: CGFloat) -> some View {
        let span = TimetableColumnLayout.nowSpan(now: now, range: range, next: next)
        return ZStack(alignment: .topLeading) {
            if let span {
                let top = TimetableColumnLayout.y(of: span.startsAt, range: range, height: height)
                let bottom = TimetableColumnLayout.y(of: span.endsAt, range: range, height: height)
                let bandHeight = max(1, bottom - top)
                let bandWidth = max(0, width - TimetableColumnLayout.overviewWidth)
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(OpeningPanelTokens.TimetableChrome.nowBand)
                    if span.insideStop {
                        TimetableNowHatch()
                    }
                    Rectangle()
                        .fill(OpeningPanelTokens.TimetableChrome.nowBandEdge)
                        .frame(height: 1)
                }
                .frame(width: bandWidth, height: bandHeight)
                .position(
                    x: TimetableColumnLayout.overviewWidth + bandWidth / 2,
                    y: top + bandHeight / 2
                )
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func leaders(frames: [TimetableRowFrame], width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, _ in
            for frame in frames {
                var path = Path()
                let fromX = TimetableColumnLayout.barOrigin + TimetableColumnLayout.barWidth
                let toX = TimetableColumnLayout.rowOrigin
                path.move(to: CGPoint(x: fromX, y: frame.bandCenter))
                path.addLine(to: CGPoint(x: fromX + 4, y: frame.bandCenter))
                path.addLine(to: CGPoint(x: toX - 4, y: frame.rowCenter))
                path.addLine(to: CGPoint(x: toX, y: frame.rowCenter))
                context.stroke(
                    path,
                    with: .color(OpeningPanelTokens.TimetableChrome.leader),
                    lineWidth: 1
                )
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func rows(framesByID: [String: TimetableRowFrame], width: CGFloat, height: CGFloat) -> some View {
        let rowWidth = max(0, width - TimetableColumnLayout.rowOrigin)
        return ZStack(alignment: .topLeading) {
            ForEach(entries) { entry in
                if let frame = framesByID[entry.id] {
                    Button {
                        onToggleEntry(entry)
                    } label: {
                        rowContents(entry)
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(false)
                    .contentShape(Rectangle())
                    .frame(width: rowWidth, height: TimetableColumnLayout.rowHeight)
                    .position(
                        x: TimetableColumnLayout.rowOrigin + rowWidth / 2,
                        y: frame.rowCenter
                    )
                    .accessibilityLabel(rowSpoken(entry))
                    .accessibilityHint("この予定の着発と通過を切り替えます")
                }
            }
        }
        .frame(width: width, height: height)
    }

    private func rowContents(_ entry: OpeningTimetableEntry) -> some View {
        HStack(spacing: 4) {
            StopMark(stops: entry.stops)
            Text(TimetableColumnLayout.clock(entry.startsAt, calendar: calendar))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(OpeningPanelTokens.TimetableChrome.rowTime)
                .frame(width: 36, alignment: .leading)
            Text(entry.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(OpeningPanelTokens.TimetableChrome.amberSolid)
                .opacity(entry.stops ? 1 : 0.8)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.trailing, 2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(OpeningPanelTokens.TimetableChrome.rowLine)
                .frame(height: 1)
        }
    }

    private func rowSpoken(_ entry: OpeningTimetableEntry) -> String {
        let mark = entry.stops ? "着" : "通"
        let time = TimetableColumnLayout.clock(entry.startsAt, calendar: calendar)
        return "\(mark) \(time) \(entry.title)"
    }
}

private struct StopMark: View {
    var stops: Bool

    var body: some View {
        Text(stops ? "着" : "通")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(
                stops
                    ? OpeningPanelTokens.TimetableChrome.markInk
                    : OpeningPanelTokens.TimetableChrome.amberSolid
            )
            .frame(width: 12, height: 12)
            .background {
                if stops {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(OpeningPanelTokens.TimetableChrome.amberSolid)
                }
            }
            .overlay {
                if !stops {
                    RoundedRectangle(cornerRadius: 1)
                        .strokeBorder(OpeningPanelTokens.TimetableChrome.amberSolid, lineWidth: 1)
                }
            }
            .accessibilityHidden(true)
    }
}

private struct DayOverview: View {
    var entries: [OpeningTimetableEntry]
    var range: TimetableRange
    var calendar: Calendar

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            ZStack(alignment: .topLeading) {
                ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                    Rectangle()
                        .fill(OpeningPanelTokens.TimetableChrome.overviewTrack)
                        .frame(width: 4, height: 1)
                        .position(x: 2, y: CGFloat(hour) / 24 * height)
                }
                ForEach(entries) { entry in
                    let top = fraction(entry.startsAt) * height
                    let bottom = fraction(entry.endsAt) * height
                    let markHeight = max(1, bottom - top)
                    Rectangle()
                        .fill(entry.stops ? OpeningPanelTokens.TimetableChrome.amberSolid : Color.clear)
                        .overlay {
                            if !entry.stops {
                                Rectangle()
                                    .strokeBorder(OpeningPanelTokens.TimetableChrome.passingEdge, lineWidth: 1)
                            }
                        }
                        .frame(width: 4, height: markHeight)
                        .position(x: 6, y: top + markHeight / 2)
                }
                rangeBracket(height: height)
            }
        }
        .accessibilityHidden(true)
    }

    private func rangeBracket(height: CGFloat) -> some View {
        let top = fraction(range.startsAt) * height
        let bottom = fraction(range.endsAt) * height
        return Path { path in
            path.move(to: CGPoint(x: 1, y: top))
            path.addLine(to: CGPoint(x: 9, y: top))
            path.addLine(to: CGPoint(x: 9, y: bottom))
            path.addLine(to: CGPoint(x: 1, y: bottom))
        }
        .stroke(OpeningPanelTokens.TimetableChrome.amberSolid, lineWidth: 1)
    }

    private func fraction(_ date: Date) -> CGFloat {
        TimetableColumnLayout.dayFraction(date, referenceDay: range.startsAt, calendar: calendar)
    }
}

private struct TimetableNowHatch: View {
    var body: some View {
        Canvas { context, size in
            var x = -size.height
            while x < size.width + size.height {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(
                    path,
                    with: .color(OpeningPanelTokens.TimetableChrome.nowBandHatch),
                    lineWidth: 3
                )
                x += 6
            }
        }
        .allowsHitTesting(false)
    }
}

#if DEBUG
private struct TimetableModulePreview: View {
    var now: Date
    var packed: Bool
    var stage: OpeningPanelTimetableStage
    @State private var twentyFour: Bool
    @State private var entries: [OpeningTimetableEntry]

    init(
        now: Date,
        packed: Bool = false,
        stage: OpeningPanelTimetableStage = .drawn,
        twentyFour: Bool = false
    ) {
        self.now = now
        self.packed = packed
        self.stage = stage
        _twentyFour = State(initialValue: twentyFour)
        _entries = State(initialValue: packed ? Self.packedEntries : Self.standardEntries)
    }

    var body: some View {
        let frame = OpeningPanelTokens.Module.timetable.frame()
        let board = OpeningTimetableBoard.make(
            entries: entries,
            now: now,
            isTwentyFourHour: twentyFour,
            referenceDay: OpeningPanelRunStatusPreviewFixtures.dayStart,
            ticketsAboveCutoff: [],
            calendar: OpeningPanelRunStatusPreviewFixtures.utc
        )
        OpeningPanelModule(tone: .standard) {
            TimetableModule(
                stage: stage,
                board: board,
                now: now,
                calendar: OpeningPanelRunStatusPreviewFixtures.utc,
                onScaleToggle: { twentyFour.toggle() },
                onToggleEntry: { entry in
                    entries = entries.map { $0.id == entry.id ? toggled(entry) : $0 }
                }
            )
        }
        .frame(width: frame.width, height: frame.height)
        .background(OpeningPanelTokens.Palette.housing)
    }

    private func toggled(_ entry: OpeningTimetableEntry) -> OpeningTimetableEntry {
        var copy = entry
        switch entry.kind {
        case .stop(let blockID):
            copy.kind = .passManual(blockID: blockID)
        case .passManual(let blockID):
            copy.kind = .stop(blockID: blockID)
        case .passNotice:
            break
        }
        return copy
    }

    private static let standardEntries: [OpeningTimetableEntry] = [
        entry("朝会", "00000000-0000-0000-0000-000000000001", 9, 30, 9, 45, stops: true),
        entry("定例ミーティング", "00000000-0000-0000-0000-000000000002", 10, 0, 11, 0, stops: true),
        entry("電話", "00000000-0000-0000-0000-000000000003", 13, 0, 13, 30, stops: false),
        entry("歯医者", "00000000-0000-0000-0000-000000000004", 16, 30, 18, 30, stops: true),
    ]

    private static let packedEntries: [OpeningTimetableEntry] = [
        entry("メール確認", "00000000-0000-0000-0000-000000000011", 8, 0, 8, 15, stops: true),
        entry("朝会", "00000000-0000-0000-0000-000000000012", 8, 15, 8, 30, stops: true),
        entry("電話", "00000000-0000-0000-0000-000000000013", 8, 45, 9, 0, stops: false),
        entry("定例ミーティング", "00000000-0000-0000-0000-000000000014", 9, 0, 10, 0, stops: true),
        entry("レビュー", "00000000-0000-0000-0000-000000000015", 10, 0, 10, 20, stops: true),
        entry("資料作成", "00000000-0000-0000-0000-000000000016", 10, 30, 11, 30, stops: false),
    ]

    private static func entry(
        _ title: String,
        _ id: String,
        _ startHour: Int,
        _ startMinute: Int,
        _ endHour: Int,
        _ endMinute: Int,
        stops: Bool
    ) -> OpeningTimetableEntry {
        let blockID = UUID(uuidString: id) ?? UUID()
        return OpeningTimetableEntry(
            kind: stops ? .stop(blockID: blockID) : .passManual(blockID: blockID),
            title: title,
            startsAt: OpeningPanelRunStatusPreviewFixtures.at(hour: startHour, minute: startMinute),
            endsAt: OpeningPanelRunStatusPreviewFixtures.at(hour: endHour, minute: endMinute)
        )
    }
}

#Preview("08:30 始発前") {
    TimetableModulePreview(now: OpeningPanelRunStatusPreviewFixtures.at(hour: 8, minute: 30))
}

#Preview("09:50 過密") {
    TimetableModulePreview(now: OpeningPanelRunStatusPreviewFixtures.at(hour: 9, minute: 50))
}

#Preview("13:10 平常運転") {
    TimetableModulePreview(now: OpeningPanelRunStatusPreviewFixtures.at(hour: 13, minute: 10))
}

#Preview("17:00 見合せ") {
    TimetableModulePreview(now: OpeningPanelRunStatusPreviewFixtures.at(hour: 17))
}

#Preview("19:10 運転終了") {
    TimetableModulePreview(now: OpeningPanelRunStatusPreviewFixtures.at(hour: 19, minute: 10))
}

#Preview("09:30 朝詰まり") {
    TimetableModulePreview(
        now: OpeningPanelRunStatusPreviewFixtures.at(hour: 9, minute: 30),
        packed: true
    )
}

#Preview("13:10 24H") {
    TimetableModulePreview(
        now: OpeningPanelRunStatusPreviewFixtures.at(hour: 13, minute: 10),
        twentyFour: true
    )
}

#Preview("充填 6") {
    TimetableModulePreview(
        now: OpeningPanelRunStatusPreviewFixtures.at(hour: 13, minute: 10),
        stage: .fill(6)
    )
}

#Preview("IN TEST") {
    TimetableModulePreview(
        now: OpeningPanelRunStatusPreviewFixtures.at(hour: 13, minute: 10),
        stage: .inTest
    )
}
#endif
