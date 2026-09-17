//
//  ServiceShutdownCover.swift
//  Todo train
//
//  運行終了: result in a TIMS well, then lamps go out.
//

import SwiftUI

struct ServiceShutdownCover: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var onError: (String) -> Void

    @State private var lamp: ServiceCabinLamp = .circuits
    @State private var lampTick = 0
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
            ServiceCabinCanopy(
                lamp: lamp,
                poweringDown: poweringDown,
                sweepTick: lampTick,
                reduceTransparency: reduceTransparency
            )
            VStack(spacing: 0) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    cabinBody(now: context.date)
                }
                console
            }
            .opacity(poweringDown && lamp == .dark ? 0.15 : 1)
        }
        .environment(\.colorScheme, .dark)
        .presentationBackground(.black)
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.9), trigger: lampTick)
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
        VStack(spacing: 10) {
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: FocusPanel.hairlineWidth)
            HStack(spacing: 10) {
                ServiceCabinKey(title: "キャンセル", kind: .cancel, enabled: !poweringDown) {
                    dismiss()
                }
                ServiceCabinKey(
                    title: "運行終了",
                    kind: .power,
                    enabled: canConfirmEnd
                ) {
                    Task { await powerOff() }
                }
                .accessibilityHint(canConfirmEnd ? "計器を落として運行を終了する" : endBlockedReason)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .padding(.top, 4)
        }
        .background(Color.black.opacity(0.72))
    }

    private func cabinBody(now: Date) -> some View {
        let occupancy = occupancyInstrument(now: now)
        return ScrollView {
            VStack(spacing: 14) {
                ServiceCabinInstruments(
                    lamp: lamp,
                    occupancyRows: occupancy.rows,
                    occupancyMarks: occupancy.marks,
                    dayText: dayText,
                    clockText: now.formatted(date: .omitted, time: .shortened),
                    statusText: statusText,
                    occupancyActionTitle: occupancy.actionTitle,
                    occupancyAction: occupancy.action
                )

                if lamp >= .occupancy {
                    ServiceCabinWell(
                        powered: lamp >= .occupancy,
                        emphasis: !poweringDown
                    ) {
                        resultClock
                            .allowsHitTesting(!poweringDown)
                    }
                }

                if lamp >= .circuits, !poweringDown {
                    pausedBlock
                    unlabeledBlock
                    if !canConfirmEnd {
                        Text(endBlockedReason)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(FocusPanel.muted)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 24)
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
            ServiceCabinWell(powered: true, emphasis: true) {
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
                                    .tint(LEDPhosphor.on)

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
            ServiceCabinWell(powered: true) {
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
                                    .tint(LEDPhosphor.on)
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
            lampTick += 1
        } else {
            while lamp > .dark {
                try? await Task.sleep(for: .seconds(ServiceCabinSequence.stepSeconds))
                if Task.isCancelled { return }
                lamp = ServiceCabinLamp(rawValue: lamp.rawValue - 1) ?? .dark
                lampTick += 1
            }
            try? await Task.sleep(for: .seconds(ServiceCabinSequence.powerOffHoldSeconds))
        }
        do {
            try sessionManager.endService()
            dismiss()
        } catch {
            poweringDown = false
            lamp = .circuits
            present(error)
        }
    }

    private func present(_ error: Error) {
        localError = error.localizedDescription
        showLocalError = true
        onError(error.localizedDescription)
    }
}
