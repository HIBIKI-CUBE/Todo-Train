//
//  HistoryCanvasZoom.swift
//  Todo train
//
//  Horizontal pinch maps to days-per-screen. Vertical hour scale stays 2pt/min.
//

import CoreGraphics
import Foundation

enum HistoryRideDensity: Equatable, Sendable {
    case day
    case compact
    case week

    init(daysVisible: CGFloat) {
        if daysVisible < 1.85 {
            self = .day
        } else if daysVisible < 4.5 {
            self = .compact
        } else {
            self = .week
        }
    }

    var showsStatsHeader: Bool { self == .day }
    /// Sliding day identity on the canvas so empty↔empty paging still has on-screen motion.
    var showsColumnHeader: Bool { true }
    var showsBadge: Bool { self == .day }
    var showsTimeRange: Bool { self == .day }
    var showsStartTimeOnly: Bool { self == .compact }
    var showsGhost: Bool { self == .day }
    var showsScheduleHairline: Bool { self == .day }
    var showsPauseBands: Bool { self != .week }
    var showsHalfHourLines: Bool { self == .day }
    var showsEmptyCaption: Bool { self != .week }
    var hourLabelStride: Int { self == .week ? 2 : 1 }
    var gutterWidth: CGFloat {
        switch self {
        case .day: 48
        case .compact: 40
        case .week: 32
        }
    }
    var gutterTrailing: CGFloat { self == .week ? 6 : 10 }
    var blockRadius: CGFloat { self == .week ? 6 : 10 }
    var accentWidth: CGFloat { self == .week ? 3 : 4 }
    var minBlockHeight: CGFloat {
        switch self {
        case .day: 22
        case .compact: 16
        case .week: 4
        }
    }
    var laneSpacing: CGFloat { self == .week ? 3 : 6 }
    var columnHeaderHeight: CGFloat {
        switch self {
        case .day: 44
        case .compact: 36
        case .week: 28
        }
    }
}

enum HistoryCanvasZoom {
    enum GestureAxis: Equatable, Sendable {
        case horizontal
        case vertical
    }

    static let minDays: CGFloat = 1
    static let maxDays: CGFloat = 7
    static let snapStops: [CGFloat] = [1, 3, 7]

    static func clamp(_ days: CGFloat) -> CGFloat {
        min(max(days, minDays), maxDays)
    }

    /// Pinch in (magnification < 1) reveals more days. Hour scale is unchanged.
    static func daysVisible(baseline: CGFloat, magnification: CGFloat) -> CGFloat {
        let mag = max(magnification, 0.12)
        return clamp(baseline / mag)
    }

    /// Scale from the horizontal span only. Vertical pinch must not use this.
    static func horizontalMagnification(startSpanX: CGFloat, currentSpanX: CGFloat) -> CGFloat {
        let start = max(abs(startSpanX), 12)
        return max(abs(currentSpanX), 1) / start
    }

    /// Lock once one axis dominates the change in finger span.
    static func pinchAxis(deltaSpanX: CGFloat, deltaSpanY: CGFloat, threshold: CGFloat = 6) -> GestureAxis? {
        let dx = abs(deltaSpanX)
        let dy = abs(deltaSpanY)
        guard max(dx, dy) >= threshold else { return nil }
        if dx > dy * 1.15 { return .horizontal }
        if dy > dx * 1.15 { return .vertical }
        return nil
    }

    /// Lock from how the two fingers sit, so a side-by-side pinch can begin on the first move.
    static func pinchAxisFromSpan(spanX: CGFloat, spanY: CGFloat, threshold: CGFloat = 16) -> GestureAxis? {
        let dx = abs(spanX)
        let dy = abs(spanY)
        guard max(dx, dy) >= threshold else { return nil }
        if dx > dy * 1.2 { return .horizontal }
        if dy > dx * 1.2 { return .vertical }
        return nil
    }

    /// Negative translation (drag left) pages forward. Uses predicted translation.
    static func pageCount(translation: CGFloat, pageWidth: CGFloat) -> Int {
        guard pageWidth > 1 else { return 0 }
        let raw = -translation / pageWidth
        if abs(raw) < 0.32 { return 0 }
        let rounded = Int(raw.rounded())
        let stepped = rounded == 0 ? (raw > 0 ? 1 : -1) : rounded
        return min(4, max(-4, stepped))
    }

    static func weekdayIndex(of date: Date, calendar: Calendar) -> Int {
        let days = HistoryStats.weekDays(containing: date, calendar: calendar)
        return days.firstIndex(where: { calendar.isDate($0, inSameDayAs: date) }) ?? 0
    }

    /// Offset that keeps `selected` at the leading edge when switching into a week window.
    static func weekAlignDrag(selected: Date, columnWidth: CGFloat, calendar: Calendar) -> CGFloat {
        -CGFloat(weekdayIndex(of: selected, calendar: calendar)) * columnWidth
    }

    /// Extra days on both sides so a drag can peek the previous / next page.
    static func pagedWindow(
        selected: Date,
        daysVisible: Int,
        calendar: Calendar,
        extraPages: Int = 1
    ) -> (days: [Date], leadingIndex: Int) {
        let visible = visibleDays(selected: selected, daysVisible: daysVisible, calendar: calendar)
        let step = daysVisible >= 7 ? 7 : 1
        let extra = max(0, extraPages) * step
        guard let first = visible.first else { return ([], 0) }
        var days: [Date] = []
        days.reserveCapacity(visible.count + extra * 2)
        for offset in -extra..<(visible.count + extra) {
            if let day = calendar.date(byAdding: .day, value: offset, to: first) {
                days.append(calendar.startOfDay(for: day))
            }
        }
        return (days, extra)
    }

    static func snappedDays(_ days: CGFloat) -> Int {
        let nearest = snapStops.min(by: { abs($0 - days) < abs($1 - days) }) ?? 1
        return Int(nearest)
    }

    static func nextStop(from days: Int, expanding: Bool) -> Int {
        if expanding {
            return snapStops.compactMap { stop in
                let value = Int(stop)
                return value > days ? value : nil
            }.first ?? Int(maxDays)
        }
        return snapStops.compactMap { stop in
            let value = Int(stop)
            return value < days ? value : nil
        }.last ?? Int(minDays)
    }

    static func leadingDay(
        selected: Date,
        daysVisible: Int,
        calendar: Calendar
    ) -> Date {
        let start = calendar.startOfDay(for: selected)
        if daysVisible >= 7 {
            return HistoryStats.weekDays(containing: start, calendar: calendar).first ?? start
        }
        return start
    }

    static func visibleDays(
        selected: Date,
        daysVisible: Int,
        calendar: Calendar
    ) -> [Date] {
        let count = min(max(daysVisible, 1), 7)
        if count >= 7 {
            return HistoryStats.weekDays(containing: selected, calendar: calendar)
        }
        let start = calendar.startOfDay(for: selected)
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func steppingSelectedDay(
        _ selected: Date,
        byPages pages: Int,
        daysVisible: Int,
        calendar: Calendar
    ) -> Date {
        let step = daysVisible >= 7 ? 7 : 1
        guard let next = calendar.date(
            byAdding: .day,
            value: pages * step,
            to: calendar.startOfDay(for: selected)
        ) else {
            return calendar.startOfDay(for: selected)
        }
        return calendar.startOfDay(for: next)
    }
}
