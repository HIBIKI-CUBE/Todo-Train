//
//  ServiceShutdownCover.swift
//  Todo train
//
//  運行終了: today's trace on the Focus panel, then the panel goes dark.
//

import SwiftUI

struct ServiceShutdownCover: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var onError: (String) -> Void

    @State private var lamp: ServiceCabinLamp = .ready
    @State private var poweringDown = false
    @State private var canvasLaunch: TransferCanvasLaunch?
    @State private var localError = ""
    @State private var showLocalError = false

    private var pausedSessions: [WorkSession] {
        sessionManager.pausedSessions
    }

    private var canConfirmEnd: Bool {
        pausedSessions.isEmpty
            && sessionManager.phase != .running
            && sessionManager.phase != .overtime
            && !poweringDown
    }

    private var dayKey: String {
        sessionManager.activeServiceDay?.calendarDayKey
            ?? ServiceDay.dayKey(for: sessionManager.clock.now, calendar: sessionManager.calendar)
    }

    private var resultDay: Date {
        HistoryStats.date(from: dayKey, calendar: sessionManager.calendar)
            ?? sessionManager.calendar.startOfDay(for: sessionManager.clock.now)
    }

    private var daySessions: [WorkSession] {
        sessionManager.workSessions(onDayKey: dayKey)
    }

    private var unlabeled: [SessionExtension] {
        ServiceCabinSequence.unlabeledExtensions(in: daySessions)
    }

    private var dayText: String {
        DayKeyFormatting.displayDay(from: dayKey)
    }

    private var statusText: String {
        sessionManager.needsServiceDayEndPrompt ? "昨日の運行が開いたまま" : "運行中"
    }

    var body: some View {
        ZStack {
            CabinBackground(phase: .cruise, reduceTransparency: reduceTransparency)

            VStack(spacing: 0) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    cabinBody(now: context.date)
                }
                console
            }
            .opacity(poweringDown && lamp == .dark ? 0 : 1)
            .animation(.easeInOut(duration: 0.45), value: poweringDown && lamp == .dark)
        }
        .environment(\.colorScheme, .dark)
        .presentationBackground(.black)
        .safeAreaPadding(.top, 4)
        .interactiveDismissDisabled(poweringDown)
        .sheet(item: $canvasLaunch) { launch in
            RemainingTicketsCanvas(parent: launch.parent, fromSessionID: launch.sessionID)
        }
        .alert("エラー", isPresented: $showLocalError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(localError)
        }
    }

    private var console: some View {
        VStack(spacing: 0) {
            FocusControlDivider()
            HStack(spacing: 0) {
                Button("キャンセル") {
                    dismiss()
                }
                .buttonStyle(
                    FocusControlCellStyle(
                        fill: FocusPanel.fill,
                        foreground: FocusPanel.muted
                    )
                )
                .font(.system(size: 17, weight: .bold, design: .default))
                .disabled(poweringDown)

                FocusControlVerticalDivider()

                Button("運行終了") {
                    Task { await powerOff() }
                }
                .buttonStyle(
                    FocusControlCellStyle(
                        fill: canConfirmEnd ? TrainTheme.signalRed : FocusPanel.fill,
                        foreground: canConfirmEnd ? Color.white : FocusPanel.dim
                    )
                )
                .font(.system(size: 20, weight: .bold, design: .default))
                .disabled(!canConfirmEnd)
                .accessibilityHint(canConfirmEnd ? "盤を落として運行を終了する" : endBlockedReason)
            }
            .frame(height: 72)
        }
    }

    private func cabinBody(now: Date) -> some View {
        let occupancy = occupancyInstrument(now: now)
        return ScrollView {
            VStack(spacing: 0) {
                ServiceCabinInstruments(
                    lamp: lamp,
                    occupancyRows: occupancy.rows,
                    occupancyMarks: occupancy.marks,
                    dayText: dayText,
                    now: now,
                    statusText: statusText,
                    paused: !pausedSessions.isEmpty,
                    occupancyActionTitle: occupancy.actionTitle,
                    occupancyAction: occupancy.action,
                    facts: ServiceCabinSequence.dayFacts(in: daySessions)
                )

                if lamp >= .live {
                    FocusControlDivider()
                    ServiceCabinPanel(powered: true) {
                        resultClock
                            .allowsHitTesting(!poweringDown)
                    }
                }

                if lamp >= .ready, !poweringDown {
                    pausedBlock
                    unlabeledBlock
                    if !canConfirmEnd {
                        FocusControlDivider()
                        ServiceCabinPanel(powered: true) {
                            Text(endBlockedReason)
                                .font(.footnote)
                                .foregroundStyle(FocusPanel.muted)
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var resultClock: some View {
        let layout = SessionTimeline.calendarDayLayout(
            on: resultDay,
            calendar: sessionManager.calendar
        )
        return HistoryDayClockView(
            sessions: daySessions,
            day: resultDay,
            sharedLayout: layout,
            density: .compact,
            showsGutter: true,
            minHeight: 0,
            onSelect: { _ in },
            onDelete: { _ in },
            strips: sessionManager.historyStrips(onDayKey: dayKey),
            openEndedAt: sessionManager.clock.now
        )
        .accessibilityLabel("今日の跡")
    }

    @ViewBuilder
    private var pausedBlock: some View {
        if pausedSessions.isEmpty {
            EmptyView()
        } else {
            FocusControlDivider()
            ServiceCabinPanel(powered: true) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(pausedSessions, id: \.id) { session in
                        if let ticket = session.ticket {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(ticket.title)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(FocusPanel.ink)

                                HStack(spacing: 8) {
                                    Button("途中下車") {
                                        disembark(session, ticket: ticket)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.white)

                                    Button("放棄", role: .destructive) {
                                        abandon(session)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .accessibilityElement(children: .contain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var unlabeledBlock: some View {
        if unlabeled.isEmpty {
            EmptyView()
        } else {
            FocusControlDivider()
            ServiceCabinPanel(powered: true) {
                VStack(alignment: .leading, spacing: TrainTheme.Space.md) {
                    ForEach(unlabeled, id: \.id) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(unlabeledCaption(item))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(FocusPanel.ink)
                            HStack(spacing: 8) {
                                ForEach(ServiceCabinSequence.extendReasons, id: \.self) { reason in
                                    Button(reason) {
                                        sessionManager.setExtensionReason(reason, on: item)
                                    }
                                    .font(.caption.weight(.semibold))
                                    .buttonStyle(.bordered)
                                    .tint(.white)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var endBlockedReason: String {
        if sessionManager.phase == .running || sessionManager.phase == .overtime {
            return "走行中は運行終了できません。"
        }
        if !pausedSessions.isEmpty {
            return "停車中を途中下車または放棄してから終了できます。"
        }
        return ""
    }

    private func unlabeledCaption(_ item: SessionExtension) -> String {
        let minutes = max(item.addedSeconds / 60, 1)
        let title = item.session?.ticket?.title ?? "延長"
        return "\(title) +\(minutes)分"
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

    private func disembark(_ session: WorkSession, ticket: Ticket) {
        let sessionID = session.id
        do {
            try sessionManager.partialDisembark(session: session)
            canvasLaunch = TransferCanvasLaunch(parent: ticket, sessionID: sessionID)
        } catch {
            present(error)
        }
    }

    private func abandon(_ session: WorkSession) {
        do {
            try sessionManager.abandon(session: session)
        } catch {
            present(error)
        }
    }

    private func powerOff() async {
        guard canConfirmEnd else { return }
        poweringDown = true
        if reduceMotion {
            lamp = .dark
        } else {
            while lamp > .dark {
                try? await Task.sleep(for: .seconds(ServiceCabinSequence.stepSeconds))
                if Task.isCancelled { return }
                lamp = ServiceCabinLamp(rawValue: lamp.rawValue - 1) ?? .dark
            }
            try? await Task.sleep(for: .seconds(ServiceCabinSequence.powerOffHoldSeconds))
        }
        do {
            try sessionManager.endService()
            dismiss()
        } catch {
            poweringDown = false
            lamp = .ready
            present(error)
        }
    }

    private func present(_ error: Error) {
        localError = error.localizedDescription
        showLocalError = true
        onError(error.localizedDescription)
    }
}
