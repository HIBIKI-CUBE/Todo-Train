//
//  HistoryCalendarStrip.swift
//  Todo train
//
//  Calendar-style week strip for picking a day of 履歴.
//

import SwiftUI

struct HistoryCalendarStrip: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.calendar) private var calendar

    let selectedDay: Date
    let daysWithRides: Set<String>
    var visibleDayKeys: Set<String> = []
    var rangeStart: Date? = nil
    var rangeEnd: Date? = nil
    var onSelect: (Date) -> Void
    var onShowDatePicker: () -> Void

    @State private var weekKey: String?
    @State private var isProgrammaticScroll = false

    var body: some View {
        VStack(spacing: TrainTheme.Space.sm) {
            header
            weekPager
        }
        .accessibilityElement(children: .contain)
        .padding(.bottom, TrainTheme.Space.sm)
        .background(TrainTheme.platform)
        .onAppear(perform: syncWeekToSelection)
        .onChange(of: selectedDay) { _, _ in
            syncWeekToSelection()
        }
        .onChange(of: weekKey) { _, newValue in
            consumeWeekChange(to: newValue)
        }
    }

    private var header: some View {
        HStack(spacing: TrainTheme.Space.sm) {
            Button {
                shiftWeek(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(TrainTheme.rail)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("前の週")

            Button(action: onShowDatePicker) {
                Text(monthTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
            }
            .accessibilityLabel(monthTitle)
            .accessibilityHint("カレンダーから日付を選ぶ")

            Button {
                shiftWeek(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(TrainTheme.rail)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("次の週")
        }
        .buttonStyle(.plain)
    }

    private var weekPager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(weeks, id: \.self) { weekStart in
                    HStack(spacing: 0) {
                        ForEach(HistoryStats.weekDays(containing: weekStart, calendar: calendar), id: \.self) { day in
                            dayCell(day)
                        }
                    }
                    .containerRelativeFrame(.horizontal)
                    .id(HistoryStats.dayKey(for: weekStart, calendar: calendar))
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $weekKey)
        .scrollIndicators(.hidden)
        .frame(height: TrainLayout.isCompactHeight(verticalSizeClass) ? 72 : 80)
    }

    private func dayCell(_ day: Date) -> some View {
        let selected = calendar.isDate(day, inSameDayAs: selectedDay)
        let today = calendar.isDateInToday(day)
        let key = HistoryStats.dayKey(for: day, calendar: calendar)
        let hasRides = daysWithRides.contains(key)
        let inView = visibleDayKeys.contains(key)
        let compact = TrainLayout.isCompactHeight(verticalSizeClass)
        let numberColor: Color = {
            if selected { return .white }
            if today { return TrainTheme.rail }
            return .primary
        }()

        return Button {
            onSelect(calendar.startOfDay(for: day))
        } label: {
            VStack(spacing: compact ? 2 : 4) {
                Text(weekdayLabel(day))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)

                ZStack {
                    if selected {
                        Circle()
                            .fill(TrainTheme.rail)
                    } else if inView {
                        Circle()
                            .fill(TrainTheme.railSoft)
                    } else if today {
                        Circle()
                            .stroke(TrainTheme.rail.opacity(0.55), lineWidth: 1.5)
                    }
                    Text(dayNumber(day))
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(numberColor)
                }
                .frame(width: compact ? 32 : 36, height: compact ? 32 : 36)

                Circle()
                    .fill(hasRides ? TrainTheme.rail : Color.clear)
                    .frame(width: 5, height: 5)
                    .opacity(selected && hasRides ? 0.85 : 1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(day: day, selected: selected, today: today, hasRides: hasRides))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var weeks: [Date] {
        HistoryStats.weekStarts(
            from: rangeStart ?? selectedDay,
            through: rangeEnd ?? selectedDay,
            calendar: calendar
        )
    }

    private var monthTitle: String {
        Self.monthFormatter.string(from: selectedDay)
    }

    private func shiftWeek(_ weeks: Int) {
        guard let next = calendar.date(byAdding: .day, value: weeks * 7, to: selectedDay) else { return }
        onSelect(calendar.startOfDay(for: next))
    }

    private func syncWeekToSelection() {
        let start = HistoryStats.weekDays(containing: selectedDay, calendar: calendar).first ?? selectedDay
        let key = HistoryStats.dayKey(for: start, calendar: calendar)
        guard weekKey != key else { return }
        isProgrammaticScroll = true
        weekKey = key
        DispatchQueue.main.async {
            isProgrammaticScroll = false
        }
    }

    private func consumeWeekChange(to newValue: String?) {
        guard !isProgrammaticScroll else { return }
        guard let newValue, let newStart = HistoryStats.date(from: newValue, calendar: calendar) else { return }
        let weekday = calendar.component(.weekday, from: selectedDay)
        let days = HistoryStats.weekDays(containing: newStart, calendar: calendar)
        let match = days.first { calendar.component(.weekday, from: $0) == weekday } ?? newStart
        let currentStart = HistoryStats.weekDays(containing: selectedDay, calendar: calendar).first
        if let currentStart, calendar.isDate(currentStart, inSameDayAs: newStart) {
            return
        }
        onSelect(calendar.startOfDay(for: match))
    }

    private func weekdayLabel(_ day: Date) -> String {
        Self.weekdayFormatter.string(from: day)
    }

    private func dayNumber(_ day: Date) -> String {
        Self.dayFormatter.string(from: day)
    }

    private func accessibilityLabel(day: Date, selected: Bool, today: Bool, hasRides: Bool) -> String {
        var parts = [Self.fullDayFormatter.string(from: day)]
        if today { parts.append("今日") }
        if selected { parts.append("選択中") }
        parts.append(hasRides ? "乗車あり" : "乗車なし")
        return parts.joined(separator: "、")
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月"
        return formatter
    }()

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

    private static let fullDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日EEEE"
        return formatter
    }()
}
