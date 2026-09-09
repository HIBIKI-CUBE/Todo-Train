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
    @Environment(\.scenePhase) private var scenePhase

    @State private var isFocusPresented = false
    @State private var didRecoverOnLaunch = false
    @State private var transferCanvas = TransferCanvasPresenter()
    @State private var ticketMotion = TicketMotionBridge()
    @Namespace private var focusZoom

    var body: some View {
        @Bindable var transferCanvas = transferCanvas
        @Bindable var ticketMotion = ticketMotion
        TabView {
            Tab("切符", systemImage: "tram.fill") {
                NavigationStack {
                    HubView()
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
        .environment(transferCanvas)
        .environment(ticketMotion)
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
        .animation(.easeInOut(duration: 0.25), value: undoCenter.bannerMessage)
        .onAppear {
            if !didRecoverOnLaunch {
                recoverOnLaunch()
                didRecoverOnLaunch = true
            } else {
                sessionManager.reconcile()
            }
            syncFocusPresentation()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Foreground: recompute Date-based phase only.
                // Do not re-run recoverOnLaunch (would re-schedule cancelled end bells).
                sessionManager.endAwayWatch()
                applyPendingFocusAction()
                syncFocusPresentation()
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
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    if !ticketMotion.suppressFocusCover {
                        ticketMotion.interruptEject = nil
                    }
                }
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
                    ArrivalInvalidateOverlay(moment: moment, skipEnter: true) {
                        sessionManager.consumePunctualityMoment()
                    }
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
        .modelContainer(container)
}
