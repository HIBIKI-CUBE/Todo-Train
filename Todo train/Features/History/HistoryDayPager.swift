//
//  HistoryDayPager.swift
//  Todo train
//
//  Layout is computed by the parent. Drag offset lives in the child so a
//  horizontal pan does not rebuild the day-clock layout every frame.
//

import SwiftUI
import UIKit

struct HistoryDayPager: View {
    let sessionsByDay: [String: [WorkSession]]
    let dayStrip: [Date]
    @Binding var selectedDay: Date
    @Binding var daysVisible: CGFloat
    let minHeight: CGFloat
    let viewportWidth: CGFloat
    var onSelect: (WorkSession) -> Void
    var onReissue: ((Ticket) -> Void)?
    var onDelete: (WorkSession) -> Void

    @Environment(\.calendar) private var calendar

    private var density: HistoryRideDensity {
        HistoryRideDensity(daysVisible: daysVisible)
    }

    private var clockMinHeight: CGFloat {
        max(0, minHeight - density.columnHeaderHeight)
    }

    private var sharedLayout: DayClockLayout {
        let reference = calendar.startOfDay(for: dayStrip.first ?? selectedDay)
        var rides: [TimelineRide] = []
        for day in dayStrip {
            let key = HistoryStats.dayKey(for: day, calendar: calendar)
            let clipped = SessionTimeline.rides(from: sessionsByDay[key] ?? []).compactMap {
                SessionTimeline.clip($0, toDay: day, calendar: calendar)
            }
            rides.append(contentsOf: clipped)
        }
        return SessionTimeline.sharedLayout(
            rides: rides,
            referenceDay: reference,
            calendar: calendar,
            minHeight: Double(max(0, clockMinHeight - HistoryDayClockView.topSlack))
        )
    }

    var body: some View {
        HistoryDayInteractiveCanvas(
            layout: sharedLayout,
            sessionsByDay: sessionsByDay,
            selectedDay: $selectedDay,
            daysVisible: $daysVisible,
            minHeight: minHeight,
            viewportWidth: viewportWidth,
            onSelect: onSelect,
            onReissue: onReissue,
            onDelete: onDelete
        )
    }
}

private struct HistoryDayInteractiveCanvas: View {
    let layout: DayClockLayout
    let sessionsByDay: [String: [WorkSession]]
    @Binding var selectedDay: Date
    @Binding var daysVisible: CGFloat
    let minHeight: CGFloat
    let viewportWidth: CGFloat
    var onSelect: (WorkSession) -> Void
    var onReissue: ((Ticket) -> Void)?
    var onDelete: (WorkSession) -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pinchBaseline: CGFloat?
    @State private var dragX: CGFloat = 0
    @State private var dragTickPage = 0
    @State private var pinchTickStop = 1
    @State private var isSettlingPage = false
    @State private var haptics = HistoryCanvasHaptics()

    private var density: HistoryRideDensity {
        HistoryRideDensity(daysVisible: daysVisible)
    }

    private var snappedDays: Int {
        HistoryCanvasZoom.snappedDays(daysVisible)
    }

    private var isPinching: Bool {
        pinchBaseline != nil
    }

    private var gutterTotal: CGFloat {
        density.gutterWidth + density.gutterTrailing
    }

    private var usableWidth: CGFloat {
        max(120, viewportWidth - gutterTotal)
    }

    private var columnWidth: CGFloat {
        usableWidth / max(daysVisible, 1)
    }

    private var clockMinHeight: CGFloat {
        max(0, minHeight - density.columnHeaderHeight)
    }

    private var pagingDayCount: Int {
        if !isPinching, snappedDays >= 7 { return 7 }
        return min(7, max(1, Int(ceil(daysVisible - 0.001))))
    }

    private var pageStrideWidth: CGFloat {
        pagingDayCount >= 7 ? usableWidth : columnWidth
    }

    private var window: (days: [Date], leadingIndex: Int) {
        HistoryCanvasZoom.pagedWindow(
            selected: selectedDay,
            daysVisible: pagingDayCount,
            calendar: calendar
        )
    }

    private var snapAnimation: Animation? {
        reduceMotion ? nil : TrainTheme.Motion.pageSnap
    }

    var body: some View {
        VStack(spacing: 0) {
            if density.showsColumnHeader {
                headerRow
            }
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    HistoryTimeGutter(layout: layout, density: density)
                        .padding(.top, HistoryDayClockView.topSlack)
                    columns
                }
                .frame(minHeight: clockMinHeight, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDisabled(dragX != 0 && !isPinching)
        }
        .gesture(pagePan)
        .gesture(zoomPinch)
        .onAppear { haptics.prepare() }
        .accessibilityHint("左右にスワイプで日付、横ピンチで1画面の日数")
        .accessibilityValue("\(snappedDays)日表示")
        .accessibilityAction(named: "次の日") { shiftDay(1) }
        .accessibilityAction(named: "前の日") { shiftDay(-1) }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                settleZoom(to: HistoryCanvasZoom.nextStop(from: snappedDays, expanding: true))
            case .decrement:
                settleZoom(to: HistoryCanvasZoom.nextStop(from: snappedDays, expanding: false))
            default:
                break
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: gutterTotal)
            slidingDays { day in
                let selected = calendar.isDate(day, inSameDayAs: selectedDay)
                columnHeader(day: day, selected: selected)
            }
        }
        .frame(height: density.columnHeaderHeight)
    }

    private var columns: some View {
        slidingDays { day in
            dayColumn(day)
        }
    }

    private func slidingDays<Content: View>(
        @ViewBuilder content: @escaping (Date) -> Content
    ) -> some View {
        let page = window
        return HStack(alignment: .top, spacing: 0) {
            ForEach(page.days, id: \.self) { day in
                content(day)
                    .frame(width: columnWidth, alignment: .top)
            }
        }
        .offset(x: -CGFloat(page.leadingIndex) * columnWidth + dragX)
        .frame(width: usableWidth, alignment: .leading)
        .clipped()
    }

    private func dayColumn(_ day: Date) -> some View {
        let key = HistoryStats.dayKey(for: day, calendar: calendar)
        let sessions = sessionsByDay[key] ?? []
        let selected = calendar.isDate(day, inSameDayAs: selectedDay)
        return ZStack(alignment: .top) {
            HistoryDayClockView(
                sessions: sessions,
                day: day,
                sharedLayout: layout,
                density: density,
                showsGutter: false,
                minHeight: clockMinHeight,
                onSelect: onSelect,
                onReissue: onReissue,
                onDelete: onDelete
            )
            if sessions.isEmpty {
                emptyDayChrome(day: day)
            }
        }
        .background(selected && density != .day ? TrainTheme.railSoft.opacity(0.4) : Color.clear)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(TrainTheme.track.opacity(0.55))
                .frame(width: 1 / 3)
                .allowsHitTesting(false)
        }
    }

    private func columnHeader(day: Date, selected: Bool) -> some View {
        Button {
            selectedDay = calendar.startOfDay(for: day)
        } label: {
            Group {
                if density == .day {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Self.monthDayFormatter.string(from: day))
                            .font(.title3.weight(.semibold).monospacedDigit())
                        Text(Self.weekdayFormatter.string(from: day))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(selected ? TrainTheme.rail : .primary)
                    .padding(.leading, 2)
                } else {
                    VStack(spacing: 1) {
                        Text(Self.weekdayFormatter.string(from: day))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(Self.dayFormatter.string(from: day))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(selected ? TrainTheme.rail : .primary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: density == .day ? .leading : .center)
            .frame(height: density.columnHeaderHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.fullDayFormatter.string(from: day))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func emptyDayChrome(day: Date) -> some View {
        Group {
            if density == .day {
                emptyFullDay(day: day)
            } else if density == .week {
                Text(Self.dayFormatter.string(from: day))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.primary.opacity(0.2))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .accessibilityHidden(true)
            } else {
                Text("乗車なし")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func emptyFullDay(day: Date) -> some View {
        VStack(spacing: 6) {
            Text(Self.dayFormatter.string(from: day))
                .font(.system(size: 88, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.primary.opacity(0.22))
            Text("乗車はありません")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .offset(y: -36)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Self.monthDayFormatter.string(from: day))の乗車はありません")
    }

    private var pagePan: DeckHorizontalPanGesture {
        DeckHorizontalPanGesture(
            isEnabled: !isPinching && !isSettlingPage,
            cancelsTouchesInView: true
        ) { x in
            dragX = x
            let preview = HistoryCanvasZoom.pageCount(translation: x, pageWidth: pageStrideWidth)
            if preview != dragTickPage {
                dragTickPage = preview
                haptics.selection.selectionChanged()
                haptics.selection.prepare()
            }
        } onEnded: { _, predicted in
            finishPage(predicted: predicted)
        }
    }

    private var zoomPinch: HistoryHorizontalPinchGesture {
        HistoryHorizontalPinchGesture { magnification in
            if pinchBaseline == nil {
                pinchBaseline = daysVisible
                pinchTickStop = snappedDays
                dragX = 0
            }
            daysVisible = HistoryCanvasZoom.daysVisible(
                baseline: pinchBaseline ?? daysVisible,
                magnification: magnification
            )
            let stop = HistoryCanvasZoom.snappedDays(daysVisible)
            if stop != pinchTickStop {
                pinchTickStop = stop
                haptics.selection.selectionChanged()
                haptics.selection.prepare()
            }
        } onEnded: { _ in
            settleCurrentZoom()
        } onCancelled: {
            if let pinchBaseline {
                daysVisible = pinchBaseline
            }
            self.pinchBaseline = nil
        }
    }

    private func finishPage(predicted: CGFloat) {
        let pages = HistoryCanvasZoom.pageCount(translation: predicted, pageWidth: pageStrideWidth)
        let target = -CGFloat(pages) * pageStrideWidth
        guard pages != 0 else {
            withAnimation(snapAnimation) { dragX = 0 }
            dragTickPage = 0
            return
        }
        let destination = HistoryCanvasZoom.steppingSelectedDay(
            selectedDay,
            byPages: pages,
            daysVisible: snappedDays,
            calendar: calendar
        )
        isSettlingPage = true
        withAnimation(snapAnimation) {
            dragX = target
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedDay = destination
                dragX = 0
                isSettlingPage = false
                dragTickPage = 0
            }
        }
    }

    private func settleCurrentZoom() {
        settleZoom(to: HistoryCanvasZoom.snappedDays(daysVisible))
    }

    private func settleZoom(to snapped: Int) {
        let weekColumn = usableWidth / 7
        let align = snapped >= 7
            ? HistoryCanvasZoom.weekAlignDrag(
                selected: selectedDay,
                columnWidth: weekColumn,
                calendar: calendar
            )
            : 0
        haptics.impact.impactOccurred()
        haptics.impact.prepare()
        var jump = Transaction()
        jump.disablesAnimations = true
        withTransaction(jump) {
            daysVisible = CGFloat(snapped)
            pinchBaseline = nil
            dragX = align
        }
        withAnimation(snapAnimation) {
            dragX = 0
        }
    }

    private func shiftDay(_ pages: Int) {
        selectedDay = HistoryCanvasZoom.steppingSelectedDay(
            selectedDay,
            byPages: pages,
            daysVisible: snappedDays,
            calendar: calendar
        )
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "E"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "d"
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    private static let fullDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日EEEE"
        return formatter
    }()
}

private final class HistoryCanvasHaptics {
    let selection = UISelectionFeedbackGenerator()
    let impact = UIImpactFeedbackGenerator(style: .light)

    func prepare() {
        selection.prepare()
        impact.prepare()
    }
}
