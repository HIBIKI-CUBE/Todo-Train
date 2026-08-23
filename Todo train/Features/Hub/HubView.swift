//
//  HubView.swift
//  Todo train
//

import SwiftUI
import SwiftData
import UIKit

struct HubView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(DeletionUndoCenter.self) private var undoCenter

    @Query(sort: \Ticket.sortOrder) private var allTickets: [Ticket]

    @State private var showQuickAdd = false
    @State private var showServiceEndSheet = false
    @State private var hubDestination: HubDestination?
    @State private var detailTicket: Ticket?
    @State private var errorMessage = ""
    @State private var showError = false
    /// Single-issue celebration playing on Hub (may overlap sheet dismiss).
    @State private var hubIssueEject: TicketIssueEjectEvent?
    @State private var focusedTicketID: UUID?
    @State private var ticketSlotFrames: [UUID: CGRect] = [:]
    @State private var departingTicketID: UUID?
    @State private var isPuttingBack = false

    @Environment(TicketMotionBridge.self) private var ticketMotion
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
        .sheet(isPresented: $showQuickAdd) {
            QuickAddSheet { event in
                hubIssueEject = event
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
        .sheet(isPresented: $showServiceEndSheet) {
            ServiceEndSheet { message in
                errorMessage = message
                showError = true
            }
        }
        .onAppear {
            presentServiceEndIfNeeded()
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
            guard presented else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                departingTicketID = nil
                focusedTicketID = nil
                isPuttingBack = false
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
                onError: { message in
                    errorMessage = message
                    showError = true
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
                    onBoard: { boardFromFocus($0) },
                    onOpenDetail: { ticket in
                        detailTicket = ticket
                    },
                    onDelete: { deleteTicket($0) }
                )
                .onPreferenceChange(TicketSlotFramesKey.self) { reported in
                    ticketSlotFrames = TrainLayout.slotFrames(
                        reported: reported,
                        keeping: Set(stackTickets.map(\.id))
                    )
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
                        onBoard: { boardFromFocus(ticket) },
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
            boardFromFocus(ticket)
        case .snap:
            break
        }
        return action
    }

    private func focusTicket(_ id: UUID) {
        guard focusedTicketID != id, !isPuttingBack else { return }
        var insert = Transaction()
        insert.animation = nil
        withTransaction(insert) {
            isPuttingBack = false
            focusedTicketID = id
        }
    }

    private func boardFromFocus(_ ticket: Ticket) {
        guard canBoardGenerally else { return }
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

    /// S-03: after a day change, surface the end-of-service flow (once Focus is not blocking).
    private func presentServiceEndIfNeeded() {
        guard sessionManager.needsServiceDayEndPrompt else { return }
        guard sessionManager.phase != .running, sessionManager.phase != .overtime else { return }
        if !showServiceEndSheet {
            showServiceEndSheet = true
        }
    }

    private func requestEndService() {
        if sessionManager.pausedTicketCount == 0 {
            do {
                try sessionManager.endService()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        } else {
            showServiceEndSheet = true
        }
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
                ticketMotion.zoomSourceID = ticket.id
                board(ticket)
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
        let absTotal = abs(remaining)
        let prefix = remaining < 0 ? "超過 " : ""
        return "\(prefix)\(absTotal / 60):\(String(format: "%02d", absTotal % 60))"
    }
}

/// Cover card cloned onto the present overlay so a returning ticket tucks under Wallet peeks.
private struct HubPresentCover: Identifiable {
    let ticket: Ticket
    let tilt: Double
    let slotLocal: CGRect
    var id: UUID { ticket.id }
}

/// Centered ticket + LED. Tilt/shadow start as the deck card so the hero does not pop.
private struct HubTicketPresentLayer: View {
    let ticket: Ticket
    let size: CGSize
    let overlaySize: CGSize
    let slotLocal: CGRect
    let sourceTilt: Double
    var isPuttingBack: Bool
    var covers: [HubPresentCover]
    let canBoard: Bool
    let disabledReason: String?
    var zoomNamespace: Namespace.ID
    let onDismiss: () -> Void
    var onHoldDragEnded: (DragGesture.Value) -> TicketStackLayout.HoldRelease
    let onOpenDetail: () -> Void
    let onBoard: () -> Void
    let onDelete: () -> Void

    @State private var settled = false
    @State private var pose: CGSize?

    private var looksSettled: Bool {
        settled && !isPuttingBack
    }

    /// Peek covers stay in the overlay while the hero is in the stack's z-order.
    /// Hidden once seated so they do not clip the centered ticket. Instant; no fade.
    private var coverOpacity: Double {
        if looksSettled { return 0 }
        if isPuttingBack { return 1 }
        return MarsTicketSpec.HubStack.focusPeerOpacity
    }

    private var restCenter: CGPoint {
        CGPoint(x: overlaySize.width / 2, y: overlaySize.height / 2)
    }

    private var slotPose: CGSize {
        CGSize(
            width: slotLocal.midX - restCenter.x,
            height: slotLocal.midY - restCenter.y
        )
    }

    /// One vector for select, drag, and put-back. Nil before launch = still in the slot.
    private var displayedPose: CGSize {
        if isPuttingBack { return slotPose }
        return pose ?? slotPose
    }

    private var signHeight: CGFloat {
        size.height * MarsTicketSpec.HubStack.departSignHeightRatio
    }

    var body: some View {
        ZStack {
            Color.black.opacity(looksSettled ? MarsTicketSpec.HubStack.focusDimOpacity : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
                .allowsHitTesting(!isPuttingBack)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("選択をやめる")

            flyingTicket

            ForEach(covers) { cover in
                coverClone(cover)
            }

            HubDepartLEDSign(
                canBoard: canBoard,
                ticketWidth: size.width,
                ticketHeight: size.height
            )
            .offset(
                y: -(size.height / 2 + MarsTicketSpec.HubStack.departSignGap + signHeight / 2)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .opacity(looksSettled ? 1 : 0)
            .allowsHitTesting(false)
        }
        .onAppear {
            var parked = Transaction()
            parked.animation = nil
            withTransaction(parked) {
                pose = slotPose
            }
            withAnimation(MarsTicketSpec.HubStack.focus) {
                pose = .zero
                settled = true
            }
        }
        .onChange(of: overlaySize) { _, _ in
            if looksSettled {
                pose = .zero
            }
        }
    }

    private var flyingTicket: some View {
        HubMarsTicketCard(
            ticket: ticket,
            isLifted: looksSettled,
            isHeldVisually: looksSettled,
            canBoard: canBoard,
            disabledReason: disabledReason,
            restOffset: .zero,
            followsFinger: false,
            onSelect: {},
            onDismissLift: onDismiss,
            onHoldDragEnded: onHoldDragEnded
        )
        .frame(width: size.width, height: size.height)
        .rotation3DEffect(
            .degrees(looksSettled ? 0 : sourceTilt),
            axis: (x: 1, y: 0, z: 0),
            anchor: .center,
            perspective: 0.65
        )
        .matchedTransitionSource(id: ticket.id, in: zoomNamespace)
        .allowsHitTesting(looksSettled)
        .contextMenu {
            Button("詳細", action: onOpenDetail)
            if canBoard {
                Button("発車", action: onBoard)
            }
            Button("削除", role: .destructive, action: onDelete)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .offset(x: displayedPose.width, y: displayedPose.height)
        .gesture(looksSettled ? holdDrag : nil)
    }

    @ViewBuilder
    private func coverClone(_ cover: HubPresentCover) -> some View {
        let coverWidth = size.width
        let coverHeight = size.height
        HubMarsTicketCard(
            ticket: cover.ticket,
            isLifted: false,
            isHeldVisually: false,
            canBoard: canBoard,
            disabledReason: disabledReason,
            restOffset: .zero,
            followsFinger: false,
            onSelect: {},
            onDismissLift: {}
        )
        .frame(width: coverWidth, height: coverHeight)
        .rotation3DEffect(
            .degrees(cover.tilt),
            axis: (x: 1, y: 0, z: 0),
            anchor: .center,
            perspective: 0.65
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .offset(
            x: cover.slotLocal.midX - restCenter.x,
            y: cover.slotLocal.midY - restCenter.y
        )
        .opacity(coverOpacity)
        .transaction { $0.animation = nil }
    }

    private var holdDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    pose = TicketStackLayout.holdOffset(
                        rest: .zero,
                        translation: value.translation
                    )
                }
            }
            .onEnded { value in
                let action = onHoldDragEnded(value)
                if action == .board {
                    var transaction = Transaction()
                    transaction.animation = nil
                    withTransaction(transaction) {
                        pose = TicketStackLayout.holdOffset(
                            rest: .zero,
                            translation: value.translation
                        )
                    }
                }
            }
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
