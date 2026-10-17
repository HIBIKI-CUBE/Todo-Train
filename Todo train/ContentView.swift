//
//  ContentView.swift
//  Todo train
//
//  Tab host + Focus fullScreenCover.
//

import SwiftUI
import SwiftData
import CoreData
import UIKit

struct ContentView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(AppSettings.self) private var settings
    @Environment(DeletionUndoCenter.self) private var undoCenter
    @Environment(CompanionSyncRuntime.self) private var companion
    @Environment(\.scenePhase) private var scenePhase

    @State private var isFocusPresented = false
    @State private var passengerCoverPresented = false
    @State private var rootTab = RootTab.tickets
    @State private var didRecoverOnLaunch = false
    @State private var transferCanvas = TransferCanvasPresenter()
    @State private var ticketMotion = TicketMotionBridge()
    @Namespace private var focusZoom

    var body: some View {
        @Bindable var transferCanvas = transferCanvas
        @Bindable var ticketMotion = ticketMotion
        tabViewWithOptionalPassengerAccessory
        #if DEBUG
        .focusUIPreviewOrientation()
        .focusUIPreviewQuickAddSheet()
        #endif
        .environment(transferCanvas)
        .environment(ticketMotion)
        .environment(ArrivalForecastTraceLog.shared)
        .environment(ArrivalForecastStore.shared)
        .environment(\.focusZoomNamespace, focusZoom)
        .environment(\.isFocusCoverPresented, isFocusPresented)
        .overlay {
            if let event = ticketMotion.interruptEject {
                TicketIssueEjectOverlay(event: event, finish: .zoomIntoFocus) {
                    ticketMotion.commitInterruptZoom()
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 8) {
            if let message = undoCenter.bannerMessage {
                DeletionUndoBanner(message: message) {
                    undoCenter.undo()
                }
                .padding(.horizontal, TrainTheme.Space.lg)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(TrainTheme.Motion.soft, value: passengerOfferMotion)
        .animation(.easeInOut(duration: 0.25), value: undoCenter.bannerMessage)
        .errorAlert(
            isPresented: Binding(
                get: { undoCenter.restoreErrorMessage != nil },
                set: { presented in
                    if !presented { undoCenter.restoreErrorMessage = nil }
                }
            ),
            message: undoCenter.restoreErrorMessage ?? ""
        )
        .onAppear {
            sessionManager.iphoneSceneActive = scenePhase == .active
            sessionManager.noteIphoneFocus(isFocusPresented)
            if !didRecoverOnLaunch {
                recoverOnLaunch()
                didRecoverOnLaunch = true
            } else {
                sessionManager.reconcile()
            }
            if foregroundReconcileWanted(for: scenePhase) {
                sessionManager.setForegroundReconcileActive(true)
            }
            syncFocusPresentation()
            syncPassengerCover()
            syncGapSurface()
            companion.handleScenePhase(.active, sessionManager: sessionManager)
            WatchSessionBridge.shared.publishCurrent()
            sessionManager.suppressProgressLocalNotifications = companion.isPaired
        }
        .onChange(of: sessionManager.companionSyncTick) { _, _ in
            companion.noteSessionChanged(sessionManager: sessionManager)
            WatchSessionBridge.shared.publishCurrent()
        }
        .onChange(of: companion.isPaired) { _, paired in
            sessionManager.suppressProgressLocalNotifications = paired
            sessionManager.syncCabinAnnouncementsWithSettings()
        }
        .onChange(of: scenePhase) { _, newPhase in
            sessionManager.noteIphoneScene(newPhase == .active)
            companion.handleScenePhase(newPhase, sessionManager: sessionManager)
            // Inactive keeps the loop (the UI is still on screen). Background stops it
            // before away is armed, so a due watch is not promoted into an alert.
            if !foregroundReconcileWanted(for: newPhase) {
                sessionManager.setForegroundReconcileActive(false)
            }
            if newPhase == .active {
                // Clear away before the rising-edge reconcile. Do not re-run
                // recoverOnLaunch (would re-schedule cancelled end bells).
                sessionManager.endAwayWatch()
                applyPendingFocusAction()
                syncFocusPresentation()
                syncPassengerCover()
                syncGapSurface()
                sessionManager.setForegroundReconcileActive(true)
            } else if newPhase == .background {
                sessionManager.beginAwayWatch()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
            sessionManager.cancelAwayWatch()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
            if scenePhase == .background {
                sessionManager.beginAwayWatch()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
            sessionManager.handleRemoteStoreChange()
        }
        .onChange(of: sessionManager.phase) { previous, _ in
            if previous == .overtime {
                dropShownOvertimeArrive()
            }
            syncFocusPresentation()
        }
        .onReceive(NotificationCenter.default.publisher(for: FocusPendingActionStore.didEnqueueNotification)) { _ in
            applyPendingFocusAction()
            syncFocusPresentation()
            syncPassengerCover()
        }
        .onChange(of: sessionManager.passengerChrome) { _, _ in
            if !isFocusPresented {
                syncPassengerCover()
            }
            syncGapSurface()
        }
        .onChange(of: rootTab) { _, _ in
            syncGapSurface()
        }
        .onChange(of: passengerCoverPresented) { _, _ in
            syncGapSurface()
        }
        .onChange(of: sessionManager.presentation.punctualityMoment?.id) { _, _ in
            syncGapSurface()
        }
        .onChange(of: ticketMotion.suppressFocusCover) { _, suppress in
            var transaction = Transaction()
            if suppress {
                transaction.disablesAnimations = true
            }
            withTransaction(transaction) {
                syncFocusPresentation()
            }
        }
        .onOpenURL { url in
            guard url.scheme == "todotrain" else { return }
            sessionManager.reconcile()
            syncFocusPresentation()
        }
        .fullScreenCover(isPresented: $passengerCoverPresented) {
            PassengerCabinCover()
                .environment(sessionManager)
                .interactiveDismissDisabled()
        }
        .fullScreenCover(isPresented: $isFocusPresented, onDismiss: {
            // Focus teardown races sheet presentation if launched from FocusView.
            // Promote after the cover is gone so 乗り継ぎ canvas actually appears.
            promoteTransferCanvasAfterFocusDismiss()
        }) {
            FocusView()
                .environment(sessionManager)
                .environment(transferCanvas)
                .environment(ticketMotion)
                .interactiveDismissDisabled()
                .navigationTransition(
                    .zoom(
                        sourceID: ticketMotion.zoomSourceID
                            ?? sessionManager.activeSession?.ticket?.id
                            ?? TicketMotionBridge.missingSource,
                        in: focusZoom
                    )
                )
        }
        .onChange(of: isFocusPresented) { wasPresented, presented in
            sessionManager.noteIphoneFocus(presented)
            syncGapSurface()
            // Safety net if onDismiss and enqueue ordering ever races.
            if wasPresented && !presented {
                promoteTransferCanvasAfterFocusDismiss()
            }
            if presented {
                // Overtime arrive stays queued until this cover exists.
                applyPendingFocusAction(focusIsPresented: true)
                passengerCoverPresented = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    if !ticketMotion.suppressFocusCover {
                        ticketMotion.interruptEject = nil
                    }
                }
            } else {
                syncPassengerCover()
            }
        }
        .sheet(item: $transferCanvas.active) { launch in
            RemainingTicketsCanvas(parent: launch.parent, fromSessionID: launch.sessionID)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .overlay {
            if let moment = sessionManager.presentation.punctualityMoment {
                switch moment.kind {
                case .arrival:
                    ArrivalInvalidateOverlay(
                        moment: moment,
                        skipEnter: true,
                        onClose: { sessionManager.consumePunctualityMoment() },
                        onStamp: { sessionID, action in
                            try sessionManager.recordArrivalStamp(sessionID: sessionID, action: action)
                        },
                        onLeadingBoard: { ticketID in
                            if moment.recordsWorkSessionStamp {
                                try sessionManager.boardFromArrivalSwipe(ticketID: ticketID)
                            } else {
                                try sessionManager.boardFromPassengerAlight(ticketID: ticketID)
                            }
                        }
                    )
                    // fullScreenCover より後ろの overlay には、その手前の environment が届かない。
                    .environment(ticketMotion)
                    .environment(settings)
                    .id(moment.id)
                case .onTimeService:
                    if !isFocusPresented {
                        PunctualityMomentOverlay(moment: moment) {
                            sessionManager.consumePunctualityMoment()
                        }
                        .id(moment.id)
                    }
                }
            }
        }
        // Arrival haptic is driven by the invalidate gesture; service moment keeps a light success.
        .sensoryFeedback(.success, trigger: sessionManager.presentation.punctualityHapticTick)
    }

    private enum RootTab: Hashable {
        case tickets
        case timetable
        case history
        case settings
    }

    /// Hub is the only iPhone surface for the arrival gap. Focus stays a driving desk.
    private func syncGapSurface() {
        let arrivalOpen: Bool = {
            if case .arrival = sessionManager.presentation.punctualityMoment?.kind { return true }
            return false
        }()
        let hub = scenePhase == .active
            && rootTab == .tickets
            && !isFocusPresented
            && !passengerCoverPresented
            && !arrivalOpen
        sessionManager.noteArrivalGapSurface(hubVisible: hub, arrivalScreenOpen: arrivalOpen)
    }

    /// まもなく／申し出のときだけ付ける。空の `tabViewBottomAccessory` はタブ上に帯が残る。
    private var showsPassengerTabAccessory: Bool {
        !isFocusPresented && sessionManager.passengerChrome.showsHubOffer
    }

    @ViewBuilder
    private var tabViewWithOptionalPassengerAccessory: some View {
        let tabs = TabView(selection: $rootTab) {
            Tab("切符", systemImage: "tram.fill", value: RootTab.tickets) {
                NavigationStack {
                    HubView()
                }
            }

            Tab(TimetableCopy.board, systemImage: "calendar", value: RootTab.timetable) {
                NavigationStack {
                    TimetableDayView()
                }
            }

            Tab("履歴", systemImage: "clock", value: RootTab.history) {
                NavigationStack {
                    HistoryView()
                }
            }

            Tab("設定", systemImage: "gearshape", value: RootTab.settings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .tint(TrainTheme.rail)

        if showsPassengerTabAccessory {
            tabs.tabViewBottomAccessory {
                PassengerOfferInset()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        } else {
            tabs
        }
    }

    /// 申し出の出現・縮約・消滅だけ。乗車中の進捗更新では動かさない。
    private var passengerOfferMotion: String {
        guard !isFocusPresented else { return "hidden" }
        switch sessionManager.passengerChrome {
        case .soon(let interval):
            return "soon-\(interval.id)"
        case .offer(let interval, let collapsed):
            return "offer-\(interval.id)-\(collapsed)"
        default:
            return "hidden"
        }
    }

    private func promoteTransferCanvasAfterFocusDismiss() {
        guard transferCanvas.pending != nil else { return }
        Task { @MainActor in
            await Task.yield()
            transferCanvas.presentPendingIfNeeded()
        }
    }

    private func syncFocusPresentation() {
        #if DEBUG
        if FocusUIPreview.isActive {
            let shouldShow = sessionManager.uiPreviewForcesFocusCover
            if isFocusPresented != shouldShow {
                isFocusPresented = shouldShow
            }
            return
        }
        #endif
        let shouldShow = sessionManager.shouldPresentFocusCover
            && !ticketMotion.suppressFocusCover
        if isFocusPresented != shouldShow {
            isFocusPresented = shouldShow
        }
    }

    private func syncPassengerCover() {
        let wants = sessionManager.passengerChrome.isFullScreen && !isFocusPresented
        if passengerCoverPresented != wants {
            passengerCoverPresented = wants
        }
    }

    /// Handle LA deep-link actions that must run even when Focus is not yet presented (e.g. paused → 到着).
    private func applyPendingFocusAction(focusIsPresented: Bool? = nil) {
        let focusIsPresented = focusIsPresented ?? isFocusPresented
        guard let pending = FocusPendingActionStore.peek() else { return }
        // 見積もり直しは Focus が必要。キューは FocusView に任せる。
        if pending.kind == .reestimate { return }
        if pending.kind == .pause || pending.kind == .resume {
            _ = sessionManager.applyPendingLiveActivityAction()
            return
        }
        guard pending.kind == .arrive else { return }
        switch ArriveHandoff.decision(
            sessionMatches: pending.sessionID == sessionManager.activeSession?.id,
            phase: sessionManager.phase,
            focusIsPresented: focusIsPresented
        ) {
        case .leaveQueued:
            return
        case .consumeOnly:
            FocusPendingActionStore.consumeIfMatches(pending)
        case .performArrive:
            do {
                try sessionManager.arrive()
                FocusPendingActionStore.consumeIfMatches(pending)
            } catch {
                // Keep queued for a later foreground pass.
            }
        }
    }

    /// Focus was already showing the overtime 3-choice. Drop a queued arrive
    /// before a later running/launch pass can treat it as a fresh arrival.
    private func dropShownOvertimeArrive() {
        guard let pending = FocusPendingActionStore.peek() else { return }
        guard ArriveHandoff.shouldDropOnLeavingOvertime(
            kind: pending.kind,
            sessionMatches: pending.sessionID == sessionManager.activeSession?.id,
            focusWasPresented: isFocusPresented
        ) else { return }
        FocusPendingActionStore.consumeIfMatches(pending)
    }

    /// Active starts the tick. Inactive keeps it. Background does not.
    private func foregroundReconcileWanted(for phase: ScenePhase) -> Bool {
        ForegroundReconcileScheduling.isForeground(
            wasForeground: sessionManager.isForegroundForReconcile,
            scene: ForegroundReconcileScheduling.Scene(phase)
        )
    }

    private func recoverOnLaunch() {
        #if DEBUG
        if FocusUIPreview.isActive {
            syncFocusPresentation()
            return
        }
        #endif
        do {
            try sessionManager.recoverOnLaunch()
        } catch {
            sessionManager.reconcile()
        }
        applyPendingFocusAction()
        syncFocusPresentation()
    }
}

private extension ForegroundReconcileScheduling.Scene {
    init(_ phase: ScenePhase) {
        switch phase {
        case .active: self = .active
        case .inactive: self = .inactive
        case .background: self = .background
        @unknown default: self = .background
        }
    }
}

#Preview {
    let container = try! AppModelContainer.make(inMemory: true)
    let manager = SessionManager(modelContext: container.mainContext)
    return ContentView()
        .environment(manager)
        .environment(AppSettings.shared)
        .environment(DeletionUndoCenter())
        .environment(CompanionSyncRuntime())
        .environment(ArrivalForecastTraceLog.shared)
        .environment(ArrivalForecastStore.shared)
        .modelContainer(container)
}
