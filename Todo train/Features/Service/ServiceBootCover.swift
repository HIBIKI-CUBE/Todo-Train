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

/// Presents the start gate over the TabView so the tab bar never leaks into the cabin.
@Observable
final class ServicePortalPresentation {
    var isBootCoverPresented = false

    func presentBootCover() {
        setBootCoverPresented(true)
    }

    func dismissBootCover() {
        setBootCoverPresented(false)
    }

    private func setBootCoverPresented(_ presented: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isBootCoverPresented = presented
        }
    }
}

struct ServiceBootCover: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(ServicePortalPresentation.self) private var servicePortal
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

    private var roomCharge: Double {
        ServicePortalSequence.roomCharge(isPriming: phase == .priming, progress: primeProgress)
    }

    private var departStaging: ServicePortalSequence.DepartStaging {
        ServicePortalSequence.departStaging(elapsed: departElapsed, reduceMotion: reduceMotion)
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.periodic(from: .now, by: timelineStep)) { context in
                portal(size: geo.size, now: context.date)
            }
        }
        .environment(\.colorScheme, .dark)
        .persistentSystemOverlays(.hidden)
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
        case .entering, .awaitingIgnition, .illuminating, .priming, .departing:
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
        case .entering, .awaitingIgnition:
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
        Rectangle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.32 + 0.58 * roomCharge)
                    ],
                    center: .center,
                    startRadius: size.width * (0.22 - 0.14 * roomCharge),
                    endRadius: size.width * (0.82 - 0.22 * roomCharge)
                )
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func chamber(now: Date, presence: ServicePortalSequence.Presence) -> some View {
        let occupancy = occupancyInstrument(now: now)
        let extras = extraNotices(now: now, occupancyRows: occupancy.rows)
        let staging = departStaging
        ServicePortalChamber(
            presence: presence,
            roomCharge: roomCharge,
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
        .scaleEffect(departBeat == .sealed ? 1 : staging.cabinScale)
        .opacity(departBeat == .sealed ? 1 : staging.cabinOpacity)
        .animation(reduceMotion ? .easeOut(duration: 0.10) : PortalCoverMotion.depart, value: departBeat)
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
                    onIgnite: { ignite(skip: reduceMotion) },
                    onHoldSkip: skipAssemble
                )
                .frame(width: width)
                .padding(.bottom, 118)
            }
            .allowsHitTesting(canHitIgnition)
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
                        ServicePortalHaptics.primeBegan()
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
        let aperture = departBeat == .sealed ? 0 : departStaging.aperture
        return ZStack {
            RoundedRectangle(cornerRadius: aperture >= 0.95 ? 0 : 26, style: .continuous)
                .fill(MarsTicketSpec.paper)
                .frame(
                    width: max(12, size.width * aperture),
                    height: max(12, size.height * aperture)
                )
                .shadow(color: Color.white.opacity(aperture > 0 && aperture < 1 ? 0.35 : 0), radius: 28)
            if aperture > 0.55 {
                ticketDeckSilhouettes
                    .padding(.horizontal, 32)
                    .opacity((aperture - 0.55) / 0.45)
                    .scaleEffect(0.90 + 0.10 * aperture)
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(reduceMotion ? .easeOut(duration: 0.10) : PortalCoverMotion.aperture, value: departBeat)
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
                    .padding(.horizontal, CGFloat(index) * 8)
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
            return illuminateElapsed < 0.70
        default:
            return false
        }
    }

    private var canHitIgnition: Bool {
        phase == .awaitingIgnition || (phase == .illuminating && illuminateElapsed < 0.70)
    }

    private var ignitionHandoff: Double {
        guard phase == .illuminating else { return 0 }
        return min(1, illuminateElapsed / ServicePortalSequence.ignitionHandoffSeconds)
    }

    private func ignite(skip: Bool) {
        guard phase == .awaitingIgnition else { return }
        skipIlluminate = skip
        ServicePortalHaptics.ignite()
        phase = ServicePortalSequence.advance(phase, .ignited(skipIlluminate: skipIlluminate))
        if skipIlluminate {
            illuminateElapsed = ServicePortalSequence.illuminateDuration(context: portalContext)
        }
    }

    private func skipAssemble() {
        guard phase == .illuminating else { return }
        skipIlluminate = true
        illuminateElapsed = ServicePortalSequence.illuminateDuration(context: portalContext)
        phase = ServicePortalSequence.advance(phase, .illuminateElapsed)
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
        servicePortal.dismissBootCover()
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
    static let depart = Animation.easeOut(duration: ServicePortalSequence.departSlitSeconds)
    static let aperture = Animation.easeOut(duration: ServicePortalSequence.departFloodSeconds)
}
