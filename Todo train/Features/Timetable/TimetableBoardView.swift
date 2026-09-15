//
//  TimetableBoardView.swift
//  Todo train
//

import SwiftData
import SwiftUI

struct TimetableBoardView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.calendar) private var calendar
    @Query(sort: \TimetableBlock.startsAt) private var blocks: [TimetableBlock]

    @State private var occurrences: [CalendarOccurrence] = []
    @State private var showManual = false
    @State private var manualTitle = ""
    @State private var manualStart = Date()
    @State private var manualEnd = Date().addingTimeInterval(30 * 60)
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var pendingOccurrence: CalendarOccurrence?

    private var todayBlocks: [TimetableBlock] {
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return blocks.filter { $0.isActive && $0.startsAt < end && $0.endsAt > start }
    }

    var body: some View {
        List {
            if let message = sessionManager.timetableQuietMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                if todayBlocks.isEmpty {
                    Text("今日載せた枠はありません。掲示から選ぶか、時刻を引いてください。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(todayBlocks, id: \.id) { block in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(block.title)
                            Text(rangeLabel(block.startsAt, block.endsAt))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button(TimetableCopy.unadopt, role: .destructive) {
                                try? sessionManager.unadopt(block: block, seriesToo: false)
                            }
                            if block.adoptionScope == .series || block.calendarRecurrenceIdentifier != nil {
                                Button("今後もしない") {
                                    try? sessionManager.unadopt(block: block, seriesToo: true)
                                }
                            }
                        }
                    }
                }
                Button(TimetableCopy.manualAdd) {
                    manualStart = Date()
                    manualEnd = Date().addingTimeInterval(30 * 60)
                    showManual = true
                }
            } header: {
                Text(TimetableCopy.board)
            }

            Section {
                if sessionManager.calendarBoard.authorization == .denied {
                    Text(TimetableCopy.calendarDenied)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if occurrences.isEmpty {
                    Text("今日の掲示はありません。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(occurrences.filter(\.isAdoptable)) { occurrence in
                        Button {
                            pendingOccurrence = occurrence
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(occurrence.title.isEmpty ? "予定" : occurrence.title)
                                        .foregroundStyle(.primary)
                                    Text(rangeLabel(occurrence.startsAt, occurrence.endsAt))
                                        .font(.footnote.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isAdopted(occurrence) {
                                    Text(TimetableCopy.board)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(TrainTheme.rail)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text(TimetableCopy.notice)
            }
        }
        .navigationTitle(TimetableCopy.board)
        .task { await reloadBoard() }
        .refreshable { await reloadBoard() }
        .confirmationDialog(TimetableCopy.adopt, isPresented: Binding(
            get: { pendingOccurrence != nil },
            set: { if !$0 { pendingOccurrence = nil } }
        ), titleVisibility: .visible) {
            if let pendingOccurrence {
                Button(TimetableCopy.thisOccurrence) {
                    adopt(pendingOccurrence, scope: .occurrence)
                }
                if pendingOccurrence.recurrenceIdentifier != nil {
                    Button(TimetableCopy.thisSeries) {
                        adopt(pendingOccurrence, scope: .series)
                    }
                }
                Button("キャンセル", role: .cancel) {
                    self.pendingOccurrence = nil
                }
            }
        }
        .sheet(isPresented: $showManual) {
            NavigationStack {
                Form {
                    TextField("題名", text: $manualTitle)
                    DatePicker("開始", selection: $manualStart, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("終了", selection: $manualEnd, displayedComponents: [.date, .hourAndMinute])
                }
                .navigationTitle(TimetableCopy.manualAdd)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") { showManual = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("載せる") {
                            try? sessionManager.adoptManualBlock(
                                title: manualTitle,
                                startsAt: manualStart,
                                endsAt: manualEnd
                            )
                            showManual = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .errorAlert(isPresented: $showError, message: errorMessage)
    }

    private func adopt(_ occurrence: CalendarOccurrence, scope: TimetableAdoptionScope) {
        do {
            try sessionManager.adoptOccurrence(occurrence, scope: scope)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        pendingOccurrence = nil
    }

    private func isAdopted(_ occurrence: CalendarOccurrence) -> Bool {
        todayBlocks.contains { block in
            block.calendarEventIdentifier == occurrence.eventIdentifier
                && abs(block.startsAt.timeIntervalSince(occurrence.startsAt)) < 1
        }
    }

    private func rangeLabel(_ start: Date, _ end: Date) -> String {
        "\(BoardingForecast.timeString(from: start))–\(BoardingForecast.timeString(from: end))"
    }

    private func reloadBoard() async {
        await sessionManager.refreshCalendarBoard()
        occurrences = sessionManager.noticeOccurrences
    }
}
