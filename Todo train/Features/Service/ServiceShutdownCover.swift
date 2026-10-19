//
//  ServiceShutdownCover.swift
//  Todo train
//
//  運行終了: today's trace on the Focus panel, then the panel goes dark.
//

import SwiftUI
import TodoTrainTicketUI

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
    @State private var prefaceHeight: CGFloat = 168
    @State private var viewportHeight: CGFloat = 0
    @State private var overviewSettled = false
    @State private var bundleFocusIndex = 0

    private static let overviewID = "service-overview"
    private static let bundleID = "ticket-stamp-bundle"
    private static let minimumClockHeight: CGFloat = 88
    /// 区切り線と「キャンセル / 運行終了」の行。扇の安全領域の下端に含める。
    private static let consoleBlockHeight: CGFloat = 72 + FocusPanel.hairlineWidth

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

    private var stampBundle: TicketStampBundleAssembly.DayBundle? {
        sessionManager.ticketStampBundle(forCalendarDayKey: dayKey)
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
                .accessibilityHint(canConfirmEnd ? "盤を落として運行を終了します" : endBlockedReason)
            }
            .frame(height: Self.consoleBlockHeight - FocusPanel.hairlineWidth)
        }
    }

    private func cabinBody(now: Date) -> some View {
        GeometryReader { geo in
            let stampCount = stampBundle?.stamps.count ?? 0
            let clockFloor = Self.minimumClockHeight + 4
            let fittingPreface = max(0, geo.size.height - clockFloor - prefaceHeight)
            // 前文まで残すと横向きで束が消える。そのときは前文をスクロールに回し、時計の下限だけ守る。
            let prefaceFits = fittingPreface >= 96
            let bundleReserve = stampCount == 0 ? 0 : TicketStampBundleLayout.collapsedFanSize.height
            let scrollHeight = geo.size.height
            let clockHeight = max(
                Self.minimumClockHeight,
                scrollHeight - prefaceHeight - 4
            )
            ZStack(alignment: .bottomTrailing) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            preface(now: now)
                                .onGeometryChange(for: CGFloat.self) { proxy in
                                    proxy.size.height
                                } action: { height in
                                    guard height > 1, abs(height - prefaceHeight) > 1 else { return }
                                    prefaceHeight = height
                                }

                            if lamp >= .live {
                                FocusControlDivider()
                                overviewClock(now: now, height: clockHeight)
                                    .id(Self.overviewID)
                            }

                            if lamp >= .ready, !poweringDown {
                                pausedBlock
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
                    .contentMargins(.bottom, bundleReserve, for: .scrollContent)
                    // 前文と時計が同時に入らないときは、下端（時計）を最初から見せる。
                    .defaultScrollAnchor(prefaceFits ? .top : .bottom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { viewportHeight = scrollHeight }
                    .onChange(of: scrollHeight) { _, height in
                        viewportHeight = height
                    }
                    .onChange(of: lamp) { _, newLamp in
                        if newLamp < .live { overviewSettled = false }
                    }
                    .onChange(of: overviewSettled) { _, settled in
                        guard settled else { return }
                        let clock = max(Self.minimumClockHeight, viewportHeight - prefaceHeight)
                        guard prefaceHeight + clock > viewportHeight + 8 else { return }
                        if reduceMotion {
                            proxy.scrollTo(Self.overviewID, anchor: .top)
                        } else {
                            withAnimation(ServiceCabinMotion.overviewPush) {
                                proxy.scrollTo(Self.overviewID, anchor: .top)
                            }
                        }
                    }
                    .task(id: lamp >= .live) {
                        await pushOverview()
                    }
                }

                if let stampBundle, lamp >= .live {
                    TicketStampBundleDeckView(
                        stamps: stampBundle.stamps,
                        focusIndex: $bundleFocusIndex,
                        style: .shutdown,
                        dayBoundaries: [],
                        pinnedSpread: previewPinnedSpread,
                        playsSpreadDemo: previewPlaysSpreadDemo,
                        layoutViewport: CGSize(
                            width: max(80, geo.size.width - TicketStampBundleLayout.safeMargin * 2),
                            height: max(80, geo.size.height + Self.consoleBlockHeight)
                        ),
                        bottomObstacle: Self.consoleBlockHeight
                    )
                    .padding(.trailing, TicketStampBundleLayout.fanTrailingPadding)
                    .padding(.bottom, TicketStampBundleLayout.bottomClearance)
                    .zIndex(4)
                    .allowsHitTesting(!poweringDown)
                    .onAppear {
                        #if DEBUG
                        if sessionManager.uiPreviewShowsServiceShutdown {
                            bundleFocusIndex = min(
                                sessionManager.uiPreviewBundleFocusIndex,
                                max(0, stampBundle.stamps.count - 1)
                            )
                            return
                        }
                        #endif
                        bundleFocusIndex = max(0, stampBundle.stamps.count - 1)
                    }
                }
            }
        }
    }

    private func preface(now: Date) -> some View {
        let occupancy = occupancyInstrument(now: now)
        return ServiceCabinInstruments(
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
    }

    private func overviewClock(now: Date, height: CGFloat) -> some View {
        let window = overviewWindow(now: now, height: height)
        let layout = window.layout(calendar: sessionManager.calendar)
        return ZStack {
            HistoryDayClockView(
                sessions: daySessions,
                day: resultDay,
                sharedLayout: layout,
                density: .compact,
                showsGutter: true,
                minHeight: 0,
                onSelect: { _ in },
                onDelete: { _ in },
                strips: sessionManager.historyStrips(onDayKey: dayKey),
                openEndedAt: now,
                hourLabelStride: ServiceCabinOverview.hourStride(pointsPerMinute: window.pointsPerMinute)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .frame(height: height)
        .background(Color.black)
        .clipped()
        .allowsHitTesting(!poweringDown)
        .accessibilityLabel("今日の跡")
        .animation(reduceMotion ? nil : ServiceCabinMotion.overviewPush, value: overviewSettled)
    }

    private func overviewWindow(now: Date, height: CGFloat) -> ServiceCabinOverviewWindow {
        let calendar = sessionManager.calendar
        let slack = HistoryDayClockView.topSlack
        if reduceMotion || overviewSettled {
            let dayStart = calendar.startOfDay(for: resultDay)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
                ?? dayStart.addingTimeInterval(86_400)
            let bounds = ServiceCabinOverview.serviceBounds(
                startedAt: sessionManager.activeServiceDay?.startedAt,
                now: now,
                dayStart: dayStart,
                dayEnd: dayEnd,
                rides: rideBounds(now: now, dayStart: dayStart, dayEnd: dayEnd)
            )
            return ServiceCabinOverview.fitted(
                bounds: bounds,
                viewportHeight: height,
                calendar: calendar,
                slack: slack
            )
        }
        return ServiceCabinOverview.fullDay(
            on: resultDay,
            viewportHeight: height,
            calendar: calendar,
            slack: slack
        )
    }

    private func rideBounds(now: Date, dayStart: Date, dayEnd: Date) -> [(start: Date, end: Date)] {
        daySessions.compactMap { session in
            let end = min(dayEnd, session.endedAt ?? now)
            let start = max(dayStart, session.startedAt)
            guard end > start else { return nil }
            return (start, end)
        }
    }

    private func pushOverview() async {
        guard lamp >= .live else { return }
        if reduceMotion {
            overviewSettled = true
            return
        }
        overviewSettled = false
        try? await Task.sleep(for: .milliseconds(520))
        if Task.isCancelled { return }
        withAnimation(ServiceCabinMotion.overviewPush) {
            overviewSettled = true
        }
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

    private var endBlockedReason: String {
        if sessionManager.phase == .running || sessionManager.phase == .overtime {
            return "走行中は運行終了できません。"
        }
        if !pausedSessions.isEmpty {
            return "停車中を途中下車または放棄してから終了できます。"
        }
        return ""
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

    private var previewPinnedSpread: CGFloat? {
        #if DEBUG
        if let value = sessionManager.uiPreviewBundleSpread {
            return CGFloat(value)
        }
        #endif
        return nil
    }

    private var previewPlaysSpreadDemo: Bool {
        #if DEBUG
        sessionManager.uiPreviewBundleFanDemo
        #else
        false
        #endif
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
