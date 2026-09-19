//
//  ServiceBootCover.swift
//  Todo train
//
//  運行開始: Focus panel comes up together. Occupancy 着発 is the hand.
//  Consist is confirmation. 切符へ leaves.
//

import SwiftData
import SwiftUI

struct ServiceBootCover: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Query(sort: \Ticket.sortOrder) private var allTickets: [Ticket]

    @State private var lamp: ServiceCabinLamp = .dark

    private var dayText: String {
        let key = sessionManager.activeServiceDay?.calendarDayKey
            ?? ServiceDay.dayKey(for: sessionManager.clock.now, calendar: sessionManager.calendar)
        return DayKeyFormatting.displayDay(from: key)
    }

    private var consistItems: [ServiceCabinConsistItem] {
        ServiceCabinSequence.consistItems(from: allTickets)
    }

    var body: some View {
        ZStack {
            CabinBackground(phase: .cruise, reduceTransparency: reduceTransparency)

            VStack(spacing: 0) {
                GeometryReader { geo in
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        instruments(now: context.date, height: geo.size.height)
                    }
                }
                console
            }
            .opacity(lamp == .dark ? 0 : 1)
            .animation(nil, value: lamp == .dark)
        }
        .environment(\.colorScheme, .dark)
        .presentationBackground(.black)
        .safeAreaPadding(.top, 4)
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.78), trigger: lamp == .test)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.62), trigger: lamp == .ready)
        .task {
            await sessionManager.refreshCalendarBoardIfAuthorized()
            await runBoot()
        }
    }

    private func instruments(now: Date, height: CGFloat) -> some View {
        let occupancy = occupancyInstrument(now: now)
        let extras = extraNotices(now: now, occupancyRows: occupancy.rows)
        let hasPrep = !occupancy.rows.isEmpty || !extras.isEmpty || !consistItems.isEmpty
        let clockHeight = min(max(height * (hasPrep ? 0.28 : 0.55), 120), 220)

        return ServiceCabinInstruments(
            lamp: lamp,
            occupancyRows: occupancy.rows,
            occupancyMarks: occupancy.marks,
            dayText: dayText,
            now: now,
            paused: sessionManager.pausedCountTowardLimit > 0,
            occupancyActionTitle: occupancy.actionTitle,
            occupancyAction: occupancy.action,
            additionalOccupancyRows: extras.map(\.row),
            additionalActionTitle: TimetableCopy.adopt,
            additionalAction: { rowID in
                guard let occurrence = extras.first(where: { $0.row.id == rowID })?.occurrence else {
                    return
                }
                sessionManager.adoptOccurrence(occurrence, scope: .occurrence)
            },
            consistItems: consistItems,
            clockHeight: clockHeight,
            expandsClock: !hasPrep,
            pinsLower: hasPrep
        )
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var console: some View {
        VStack(spacing: 0) {
            FocusControlDivider()
            Button("切符へ") {
                dismiss()
            }
            .buttonStyle(
                FocusControlCellStyle(
                    fill: FocusPanel.fillRaised,
                    foreground: FocusPanel.ink
                )
            )
            .font(.system(size: 20, weight: .bold, design: .default))
            .frame(height: 72)
            .accessibilityHint("Hub に戻る。運行は始まっています")
        }
    }

    private func extraNotices(
        now: Date,
        occupancyRows: [TimetableOccupancyRow]
    ) -> [(occurrence: CalendarOccurrence, row: TimetableOccupancyRow)] {
        ServiceCabinSequence.morningNotices(
            remaining: sessionManager.remainingUnadoptedNotices(at: now),
            occupancyRows: occupancyRows,
            now: now
        )
        .map { occurrence in
            (
                occurrence,
                TimetableFit.occupancyRow(
                    for: occurrence,
                    now: now,
                    calendar: sessionManager.calendar
                )
            )
        }
    }

    private func occupancyInstrument(now: Date) -> (
        rows: [TimetableOccupancyRow],
        marks: [TimetableOccupancyMark],
        actionTitle: String?,
        action: (() -> Void)?
    ) {
        let fit = sessionManager.timetableFit(at: now)
        let rows = TimetableFit.occupancyRows(
            fit: fit,
            now: now,
            calendar: sessionManager.calendar
        )
        let marks = TimetableFit.occupancyMarks(fit: fit, now: now)
        if fit.currentOccupancy?.isAdopted == true {
            return (rows, marks, TimetableCopy.unadopt, { sessionManager.unadoptCurrentOccurrence() })
        }
        if fit.currentOccupancy?.isAdopted == false {
            return (rows, marks, TimetableCopy.adopt, { sessionManager.adoptCurrentNoticeThisTime() })
        }
        return (rows, marks, nil, nil)
    }

    private func runBoot() async {
        if reduceMotion {
            lamp = .ready
            return
        }
        try? await Task.sleep(for: .seconds(ServiceCabinSequence.darkHoldSeconds))
        if Task.isCancelled { return }
        lamp = .test
        try? await Task.sleep(for: .seconds(ServiceCabinSequence.testHoldSeconds))
        if Task.isCancelled { return }
        lamp = .live
        try? await Task.sleep(for: .seconds(ServiceCabinSequence.liveHoldSeconds))
        if Task.isCancelled { return }
        lamp = .ready
    }
}
