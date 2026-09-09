//
//  FocusView.swift
//  Todo train
//

import SwiftData
import SwiftUI

struct FocusView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(AppSettings.self) private var settings
    @Environment(TransferCanvasPresenter.self) private var transferCanvas
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Environment(TicketMotionBridge.self) private var ticketMotion

    @State private var showExtendChips = false
    @State private var showPauseLimitSheet = false
    @State private var showInterruptIssue = false
    @State private var pendingSwitchTicketID: UUID?
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var didPlayOvertimeSound = false
    @State private var overtimePulse = false
    @State private var overtimeHaptic = 0
    @State private var extendReason: String?
    @State private var didConsumePendingAction = false

    private let extendReasons = ["仕事が膨らんだ", "割り込みが入った", "まだかかる", "その他"]

    /// Portrait: controls take ~38% of height. Compact: right pane ~40% of width.
    private let portraitControlFraction: CGFloat = 0.38
    private let compactControlFraction: CGFloat = 0.40

    var body: some View {
        ZStack {
            CabinBackground(
                phase: currentTimerPhase,
                reduceTransparency: reduceTransparency
            )

            GeometryReader { geo in
                if verticalSizeClass == .compact {
                    compactDashboard(size: geo.size)
                } else {
                    portraitDashboard(size: geo.size)
                }
            }
        }
        .sensoryFeedback(.warning, trigger: overtimeHaptic)
        .sensoryFeedback(.warning, trigger: sessionManager.checkInHapticTick)
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
        .onChange(of: sessionManager.phase) { _, newPhase in
            if newPhase != .overtime {
                didPlayOvertimeSound = false
                overtimePulse = false
                showExtendChips = false
            } else {
                overtimePulse = true
                overtimeHaptic += 1
                handleOvertimeSound()
            }
        }
        .modifier(FocusKeepAwakeModifier(settingEnabled: settings.keepAwakeWhileChargingInFocus))
    }

    // MARK: - Dashboards

    private func portraitDashboard(size: CGSize) -> some View {
        let controlHeight = size.height * portraitControlFraction
        return VStack(spacing: 0) {
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

    private func compactDashboard(size: CGSize) -> some View {
        let controlWidth = size.width * compactControlFraction
        return HStack(spacing: 0) {
            VStack(spacing: 0) {
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
        .safeAreaPadding(.leading, 4)
        .safeAreaPadding(.trailing, 4)
    }

    // MARK: - Panels

    private var headerStrip: some View {
        HStack(alignment: .center, spacing: TrainTheme.Space.sm) {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .default))
                .foregroundStyle(FocusPanel.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            if let label = headerStateLabel {
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
                        : currentTimerPhase.accentColor
                )
                .frame(width: 3)
                .opacity(
                    currentTimerPhase == .cruise && sessionManager.pendingCheckIn != .progress ? 0 : 1
                )
        }
    }

    private var timerPanel: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = sessionManager.remainingSeconds
            let phase = timerPhase(remaining: remaining)

            GeometryReader { geo in
                let fontSize = timerFontSize(in: geo.size)
                Text(timerLabel(remaining))
                    .font(.system(size: fontSize, weight: .semibold, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(phase.accentColor)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .scaleEffect((overtimePulse && !reduceMotion) ? 1.02 : 1)
                    .animation(reduceMotion ? nil : TrainTheme.Motion.pulse, value: overtimePulse)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("残り時間")
                    .accessibilityValue(timerLabel(remaining))
            }
            .onChange(of: context.date) { _, _ in
                sessionManager.reconcile()
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

            VStack(spacing: 0) {
                FocusProgressBar(
                    progress: progressValue(at: context.date),
                    phase: phase
                )

                HStack(spacing: TrainTheme.Space.md) {
                    Text(deadlineLabel(remaining: remaining, now: context.date))
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .foregroundStyle(phase == .overtime ? TrainTheme.signalRed : FocusPanel.ink)
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
            }
            .background(FocusPanel.fill)
        }
    }

    private var controlSection: some View {
        Group {
            if showExtendChips {
                FocusExtendPanel(
                    reasons: extendReasons,
                    selectedReason: $extendReason,
                    onExtend: { minutes in
                        applyExtend(minutes: minutes)
                    },
                    onDismiss: {
                        withAnimation(TrainTheme.Motion.soft) {
                            showExtendChips = false
                            extendReason = nil
                        }
                    }
                )
            } else if sessionManager.phase == .overtime {
                OvertimeControlsView(
                    onAlreadyDone: { run { try sessionManager.arrive(resolution: .alreadyDone) } },
                    onJustFinished: { run { try sessionManager.arrive(resolution: .justFinished) } },
                    onExtend: {
                        withAnimation(TrainTheme.Motion.soft) {
                            showExtendChips = true
                        }
                    }
                )
            } else if sessionManager.pendingCheckIn == .progress {
                CheckInControlsView(
                    prompt: sessionManager.checkInPromptLine,
                    onStillOnIt: { run { try sessionManager.answerCheckIn(.stillOnIt) } },
                    onPause: { run { try sessionManager.answerCheckIn(.paused) } },
                    onAlreadyDone: { run { try sessionManager.answerCheckIn(.alreadyDone) } },
                    onWillExtend: {
                        run { try sessionManager.answerCheckIn(.willExtend) }
                        withAnimation(TrainTheme.Motion.soft) {
                            showExtendChips = true
                        }
                    }
                )
            } else {
                FocusControlsView(
                    onPause: { run { try sessionManager.pause() } },
                    onPartialDisembark: { partialDisembarkAndShowCanvas() },
                    onArrive: { run { try sessionManager.arrive() } },
                    onExtendMenu: {
                        withAnimation(TrainTheme.Motion.soft) {
                            showExtendChips.toggle()
                        }
                    },
                    onInterrupt: { showInterruptIssue = true }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FocusPanel.fill)
    }

    // MARK: - Data

    private var title: String {
        sessionManager.activeSession?.ticket?.title ?? "乗務中"
    }

    private var currentBudgetSeconds: TimeInterval {
        TimeInterval(sessionManager.activeSession?.budgetSecondsAtStart ?? 1)
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
        return currentTimerPhase.accentColor
    }

    private var estimateMetaText: String? {
        guard let budget = sessionManager.activeSession?.budgetSecondsAtStart,
              let estimate = sessionManager.activeSession?.estimatedSecondsAtStart else {
            return nil
        }
        let extensionMinutes = max(0, (budget - estimate) / 60)
        if extensionMinutes > 0 {
            return "見積もり \(estimate / 60)分 · 延長 +\(extensionMinutes)分"
        }
        return "見積もり \(estimate / 60)分"
    }

    private func timerFontSize(in size: CGSize) -> CGFloat {
        let byWidth = size.width * 0.48
        let byHeight = size.height * 0.72
        let capped: CGFloat = verticalSizeClass == .compact ? 140 : 220
        return min(byWidth, byHeight, capped)
    }

    private func timerLabel(_ remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded())
        if total < 0 {
            let absTotal = abs(total)
            return String(format: "%d:%02d", absTotal / 60, absTotal % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func progressValue(at now: Date) -> Double {
        guard let session = sessionManager.activeSession else { return 0 }
        let budget = max(TimeInterval(session.budgetSecondsAtStart), 1)
        return session.elapsedSeconds(at: now) / budget
    }

    private func timerPhase(remaining: TimeInterval) -> FocusTimerPhase {
        FocusTimerPhase(remaining: remaining, budgetSeconds: currentBudgetSeconds)
    }

    private func deadlineLabel(remaining: TimeInterval, now: Date) -> String {
        if remaining <= 0 {
            return "予定を超過"
        }
        let deadline = now.addingTimeInterval(remaining)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "予定 HH:mm"
        return formatter.string(from: deadline)
    }

    private func applyExtend(minutes: Int) {
        run {
            try sessionManager.extend(
                by: TimeInterval(minutes * 60),
                reason: extendReason
            )
        }
        showExtendChips = false
        extendReason = nil
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
        guard let action = FocusPendingActionStore.consume() else { return }
        didConsumePendingAction = true
        guard action.sessionID == sessionManager.activeSession?.id else { return }

        switch action.kind {
        case .arrive:
            // Overtime keeps the in-Focus 3-choice UI; running/paused arrive immediately.
            if sessionManager.phase != .overtime {
                run { try sessionManager.arrive() }
            }
        case .extend:
            withAnimation(TrainTheme.Motion.soft) {
                showExtendChips = true
            }
        case .pause:
            if sessionManager.phase == .running || sessionManager.phase == .overtime {
                run { try sessionManager.pause() }
            }
        case .resume:
            run { try sessionManager.resume() }
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

    private func partialDisembarkAndShowCanvas() {
        guard let ticket = sessionManager.activeSession?.ticket else { return }
        let sessionID = sessionManager.activeSession?.id
        do {
            // Enqueue before close: Focus fullScreenCover dismisses on phase change.
            transferCanvas.enqueueAfterFocusDismiss(parent: ticket, sessionID: sessionID)
            try sessionManager.partialDisembark()
        } catch {
            transferCanvas.clearPending()
            errorMessage = error.localizedDescription
            showError = true
        }
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
        .environment(TransferCanvasPresenter())
        .environment(TicketMotionBridge())
        .modelContainer(container)
}
