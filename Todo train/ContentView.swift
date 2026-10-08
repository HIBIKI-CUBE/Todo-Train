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
    @Environment(DeletionUndoCenter.self) private var undoCenter
    @Environment(CompanionSyncRuntime.self) private var companion
    @Environment(\.scenePhase) private var scenePhase

    @State private var isFocusPresented = false
    @State private var passengerCoverPresented = false
    @State private var didRecoverOnLaunch = false
    @State private var transferCanvas = TransferCanvasPresenter()
    @State private var ticketMotion = TicketMotionBridge()
    @Namespace private var focusZoom

    var body: some View {
        @Bindable var transferCanvas = transferCanvas
        @Bindable var ticketMotion = ticketMotion
        tabViewWithOptionalPassengerAccessory
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
        .onAppear {
            if !didRecoverOnLaunch {
                recoverOnLaunch()
                didRecoverOnLaunch = true
            } else {
                sessionManager.reconcile()
            }
            syncFocusPresentation()
            syncPassengerCover()
            companion.handleScenePhase(.active, sessionManager: sessionManager)
            sessionManager.suppressProgressLocalNotifications = companion.isPaired
        }
        .onChange(of: sessionManager.companionSyncTick) { _, _ in
            companion.noteSessionChanged(sessionManager: sessionManager)
        }
        .onChange(of: companion.isPaired) { _, paired in
            sessionManager.suppressProgressLocalNotifications = paired
            sessionManager.syncCabinAnnouncementsWithSettings()
        }
        .onChange(of: scenePhase) { _, newPhase in
            companion.handleScenePhase(newPhase, sessionManager: sessionManager)
            if newPhase == .active {
                // Foreground: recompute Date-based phase only.
                // Do not re-run recoverOnLaunch (would re-schedule cancelled end bells).
                sessionManager.endAwayWatch()
                applyPendingFocusAction()
                syncFocusPresentation()
                syncPassengerCover()
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
        .onChange(of: sessionManager.phase) { _, _ in
            syncFocusPresentation()
        }
        .onChange(of: sessionManager.passengerChrome) { _, _ in
            if !isFocusPresented {
                syncPassengerCover()
            }
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
            // Safety net if onDismiss and enqueue ordering ever races.
            if wasPresented && !presented {
                promoteTransferCanvasAfterFocusDismiss()
            }
            if presented {
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
            if let moment = sessionManager.punctualityMoment {
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
                            try sessionManager.boardFromArrivalSwipe(ticketID: ticketID)
                        }
                    )
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
        .sensoryFeedback(.success, trigger: sessionManager.punctualityHapticTick)
    }

    /// まもなく／申し出のときだけ付ける。空の `tabViewBottomAccessory` はタブ上に帯が残る。
    private var showsPassengerTabAccessory: Bool {
        !isFocusPresented && sessionManager.passengerChrome.showsHubOffer
    }

    @ViewBuilder
    private var tabViewWithOptionalPassengerAccessory: some View {
        let tabs = TabView {
            Tab("切符", systemImage: "tram.fill") {
                NavigationStack {
                    HubView()
                }
            }

            Tab(TimetableCopy.board, systemImage: "calendar") {
                NavigationStack {
                    TimetableDayView()
                }
            }

            Tab("履歴", systemImage: "clock") {
                NavigationStack {
                    HistoryView()
                }
            }

            Tab("設定", systemImage: "gearshape") {
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
    private func applyPendingFocusAction() {
        guard let pending = FocusPendingActionStore.peek() else { return }
        // Extend always needs Focus; leave the queue for FocusView.
        if pending.kind == .extend { return }
        if pending.kind == .pause || pending.kind == .resume {
            _ = sessionManager.applyPendingLiveActivityAction()
            return
        }
        guard let consumed = FocusPendingActionStore.consume() else { return }
        guard consumed.sessionID == sessionManager.activeSession?.id else { return }
        if consumed.kind == .arrive, sessionManager.phase != .overtime {
            try? sessionManager.arrive()
        }
    }

    private func recoverOnLaunch() {
        do {
            try sessionManager.recoverOnLaunch()
        } catch {
            sessionManager.reconcile()
        }
        applyPendingFocusAction()
        syncFocusPresentation()
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
