//
//  HistoryView.swift
//  Todo train
//

import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionManager.self) private var sessionManager
    @Environment(DeletionUndoCenter.self) private var undoCenter
    @Environment(\.calendar) private var calendar

    @Query(sort: \WorkSession.endedAt, order: .reverse)
    private var sessions: [WorkSession]

    @State private var searchText = ""
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var showDatePicker = false
    @State private var selectedRideID: UUID?
    @State private var didFocusInitialDay = false
    @State private var isSearchPresented = false
    @State private var daysVisible: CGFloat = 1
    @FocusState private var searchFieldFocused: Bool

    init(focusDay: Date? = nil) {
        let calendar = Calendar.current
        _selectedDay = State(initialValue: focusDay ?? calendar.startOfDay(for: Date()))
        _didFocusInitialDay = State(initialValue: focusDay != nil)
    }

    private var endedSessions: [WorkSession] {
        sessions.filter { $0.endedAt != nil }
    }

    private var filteredSessions: [WorkSession] {
        HistorySearch.filter(sessions: endedSessions, query: searchText)
    }

    private var groups: [(dayKey: String, sessions: [WorkSession])] {
        HistoryStats.groupByDay(sessions: filteredSessions, calendar: calendar)
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedDayKey: String {
        HistoryStats.dayKey(for: selectedDay, calendar: calendar)
    }

    private var selectedDaySessions: [WorkSession] {
        groups.first(where: { $0.dayKey == selectedDayKey })?.sessions ?? []
    }

    private var daysWithRides: Set<String> {
        Set(HistoryStats.groupByDay(sessions: endedSessions, calendar: calendar).map(\.dayKey))
    }

    private var sessionsByDay: [String: [WorkSession]] {
        Dictionary(uniqueKeysWithValues: groups.map { ($0.dayKey, $0.sessions) })
    }

    private var canvasDayRange: (start: Date, end: Date) {
        let today = calendar.startOfDay(for: Date())
        var start = min(today, calendar.startOfDay(for: selectedDay))
        var end = max(today, calendar.startOfDay(for: selectedDay))
        for key in daysWithRides {
            guard let date = HistoryStats.date(from: key, calendar: calendar) else { continue }
            start = min(start, date)
            end = max(end, date)
        }
        return (
            calendar.date(byAdding: .day, value: -14, to: start) ?? start,
            calendar.date(byAdding: .day, value: 14, to: end) ?? end
        )
    }

    private var dayStrip: [Date] {
        HistoryStats.days(from: canvasDayRange.start, through: canvasDayRange.end, calendar: calendar)
    }

    private var rideDensity: HistoryRideDensity {
        HistoryRideDensity(daysVisible: daysVisible)
    }

    private var visibleDayKeys: Set<String> {
        Set(
            HistoryCanvasZoom.visibleDays(
                selected: selectedDay,
                daysVisible: HistoryCanvasZoom.snappedDays(daysVisible),
                calendar: calendar
            ).map { HistoryStats.dayKey(for: $0, calendar: calendar) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if isSearchPresented {
                searchFieldRow
            }

            if isSearching {
                if filteredSessions.isEmpty {
                    ContentUnavailableView {
                        Label("一致する履歴がありません", systemImage: "magnifyingglass")
                    } description: {
                        Text("別の切符名で検索してみてください。")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    searchResults
                }
            } else if endedSessions.isEmpty {
                ContentUnavailableView {
                    Label("まだ履歴がありません", systemImage: "clock")
                } description: {
                    Text("発車して到着・途中下車するとここに残ります。")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                calendarDay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(TrainTheme.platform)
        .navigationTitle("履歴")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(TrainTheme.platform, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("今日") {
                    selectedDay = calendar.startOfDay(for: Date())
                }
                .disabled(calendar.isDateInToday(selectedDay) || isSearchPresented)
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    WeeklyReportView()
                } label: {
                    Text("週次")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    toggleSearch()
                } label: {
                    Image(systemName: isSearchPresented ? "xmark" : "magnifyingglass")
                }
                .accessibilityLabel(isSearchPresented ? "検索を閉じる" : "検索")
            }
        }
        .sheet(isPresented: $showDatePicker) {
            datePickerSheet
        }
        .sheet(item: selectedRideBinding) { item in
            if let session = endedSessions.first(where: { $0.id == item.id }) {
                NavigationStack {
                    HistoryRideDetailView(
                        session: session,
                        onReissue: reissue,
                        onDelete: deleteSession
                    )
                }
                .presentationDetents([.medium, .large])
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.visible)
            }
        }
        .errorAlert(isPresented: $showError, message: errorMessage)
        .onAppear(perform: focusInitialDayIfNeeded)
        .sensoryFeedback(.selection, trigger: selectedDayKey)
    }

    private var searchFieldRow: some View {
        HStack(spacing: TrainTheme.Space.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("切符名で検索", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFieldFocused)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("入力を消す")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, TrainTheme.Space.md)
        .padding(.vertical, TrainTheme.Space.sm)
        .background(TrainTheme.platform)
    }

    private var calendarDay: some View {
        VStack(spacing: 0) {
            HistoryCalendarStrip(
                selectedDay: selectedDay,
                daysWithRides: daysWithRides,
                visibleDayKeys: visibleDayKeys,
                rangeStart: canvasDayRange.start,
                rangeEnd: canvasDayRange.end,
                onSelect: { day in
                    selectedDay = calendar.startOfDay(for: day)
                },
                onShowDatePicker: { showDatePicker = true }
            )
            .padding(.horizontal, TrainTheme.Space.md)
            .padding(.top, TrainTheme.Space.xs)
            .padding(.bottom, TrainTheme.Space.sm)

            if rideDensity.showsStatsHeader, !selectedDaySessions.isEmpty {
                DailyStatsHeader(
                    dayKey: selectedDayKey,
                    aggregate: HistoryStats.aggregate(sessions: selectedDaySessions),
                    showsDay: false
                )
                .padding(.horizontal, TrainTheme.Space.md)
                .padding(.bottom, TrainTheme.Space.sm)
            }

            GeometryReader { geo in
                HistoryDayPager(
                    sessionsByDay: sessionsByDay,
                    dayStrip: dayStrip,
                    selectedDay: $selectedDay,
                    daysVisible: $daysVisible,
                    minHeight: geo.size.height,
                    viewportWidth: geo.size.width,
                    onSelect: { session in
                        selectedRideID = session.id
                    },
                    onReissue: reissue,
                    onDelete: deleteSession
                )
                .safeAreaPadding(.bottom)
            }
            .padding(.horizontal, rideDensity == .day ? TrainTheme.Space.md : TrainTheme.Space.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(TrainTheme.platform)
    }

    private func toggleSearch() {
        if isSearchPresented {
            isSearchPresented = false
            searchText = ""
            searchFieldFocused = false
        } else {
            isSearchPresented = true
            searchFieldFocused = true
        }
    }

    private var searchResults: some View {
        List {
            ForEach(groups, id: \.dayKey) { group in
                Section {
                    ForEach(group.sessions, id: \.id) { session in
                        Button {
                            if let endedAt = session.endedAt {
                                selectedDay = calendar.startOfDay(for: endedAt)
                            }
                            selectedRideID = session.id
                            searchText = ""
                            isSearchPresented = false
                            searchFieldFocused = false
                        } label: {
                            searchRow(session)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(DayKeyFormatting.displayDay(from: group.dayKey))
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func searchRow(_ session: WorkSession) -> some View {
        let ride = SessionTimeline.rides(from: [session]).first
        return HStack(alignment: .firstTextBaseline, spacing: TrainTheme.Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ride?.title ?? session.ticket?.title ?? "不明な切符")
                    .font(TrainTheme.TypeScale.ticketTitle())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let ride {
                    Text(
                        "\(Self.timeFormatter.string(from: ride.startedAt))–\(Self.timeFormatter.string(from: ride.endedAt))"
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            HistoryOutcomeBadge(session: session)
        }
    }

    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker(
                "日付",
                selection: $selectedDay,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .padding(.horizontal, TrainTheme.Space.md)
            .navigationTitle("日付を選ぶ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        selectedDay = calendar.startOfDay(for: selectedDay)
                        showDatePicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var selectedRideBinding: Binding<RideSheetItem?> {
        Binding(
            get: { selectedRideID.map(RideSheetItem.init(id:)) },
            set: { selectedRideID = $0?.id }
        )
    }

    private func focusInitialDayIfNeeded() {
        guard !didFocusInitialDay else { return }
        didFocusInitialDay = true
        let todayKey = HistoryStats.dayKey(for: Date(), calendar: calendar)
        if daysWithRides.contains(todayKey) { return }
        guard let latest = HistoryStats.groupByDay(sessions: endedSessions, calendar: calendar).first,
              let date = HistoryStats.date(from: latest.dayKey, calendar: calendar)
        else { return }
        selectedDay = date
    }

    private func deleteSession(_ session: WorkSession) {
        let title = session.ticket?.title ?? "不明な切符"
        let remainingIDs = session.ticket?.sessions.map(\.id) ?? [session.id]
        let deletesTicket = TicketDeletion.shouldDeleteOrphanTicket(
            remainingSessionIDs: remainingIDs,
            removing: session.id
        )
        do {
            if deletesTicket, let ticket = session.ticket {
                let record = DeletionUndo.captureTicket(ticket)
                try sessionManager.deleteEndedSession(session)
                undoCenter.offer(
                    message: DeletionUndo.bannerMessage(
                        historyTicketTitle: title,
                        deletedTicketToo: true
                    )
                ) {
                    withAnimation {
                        try? sessionManager.restoreDeletedTicket(record)
                    }
                }
            } else {
                let record = DeletionUndo.captureSession(session)
                try sessionManager.deleteEndedSession(session)
                undoCenter.offer(
                    message: DeletionUndo.bannerMessage(
                        historyTicketTitle: title,
                        deletedTicketToo: false
                    )
                ) {
                    withAnimation {
                        try? sessionManager.restoreDeletedSession(record)
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func reissue(from ticket: Ticket) {
        let nextOrder = nextSortOrder()
        let copy = TicketReissue.makeTodayCopy(from: ticket, sortOrder: nextOrder)
        modelContext.insert(copy)
        try? modelContext.save()
    }

    private func nextSortOrder() -> Int {
        let descriptor = FetchDescriptor<Ticket>(
            predicate: #Predicate { $0.closedAt == nil },
            sortBy: [SortDescriptor(\.sortOrder, order: .reverse)]
        )
        let maxOrder = (try? modelContext.fetch(descriptor).first?.sortOrder) ?? -1
        return maxOrder + 1
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct RideSheetItem: Identifiable {
    var id: UUID
}

#Preview("直近日") {
    let container = try! AppModelContainer.make(inMemory: true)
    HistoryPreviewSeed.insertSampleWeek(into: container.mainContext)
    let manager = SessionManager(modelContext: container.mainContext)
    return NavigationStack {
        HistoryView()
            .environment(manager)
            .environment(DeletionUndoCenter())
            .environment(TicketMotionBridge())
            .modelContainer(container)
    }
}

#Preview("重なりのある火曜") {
    let container = try! AppModelContainer.make(inMemory: true)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    HistoryPreviewSeed.insertSampleWeek(into: container.mainContext, calendar: calendar)
    let tuesday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8))!
    let manager = SessionManager(modelContext: container.mainContext)
    return NavigationStack {
        HistoryView(focusDay: tuesday)
            .environment(manager)
            .environment(DeletionUndoCenter())
            .environment(TicketMotionBridge())
            .modelContainer(container)
    }
}
