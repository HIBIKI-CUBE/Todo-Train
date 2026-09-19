//
//  ServiceBootCover.swift
//  Todo train
//
//  運行開始の門. 起動 → 今日が揃う → 発車用意 → ホームへ。
//

import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ServiceBootCover: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Ticket.sortOrder) private var allTickets: [Ticket]

    @State private var phase: ServiceGatePhase = .entering
    @State private var illuminateElapsed: TimeInterval = 0
    @State private var skipIlluminate = false
    @State private var primeProgress: Double = 0
    @State private var lastPrimeTick = -1
    @State private var leadTicketID: UUID?
    @State private var occupancyHapticCount = 0
    @State private var didReadyHaptic = false

    private var openTickets: [Ticket] {
        allTickets.filter(\.isOpen)
    }

    private var dayText: String {
        let key = sessionManager.activeServiceDay?.calendarDayKey
            ?? ServiceDay.dayKey(for: sessionManager.clock.now, calendar: sessionManager.calendar)
        return DayKeyFormatting.displayDay(from: key)
    }

    private var gateContext: ServiceGateSequence.Context {
        let occupancy = occupancyInstrument(now: sessionManager.clock.now)
        let extras = extraNotices(now: sessionManager.clock.now, occupancyRows: occupancy.rows)
        return ServiceGateSequence.Context(
            occupancyCount: occupancy.rows.count + extras.count,
            consistCount: openTickets.count,
            reduceMotion: reduceMotion,
            skipIlluminate: skipIlluminate
        )
    }

    private var reveal: ServiceGateSequence.Reveal {
        switch phase {
        case .entering, .awaitingIgnition:
            return ServiceGateSequence.reveal(elapsed: 0, context: gateContext)
                .darkened
        case .illuminating:
            return ServiceGateSequence.reveal(elapsed: illuminateElapsed, context: gateContext)
        case .readyToPrime, .priming, .departing, .done:
            return ServiceGateSequence.reveal(
                elapsed: ServiceGateSequence.illuminateDuration(context: gateContext),
                context: gateContext
            )
        }
    }

    var body: some View {
        ZStack {
            CabinBackground(phase: .cruise, reduceTransparency: reduceTransparency)
                .opacity(phase == .departing || phase == .done ? (reduceMotion ? 0.35 : 0) : 1)

            if phase == .departing || phase == .done {
                Color.white.opacity(reduceMotion ? 0.10 : 0.20)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                TimelineView(.periodic(from: .now, by: 0.05)) { context in
                    deck(now: context.date)
                }
                if phase >= .readyToPrime {
                    console
                }
            }
            .opacity(panelOpacity)
            .scaleEffect(departScale, anchor: .center)
            .offset(y: phase == .departing || phase == .done ? -28 : 0)

            if phase == .awaitingIgnition {
                ignitionControl
                    .frame(height: 72)
                    .padding(.horizontal, 28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .environment(\.colorScheme, .dark)
        .presentationBackground(.black)
        .safeAreaPadding(.top, 4)
        .interactiveDismissDisabled(phase != .done)
        .animation(reduceMotion ? .easeOut(duration: 0.22) : ServiceCabinMotion.clockLock, value: phase)
        .task {
            await sessionManager.refreshCalendarBoardIfAuthorized()
            await runEnter()
        }
        .task(id: phase) {
            await runPhaseTask()
        }
        .onChange(of: reveal.occupancyLive) { _, live in
            if live > occupancyHapticCount {
                occupancyHapticCount = live
                ServiceGateHaptics.occupancyLanded()
            }
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .readyToPrime, !didReadyHaptic {
                didReadyHaptic = true
                ServiceGateHaptics.readyToPrime()
            }
        }
        .onChange(of: primeProgress) { _, progress in
            let tick = Int(progress * 3)
            if tick != lastPrimeTick, phase == .priming, progress < 1 {
                lastPrimeTick = tick
                ServiceGateHaptics.primeTick(progress: progress)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var panelOpacity: Double {
        switch phase {
        case .entering:
            return 0
        case .departing, .done:
            return reduceMotion ? 0.2 : 0
        default:
            return 1
        }
    }

    private var departScale: CGFloat {
        if phase == .departing || phase == .done {
            return reduceMotion ? 1.02 : 1.06
        }
        return 1
    }

    @ViewBuilder
    private func deck(now: Date) -> some View {
        if phase == .entering || phase == .awaitingIgnition {
            Color.clear
        } else {
            let occupancy = occupancyInstrument(now: now)
            let extras = extraNotices(now: now, occupancyRows: occupancy.rows)
            ServiceGateDeck(
                reveal: reveal,
                dayText: dayText,
                now: now,
                occupancyRows: occupancy.rows,
                occupancyMarks: occupancy.marks,
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
                consistTickets: openTickets,
                leadTicketID: leadTicketID ?? openTickets.first?.id,
                calendarAuthorization: sessionManager.calendarBoard.authorizationStatus(),
                onMakeLead: makeLead,
                onMoveConsist: moveConsist,
                onRequestCalendar: {
                    Task { await requestCalendar() }
                }
            )
        }
    }

    @ViewBuilder
    private var console: some View {
        VStack(spacing: 0) {
            FocusControlDivider()
            primeControl
                .frame(height: 72)
        }
    }

    private var ignitionControl: some View {
        IgnitionPressControl(
            title: "起動",
            skipAfter: 0.65,
            onTap: { ignite(skip: false) },
            onSkip: { ignite(skip: true) }
        )
        .accessibilityHint("今日の運行の内側を起こす。長押しで揃えを短くする")
    }

    private var primeControl: some View {
        PrimeHoldControl(
            title: "発車用意",
            holdSeconds: ServiceGateSequence.primeHoldSeconds,
            progress: $primeProgress,
            enabled: phase == .readyToPrime || phase == .priming,
            onBegan: {
                phase = ServiceGateSequence.advance(phase, .primeBegan)
            },
            onCancelled: {
                phase = ServiceGateSequence.advance(phase, .primeCancelled)
                primeProgress = 0
                lastPrimeTick = -1
            },
            onCompleted: {
                ServiceGateHaptics.primeComplete()
                phase = ServiceGateSequence.advance(phase, .primeCompleted)
            }
        )
        .accessibilityHint("押し続けてホームへ出る")
    }

    private func ignite(skip: Bool) {
        guard phase == .awaitingIgnition else { return }
        skipIlluminate = skip || reduceMotion
        ServiceGateHaptics.ignite()
        phase = ServiceGateSequence.advance(phase, .ignited(skipIlluminate: skipIlluminate))
        if skipIlluminate {
            illuminateElapsed = ServiceGateSequence.illuminateDuration(context: gateContext)
        }
    }

    private func runEnter() async {
        ServiceGateHaptics.enter()
        try? await Task.sleep(for: .seconds(ServiceGateSequence.enterHoldSeconds))
        if Task.isCancelled { return }
        phase = ServiceGateSequence.advance(phase, .enterElapsed)
    }

    private func runPhaseTask() async {
        switch phase {
        case .illuminating:
            await runIlluminate()
        case .departing:
            let duration = ServiceGateSequence.departDuration(reduceMotion: reduceMotion)
            try? await Task.sleep(for: .seconds(duration))
            if Task.isCancelled { return }
            phase = ServiceGateSequence.advance(phase, .departElapsed)
            dismiss()
        default:
            break
        }
    }

    private func runIlluminate() async {
        let duration = ServiceGateSequence.illuminateDuration(context: gateContext)
        let step: TimeInterval = reduceMotion ? duration : 0.05
        var elapsed: TimeInterval = 0
        while elapsed < duration {
            try? await Task.sleep(for: .seconds(step))
            if Task.isCancelled { return }
            elapsed = min(duration, elapsed + step)
            illuminateElapsed = elapsed
            if phase != .illuminating { return }
        }
        phase = ServiceGateSequence.advance(phase, .illuminateElapsed)
    }

    private func makeLead(_ ticket: Ticket) {
        var ordered = openTickets
        ordered.removeAll { $0.id == ticket.id }
        ordered.insert(ticket, at: 0)
        reindex(ordered)
        leadTicketID = ticket.id
        try? modelContext.save()
    }

    private func moveConsist(_ ticket: Ticket, offset: Int) {
        var ordered = openTickets
        guard let index = ordered.firstIndex(where: { $0.id == ticket.id }) else { return }
        let destination = index + offset
        guard ordered.indices.contains(destination) else { return }
        ordered.swapAt(index, destination)
        reindex(ordered)
        if destination == 0 {
            leadTicketID = ticket.id
        } else if leadTicketID == ticket.id {
            leadTicketID = ordered.first?.id
        }
        try? modelContext.save()
    }

    private func reindex(_ ordered: [Ticket]) {
        for (index, ticket) in ordered.enumerated() {
            ticket.sortOrder = index
        }
    }

    private func requestCalendar() async {
        _ = await sessionManager.calendarBoard.requestAccess()
        await sessionManager.refreshCalendarBoardIfAuthorized()
        #if canImport(UIKit)
        if sessionManager.calendarBoard.authorizationStatus() == .denied,
           let url = URL(string: UIApplication.openSettingsURLString) {
            await UIApplication.shared.open(url)
        }
        #endif
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

    private var accessibilityLabel: String {
        switch phase {
        case .entering:
            return "運行の内側"
        case .awaitingIgnition:
            return "起動"
        case .illuminating:
            return reveal.isPeak ? "今日が読める" : "今日が揃う"
        case .readyToPrime, .priming:
            return "発車用意"
        case .departing, .done:
            return "ホーム"
        }
    }
}

private extension ServiceGateSequence.Reveal {
    var darkened: ServiceGateSequence.Reveal {
        var copy = self
        copy.edgeLift = 0
        copy.wash = 0
        copy.theatricalLampCount = 0
        copy.plaque = nil
        copy.serviceLit = false
        copy.dateLit = false
        copy.clockProgress = 0
        copy.occupancySilhouettes = 0
        copy.occupancyLive = 0
        copy.consistSilhouettes = 0
        copy.consistLive = 0
        copy.tapeLive = false
        copy.canInteract = false
        copy.canPrime = false
        copy.isPeak = false
        return copy
    }
}

private struct IgnitionPressControl: View {
    var title: String
    var skipAfter: TimeInterval
    var onTap: () -> Void
    var onSkip: () -> Void

    @State private var pressStarted: Date?

    var body: some View {
        Text(title)
            .font(.system(size: 22, weight: .bold, design: .default))
            .foregroundStyle(FocusPanel.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FocusPanel.fillRaised)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if pressStarted == nil {
                            pressStarted = .now
                        }
                    }
                    .onEnded { _ in
                        let duration = Date.now.timeIntervalSince(pressStarted ?? .now)
                        pressStarted = nil
                        if duration >= skipAfter {
                            onSkip()
                        } else {
                            onTap()
                        }
                    }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(title)
            .accessibilityAction {
                onTap()
            }
    }
}

private struct PrimeHoldControl: View {
    var title: String
    var holdSeconds: TimeInterval
    var progress: Binding<Double>
    var enabled: Bool
    var onBegan: () -> Void
    var onCancelled: () -> Void
    var onCompleted: () -> Void

    @State private var pressStarted: Date?
    @State private var holding = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: holding ? 0.03 : 1)) { context in
            let current = currentProgress(at: context.date)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    FocusPanel.fillRaised
                    FocusPanel.ink.opacity(0.18 + 0.16 * current)
                        .frame(width: geo.size.width * current)
                    Text(title)
                        .font(.system(size: 22, weight: .bold, design: .default))
                        .foregroundStyle(FocusPanel.ink)
                        .frame(maxWidth: .infinity)
                }
            }
            .opacity(enabled ? 1 : 0.45)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard enabled else { return }
                    if pressStarted == nil {
                        pressStarted = .now
                        holding = true
                        onBegan()
                    }
                    if let pressStarted {
                        let value = min(1, Date.now.timeIntervalSince(pressStarted) / holdSeconds)
                        progress.wrappedValue = value
                        if value >= 1 {
                            finish()
                        }
                    }
                }
                .onEnded { _ in
                    guard holding else { return }
                    if (progress.wrappedValue) >= 1 {
                        finish()
                    } else {
                        holding = false
                        pressStarted = nil
                        progress.wrappedValue = 0
                        onCancelled()
                    }
                }
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(title)
        .accessibilityHint("押し続ける")
        .accessibilityAction {
            onBegan()
            onCompleted()
        }
    }

    private func currentProgress(at date: Date) -> Double {
        guard let pressStarted, holding else { return progress.wrappedValue }
        return min(1, date.timeIntervalSince(pressStarted) / holdSeconds)
    }

    private func finish() {
        guard holding else { return }
        holding = false
        pressStarted = nil
        progress.wrappedValue = 1
        onCompleted()
    }
}
