//
//  ServiceBootCover.swift
//  Todo train
//
//  運行開始の門。起動 → 今日が揃う → 発車用意 → ホームへ。
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

    @State private var phase: ServicePortalPhase = .entering
    @State private var illuminateElapsed: TimeInterval = 0
    @State private var departElapsed: TimeInterval = 0
    @State private var skipIlluminate = false
    @State private var primeProgress: Double = 0
    @State private var lastPrimeTick = -1
    @State private var leadTicketID: UUID?
    @State private var occupancyHapticCount = 0
    @State private var didReadyHaptic = false

    private var openTickets: [Ticket] {
        allTickets.filter(\.isOpen)
    }

    private var consistItems: [ServiceCabinConsistItem] {
        ServiceCabinSequence.consistItems(from: allTickets)
    }

    private var dayText: String {
        let key = sessionManager.activeServiceDay?.calendarDayKey
            ?? ServiceDay.dayKey(for: sessionManager.clock.now, calendar: sessionManager.calendar)
        return DayKeyFormatting.displayDay(from: key)
    }

    private var portalContext: ServicePortalSequence.Context {
        let occupancy = occupancyInstrument(now: sessionManager.clock.now)
        let extras = extraNotices(now: sessionManager.clock.now, occupancyRows: occupancy.rows)
        return ServicePortalSequence.Context(
            occupancyCount: occupancy.rows.count + extras.count,
            consistCount: openTickets.count,
            reduceMotion: reduceMotion,
            skipIlluminate: skipIlluminate
        )
    }

    private var departBeat: ServicePortalDepartBeat {
        switch phase {
        case .departing, .done:
            return ServicePortalSequence.departBeat(elapsed: departElapsed, reduceMotion: reduceMotion)
        default:
            return .sealed
        }
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.periodic(from: .now, by: timelineStep)) { context in
                portal(size: geo.size, now: context.date)
            }
        }
        .environment(\.colorScheme, .dark)
        .presentationBackground(Color.black)
        .interactiveDismissDisabled(phase != .done)
        .task {
            await sessionManager.refreshCalendarBoardIfAuthorized()
            await runEnter()
        }
        .task(id: phase) {
            await runPhaseTask()
        }
        .onChange(of: occupancyLive) { _, live in
            if live > occupancyHapticCount {
                occupancyHapticCount = live
                ServicePortalHaptics.occupancyLanded()
            }
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .readyToPrime, !didReadyHaptic {
                didReadyHaptic = true
                ServicePortalHaptics.readyToPrime()
            }
        }
        .onChange(of: primeProgress) { _, progress in
            let tick = Int(progress * 4)
            if tick != lastPrimeTick, phase == .priming, progress < 1 {
                lastPrimeTick = tick
                ServicePortalHaptics.primeTick(progress: progress)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var occupancyLive: Int {
        presence(now: sessionManager.clock.now, breath: 0).occupancyLive
    }

    private var timelineStep: TimeInterval {
        if reduceMotion { return 0.2 }
        switch phase {
        case .awaitingIgnition, .illuminating, .priming, .departing:
            return 0.04
        default:
            return 0.2
        }
    }

    private func portal(size: CGSize, now: Date) -> some View {
        let breath = reduceMotion ? 0.55 : (sin(now.timeIntervalSinceReferenceDate * 1.55) + 1) / 2
        let current = presence(now: now, breath: breath)
        return ZStack {
            Color.black.ignoresSafeArea()
            walls(size: size)
            chamber(now: now, presence: current)
            ignitionLayer(width: min(size.width - 48, 420), breath: breath)
            primeLayer
            platformAperture(size: size)
        }
    }

    private func presence(now: Date, breath: Double) -> ServicePortalSequence.Presence {
        switch phase {
        case .entering:
            return ServicePortalSequence.sealedPlace()
        case .awaitingIgnition:
            return ServicePortalSequence.premonition(breath: breath)
        case .illuminating:
            return ServicePortalSequence.reveal(elapsed: illuminateElapsed, context: portalContext)
        case .readyToPrime, .priming, .departing, .done:
            return ServicePortalSequence.reveal(
                elapsed: ServicePortalSequence.illuminateDuration(context: portalContext),
                context: portalContext
            )
        }
    }

    private func walls(size: CGSize) -> some View {
        let tighten = phase == .priming ? primeProgress : 0
        return Rectangle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.35 + 0.40 * tighten)
                    ],
                    center: .center,
                    startRadius: size.width * (0.18 - 0.06 * tighten),
                    endRadius: size.width * (0.78 - 0.12 * tighten)
                )
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func chamber(now: Date, presence: ServicePortalSequence.Presence) -> some View {
        if phase != .entering {
            let occupancy = occupancyInstrument(now: now)
            let extras = extraNotices(now: now, occupancyRows: occupancy.rows)
            ServicePortalChamber(
                presence: presence,
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
                consistItems: consistItems,
                leadTicketID: leadTicketID ?? consistItems.first?.id,
                calendarAuthorization: sessionManager.calendarBoard.authorizationStatus(),
                onMakeLead: makeLead,
                onRequestCalendar: {
                    Task { await requestCalendar() }
                }
            )
            .opacity(chamberOpacity)
            .offset(y: chamberSink)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : PortalCoverMotion.depart, value: departBeat)
        }
    }

    @ViewBuilder
    private func ignitionLayer(width: CGFloat, breath: Double) -> some View {
        if showsIgnition {
            VStack {
                Spacer(minLength: 0)
                PortalIgnitionBar(
                    title: "起動",
                    skipAfter: 0.65,
                    breath: breath,
                    handoff: ignitionHandoff,
                    reduceMotion: reduceMotion,
                    onTap: { ignite(skip: false) },
                    onSkip: { ignite(skip: true) }
                )
                .frame(width: width)
                .padding(.bottom, 118)
            }
            .allowsHitTesting(phase == .awaitingIgnition)
        }
    }

    @ViewBuilder
    private var primeLayer: some View {
        if phase == .readyToPrime || phase == .priming {
            VStack {
                Spacer(minLength: 0)
                PortalPrimeLip(
                    title: "発車用意",
                    holdSeconds: ServicePortalSequence.primeHoldSeconds,
                    progress: $primeProgress,
                    enabled: phase == .readyToPrime || phase == .priming,
                    reduceMotion: reduceMotion,
                    onBegan: {
                        phase = ServicePortalSequence.advance(phase, .primeBegan)
                    },
                    onCancelled: {
                        phase = ServicePortalSequence.advance(phase, .primeCancelled)
                        primeProgress = 0
                        lastPrimeTick = -1
                    },
                    onCompleted: {
                        ServicePortalHaptics.primeComplete()
                        phase = ServicePortalSequence.advance(phase, .primeCompleted)
                    }
                )
            }
        }
    }

    private func platformAperture(size: CGSize) -> some View {
        let open: CGFloat = {
            switch departBeat {
            case .sealed:
                return 0
            case .slit:
                return reduceMotion ? 0.18 : 0.14
            case .flood:
                return 1
            }
        }()
        return VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                MarsTicketSpec.paper
                if departBeat == .flood {
                    ticketDeckSilhouettes
                        .padding(.bottom, 36)
                }
            }
            .frame(height: max(0, size.height * open))
            Spacer(minLength: 0)
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? .easeOut(duration: 0.12) : PortalCoverMotion.aperture, value: departBeat)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var ticketDeckSilhouettes: some View {
        VStack(spacing: -36) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: MarsTicketSpec.cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.72))
                    .overlay {
                        RoundedRectangle(cornerRadius: MarsTicketSpec.cornerRadius, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.6)
                    }
                    .aspectRatio(MarsTicketSpec.aspectRatio, contentMode: .fit)
                    .padding(.horizontal, 36 + CGFloat(index) * 8)
                    .rotationEffect(.degrees(Double(index - 1) * 2.2))
                    .shadow(color: Color.black.opacity(0.12), radius: 8, y: 4)
            }
        }
    }

    private var showsIgnition: Bool {
        switch phase {
        case .entering, .awaitingIgnition:
            return true
        case .illuminating:
            return illuminateElapsed < ServicePortalSequence.ignitionHandoffSeconds
        default:
            return false
        }
    }

    private var ignitionHandoff: Double {
        guard phase == .illuminating else { return phase == .entering ? 0.55 : 0 }
        return min(1, illuminateElapsed / ServicePortalSequence.ignitionHandoffSeconds)
    }

    private var chamberOpacity: Double {
        switch departBeat {
        case .sealed:
            return 1
        case .slit:
            return reduceMotion ? 0.62 : 0.78
        case .flood:
            return 0
        }
    }

    private var chamberSink: CGFloat {
        switch departBeat {
        case .sealed:
            return 0
        case .slit:
            return reduceMotion ? 10 : 22
        case .flood:
            return 56
        }
    }

    private func ignite(skip: Bool) {
        guard phase == .awaitingIgnition else { return }
        skipIlluminate = skip || reduceMotion
        ServicePortalHaptics.ignite()
        phase = ServicePortalSequence.advance(phase, .ignited(skipIlluminate: skipIlluminate))
        if skipIlluminate {
            illuminateElapsed = ServicePortalSequence.illuminateDuration(context: portalContext)
        }
    }

    private func runEnter() async {
        ServicePortalHaptics.enter()
        try? await Task.sleep(for: .seconds(ServicePortalSequence.enterHoldSeconds))
        if Task.isCancelled { return }
        phase = ServicePortalSequence.advance(phase, .enterElapsed)
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
        let duration = ServicePortalSequence.illuminateDuration(context: portalContext)
        let step: TimeInterval = reduceMotion ? duration : 0.04
        var elapsed: TimeInterval = 0
        while elapsed < duration {
            try? await Task.sleep(for: .seconds(step))
            if Task.isCancelled { return }
            elapsed = min(duration, elapsed + step)
            illuminateElapsed = elapsed
            if phase != .illuminating { return }
        }
        phase = ServicePortalSequence.advance(phase, .illuminateElapsed)
    }

    private func runDepart() async {
        let duration = ServicePortalSequence.departDuration(reduceMotion: reduceMotion)
        let step: TimeInterval = 0.03
        var elapsed: TimeInterval = 0
        while elapsed < duration {
            try? await Task.sleep(for: .seconds(step))
            if Task.isCancelled { return }
            elapsed = min(duration, elapsed + step)
            departElapsed = elapsed
        }
        phase = ServicePortalSequence.advance(phase, .departElapsed)
        dismiss()
    }

    private func makeLead(_ id: UUID) {
        var ordered = openTickets
        guard let ticket = ordered.first(where: { $0.id == id }) else { return }
        ordered.removeAll { $0.id == id }
        ordered.insert(ticket, at: 0)
        for (index, item) in ordered.enumerated() {
            item.sortOrder = index
        }
        leadTicketID = id
        try? modelContext.save()
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
            return "今日が揃う"
        case .readyToPrime, .priming:
            return "発車用意"
        case .departing, .done:
            return "ホーム"
        }
    }
}

private enum PortalCoverMotion {
    static let depart = Animation.easeIn(duration: ServicePortalSequence.departSlitSeconds)
    static let aperture = Animation.easeOut(duration: ServicePortalSequence.departFloodSeconds)
}
