//
//  ServiceBootCover.swift
//  Todo train
//
//  運行開始の門. 起動 → 今日が揃う → 発車用意 → ホームへ。
//  演出の正本は Issue #53。
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
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Ticket.sortOrder) private var allTickets: [Ticket]

    @State private var phase: ServiceGatePhase = .entering
    @State private var illuminateElapsed: TimeInterval = 0
    @State private var departElapsed: TimeInterval = 0
    @State private var skipIlluminate = false
    @State private var primeProgress: Double = 0
    @State private var lastPrimeTick = -1
    @State private var leadTicketID: UUID?
    @State private var occupancyHapticCount = 0
    @State private var didReadyHaptic = false
    @State private var ignitionPressed = false
    @State private var completeFlash = false

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
            return .dormant
        case .illuminating:
            return ServiceGateSequence.reveal(elapsed: illuminateElapsed, context: gateContext)
        case .readyToPrime, .priming, .departing, .done:
            return ServiceGateSequence.reveal(
                elapsed: ServiceGateSequence.illuminateDuration(context: gateContext),
                context: gateContext
            )
        }
    }

    private var departBeat: ServiceGateDepartBeat {
        switch phase {
        case .departing, .done:
            return ServiceGateSequence.departBeat(elapsed: departElapsed, reduceMotion: reduceMotion)
        default:
            return .sealed
        }
    }

    var body: some View {
        GeometryReader { geo in
            gateLayers(size: geo.size)
        }
        .environment(\.colorScheme, .dark)
        .presentationBackground(coverBackground)
        .interactiveDismissDisabled(phase != .done)
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
            let tick = Int(progress * 4)
            if tick != lastPrimeTick, phase == .priming, progress < 1 {
                lastPrimeTick = tick
                ServiceGateHaptics.primeTick(progress: progress)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var coverBackground: Color {
        departBeat == .opening ? Self.platformOpenFill : Color.black
    }

    @ViewBuilder
    private func gateLayers(size: CGSize) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if phase == .entering || phase == .awaitingIgnition {
                ignitionAtmosphere
            }
            litDeck
            if phase == .priming {
                primeWash
            }
            ignitionLayer(width: min(size.width - 56, 420))
            primeLayer
            if completeFlash {
                Color.white.opacity(0.42)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            if departBeat != .sealed {
                platformAperture(size: size)
            }
        }
    }

    @ViewBuilder
    private var litDeck: some View {
        if phase >= .illuminating {
            TimelineView(.periodic(from: .now, by: 0.05)) { context in
                deck(now: context.date)
            }
            .opacity(deckOpacity)
            .scaleEffect(departCabinScale, anchor: .bottom)
            .offset(y: departCabinOffset)
            .animation(
                reduceMotion ? .easeOut(duration: 0.14) : ServiceCabinMotion.departUnlock,
                value: departBeat
            )
        }
    }

    @ViewBuilder
    private func ignitionLayer(width: CGFloat) -> some View {
        if phase == .awaitingIgnition || phase == .entering {
            ignitionControl
                .frame(width: width, height: 78)
                .opacity(phase == .awaitingIgnition ? 1 : 0.22)
                .scaleEffect(phase == .awaitingIgnition ? 1 : 0.92)
                .allowsHitTesting(phase == .awaitingIgnition)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private var primeLayer: some View {
        if phase == .readyToPrime || phase == .priming {
            VStack {
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
                primeControl
                    .frame(height: 88)
            }
            .padding(.bottom, 18)
        }
    }

    private var deckOpacity: Double {
        switch departBeat {
        case .sealed:
            return 1
        case .unlocking:
            return reduceMotion ? 0.55 : 0.72
        case .opening:
            return 0
        }
    }

    private var departCabinScale: CGFloat {
        switch departBeat {
        case .sealed:
            return 1
        case .unlocking:
            return reduceMotion ? 0.98 : 0.94
        case .opening:
            return 0.88
        }
    }

    private var departCabinOffset: CGFloat {
        switch departBeat {
        case .sealed:
            return 0
        case .unlocking:
            return reduceMotion ? -8 : -18
        case .opening:
            return -40
        }
    }

    private var ignitionAtmosphere: some View {
        TimelineView(.periodic(from: .now, by: reduceMotion ? 1 : 0.05)) { context in
            let breath = reduceMotion ? 0.45 : (sin(context.date.timeIntervalSinceReferenceDate * 1.6) + 1) / 2
            RadialGradient(
                colors: [
                    Color.white.opacity(0.10 + 0.08 * breath),
                    Color.white.opacity(0.03 + 0.02 * breath),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 280
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    private var primeWash: some View {
        GeometryReader { geo in
            VStack {
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.02),
                        Color.white.opacity(0.10 + 0.38 * primeProgress)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: geo.size.height * (0.28 + 0.72 * primeProgress))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func platformAperture(size: CGSize) -> some View {
        let progress: CGFloat = {
            switch departBeat {
            case .sealed:
                return 0
            case .unlocking:
                return reduceMotion ? 0.22 : 0.18
            case .opening:
                return 1
            }
        }()
        let width = max(8, size.width * progress)
        let height = max(12, size.height * (departBeat == .opening ? 1 : 0.42 + 0.2 * progress))
        return RoundedRectangle(cornerRadius: departBeat == .opening ? 0 : 18, style: .continuous)
            .fill(Self.platformOpenFill)
            .frame(width: width, height: height)
            .scaleEffect(departBeat == .opening ? 1.04 : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.14) : ServiceCabinMotion.departOpen,
                value: departBeat
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func deck(now: Date) -> some View {
        let occupancy = occupancyInstrument(now: now)
        let extras = extraNotices(now: now, occupancyRows: occupancy.rows)
        ServiceGateDeck(
            reveal: reveal,
            primeProgress: phase == .priming ? primeProgress : 0,
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

    private var ignitionControl: some View {
        IgnitionPressControl(
            title: "起動",
            skipAfter: 0.65,
            pressed: $ignitionPressed,
            reduceMotion: reduceMotion,
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
            reduceMotion: reduceMotion,
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
                completeFlash = true
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
            await runDepart()
        default:
            break
        }
    }

    private func runIlluminate() async {
        let duration = ServiceGateSequence.illuminateDuration(context: gateContext)
        let step: TimeInterval = reduceMotion ? duration : 0.04
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

    private func runDepart() async {
        completeFlash = false
        let duration = ServiceGateSequence.departDuration(reduceMotion: reduceMotion)
        let step: TimeInterval = 0.03
        var elapsed: TimeInterval = 0
        while elapsed < duration {
            try? await Task.sleep(for: .seconds(step))
            if Task.isCancelled { return }
            elapsed = min(duration, elapsed + step)
            departElapsed = elapsed
        }
        phase = ServiceGateSequence.advance(phase, .departElapsed)
        dismiss()
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

    private static let platformOpenFill = Color(red: 0.95, green: 0.95, blue: 0.97)

    private var accessibilityLabel: String {
        switch phase {
        case .entering:
            return "運行の内側"
        case .awaitingIgnition:
            return "起動"
        case .illuminating:
            return reveal.fullLit ? "盤が灯った" : (reveal.isPeak ? "今日が読める" : "今日が揃う")
        case .readyToPrime, .priming:
            return "発車用意"
        case .departing, .done:
            return "ホーム"
        }
    }
}

private extension ServiceGateSequence.Reveal {
    static let dormant = ServiceGateSequence.Reveal(
        rise: 0,
        wash: 0,
        bloom: 0,
        theatricalLampCount: 0,
        plaque: nil,
        serviceLit: false,
        dateLit: false,
        clockProgress: 0,
        occupancyLive: 0,
        consistLive: 0,
        tapeLive: false,
        canInteract: false,
        canPrime: false,
        isPeak: false,
        fullLit: false
    )
}
