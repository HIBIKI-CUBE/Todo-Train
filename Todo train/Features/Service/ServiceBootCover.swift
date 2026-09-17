//
//  ServiceBootCover.swift
//  Todo train
//
//  運行開始: the cabin lights. Density is spectacle.
//  運行中 and occupancy are Hub/Focus instruments. 切符へ is the hand.
//

import SwiftUI

struct ServiceBootCover: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var lamp: ServiceCabinLamp = .dark
    @State private var lampTick = 0

    private var dayText: String {
        let key = sessionManager.activeServiceDay?.calendarDayKey
            ?? ServiceDay.dayKey(for: sessionManager.clock.now, calendar: sessionManager.calendar)
        return DayKeyFormatting.displayDay(from: key)
    }

    var body: some View {
        ZStack {
            ServiceCabinCanopy(
                lamp: lamp,
                sweepTick: lampTick,
                reduceTransparency: reduceTransparency
            )
            VStack(spacing: 0) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    cabinBody(now: context.date)
                }
                console
            }
        }
        .environment(\.colorScheme, .dark)
        .presentationBackground(.black)
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.9), trigger: lampTick)
        .task {
            await sessionManager.refreshCalendarBoardIfAuthorized()
            await runBoot()
        }
    }

    private var console: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: FocusPanel.hairlineWidth)
            ServiceCabinKey(title: "切符へ", kind: .stand) {
                dismiss()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .accessibilityHint("Hub に戻る。運行は始まっています")
        }
        .background(Color.black.opacity(0.72))
    }

    private func cabinBody(now: Date) -> some View {
        let occupancy = occupancyInstrument(now: now)
        return ScrollView {
            ServiceCabinInstruments(
                lamp: lamp,
                occupancyRows: occupancy.rows,
                occupancyMarks: occupancy.marks,
                dayText: dayText,
                clockText: now.formatted(date: .omitted, time: .shortened),
                occupancyActionTitle: occupancy.actionTitle,
                occupancyAction: occupancy.action
            )
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
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
            lamp = .circuits
            lampTick += 1
            return
        }
        try? await Task.sleep(for: .seconds(ServiceCabinSequence.darkHoldSeconds))
        if Task.isCancelled { return }
        while lamp < .circuits {
            let nextRaw = lamp.rawValue + 1
            lamp = ServiceCabinLamp(rawValue: nextRaw) ?? .circuits
            lampTick += 1
            if lamp == .circuits { return }
            try? await Task.sleep(for: .seconds(ServiceCabinSequence.stepSeconds))
            if Task.isCancelled { return }
        }
    }
}
