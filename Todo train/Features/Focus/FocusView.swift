//
//  FocusView.swift
//  Todo train
//

import SwiftData
import SwiftUI
import TodoTrainSync

struct FocusView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Environment(TicketMotionBridge.self) private var ticketMotion

    @State private var showPauseLimitSheet = false
    @State private var showInterruptIssue = false
    @State private var showNextRideReserve = false
    @State private var pendingSwitchTicketID: UUID?
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var didPlayOvertimeSound = false
    @State private var overtimePulse = false
    @State private var nudgePulse = false
    @State private var overtimeHaptic = 0
    @State private var didConsumePendingAction = false
    @AppStorage(PunctualityFirstTimeTips.homeStorageKey) private var sawHomeTip = false

    /// Portrait: controls take ~38% of height. Compact: right pane ~40% of width.
    private let portraitControlFraction: CGFloat = 0.38
    private let expandedPortraitControlFraction: CGFloat = 0.44
    private let compactControlFraction: CGFloat = 0.46

    var body: some View {
        ZStack {
            CabinBackground(
                phase: cabinPhase,
                reduceTransparency: reduceTransparency
            )

            GeometryReader { geo in
                if verticalSizeClass == .compact {
                    compactDashboard(proxy: geo)
                } else {
                    portraitDashboard(size: geo.size)
                }
            }
        }
        .sensoryFeedback(.warning, trigger: overtimeHaptic)
        .sensoryFeedback(.warning, trigger: sessionManager.presentation.checkInHapticTick)
        .sheet(isPresented: $showPauseLimitSheet, onDismiss: {
            pendingSwitchTicketID = nil
        }) {
            PauseLimitSheet(
                pendingTicket: pendingSwitchTicketID.flatMap { ticket(id: $0) },
                onSlotFreedTryBoard: {
                    if let pendingSwitchTicketID, let ticket = ticket(id: pendingSwitchTicketID) {
                        presentIssuedInterrupt(TicketIssueEjectEvent(ticket: ticket), ticket: ticket)
                        self.pendingSwitchTicketID = nil
                    }
                }
            )
            .environment(sessionManager)
        }
        .sheet(isPresented: $showInterruptIssue) {
            QuickAddSheet(presentation: .focusInterrupt) { event in
                boardIssuedInterrupt(event)
            }
        }
        .sheet(isPresented: $showNextRideReserve) {
            NextRideReserveSheet()
                .environment(sessionManager)
        }
        .alert("エラー", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            sessionManager.reconcile()
            handleOvertimeSound()
            consumePendingActionIfNeeded()
        }
        .onChange(of: sessionManager.nudgeRingTick) { _, _ in
            playNudgeRing()
        }
        .onChange(of: sessionManager.phase) { _, newPhase in
            if newPhase != .overtime {
                didPlayOvertimeSound = false
                overtimePulse = false
                sessionManager.dismissReestimate()
            } else {
                #if DEBUG
                if sessionManager.uiPreviewSuppressMotion {
                    overtimePulse = false
                } else {
                    overtimePulse = true
                    overtimeHaptic += 1
                    handleOvertimeSound()
                }
                #else
                overtimePulse = true
                overtimeHaptic += 1
                handleOvertimeSound()
                #endif
            }
        }
        .modifier(FocusKeepAwakeModifier(settingEnabled: settings.keepAwakeWhileChargingInFocus))
    }

    private var portraitControlHeightFraction: CGFloat {
        if sessionManager.reestimateRequest != nil || sessionManager.phase == .overtime {
            return expandedPortraitControlFraction
        }
        return portraitControlFraction
    }

    // MARK: - Dashboards

    private func portraitDashboard(size: CGSize) -> some View {
        let controlHeight = size.height * portraitControlHeightFraction
        return VStack(spacing: 0) {
            PassengerFocusBand()
            headerStrip
            FocusControlDivider()
            timerPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            FocusControlDivider()
            telemetryStrip
            FocusControlDivider()
            controlSection
                .frame(height: controlHeight)
        }
        .safeAreaPadding(.top, 4)
    }

    private func compactDashboard(proxy: GeometryProxy) -> some View {
        let size = proxy.size
        let controlWidth = size.width * compactControlFraction
        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                PassengerFocusBand()
                headerStrip
                FocusControlDivider()
                timerPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                FocusControlDivider()
                telemetryStrip
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FocusControlVerticalDivider()

            controlSection
                .frame(width: controlWidth)
                .frame(maxHeight: .infinity)
        }
        .background(FocusPanel.fill.ignoresSafeArea(edges: .trailing))
        .padding(.trailing, -proxy.safeAreaInsets.trailing)
        .safeAreaPadding(.leading, 4)
    }

    // MARK: - Panels

    private var headerStrip: some View {
        HStack(alignment: .center, spacing: TrainTheme.Space.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .default))
                    .foregroundStyle(FocusPanel.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if sessionManager.phase == .overtime || cabinPhase == .overtime {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(CockpitColors.red)
                    .accessibilityLabel("予定の時刻を過ぎています")
            } else if let label = headerStateLabel {
                Text(label)
                    .font(.system(size: 20, weight: .bold, design: .default))
                    .foregroundStyle(headerStateColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.trailing)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(FocusPanel.fill)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(
                    sessionManager.pendingCheckIn == .progress && sessionManager.phase != .overtime
                        ? TrainTheme.signalAmber
                        : cabinPhase.accentColor
                )
                .frame(width: 3)
                .opacity(
                    cabinPhase == .cruise && sessionManager.pendingCheckIn != .progress ? 0 : 1
                )
        }
    }

    private var timerPanel: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = sessionManager.remainingSeconds
            let phase = instrumentPhase(remaining: remaining)

            GeometryReader { geo in
                let fontSize = timerFontSize(in: geo.size)
                Text(CockpitFormat.timerLabel(remaining: remaining))
                    .font(.system(size: fontSize, weight: .semibold, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(phase.accentColor)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .scaleEffect(((overtimePulse || nudgePulse) && !reduceMotion) ? 1.02 : 1)
                    .animation(reduceMotion ? nil : TrainTheme.Motion.pulse, value: overtimePulse)
                    .animation(reduceMotion ? nil : TrainTheme.Motion.pulse, value: nudgePulse)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("残り時間")
                    .accessibilityValue(CockpitFormat.timerLabel(remaining: remaining))
            }
            .onChange(of: context.date) { _, _ in
                // Phase / side effects tick from SessionManager's foreground reconcile.
                handleOvertimeSound()
            }
        }
        .background(Color.black)
        .overlay {
            Rectangle()
                .strokeBorder(currentTimerPhase.panelBorder, lineWidth: FocusPanel.hairlineWidth)
                .padding(0)
                .allowsHitTesting(false)
        }
    }

    private var telemetryStrip: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = sessionManager.remainingSeconds
            let phase = timerPhase(remaining: remaining)
            let occupancy = occupancyInstrument(now: context.date)
            let dispatched = TimetableFit.rideDispatch(
                occupancy: occupancy.progress,
                progress: progressValue(at: context.date)
            )
            let remainingInterval = TimeInterval(max(remaining, 0))
            let clearance = TimetableFit.boardingClearance(
                fit: occupancy.fit,
                now: context.date,
                scheduledArrival: context.date.addingTimeInterval(remainingInterval),
                predictedArrival: nil
            )
            let reservedRide = showsNextRideReserve ? sessionManager.reservedNextTicket() : nil
            let punctuality = punctualityInstrument(now: context.date)

            VStack(spacing: 0) {
                if let punctuality {
                    PunctualityHomeMeterRow(
                        judgment: punctuality.judgment,
                        activeSeconds: punctuality.activeSeconds,
                        budgetSeconds: punctuality.budgetSeconds,
                        sealLuxury: punctuality.sealLuxury,
                        showsFirstTimeTip: !sawHomeTip
                    )
                    .padding(.top, 8)
                    .onAppear {
                        if !sawHomeTip { sawHomeTip = true }
                    }
                }

                FocusProgressBar(
                    progress: dispatched.progress,
                    phase: phase,
                    occupancy: dispatched.occupancy,
                    pinch: clearance == .pinch,
                    overrun: clearance == .overrun,
                    budgetSeconds: punctuality?.budgetSeconds ?? sessionManager.activeSession?.activeBudgetSeconds ?? 1,
                    homeBand: punctuality?.homeBand
                )

                HStack(spacing: TrainTheme.Space.md) {
                    Text(deadlineLabel(remaining: remaining, now: context.date))
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .foregroundStyle(FocusPanel.muted)
                        .monospacedDigit()

                    Spacer(minLength: 0)

                    if let meta = estimateMetaText {
                        Text(meta)
                            .font(.system(size: 14, weight: .medium, design: .default))
                            .foregroundStyle(FocusPanel.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                if !occupancy.rows.isEmpty || reservedRide != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(occupancy.rows) { row in
                            OccupancyDestinationSign(
                                row: row,
                                surface: .cabin,
                                compact: false,
                                actionTitle: row.id == occupancy.rows.first?.id
                                    ? occupancy.actionTitle : nil,
                                action: row.id == occupancy.rows.first?.id
                                    ? occupancy.action : nil
                            )
                        }
                        if let reservedRide {
                            Button {
                                showNextRideReserve = true
                            } label: {
                                ReservedNextRideSign(title: reservedRide.title)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
            }
            .background(FocusPanel.fill)
        }
    }

    private var controlSection: some View {
        Group {
            if sessionManager.reestimateRequest != nil {
                FocusReestimatePanel(
                    activeSeconds: sessionManager.activeSession?.elapsedSeconds(at: .now) ?? 0,
                    remainingSeconds: sessionManager.remainingSeconds,
                    plannedBudgetSeconds: sessionManager.activeSession?.activeBudgetSeconds ?? 1,
                    judgment: {
                        guard let session = sessionManager.activeSession else {
                            return PunctualityJudgment.judge(
                                PunctualityJudgment.RideInput(
                                    arrived: false,
                                    activeSeconds: 0,
                                    estimatedSecondsAtStart: 1
                                )
                            )
                        }
                        return Punctuality.judgment(for: session)
                    }(),
                    recoverySealLuxury: {
                        guard let session = sessionManager.activeSession else { return nil }
                        let commits = session.reestimateEvents
                            .filter { $0.undoneAt == nil }
                            .map {
                                PunctualityJudgment.ReestimateCommit(
                                    reestimateIndex: $0.reestimateIndex,
                                    activeSeconds: $0.activeSeconds,
                                    committedRemainingSeconds: $0.committedRemainingSeconds
                                )
                            }
                        let judgment = Punctuality.judgment(for: session)
                        return PunctualityPresentation.ridingSealLuxury(
                            judgment: judgment,
                            reestimates: commits
                        )
                    }(),
                    now: sessionManager.clock.now,
                    onCommit: { declaration, progress, projectedTotal in
                        run {
                            let active = sessionManager.activeSession?.elapsedSeconds(at: .now) ?? 0
                            let remaining = declaration == .adjust
                                ? max(0, projectedTotal - Int(active.rounded()))
                                : Int(sessionManager.remainingSeconds.rounded())
                            try sessionManager.commitReestimate(
                                mode: .positionReport,
                                progressAnswer: progress,
                                committedRemainingSeconds: remaining,
                                shownBandLowSeconds: nil,
                                shownBandHighSeconds: nil,
                                detailsOpened: false,
                                promptId: ReestimatePromptID.positionV1,
                                declaration: declaration,
                                projectedTotalSeconds: declaration == .adjust ? projectedTotal : nil
                            )
                        }
                    },
                    onArrive: {
                        sessionManager.dismissReestimate()
                        if sessionManager.phase == .overtime {
                            run { try sessionManager.arrive(resolution: .justFinished) }
                        } else {
                            run { try sessionManager.arrive() }
                        }
                    },
                    onClose: { sessionManager.dismissReestimate() },
                    previewConfiguration: {
                        #if DEBUG
                        return sessionManager.focusReestimatePreview
                        #else
                        return nil
                        #endif
                    }()
                )
            } else if sessionManager.phase == .overtime {
                OvertimeControlsView(
                    onAlreadyDone: { run { try sessionManager.arrive(resolution: .alreadyDone) } },
                    onJustFinished: { run { try sessionManager.arrive(resolution: .justFinished) } },
                    onReestimate: { openReestimate(trigger: .planEnd) },
                    onInterrupt: { showInterruptIssue = true },
                    onPause: { pauseWithUndo() }
                )
            } else if sessionManager.pendingCheckIn == .progress {
                CheckInControlsView(
                    prompt: sessionManager.checkInPromptLine,
                    onStillOnIt: { run { try sessionManager.answerCheckIn(.stillOnIt) } },
                    onReestimate: {
                        run { try sessionManager.answerCheckIn(.willExtend) }
                        openReestimate(trigger: .checkIn)
                    }
                )
            } else {
                FocusControlsView(
                    onPause: { pauseWithUndo() },
                    onReserve: { showNextRideReserve = true },
                    onArrive: { run { try sessionManager.arrive() } },
                    onReestimate: { openReestimate(trigger: .manual) },
                    onInterrupt: { showInterruptIssue = true },
                    showsReserve: showsNextRideReserve
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FocusPanel.fill)
        .overlay(alignment: .top) {
            if let offer = sessionManager.focusUndoOffer {
                focusUndoBar(offer)
            }
        }
    }

    // MARK: - Data

    private var title: String {
        sessionManager.activeSession?.ticket?.title ?? "乗務中"
    }

    /// 乗客 aboard 中は予約欄を出さない。ボタン自体も予約した切符を示さない。
    private var showsNextRideReserve: Bool {
        !sessionManager.passengerChrome.locksDriving && sessionManager.fetchOpenPassengerRide() == nil
    }

    private var currentBudgetSeconds: TimeInterval {
        TimeInterval(sessionManager.activeSession?.activeBudgetSeconds ?? 1)
    }

    private var currentTimerPhase: FocusTimerPhase {
        FocusTimerPhase(
            remaining: sessionManager.remainingSeconds,
            budgetSeconds: currentBudgetSeconds
        )
    }

    private var headerStateLabel: String? {
        if sessionManager.phase == .overtime {
            return currentTimerPhase.stateLabel
        }
        if sessionManager.pendingCheckIn == .progress {
            return sessionManager.checkInPromptLine
        }
        return currentTimerPhase.stateLabel
    }

    private var headerStateColor: Color {
        if sessionManager.pendingCheckIn == .progress, sessionManager.phase != .overtime {
            return TrainTheme.signalAmber
        }
        return cabinPhase.accentColor
    }

    private var estimateMetaText: String? {
        guard let session = sessionManager.activeSession else { return nil }
        let estimate = session.estimatedSecondsAtStart
        let budget = session.activeBudgetSeconds
        return "見積もり \(estimate / 60)分 · 予定 \(budget / 60)分"
    }

    private var cabinPhase: FocusTimerPhase {
        instrumentPhase(remaining: sessionManager.remainingSeconds)
    }

    private func instrumentPhase(remaining: TimeInterval) -> FocusTimerPhase {
        if sessionManager.phase == .overtime || remaining <= 0 {
            return timerPhase(remaining: remaining)
        }
        if sessionManager.nudgeCurrentStage == .approach {
            return .approach
        }
        return timerPhase(remaining: remaining)
    }

    private func timerFontSize(in size: CGSize) -> CGFloat {
        let byWidth = size.width * 0.48
        let byHeight = size.height * 0.72
        let capped: CGFloat = verticalSizeClass == .compact ? 140 : 220
        return min(byWidth, byHeight, capped)
    }

    private func progressValue(at now: Date) -> Double {
        guard let session = sessionManager.activeSession else { return 0 }
        let budget = max(TimeInterval(session.activeBudgetSeconds), 1)
        return session.elapsedSeconds(at: now) / budget
    }

    private func timerPhase(remaining: TimeInterval) -> FocusTimerPhase {
        FocusTimerPhase(remaining: remaining, budgetSeconds: currentBudgetSeconds)
    }

    private func deadlineLabel(remaining: TimeInterval, now: Date) -> String {
        let deadline = now.addingTimeInterval(remaining)
        return CockpitFormat.scheduledLabel(deadline: deadline) ?? "予定 —"
    }

    private func punctualityInstrument(now: Date) -> (
        judgment: PunctualityJudgment.Judgment,
        activeSeconds: TimeInterval,
        budgetSeconds: Int,
        sealLuxury: Double?,
        homeBand: (start: Double, end: Double)?
    )? {
        guard let session = sessionManager.activeSession, session.isOpen else { return nil }
        let judgment = Punctuality.judgment(for: session)
        let active = session.elapsedSeconds(at: now)
        let budget = max(session.activeBudgetSeconds, 1)
        let commits = session.reestimateEvents
            .filter { $0.undoneAt == nil }
            .map {
                PunctualityJudgment.ReestimateCommit(
                    reestimateIndex: $0.reestimateIndex,
                    activeSeconds: $0.activeSeconds,
                    committedRemainingSeconds: $0.committedRemainingSeconds
                )
            }
        let luxury = PunctualityPresentation.ridingSealLuxury(judgment: judgment, reestimates: commits)
        let band = PunctualityPresentation.homeBandFractions(judgment: judgment, budgetSeconds: budget)
        return (judgment, active, budget, luxury, band)
    }

    private func occupancyInstrument(now: Date) -> (
        fit: TimetableFitSnapshot,
        rows: [TimetableOccupancyRow],
        progress: TimetableProgressOccupancy,
        actionTitle: String?,
        action: (() -> Void)?
    ) {
        let fit = sessionManager.timetableFit(at: now)
        let rows = TimetableFit.occupancyRows(
            fit: fit,
            now: now,
            calendar: sessionManager.calendar
        )
        let elapsed = sessionManager.activeSession?.elapsedSeconds(at: now) ?? 0
        let progress = TimetableFit.occupancyOnProgress(
            fit: fit,
            now: now,
            elapsed: elapsed,
            budget: currentBudgetSeconds
        )
        if fit.currentOccupancy?.isAdopted == true {
            return (fit, rows, progress, TimetableCopy.unadopt, { sessionManager.unadoptCurrentOccurrence() })
        }
        if fit.currentOccupancy?.isAdopted == false {
            return (fit, rows, progress, TimetableCopy.adopt, { sessionManager.adoptCurrentNoticeThisTime() })
        }
        return (fit, rows, progress, nil, nil)
    }

    private func openReestimate(trigger: ReestimateTrigger) {
        #if DEBUG
        let landscape = sessionManager.uiPreviewLandscape || verticalSizeClass == .compact
        #else
        let landscape = verticalSizeClass == .compact
        #endif
        sessionManager.presentReestimate(
            trigger: trigger,
            surface: sessionManager.reestimateSurface(isLandscape: landscape)
        )
    }

    private func pauseWithUndo() {
        run {
            try sessionManager.pause()
            let pauseID = sessionManager.activeSession?.pauses.first(where: { $0.endedAt == nil })?.id ?? UUID()
            let expiresAt = sessionManager.clock.now.addingTimeInterval(5)
            sessionManager.focusUndoOffer = SessionManager.FocusUndoOffer(
                kind: .pause,
                message: "停車を取り消す",
                eventID: pauseID,
                expiresAt: expiresAt
            )
            sessionManager.scheduleFocusUndoExpiry(at: expiresAt)
        }
    }

    private func focusUndoBar(_ offer: SessionManager.FocusUndoOffer) -> some View {
        HStack {
            Text(offer.message)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Button("取り消し") {
                switch offer.kind {
                case .pause:
                    run { try sessionManager.undoPauseFromFocus(pauseID: offer.eventID) }
                case .reestimate:
                    run { try sessionManager.undoReestimate(eventID: offer.eventID) }
                }
                sessionManager.focusUndoOffer = nil
            }
            .font(.subheadline.weight(.bold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(FocusPanel.fillRaised.opacity(0.96))
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    private func playNudgeRing() {
        if settings.overtimeSoundEnabled {
            OvertimeAlert.playSound()
        }
        overtimeHaptic += 1
        if !reduceMotion {
            nudgePulse.toggle()
        }
    }

    private func handleOvertimeSound() {
        guard settings.overtimeSoundEnabled else { return }
        // AlarmKit owns the audible end signal when authorized.
        guard !sessionManager.isAlarmKitEndBellActive else { return }
        guard sessionManager.phase == .overtime, !didPlayOvertimeSound else { return }
        didPlayOvertimeSound = true
        OvertimeAlert.playSound()
    }

    private func consumePendingActionIfNeeded() {
        guard !didConsumePendingAction else { return }
        guard let action = FocusPendingActionStore.peek() else { return }
        // Mismatch: leave queued (activeSession may still be recovering).
        guard action.sessionID == sessionManager.activeSession?.id else { return }

        switch action.kind {
        case .arrive:
            switch ArriveHandoff.decision(
                sessionMatches: true,
                phase: sessionManager.phase,
                focusIsPresented: true
            ) {
            case .leaveQueued:
                return
            case .consumeOnly:
                // Overtime keeps the in-Focus 3-choice UI.
                if FocusPendingActionStore.consumeIfMatches(action) {
                    didConsumePendingAction = true
                }
            case .performArrive:
                applyPendingMutation(action) {
                    try sessionManager.arrive()
                }
            }
        case .reestimate:
            if FocusPendingActionStore.consumeIfMatches(action) {
                didConsumePendingAction = true
                openReestimate(trigger: .planEnd)
            }
        case .pause:
            if sessionManager.phase == .running || sessionManager.phase == .overtime {
                applyPendingMutation(action) {
                    try sessionManager.pause()
                }
            } else if sessionManager.phase == .paused {
                if FocusPendingActionStore.consumeIfMatches(action) {
                    didConsumePendingAction = true
                }
            }
        case .resume:
            if sessionManager.phase == .paused {
                applyPendingMutation(action) {
                    try sessionManager.resume()
                }
            } else if sessionManager.phase == .running || sessionManager.phase == .overtime {
                if FocusPendingActionStore.consumeIfMatches(action) {
                    didConsumePendingAction = true
                }
            }
        case .still:
            guard action.sessionID == sessionManager.activeSession?.id else { return }
            sessionManager.acknowledgeCabinStill()
            if FocusPendingActionStore.consumeIfMatches(action) {
                didConsumePendingAction = true
            }
        }
    }

    /// Consume the App Group handoff only after the session mutation succeeds,
    /// and only if a newer handoff has not replaced the slot.
    private func applyPendingMutation(
        _ expected: FocusPendingAction,
        _ body: () throws -> Void
    ) {
        do {
            try body()
            if FocusPendingActionStore.consumeIfMatches(expected) {
                didConsumePendingAction = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func boardIssuedInterrupt(_ event: TicketIssueEjectEvent) {
        guard let issued = ticket(id: event.ticketID) else { return }
        presentIssuedInterrupt(event, ticket: issued)
    }

    private func presentIssuedInterrupt(_ event: TicketIssueEjectEvent, ticket issued: Ticket) {
        do {
            ticketMotion.presentInterruptTicket(event)
            try sessionManager.switchBoard(ticket: issued)
            pendingSwitchTicketID = nil
        } catch let error as SessionError where error == .pauseLimitReached {
            ticketMotion.cancelInterruptTicket()
            pendingSwitchTicketID = issued.id
            showPauseLimitSheet = true
        } catch {
            ticketMotion.cancelInterruptTicket()
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func ticket(id: UUID) -> Ticket? {
        var descriptor = FetchDescriptor<Ticket>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func run(_ body: () throws -> Void) {
        do {
            try body()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

/// ダイヤの「次」とは別の行先。題名が主。見積もりの分は券面に残す。
private struct ReservedNextRideSign: View {
    var title: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("予約")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(minWidth: 36)
                .padding(.vertical, 4)
                .background {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
                }
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.medium))
                    .tracking(StationSignMetrics.nameTracking(title, compact: false))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle()
                    .fill(TrainTheme.rail.opacity(0.55))
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("予約 \(title)")
        .accessibilityHint("予約欄を開きます。乗車は始まりません。")
    }
}

#Preview {
    let container = try! AppModelContainer.make(inMemory: true)
    let context = container.mainContext
    let manager = SessionManager(modelContext: context)
    try! manager.startService()
    let ticket = Ticket(title: "プレビュー切符", estimatedSeconds: 90)
    context.insert(ticket)
    try! manager.board(ticket: ticket)
    return FocusView()
        .environment(manager)
        .environment(AppSettings.shared)
        .environment(TicketMotionBridge())
        .modelContainer(container)
}
