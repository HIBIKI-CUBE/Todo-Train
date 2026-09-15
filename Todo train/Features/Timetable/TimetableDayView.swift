//
//  TimetableDayView.swift
//  Todo train
//
//  今日の運転図表. 載せる = if-then. 空きは折らない. 毎日開けとは言わない.
//

import SwiftUI
import SwiftData

struct TimetableDayView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(AppSettings.self) private var settings
    @Environment(\.calendar) private var calendar

    @Query(sort: \TimetableBlock.startsAt) private var storedBlocks: [TimetableBlock]
    @Query(sort: \WorkSession.startedAt) private var sessions: [WorkSession]

    @State private var didScrollToNow = false
    @State private var adoptTarget: CalendarOccurrence?
    @State private var unadoptID: UUID?
    @State private var showManual = false
    @State private var availableCalendars: [CalendarSource] = []

    private var day: Date {
        calendar.startOfDay(for: sessionManager.clock.now)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            canvas(now: context.date)
        }
        .navigationTitle(TimetableCopy.board)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                calendarFilterMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showManual = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(TimetableCopy.drawTime)
            }
        }
        .safeAreaInset(edge: .top) {
            diagramChrome
        }
        .safeAreaInset(edge: .bottom) {
            Text(TimetableCopy.atsFooter)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TrainTheme.Space.lg)
                .padding(.vertical, TrainTheme.Space.sm)
        }
        .task {
            await sessionManager.refreshCalendarBoard()
            availableCalendars = sessionManager.calendarBoard.availableCalendars()
        }
        .sheet(item: $adoptTarget) { occurrence in
            TimetableAdoptSheet(occurrence: occurrence) { scope in
                sessionManager.adoptOccurrence(occurrence, scope: scope)
            }
        }
        .sheet(item: unadoptSheet) { target in
            TimetableUnadoptSheet(block: target.block) { scope in
                sessionManager.unadopt(blockID: target.block.id, scope: scope)
            }
        }
        .sheet(isPresented: $showManual) {
            TimetableManualSheet(day: day) { title, start, end in
                sessionManager.adoptManualBlock(title: title, startsAt: start, endsAt: end)
            }
        }
    }

    private var authorization: CalendarBoardAuthorization {
        sessionManager.calendarBoard.authorizationStatus()
    }

    private var hasNoVisibleCalendars: Bool {
        authorization == .authorized
            && !availableCalendars.isEmpty
            && availableCalendars.allSatisfy { !settings.isTimetableCalendarVisible($0.identifier) }
    }

    private var diagramChrome: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(TimetableCopy.diagramLead)
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: TrainTheme.Space.md) {
                legendDot(opacity: 0.35, label: TimetableCopy.legendNotice)
                legendDot(opacity: 0.9, label: TimetableCopy.legendAdopted)
                Text(TimetableCopy.legendRide)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if authorization == .denied {
                Text(TimetableCopy.calendarDenied)
                    .font(.footnote)
                    .foregroundStyle(TrainTheme.signalAmber)
            } else if hasNoVisibleCalendars {
                Text(TimetableCopy.noCalendarsSelected)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TrainTheme.Space.lg)
        .padding(.vertical, TrainTheme.Space.sm)
        .background(.bar)
    }

    private func legendDot(opacity: Double, label: String) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(TrainTheme.rail.opacity(opacity))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var calendarFilterMenu: some View {
        Menu {
            if availableCalendars.isEmpty {
                Text("カレンダーがありません")
            } else {
                ForEach(availableCalendars) { calendar in
                    Toggle(calendar.title, isOn: calendarVisibleBinding(calendar.identifier))
                }
            }
        } label: {
            Image(systemName: "calendar.badge.checkmark")
        }
        .disabled(authorization != .authorized)
        .accessibilityLabel(TimetableCopy.calendarFilter)
    }

    private func calendarVisibleBinding(_ identifier: String) -> Binding<Bool> {
        Binding(
            get: { settings.isTimetableCalendarVisible(identifier) },
            set: { visible in
                settings.setTimetableCalendar(
                    identifier,
                    visible: visible,
                    knownIdentifiers: availableCalendars.map(\.identifier)
                )
                Task {
                    await sessionManager.refreshCalendarBoardIfAuthorized()
                }
            }
        )
    }

    private var unadoptSheet: Binding<UnadoptTarget?> {
        Binding(
            get: {
                guard let unadoptID,
                      let block = storedBlocks.first(where: { $0.id == unadoptID }) else { return nil }
                return UnadoptTarget(id: block.id, block: block)
            },
            set: { unadoptID = $0?.id }
        )
    }

    private func canvas(now: Date) -> some View {
        let layout = SessionTimeline.calendarDayLayout(on: day, calendar: calendar)
        let rides = SessionTimeline.rides(
            from: sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: day) },
            openEndedAt: now
        )
        return ScrollViewReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    HistoryTimeGutter(layout: layout, density: .day)
                    ZStack(alignment: .topLeading) {
                        HourGridCanvas(layout: layout, density: .day)
                            .allowsHitTesting(false)

                        ForEach(noticeItems(layout: layout)) { item in
                            stripButton(item.strip, layout: layout) {
                                adoptTarget = item.occurrence
                            }
                        }

                        ForEach(adoptedStrips()) { strip in
                            stripButton(strip, layout: layout) {
                                unadoptID = strip.id
                            }
                        }

                        rideOverlay(rides: rides, layout: layout)
                        nowMarker(now: now, layout: layout)
                            .id("now")
                    }
                    .frame(maxWidth: .infinity, minHeight: CGFloat(layout.height), alignment: .topLeading)
                }
                .padding(.top, HistoryDayClockView.topSlack)
                .frame(height: CGFloat(layout.height) + HistoryDayClockView.topSlack, alignment: .top)
            }
            .onAppear {
                guard !didScrollToNow else { return }
                didScrollToNow = true
                proxy.scrollTo("now", anchor: .center)
            }
        }
    }

    private func adoptedStrips() -> [DayClockStrip] {
        storedBlocks.filter(\.isActive).map { block in
            DayClockStrip(
                id: block.id,
                title: block.title,
                startsAt: block.startsAt,
                endsAt: block.endsAt,
                style: .adopted
            )
        }
    }

    private func noticeItems(layout: DayClockLayout) -> [NoticeItem] {
        sessionManager.noticeOccurrences.compactMap { occurrence in
            guard occurrence.startsAt < layout.end, occurrence.endsAt > layout.start else { return nil }
            if storedBlocks.contains(where: {
                $0.isActive && $0.calendarEventIdentifier == occurrence.eventIdentifier
                    && abs(($0.occurrenceStartKey ?? $0.startsAt.timeIntervalSince1970) - occurrence.occurrenceStartKey) < 0.5
            }) {
                return nil
            }
            return NoticeItem(
                id: occurrence.id,
                occurrence: occurrence,
                strip: DayClockStrip(
                    id: UUID(),
                    title: occurrence.title,
                    startsAt: occurrence.startsAt,
                    endsAt: occurrence.endsAt,
                    style: .notice
                )
            )
        }
    }

    private func stripButton(_ strip: DayClockStrip, layout: DayClockLayout, action: @escaping () -> Void) -> some View {
        let y = CGFloat(layout.y(for: max(strip.startsAt, layout.start)))
        let height = max(
            CGFloat(layout.height(from: max(strip.startsAt, layout.start), to: min(strip.endsAt, layout.end))),
            22
        )
        return Button(action: action) {
            HStack(spacing: 6) {
                Capsule()
                    .fill(TrainTheme.rail.opacity(strip.style == .adopted ? 0.9 : 0.35))
                    .frame(width: 4)
                    .padding(.vertical, 4)
                    .padding(.leading, 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(strip.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(timeRange(strip.startsAt, strip.endsAt))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(strip.style == .adopted ? TimetableCopy.unadopt : TimetableCopy.adopt)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(strip.style == .adopted ? .secondary : TrainTheme.rail)
                    .padding(.trailing, 8)
            }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(TrainTheme.rail.opacity(strip.style == .adopted ? 0.28 : 0.10))
            }
        }
        .buttonStyle(.plain)
        .padding(.top, y)
        .accessibilityLabel("\(strip.style == .adopted ? TimetableCopy.board : TimetableCopy.notice) \(strip.title)")
        .accessibilityHint(strip.style == .adopted ? TimetableCopy.unadopt : TimetableCopy.adopt)
    }

    private func rideOverlay(rides: [TimelineRide], layout: DayClockLayout) -> some View {
        ForEach(rides) { ride in
            let y = CGFloat(layout.y(for: ride.startedAt))
            let height = max(CGFloat(layout.height(from: ride.startedAt, to: ride.endedAt)), 8)
            HStack(spacing: 0) {
                Capsule()
                    .fill(HistoryDayClockView.stripColor(for: ride))
                    .frame(width: 3)
                    .padding(.vertical, 3)
                    .padding(.leading, 4)
                Text(ride.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(1)
                    .padding(.leading, 4)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(HistoryDayClockView.stripColor(for: ride).opacity(0.16))
            )
            .padding(.top, y)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func nowMarker(now: Date, layout: DayClockLayout) -> some View {
        Rectangle()
            .fill(TrainTheme.signalRed)
            .frame(height: 2)
            .padding(.top, CGFloat(layout.y(for: now)))
            .accessibilityLabel("いま")
    }

    private func timeRange(_ start: Date, _ end: Date) -> String {
        "\(Self.timeFormatter.string(from: start))–\(Self.timeFormatter.string(from: end))"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct NoticeItem: Identifiable {
    var id: String
    var occurrence: CalendarOccurrence
    var strip: DayClockStrip
}

private struct UnadoptTarget: Identifiable {
    var id: UUID
    var block: TimetableBlock
}

private struct TimetableAdoptSheet: View {
    let occurrence: CalendarOccurrence
    let onAdopt: (TimetableAdoptionScope) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(occurrence.title)
                    Text(range)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button(TimetableCopy.thisTime) {
                        onAdopt(.occurrence)
                        dismiss()
                    }
                    if occurrence.recurrenceIdentifier != nil {
                        Button(TimetableCopy.ongoing) {
                            onAdopt(.series)
                            dismiss()
                        }
                    }
                } footer: {
                    Text("載せるは、この枠なら停車するという決めです。発車は止めません。")
                }
            }
            .navigationTitle(TimetableCopy.adopt)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var range: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: occurrence.startsAt))–\(formatter.string(from: occurrence.endsAt))"
    }
}

private struct TimetableUnadoptSheet: View {
    let block: TimetableBlock
    let onUnadopt: (TimetableAdoptionScope) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(block.title)
                }
                Section {
                    Button(TimetableCopy.thisTime) {
                        onUnadopt(.occurrence)
                        dismiss()
                    }
                    if block.calendarRecurrenceIdentifier != nil {
                        Button(TimetableCopy.ongoing) {
                            onUnadopt(.series)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(TimetableCopy.unadopt)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct TimetableManualSheet: View {
    let day: Date
    let onSave: (String, Date, Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var startsAt: Date
    @State private var endsAt: Date

    init(day: Date, onSave: @escaping (String, Date, Date) -> Void) {
        self.day = day
        self.onSave = onSave
        let start = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: day) ?? day
        _startsAt = State(initialValue: start)
        _endsAt = State(initialValue: start.addingTimeInterval(1800))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("題名", text: $title)
                DatePicker("開始", selection: $startsAt, displayedComponents: [.hourAndMinute])
                DatePicker("終了", selection: $endsAt, displayedComponents: [.hourAndMinute])
            }
            .navigationTitle(TimetableCopy.drawTime)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("載せる") {
                        onSave(title, startsAt, endsAt)
                        dismiss()
                    }
                    .disabled(endsAt <= startsAt)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
