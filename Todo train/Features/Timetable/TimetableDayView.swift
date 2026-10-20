//
//  TimetableDayView.swift
//  Todo train
//
//  今日の運転図表. 着発 = if-then. 空きは折らない. 毎日開けとは言わない.
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
    @State private var showManual = false
    @State private var availableCalendars: [CalendarSource] = []
    @State private var togglePulse = 0

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
        .sensoryFeedback(.selection, trigger: togglePulse)
        .task {
            await sessionManager.refreshCalendarBoard()
            availableCalendars = sessionManager.calendarBoard.availableCalendars()
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

    private func canvas(now: Date) -> some View {
        let layout = SessionTimeline.calendarDayLayout(on: day, calendar: calendar)
        let rides = SessionTimeline.rides(
            from: sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: day) },
            openEndedAt: now
        )
        let events = diagramEvents(layout: layout)
        let placements = TimetableStripLayout.placements(
            for: events.map {
                TimetableStripLayout.Interval(id: $0.id, startsAt: $0.startsAt, endsAt: $0.endsAt)
            }
        )
        return ScrollViewReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    HistoryTimeGutter(layout: layout, density: .day)
                    ZStack(alignment: .topLeading) {
                        HourGridCanvas(layout: layout, density: .day)
                            .allowsHitTesting(false)

                        ForEach(events) { event in
                            stripButton(
                                event,
                                layout: layout,
                                placement: placements[event.id] ?? .init(lane: 0, laneCount: 1)
                            )
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

    private func diagramEvents(layout: DayClockLayout) -> [DiagramEvent] {
        let adopted = storedBlocks.filter(\.isActive).compactMap { block -> DiagramEvent? in
            guard block.startsAt < layout.end, block.endsAt > layout.start else { return nil }
            return DiagramEvent(
                id: block.id.uuidString,
                source: .adopted(block),
                title: block.title,
                startsAt: block.startsAt,
                endsAt: block.endsAt
            )
        }
        let notices = sessionManager.noticeOccurrences.compactMap { occurrence -> DiagramEvent? in
            guard occurrence.startsAt < layout.end, occurrence.endsAt > layout.start else { return nil }
            if storedBlocks.contains(where: {
                $0.isActive && $0.calendarEventIdentifier == occurrence.eventIdentifier
                    && abs(($0.occurrenceStartKey ?? $0.startsAt.timeIntervalSince1970) - occurrence.occurrenceStartKey) < 0.5
            }) {
                return nil
            }
            return DiagramEvent(
                id: occurrence.id,
                source: .notice(occurrence),
                title: occurrence.title,
                startsAt: occurrence.startsAt,
                endsAt: occurrence.endsAt
            )
        }
        return (adopted + notices).sorted {
            if $0.startsAt != $1.startsAt { return $0.startsAt < $1.startsAt }
            return $0.id < $1.id
        }
    }

    private func stripButton(
        _ event: DiagramEvent,
        layout: DayClockLayout,
        placement: TimetableStripLayout.Placement
    ) -> some View {
        let y = CGFloat(layout.y(for: max(event.startsAt, layout.start)))
        let height = max(
            CGFloat(layout.height(from: max(event.startsAt, layout.start), to: min(event.endsAt, layout.end))),
            28
        )
        return HStack(spacing: 4) {
            ForEach(0..<placement.laneCount, id: \.self) { lane in
                Group {
                    if lane == placement.lane {
                        Button {
                            toggle(event)
                        } label: {
                            stripLabel(event, height: height)
                        }
                        .buttonStyle(StripToggleStyle())
                        .modifier(SeriesAdoptionMenu(event: event) { scope in
                            toggle(event, scope: scope)
                        })
                        .accessibilityLabel("\(event.isAdopted ? TimetableCopy.board : TimetableCopy.notice) \(event.title)")
                        .accessibilityValue(event.isAdopted ? TimetableCopy.board : TimetableCopy.notice)
                        .accessibilityHint(event.isAdopted ? TimetableCopy.unadoptThisTime : TimetableCopy.adoptThisTime)
                        .accessibilityAddTraits(event.isAdopted ? .isSelected : AccessibilityTraits())
                    } else {
                        Color.clear
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .padding(.top, y)
    }

    private func stripLabel(_ event: DiagramEvent, height: CGFloat) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(TrainTheme.rail.opacity(event.isAdopted ? 0.9 : 0.35))
                .frame(width: 4)
                .padding(.vertical, 4)
                .padding(.leading, 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.caption.weight(.semibold))
                    .tracking(StationSignMetrics.nameTracking(event.title, compact: true))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(timeRange(event.startsAt, event.endsAt))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: event.isAdopted ? "checkmark.circle.fill" : "circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(event.isAdopted ? TrainTheme.rail : TrainTheme.rail.opacity(0.55))
                .padding(.trailing, 8)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(TrainTheme.rail.opacity(event.isAdopted ? 0.28 : 0.10))
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func toggle(_ event: DiagramEvent, scope: TimetableAdoptionScope = .occurrence) {
        withAnimation(.snappy) {
            switch event.source {
            case .notice(let occurrence):
                sessionManager.adoptOccurrence(occurrence, scope: scope)
            case .adopted(let block):
                sessionManager.unadopt(blockID: block.id, scope: scope)
            }
        }
        togglePulse += 1
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

private struct DiagramEvent: Identifiable {
    enum Source {
        case notice(CalendarOccurrence)
        case adopted(TimetableBlock)
    }

    var id: String
    var source: Source
    var title: String
    var startsAt: Date
    var endsAt: Date

    var isAdopted: Bool {
        if case .adopted = source { return true }
        return false
    }

    var isRecurring: Bool {
        switch source {
        case .notice(let occurrence):
            return occurrence.recurrenceIdentifier != nil
        case .adopted(let block):
            return block.calendarRecurrenceIdentifier != nil
        }
    }
}

private struct SeriesAdoptionMenu: ViewModifier {
    let event: DiagramEvent
    let onToggle: (TimetableAdoptionScope) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if event.isRecurring {
            content.contextMenu {
                Button(event.isAdopted ? TimetableCopy.unadoptOngoing : TimetableCopy.adoptOngoing) {
                    onToggle(.series)
                }
            }
        } else {
            content
        }
    }
}

private struct StripToggleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
                    Button(TimetableCopy.adopt) {
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
