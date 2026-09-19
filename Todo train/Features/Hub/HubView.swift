//
//  HubView.swift
//  Todo train
//

import SwiftUI
import SwiftData
import UIKit
import TodoTrainSync

struct HubView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(DeletionUndoCenter.self) private var undoCenter
    @Environment(ServicePortalPresentation.self) private var servicePortal

    @Query(sort: \Ticket.sortOrder) private var allTickets: [Ticket]

    @State private var showQuickAdd = false
    @State private var showServiceShutdownCover = false
    @State private var hubDestination: HubDestination?
    @State private var detailTicket: Ticket?
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var showPauseLimitSheet = false
    @State private var pendingBoardTicket: Ticket?
    /// Single-issue celebration playing on Hub (may overlap sheet dismiss).
    @State private var hubIssueEject: TicketIssueEjectEvent?
    @State private var focusedTicketID: UUID?
    @State private var ticketSlotFrames: [UUID: CGRect] = [:]
    @State private var slotFrameCache = HubSlotFrameCache()
    @State private var departingTicketID: UUID?
    @State private var isPuttingBack = false
    @State private var lastWarmedBand: WorkHourBand?

    @Environment(TicketMotionBridge.self) private var ticketMotion
    @Environment(ArrivalForecastStore.self) private var forecastStore
    @Environment(\.focusZoomNamespace) private var focusZoomNamespace
    @Environment(\.isFocusCoverPresented) private var isFocusCoverPresented
    @Namespace private var previewZoomNamespace

    private enum HubDestination: Hashable, Identifiable {
        case tags
        case reorder

        var id: Self { self }
    }

    private var openTickets: [Ticket] {
        allTickets.filter(\.isOpen)
    }

    /// Open tickets that are not currently paused (paused live in their own section).
    private var backlogTickets: [Ticket] {
        openTickets.filter { !isPaused($0) }
    }

    /// Keep the boarding ticket in the deck until Focus zoom has a source view.
    private var stackTickets: [Ticket] {
        var list = backlogTickets
        if let departingTicketID,
           let ticket = allTickets.first(where: { $0.id == departingTicketID }),
           !list.contains(where: { $0.id == departingTicketID }) {
            list.append(ticket)
        }
        return list
    }

    private var currentBand: WorkHourBand {
        WorkHourBand.of(hour: Calendar.current.component(.hour, from: .now))
    }

    private func warmForecasts() {
        guard !isFocusCoverPresented else { return }
        lastWarmedBand = currentBand
        let sessions = (try? modelContext.fetch(FetchDescriptor<WorkSession>())) ?? []
        forecastStore.warm(tickets: stackTickets, sessions: sessions)
    }

    private var zoomNamespace: Namespace.ID {
        focusZoomNamespace ?? previewZoomNamespace
    }

    private var canBoardGenerally: Bool {
        sessionManager.isInService
            && sessionManager.phase != .running
            && sessionManager.phase != .overtime
    }

    private var boardDisabledReason: String {
        if sessionManager.needsServiceDayEndPrompt {
            return "昨日の運行を終了してください"
        }
        if !sessionManager.isInService {
            return "運行開始が必要です"
        }
        if sessionManager.phase == .running || sessionManager.phase == .overtime {
            return "すでに走行中の切符があります"
        }
        if sessionManager.pausedCountTowardLimit >= sessionManager.pauseLimit {
            return "停車が上限です。先に片付けるか、停車中から再乗車してください"
        }
        return "発車できません"
    }

    private var isCompactHeight: Bool {
        verticalSizeClass == .compact
    }

    /// Ticket lift does not hide chrome (toolbar(.hidden) mid-flight caused layout がくつき).
    /// Focus cover is the mode cut — no extra black wait on Hub.

    var body: some View {
        GeometryReader { geo in
            let split = TrainLayout.shouldSplitHub(
                availableWidth: geo.size.width,
                compactHeight: isCompactHeight
            )
            let pane = TrainLayout.hubServicePaneWidth(for: geo.size.width)
            Group {
                if split {
                    landscapeSplitHub(servicePaneWidth: pane)
                } else {
                    portraitHub
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(.named(HubTicketCanvas.spaceName))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        hubDestination = .tags
                    } label: {
                        Label("タグ", systemImage: "tag")
                    }
                    Button {
                        hubDestination = .reorder
                    } label: {
                        Label("並べ替え", systemImage: "arrow.up.arrow.down")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("その他")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showQuickAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("切符を追加")
            }
        }
        .navigationTitle("Todo train")
        .navigationBarTitleDisplayMode(
            TrainLayout.navigationBarTitleDisplayMode(verticalSizeClass: verticalSizeClass)
        )
        .navigationDestination(item: $hubDestination) { destination in
            switch destination {
            case .tags:
                TagManagerView()
            case .reorder:
                ReorderView()
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { detailTicket != nil },
            set: { if !$0 { detailTicket = nil } }
        )) {
            if let detailTicket {
                TicketDetailView(ticket: detailTicket)
            }
        }
        .errorAlert(isPresented: $showError, message: errorMessage)
        .task {
            await sessionManager.refreshCalendarBoardIfAuthorized()
        }
        .sheet(isPresented: $showPauseLimitSheet) {
            PauseLimitSheet(
                pendingTicket: pendingBoardTicket,
                onSlotFreedTryBoard: {
                    if let pendingBoardTicket {
                        requestBoard(pendingBoardTicket)
                    }
                }
            )
        }
        .sheet(isPresented: $showQuickAdd) {
            QuickAddSheet { event in
                ticketSlotFrames = slotFrameCache.frames
                hubIssueEject = event
                sessionManager.noteCabinActivity()
                // Stay on the list so the issue celebration can play; do not auto-enter focus.
            }
        }
        .overlay {
            if let hubIssueEject {
                TicketIssueEjectOverlay(
                    event: hubIssueEject,
                    landingRect: ticketSlotFrames[hubIssueEject.ticketID]
                ) {
                    if self.hubIssueEject?.id == hubIssueEject.id {
                        self.hubIssueEject = nil
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showServiceShutdownCover) {
            ServiceShutdownCover { message in
                errorMessage = message
                showError = true
            }
            .environment(sessionManager)
        }
        .onAppear {
            presentServiceEndIfNeeded()
            warmForecasts()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                if !isFocusCoverPresented, lastWarmedBand != currentBand {
                    warmForecasts()
                }
            }
        }
        .onChange(of: sessionManager.needsServiceDayEndPrompt) { _, needs in
            if needs {
                presentServiceEndIfNeeded()
            }
        }
        .onChange(of: sessionManager.phase) { _, _ in
            presentServiceEndIfNeeded()
        }
        .onChange(of: isFocusCoverPresented) { _, presented in
            if presented {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    departingTicketID = nil
                    focusedTicketID = nil
                    isPuttingBack = false
                }
            } else if lastWarmedBand != currentBand {
                warmForecasts()
            }
        }
    }

    // MARK: - Portrait

    private var portraitHub: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TrainTheme.Space.lg) {
                VStack(alignment: .leading, spacing: TrainTheme.Space.lg) {
                    serviceBlock
                    if !sessionManager.pausedSessions.isEmpty {
                        pausedBlock
                    }
                }
                .overlay { hubChromeDim }

                ticketsBlock
            }
            .padding(.bottom, TrainTheme.Space.xl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollClipDisabled()
        .scrollDisabled(isPresentingOnDeck)
        .overlay { hubPresentOverlay }
    }

    // MARK: - Landscape split

    private func landscapeSplitHub(servicePaneWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: TrainTheme.Space.md) {
                    serviceBlock
                    if !sessionManager.pausedSessions.isEmpty {
                        pausedBlock
                    }
                }
                .padding(.bottom, TrainTheme.Space.lg)
            }
            .scrollDisabled(isPresentingOnDeck)
            .overlay { hubChromeDim }
            .frame(width: servicePaneWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(TrainTheme.platform)

            ScrollView {
                ticketsBlock
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.bottom, TrainTheme.Space.lg)
            }
            .scrollClipDisabled()
            .scrollDisabled(isPresentingOnDeck)
            .overlay { hubPresentOverlay }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Blocks

    private var serviceBlock: some View {
        VStack(alignment: .leading, spacing: TrainTheme.Space.sm) {
            Text("運行")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, TrainTheme.Space.lg)
            ServiceSummaryBar(
                onRequestStartService: {
                    requestStartService()
                },
                onRequestEndService: {
                    requestEndService()
                }
            )
            .padding(.horizontal, TrainTheme.Space.md)
        }
        .padding(.top, TrainTheme.Space.sm)
    }

    private var pausedBlock: some View {
        VStack(alignment: .leading, spacing: TrainTheme.Space.sm) {
            Text("停車中")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, TrainTheme.Space.lg)

            if let quiet = sessionManager.timetableQuietMessage {
                VStack(alignment: .leading, spacing: 4) {
                    Text(quiet)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if sessionManager.timetableFit().currentOccupancy?.isAdopted == true {
                        Button(TimetableCopy.unadoptThisTime) {
                            sessionManager.unadoptCurrentOccurrence()
                        }
                        .font(.footnote.weight(.semibold))
                    }
                }
                .padding(.horizontal, TrainTheme.Space.lg)
            }

            VStack(spacing: TrainTheme.Space.sm) {
                ForEach(sessionManager.pausedSessions, id: \.id) { session in
                    if let ticket = session.ticket {
                        pausedTicketRow(ticket: ticket, session: session)
                            .padding(.horizontal, TrainTheme.Space.md)
                            .contextMenu {
                                Button("削除", role: .destructive) {
                                    deleteTicket(ticket)
                                }
                            }
                    }
                }
            }
        }
    }

    private var ticketsBlock: some View {
        VStack(alignment: .leading, spacing: TrainTheme.Space.sm) {
            Text("切符")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, TrainTheme.Space.lg)

            if openTickets.isEmpty {
                ContentUnavailableView {
                    Label("切符がありません", systemImage: "tram")
                } description: {
                    Text("右上の ＋ から掃き出しましょう。")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, isCompactHeight ? 8 : 24)
            } else if stackTickets.isEmpty {
                Text("未乗車の切符はありません。停車中から再乗車するか、＋ で追加してください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, TrainTheme.Space.lg)
            } else {
                TicketStackView(
                    tickets: stackTickets,
                    canBoard: canBoardGenerally,
                    boardDisabledReason: boardDisabledReason,
                    focusedTicketID: $focusedTicketID,
                    hiddenTicketID: hubIssueEject?.ticketID,
                    isPuttingBack: isPuttingBack,
                    onFocusTicket: { focusTicket($0) },
                    onDismissFocus: { dismissTicketFocus() },
                    onBoard: { requestBoard($0) },
                    onOpenDetail: { ticket in
                        detailTicket = ticket
                    },
                    onDelete: { deleteTicket($0) },
                    zoomNamespace: zoomNamespace
                )
                .onPreferenceChange(TicketDeckFrameKey.self) { deckFrame in
                    consumeDeckFrame(deckFrame)
                }
            }
        }
        .padding(.top, TrainTheme.Space.sm)
    }

    /// Overlay container stays mounted; this tracks whether a ticket is still the presented identity.
    private var isPresentingOnDeck: Bool {
        focusedTicketID != nil
    }

    /// Dim + tap-to-put-back on 運行 / 停車 only. Present overlay covers the deck.
    private var hubChromeDim: some View {
        Rectangle()
            .fill(
                Color.black.opacity(
                    focusedTicketID == nil || isPuttingBack ? 0 : MarsTicketSpec.HubStack.focusDimOpacity
                )
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var presentedTicket: Ticket? {
        guard let focusedTicketID else { return nil }
        return stackTickets.first(where: { $0.id == focusedTicketID })
            ?? allTickets.first(where: { $0.id == focusedTicketID })
    }

    /// Wallet presentation: ticket flies from its slot; LED stays centered above rest.
    /// GeometryReader stays mounted so safe-area overlay unmount does not shift the scroll view.
    private var hubPresentOverlay: some View {
        GeometryReader { geo in
            let overlayFrame = geo.frame(in: .named(HubTicketCanvas.spaceName))
            ZStack {
                Color.clear.ignoresSafeArea()
                if let ticket = presentedTicket {
                    let size = presentedCardSize(in: geo, ticketID: ticket.id)
                    let slotLocal = slotRectLocal(
                        ticketID: ticket.id,
                        overlayFrame: overlayFrame,
                        overlaySize: geo.size,
                        fallbackSize: size
                    )
                    HubTicketPresentLayer(
                        ticket: ticket,
                        size: size,
                        overlaySize: geo.size,
                        slotLocal: slotLocal,
                        sourceTilt: presentedTilt,
                        isPuttingBack: isPuttingBack,
                        covers: presentCovers(
                            overlayFrame: overlayFrame,
                            overlaySize: geo.size
                        ),
                        canBoard: canBoardGenerally,
                        disabledReason: boardDisabledReason,
                        zoomNamespace: zoomNamespace,
                        onDismiss: { dismissTicketFocus() },
                        onHoldDragEnded: { finishPresentDrag($0, ticket: ticket) },
                        onOpenDetail: { detailTicket = ticket },
                        onBoard: { requestBoard(ticket) },
                        onDelete: { deleteTicket(ticket) }
                    )
                }
            }
        }
        .allowsHitTesting(presentedTicket != nil)
        .transition(.identity)
    }

    private func slotRectLocal(
        ticketID: UUID,
        overlayFrame: CGRect,
        overlaySize: CGSize,
        fallbackSize: CGSize
    ) -> CGRect {
        let slot = ticketSlotFrames[ticketID] ?? CGRect(
            x: overlayFrame.minX + (overlaySize.width - fallbackSize.width) / 2,
            y: overlayFrame.minY + (overlaySize.height - fallbackSize.height) / 2,
            width: fallbackSize.width,
            height: fallbackSize.height
        )
        return CGRect(
            x: slot.minX - overlayFrame.minX,
            y: slot.minY - overlayFrame.minY,
            width: fallbackSize.width,
            height: fallbackSize.height
        )
    }

    /// Tickets in front of the focused one (Wallet: later index = on top).
    /// Used for fly-out and put-back so the moving ticket tucks under peeks.
    private func presentCovers(
        overlayFrame: CGRect,
        overlaySize: CGSize
    ) -> [HubPresentCover] {
        guard let focusedTicketID,
              let focusedIndex = stackTickets.firstIndex(where: { $0.id == focusedTicketID })
        else { return [] }
        let count = stackTickets.count
        return stackTickets.enumerated().compactMap { index, ticket in
            guard index > focusedIndex else { return nil }
            let size = presentedCardSize(
                overlayWidth: overlaySize.width,
                ticketID: ticket.id
            )
            return HubPresentCover(
                ticket: ticket,
                tilt: TicketStackLayout.tiltDegrees(index: index, count: count),
                slotLocal: slotRectLocal(
                    ticketID: ticket.id,
                    overlayFrame: overlayFrame,
                    overlaySize: overlaySize,
                    fallbackSize: size
                )
            )
        }
    }

    private var presentedTilt: Double {
        guard let focusedTicketID,
              let index = stackTickets.firstIndex(where: { $0.id == focusedTicketID })
        else { return 0 }
        return TicketStackLayout.tiltDegrees(index: index, count: stackTickets.count)
    }

    private func presentedCardSize(in geo: GeometryProxy, ticketID: UUID) -> CGSize {
        presentedCardSize(overlayWidth: geo.size.width, ticketID: ticketID)
    }

    private func presentedCardSize(overlayWidth: CGFloat, ticketID: UUID) -> CGSize {
        _ = ticketID
        return TrainLayout.presentedCardSize(overlayWidth: overlayWidth)
    }

    private func finishPresentDrag(
        _ value: DragGesture.Value,
        ticket: Ticket
    ) -> TicketStackLayout.HoldRelease {
        let live = TicketStackLayout.holdOffset(rest: .zero, translation: value.translation)
        let action = TicketStackLayout.holdRelease(
            hold: live,
            translation: value.translation,
            predictedEnd: value.predictedEndTranslation,
            canBoard: canBoardGenerally
        )
        switch action {
        case .putBack:
            let flicked = hypot(value.velocity.width, value.velocity.height) > 40
                || hypot(live.width, live.height) > 12
            dismissTicketFocus(
                inertial: flicked
            )
        case .board:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            proceedBoard(ticket)
        case .snap:
            break
        }
        return action
    }

    private func consumeDeckFrame(_ deckFrame: CGRect) {
        let reported = TrainLayout.slotFrames(
            deckFrame: deckFrame,
            orderedIDs: stackTickets.map(\.id)
        )
        slotFrameCache.frames = reported
        if TrainLayout.shouldPublishSlotFrames(
            needsLiveFrames: focusedTicketID != nil || hubIssueEject != nil,
            reported: reported,
            published: ticketSlotFrames
        ) {
            ticketSlotFrames = reported
        }
    }

    private func focusTicket(_ id: UUID) {
        guard focusedTicketID != id, !isPuttingBack else { return }
        var insert = Transaction()
        insert.animation = nil
        withTransaction(insert) {
            isPuttingBack = false
            ticketSlotFrames = slotFrameCache.frames
            focusedTicketID = id
        }
    }

    private func requestBoard(_ ticket: Ticket) {
        guard canBoardGenerally else { return }
        proceedBoard(ticket)
    }

    private func proceedBoard(_ ticket: Ticket) {
        ticketMotion.zoomSourceID = ticket.id
        departingTicketID = ticket.id
        board(ticket)
    }

    private func dismissTicketFocus(inertial: Bool = false) {
        guard focusedTicketID != nil, !isPuttingBack else { return }
        withAnimation(inertial ? MarsTicketSpec.HubStack.putBack : MarsTicketSpec.HubStack.focus) {
            isPuttingBack = true
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                focusedTicketID = nil
                isPuttingBack = false
            }
        }
    }

    /// S-03: after a day change, surface shutdown (once Focus is not blocking).
    private func presentServiceEndIfNeeded() {
        guard sessionManager.needsServiceDayEndPrompt else { return }
        guard sessionManager.phase != .running, sessionManager.phase != .overtime else { return }
        if !showServiceShutdownCover {
            showServiceShutdownCover = true
        }
    }

    private func requestStartService() {
        do {
            try sessionManager.startService()
            servicePortal.presentBootCover()
        } catch {
            if sessionManager.needsServiceDayEndPrompt {
                showServiceShutdownCover = true
            } else {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func requestEndService() {
        showServiceShutdownCover = true
    }

    @ViewBuilder
    private func pausedTicketRow(ticket: Ticket, session: WorkSession) -> some View {
        HStack(spacing: TrainTheme.Space.md) {
            Button {
                detailTicket = ticket
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ticket.title)
                        .font(TrainTheme.TypeScale.ticketTitle())
                        .lineLimit(isCompactHeight ? 2 : nil)
                        .foregroundStyle(.primary)
                    Text("残り \(formatRemaining(session))")
                        .font(TrainTheme.TypeScale.meta())
                        .foregroundStyle(TrainTheme.signalAmber)
                        .monospacedDigit()
                    SignalBadge(kind: .paused)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button("再乗車") {
                requestBoard(ticket)
            }
            .buttonStyle(.borderedProminent)
            .tint(TrainTheme.rail)
            .matchedTransitionSource(id: ticket.id, in: zoomNamespace)
            .disabled(!canBoardGenerally)
            .accessibilityHint(canBoardGenerally ? "停車中の切符を再開" : boardDisabledReason)
        }
        .padding(TrainTheme.Space.md)
        .background(TrainTheme.surface, in: RoundedRectangle(cornerRadius: TrainTheme.Radius.control, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func isPaused(_ ticket: Ticket) -> Bool {
        sessionManager.pausedSessions.contains { $0.ticket?.id == ticket.id }
    }

    private func board(_ ticket: Ticket) {
        do {
            try sessionManager.board(ticket: ticket)
        } catch let error as SessionError where error == .pauseLimitReached {
            departingTicketID = nil
            ticketMotion.zoomSourceID = nil
            pendingBoardTicket = ticket
            showPauseLimitSheet = true
        } catch {
            departingTicketID = nil
            ticketMotion.zoomSourceID = nil
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func deleteTicket(_ ticket: Ticket) {
        let title = ticket.title
        let record = DeletionUndo.captureTicket(ticket)
        do {
            try sessionManager.deleteTicket(ticket)
            undoCenter.offer(message: DeletionUndo.bannerMessage(ticketTitle: title)) {
                withAnimation {
                    try? sessionManager.restoreDeletedTicket(record)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func formatRemaining(_ session: WorkSession) -> String {
        let remaining = Int(session.remainingSeconds(at: .now).rounded())
        let prefix = remaining < 0 ? "超過 " : ""
        return prefix + ClockTime.mmss(remaining)
    }
}

#Preview("運行中・未乗車") {
    HubPreviewSeed.hubView(scenario: .inService)
}

#Preview("停車あり") {
    HubPreviewSeed.hubView(scenario: .inServiceWithPause)
}

#Preview("運行前") {
    HubPreviewSeed.hubView(scenario: .backlogIdle)
}

#Preview("空のホーム") {
    HubPreviewSeed.hubView(scenario: .empty)
}
