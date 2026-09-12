//
//  HistoryCanvasZoomTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

struct HistoryCanvasZoomTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1
        return calendar
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func pinchIn_revealsMoreDays() {
        #expect(HistoryCanvasZoom.daysVisible(baseline: 1, magnification: 1) == 1)
        #expect(HistoryCanvasZoom.daysVisible(baseline: 1, magnification: 0.5) == 2)
        #expect(HistoryCanvasZoom.daysVisible(baseline: 1, magnification: 0.1) == 7)
        #expect(HistoryCanvasZoom.daysVisible(baseline: 3, magnification: 3) == 1)
    }

    @Test func snap_picksNearestStop() {
        #expect(HistoryCanvasZoom.snappedDays(1) == 1)
        #expect(HistoryCanvasZoom.snappedDays(1.4) == 1)
        #expect(HistoryCanvasZoom.snappedDays(2.2) == 3)
        #expect(HistoryCanvasZoom.snappedDays(4.9) == 3)
        #expect(HistoryCanvasZoom.snappedDays(5.1) == 7)
        #expect(HistoryCanvasZoom.snappedDays(7) == 7)
    }

    @Test func density_hidesDetailAsDaysIncrease() {
        #expect(HistoryRideDensity(daysVisible: 1) == .day)
        #expect(HistoryRideDensity(daysVisible: 1).showsBadge)
        #expect(HistoryRideDensity(daysVisible: 1).showsGhost)
        #expect(HistoryRideDensity(daysVisible: 3) == .compact)
        #expect(!HistoryRideDensity(daysVisible: 3).showsBadge)
        #expect(HistoryRideDensity(daysVisible: 3).showsStartTimeOnly)
        #expect(HistoryRideDensity(daysVisible: 7) == .week)
        #expect(!HistoryRideDensity(daysVisible: 7).showsPauseBands)
        #expect(!HistoryRideDensity(daysVisible: 7).showsStatsHeader)
        #expect(HistoryRideDensity(daysVisible: 1).showsColumnHeader)
        #expect(HistoryRideDensity(daysVisible: 3).showsColumnHeader)
        #expect(HistoryRideDensity(daysVisible: 7).showsColumnHeader)
        #expect(HistoryRideDensity(daysVisible: 1).columnHeaderHeight > 0)
        #expect(HistoryRideDensity(daysVisible: 7).columnHeaderHeight > 0)
    }

    @Test func visibleDays_usesCalendarWeekWhenZoomedToSeven() {
        let tuesday = date(year: 2026, month: 9, day: 8)
        let week = HistoryCanvasZoom.visibleDays(selected: tuesday, daysVisible: 7, calendar: calendar)
        #expect(week.count == 7)
        #expect(calendar.component(.day, from: week[0]) == 6)
        #expect(calendar.component(.day, from: week[6]) == 12)

        let three = HistoryCanvasZoom.visibleDays(selected: tuesday, daysVisible: 3, calendar: calendar)
        #expect(three.count == 3)
        #expect(calendar.component(.day, from: three[0]) == 8)
        #expect(calendar.component(.day, from: three[2]) == 10)
    }

    @Test func leadingDay_snapsToWeekStartForWeekZoom() {
        let tuesday = date(year: 2026, month: 9, day: 8)
        let leading = HistoryCanvasZoom.leadingDay(selected: tuesday, daysVisible: 7, calendar: calendar)
        #expect(calendar.component(.day, from: leading) == 6)
        #expect(
            HistoryCanvasZoom.leadingDay(selected: tuesday, daysVisible: 3, calendar: calendar)
                == calendar.startOfDay(for: tuesday)
        )
    }

    @Test func stepping_movesByWeekWhenShowingSevenDays() {
        let tuesday = date(year: 2026, month: 9, day: 8)
        let nextWeek = HistoryCanvasZoom.steppingSelectedDay(
            tuesday,
            byPages: 1,
            daysVisible: 7,
            calendar: calendar
        )
        #expect(calendar.component(.day, from: nextWeek) == 15)

        let nextDay = HistoryCanvasZoom.steppingSelectedDay(
            tuesday,
            byPages: 1,
            daysVisible: 1,
            calendar: calendar
        )
        #expect(calendar.component(.day, from: nextDay) == 9)
    }

    @Test func nextStop_expandsAndContractsAlongSnaps() {
        #expect(HistoryCanvasZoom.nextStop(from: 1, expanding: true) == 3)
        #expect(HistoryCanvasZoom.nextStop(from: 3, expanding: true) == 7)
        #expect(HistoryCanvasZoom.nextStop(from: 7, expanding: true) == 7)
        #expect(HistoryCanvasZoom.nextStop(from: 7, expanding: false) == 3)
        #expect(HistoryCanvasZoom.nextStop(from: 3, expanding: false) == 1)
        #expect(HistoryCanvasZoom.nextStop(from: 1, expanding: false) == 1)
    }

    @Test func pinchAxis_requiresDominantSpanChange() {
        #expect(HistoryCanvasZoom.pinchAxis(deltaSpanX: 4, deltaSpanY: 2) == nil)
        #expect(HistoryCanvasZoom.pinchAxis(deltaSpanX: 24, deltaSpanY: 6) == .horizontal)
        #expect(HistoryCanvasZoom.pinchAxis(deltaSpanX: 6, deltaSpanY: 24) == .vertical)
        #expect(HistoryCanvasZoom.pinchAxis(deltaSpanX: 20, deltaSpanY: 18) == nil)
    }

    @Test func pinchAxisFromSpan_locksFromFingerPlacement() {
        #expect(HistoryCanvasZoom.pinchAxisFromSpan(spanX: 8, spanY: 4) == nil)
        #expect(HistoryCanvasZoom.pinchAxisFromSpan(spanX: 80, spanY: 20) == .horizontal)
        #expect(HistoryCanvasZoom.pinchAxisFromSpan(spanX: 20, spanY: 80) == .vertical)
    }

    @Test func horizontalMagnification_usesXSpanOnly() {
        #expect(HistoryCanvasZoom.horizontalMagnification(startSpanX: 80, currentSpanX: 160) == 2)
        #expect(HistoryCanvasZoom.horizontalMagnification(startSpanX: 80, currentSpanX: 40) == 0.5)
        #expect(HistoryCanvasZoom.horizontalMagnification(startSpanX: 0, currentSpanX: 24) == 2)
    }

    @Test func pageCount_needsAboutAThirdOfAPage() {
        #expect(HistoryCanvasZoom.pageCount(translation: 0, pageWidth: 100) == 0)
        #expect(HistoryCanvasZoom.pageCount(translation: -20, pageWidth: 100) == 0)
        #expect(HistoryCanvasZoom.pageCount(translation: -40, pageWidth: 100) == 1)
        #expect(HistoryCanvasZoom.pageCount(translation: 40, pageWidth: 100) == -1)
        #expect(HistoryCanvasZoom.pageCount(translation: -180, pageWidth: 100) == 2)
    }

    @Test func pagedWindow_addsAPeekPageOnBothSides() {
        let tuesday = date(year: 2026, month: 9, day: 8)
        let three = HistoryCanvasZoom.pagedWindow(selected: tuesday, daysVisible: 3, calendar: calendar)
        #expect(three.leadingIndex == 1)
        #expect(three.days.count == 5)
        #expect(calendar.component(.day, from: three.days[1]) == 8)

        let week = HistoryCanvasZoom.pagedWindow(selected: tuesday, daysVisible: 7, calendar: calendar)
        #expect(week.leadingIndex == 7)
        #expect(week.days.count == 21)
        #expect(calendar.component(.day, from: week.days[7]) == 6)
    }

    @Test func weekAlignDrag_keepsSelectedAtLeadingEdge() {
        let tuesday = date(year: 2026, month: 9, day: 8)
        #expect(HistoryCanvasZoom.weekdayIndex(of: tuesday, calendar: calendar) == 2)
        #expect(HistoryCanvasZoom.weekAlignDrag(selected: tuesday, columnWidth: 40, calendar: calendar) == -80)
    }
}
