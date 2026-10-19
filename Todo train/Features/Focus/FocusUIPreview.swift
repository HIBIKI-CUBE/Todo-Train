//
//  FocusUIPreview.swift
//  Todo train
//
//  DEBUG のみ。`-uiPreviewState` で Focus / 見積もり直しのスクショ用状態を作る。
//

import Foundation
import SwiftData
import TodoTrainSync
#if canImport(UIKit)
import UIKit
#endif

/// DEBUG プレビューで、開いている走行の合計を `activeSeconds` にする置き方。
/// 区間の開始は `now` に置き、合計は積み上げだけが表す。
struct FocusPreviewActiveTime: Equatable {
    var accumulatedActiveSeconds: TimeInterval
    var segmentStartedAt: Date

    func elapsedSeconds(at now: Date) -> TimeInterval {
        accumulatedActiveSeconds + now.timeIntervalSince(segmentStartedAt)
    }

    static func placement(activeSeconds: TimeInterval, now: Date) -> FocusPreviewActiveTime {
        FocusPreviewActiveTime(
            accumulatedActiveSeconds: activeSeconds,
            segmentStartedAt: now
        )
    }
}

struct FocusReestimatePreviewConfiguration {
    enum Stage {
        case position
        case declare
        case onTimeOnly
        case full
    }

    var stage: Stage
    var progressValue: Int
    var committedProgress: Double?
    var projectedTotalSeconds: TimeInterval?
}

#if DEBUG
enum FocusUIPreview {
    static let stateArgument = "-uiPreviewState"
    static let landscapeArgument = "-uiPreviewLandscape"
    static let bundleSpreadArgument = "-uiPreviewBundleSpread"
    static let bundleFanDemoArgument = "-uiPreviewBundleFanDemo"

    static func parsedState() -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: stateArgument), index + 1 < args.count else {
            return nil
        }
        return args[index + 1]
    }

    static var wantsLandscape: Bool {
        ProcessInfo.processInfo.arguments.contains(landscapeArgument)
    }

    static var requestedBundleSpread: Double? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: bundleSpreadArgument), index + 1 < args.count else {
            return nil
        }
        return Double(args[index + 1])
    }

    static var wantsBundleFanDemo: Bool {
        ProcessInfo.processInfo.arguments.contains(bundleFanDemoArgument)
    }

    static var isActive: Bool { parsedState() != nil }

    /// Preview launches use an in-memory store and a no-op Live Activity.
    /// `-uiPreviewLiveActivity` keeps the real ActivityKit manager so a Dynamic Island shot can start.
    static let liveActivityArgument = "-uiPreviewLiveActivity"

    static var wantsLiveActivity: Bool {
        ProcessInfo.processInfo.arguments.contains(liveActivityArgument)
    }

    static var showsSealGallery: Bool { parsedState() == "sealGallery" }

    /// DEBUG スクショ用。通知・AlarmKit の許可ダイアログを出さない。
    static var skipsNotificationAuthorization: Bool { isActive }

    /// 到着オーバーレイの UI テスト／スクショ待ち受け用。
    static let arrivalOverlayReadyNotification = Notification.Name("FocusUIPreview.arrivalOverlayReady")
    static let arrivalOverlayAccessibilityID = "FocusUIPreview.ArrivalOverlay"

    #if canImport(UIKit)
    static func requestLandscapeOrientationIfNeeded() {
        guard isActive, wantsLandscape else { return }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
    }
    #endif

    @MainActor
    static func bootstrap(manager: SessionManager, context: ModelContext) throws {
        guard let state = parsedState() else { return }
        switch state {
        case "shutdownBundle", "shutdownBundlePeel", "shutdownBundleLandscape", "shutdownBundlePeelLandscape",
            "historyBundle", "historyBundleLandscape", "historyEmptyBundle",
            "historyBundleViewer", "historyBundleViewerLandscape",
            "historyBundleViewerBoundary", "historyBundleViewerBoundaryLandscape":
            try configureTicketBundlePreview(manager: manager, context: context, state: state)
            manager.uiPreviewLandscape = wantsLandscape
            manager.uiPreviewBundleSpread = requestedBundleSpread
            manager.uiPreviewBundleFanDemo = wantsBundleFanDemo
            return
        case "sealGallery":
            manager.uiPreviewSuppressMotion = true
            return
        default:
            break
        }

        try manager.startService()
        let ticket = Ticket(title: "スクショ用", estimatedSeconds: 45 * 60, sortOrder: 0)
        context.insert(ticket)
        try context.save()
        queueRideBeforeBoard(state: state, ticket: ticket)
        try manager.board(ticket: ticket)
        guard let session = manager.activeSession else { return }

        switch state {
        case "reestimateProgress":
            session.estimatedSecondsAtStart = 45 * 60
            session.currentBudgetSeconds = 45 * 60
            session.accumulatedActiveSeconds = 9 * 60
            manager.presentReestimate(trigger: .manual, surface: .iphonePortrait)
            manager.focusReestimatePreview = FocusReestimatePreviewConfiguration(
                stage: .position,
                progressValue: 20,
                committedProgress: nil,
                projectedTotalSeconds: nil
            )
            manager.uiPreviewForcesFocusCover = true

        case "positionReportDeclare":
            session.estimatedSecondsAtStart = 30 * 60
            session.currentBudgetSeconds = 30 * 60
            session.accumulatedActiveSeconds = 21 * 60
            manager.presentReestimate(trigger: .manual, surface: .iphonePortrait)
            manager.focusReestimatePreview = FocusReestimatePreviewConfiguration(
                stage: .declare,
                progressValue: 60,
                committedProgress: 0.6,
                projectedTotalSeconds: 35 * 60
            )
            manager.uiPreviewForcesFocusCover = true

        case "positionReportOnTime":
            session.estimatedSecondsAtStart = 30 * 60
            session.currentBudgetSeconds = 30 * 60
            session.accumulatedActiveSeconds = 18 * 60
            manager.presentReestimate(trigger: .manual, surface: .iphonePortrait)
            manager.focusReestimatePreview = FocusReestimatePreviewConfiguration(
                stage: .onTimeOnly,
                progressValue: 60,
                committedProgress: 0.6,
                projectedTotalSeconds: 30 * 60
            )
            manager.uiPreviewForcesFocusCover = true

        case "positionReportFull":
            session.accumulatedActiveSeconds = 40 * 60
            manager.presentReestimate(trigger: .manual, surface: .iphonePortrait)
            manager.focusReestimatePreview = FocusReestimatePreviewConfiguration(
                stage: .full,
                progressValue: 100,
                committedProgress: 1.0,
                projectedTotalSeconds: nil
            )
            manager.uiPreviewForcesFocusCover = true

        case "positionReportOvertime":
            session.estimatedSecondsAtStart = 30 * 60
            session.currentBudgetSeconds = 30 * 60
            let active = TimeInterval(68 * 60)
            let placed = FocusPreviewActiveTime.placement(activeSeconds: active, now: manager.clock.now)
            session.accumulatedActiveSeconds = placed.accumulatedActiveSeconds
            session.segmentStartedAt = placed.segmentStartedAt
            manager.reconcile(now: manager.clock.now)
            manager.presentReestimate(trigger: .planEnd, surface: .iphonePortrait)
            manager.focusReestimatePreview = FocusReestimatePreviewConfiguration(
                stage: .declare,
                progressValue: 60,
                committedProgress: 0.6,
                projectedTotalSeconds: PositionReport.projection(
                    activeSeconds: active,
                    progress: 0.6
                )
            )
            manager.uiPreviewForcesFocusCover = true

        case "planEnd":
            session.currentBudgetSeconds = 45 * 60
            let active = TimeInterval(46 * 60)
            let placed = FocusPreviewActiveTime.placement(activeSeconds: active, now: manager.clock.now)
            session.accumulatedActiveSeconds = placed.accumulatedActiveSeconds
            session.segmentStartedAt = placed.segmentStartedAt
            manager.reconcile(now: manager.clock.now)
            manager.uiPreviewForcesFocusCover = true

        case "undoBanner":
            try manager.pause()
            let pauseID = session.pauses.first(where: { $0.endedAt == nil })?.id ?? UUID()
            let expiresAt = manager.clock.now.addingTimeInterval(5)
            manager.focusUndoOffer = SessionManager.FocusUndoOffer(
                kind: .pause,
                message: "停車を取り消す",
                eventID: pauseID,
                expiresAt: expiresAt
            )
            manager.uiPreviewForcesFocusCover = false

        case "homeSignalGreen":
            session.estimatedSecondsAtStart = 30 * 60
            session.currentBudgetSeconds = 30 * 60
            session.accumulatedActiveSeconds = 8 * 60
            manager.uiPreviewForcesFocusCover = true

        case "homeSignalYellow":
            session.estimatedSecondsAtStart = 30 * 60
            session.currentBudgetSeconds = 30 * 60
            session.accumulatedActiveSeconds = 28 * 60
            manager.uiPreviewForcesFocusCover = true

        case "homeSignalOff":
            session.estimatedSecondsAtStart = 30 * 60
            session.budgetSecondsAtStart = 45 * 60
            session.currentBudgetSeconds = 45 * 60
            session.accumulatedActiveSeconds = 35 * 60
            manager.uiPreviewForcesFocusCover = true

        case "laRemain12":
            // Launch and the island settle take a few seconds. Start long so the shot reads 12:00.
            placeLiveActivity(session, manager: manager, budget: 20 * 60, active: 8 * 60 - 8)
        case "laRemain90":
            placeLiveActivity(session, manager: manager, budget: 20 * 60, active: 20 * 60 - 90 - 8)
        case "laOvertime":
            placeLiveActivity(session, manager: manager, budget: 20 * 60, active: 20 * 60 + 90)
        case "laPaused":
            placeLiveActivity(session, manager: manager, budget: 20 * 60, active: 8 * 60)
            try manager.pause()
        case "laPrompt":
            placeLiveActivity(session, manager: manager, budget: 20 * 60, active: 8 * 60)
            session.pendingCheckIn = .progress
            session.checkInPromptLine = CheckInCopy.away
            manager.refreshLiveActivity(for: session, now: manager.clock.now)

        case "arrivalOnTimeTicketing", "arrivalOnTimeEarly", "arrivalOnTimeLate", "arrivalNotOnTime", "arrivalLateLog":
            try configureArrivalPreview(
                manager: manager,
                session: session,
                state: state
            )

        default:
            break
        }
        manager.uiPreviewLandscape = wantsLandscape
        manager.uiPreviewSuppressMotion = true
    }

    /// Applied inside `startNewSession`, before the first Live Activity request.
    /// An update that moves the deadline into the past does not replace the
    /// activity started by `board()` (the overtime shot stayed on the 45-minute
    /// countdown). Queuing the ride makes that first request already overtime.
    private static var queuedRide: (budget: Int, active: TimeInterval)?

    private static func queueRideBeforeBoard(state: String, ticket: Ticket) {
        switch state {
        case "laRemain12":
            queueRide(budget: 20 * 60, active: 8 * 60 - 8, ticket: ticket)
        case "laRemain90":
            queueRide(budget: 20 * 60, active: 20 * 60 - 90 - 8, ticket: ticket)
        case "laOvertime":
            queueRide(budget: 20 * 60, active: 20 * 60 + 90, ticket: ticket)
        case "laPaused", "laPrompt":
            queueRide(budget: 20 * 60, active: 8 * 60, ticket: ticket)
        default:
            break
        }
    }

    private static func queueRide(budget: Int, active: TimeInterval, ticket: Ticket) {
        ticket.estimatedSeconds = budget
        queuedRide = (budget, active)
    }

    static func applyQueuedRide(to session: WorkSession, now: Date) {
        guard let queued = queuedRide else { return }
        queuedRide = nil
        session.estimatedSecondsAtStart = queued.budget
        session.budgetSecondsAtStart = queued.budget
        session.currentBudgetSeconds = queued.budget
        let placed = FocusPreviewActiveTime.placement(activeSeconds: queued.active, now: now)
        session.accumulatedActiveSeconds = placed.accumulatedActiveSeconds
        session.segmentStartedAt = placed.segmentStartedAt
    }

    /// DEBUG Live Activity shots. Remaining time is `budget - active` at `now`.
    @MainActor
    private static func placeLiveActivity(
        _ session: WorkSession,
        manager: SessionManager,
        budget: Int,
        active: TimeInterval
    ) {
        session.estimatedSecondsAtStart = budget
        session.budgetSecondsAtStart = budget
        session.currentBudgetSeconds = budget
        let placed = FocusPreviewActiveTime.placement(activeSeconds: active, now: manager.clock.now)
        session.accumulatedActiveSeconds = placed.accumulatedActiveSeconds
        session.segmentStartedAt = placed.segmentStartedAt
        manager.reconcile(now: manager.clock.now)
        manager.refreshLiveActivity(for: session, now: manager.clock.now)
        manager.uiPreviewForcesFocusCover = true
    }

    @MainActor
    private static func configureArrivalPreview(
        manager: SessionManager,
        session: WorkSession,
        state: String
    ) throws {
        manager.uiPreviewForcesFocusCover = false
        switch state {
        case "arrivalOnTimeTicketing":
            session.estimatedSecondsAtStart = 30 * 60
            session.accumulatedActiveSeconds = 30 * 60
            try manager.arrive()
        case "arrivalOnTimeEarly":
            session.estimatedSecondsAtStart = 30 * 60
            session.accumulatedActiveSeconds = 10 * 60
            manager.presentReestimate(trigger: .manual, surface: .iphonePortrait)
            try manager.commitReestimate(
                mode: .minutesOnly,
                progressAnswer: nil,
                committedRemainingSeconds: 40 * 60,
                shownBandLowSeconds: nil,
                shownBandHighSeconds: nil,
                detailsOpened: false,
                promptId: ReestimatePromptID.remainingV1
            )
            session.accumulatedActiveSeconds = 50 * 60
            try manager.arrive()
        case "arrivalOnTimeLate":
            session.estimatedSecondsAtStart = 30 * 60
            session.accumulatedActiveSeconds = 25 * 60
            manager.presentReestimate(trigger: .manual, surface: .iphonePortrait)
            try manager.commitReestimate(
                mode: .minutesOnly,
                progressAnswer: nil,
                committedRemainingSeconds: 15 * 60,
                shownBandLowSeconds: nil,
                shownBandHighSeconds: nil,
                detailsOpened: false,
                promptId: ReestimatePromptID.remainingV1
            )
            session.accumulatedActiveSeconds = 40 * 60
            try manager.arrive()
        case "arrivalNotOnTime":
            session.estimatedSecondsAtStart = 30 * 60
            session.accumulatedActiveSeconds = 5 * 60
            try manager.arrive()
        case "arrivalLateLog":
            session.estimatedSecondsAtStart = 30 * 60
            session.currentBudgetSeconds = 30 * 60
            session.accumulatedActiveSeconds = 12 * 60
            manager.presentReestimate(trigger: .manual, surface: .iphonePortrait)
            try manager.commitReestimate(
                mode: .progress,
                progressAnswer: 0.4,
                committedRemainingSeconds: 38 * 60,
                shownBandLowSeconds: nil,
                shownBandHighSeconds: nil,
                detailsOpened: false,
                promptId: ReestimatePromptID.progressV1
            )
            session.accumulatedActiveSeconds = 58 * 60
            try manager.arrive(resolution: .justFinished)
        default:
            break
        }
        manager.arrivalUIPreviewStamp = SessionManager.ArrivalUIPreviewStamp(stampCommitted: true)
    }
}
#endif
