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

struct FocusReestimatePreviewConfiguration {
    enum Stage {
        case progress
        case remaining
    }

    var stage: Stage
    var progressValue: Int
    var remainingMinutes: Int
}

#if DEBUG
enum FocusUIPreview {
    static let stateArgument = "-uiPreviewState"
    static let landscapeArgument = "-uiPreviewLandscape"

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

    static var isActive: Bool { parsedState() != nil }

    /// DEBUG スクショ用。通知・AlarmKit の許可ダイアログを出さない。
    static var skipsNotificationAuthorization: Bool { isActive }

    /// 到着オーバーレイの UI テスト／スクショ待ち受け用。
    static let arrivalOverlayReadyNotification = Notification.Name("FocusUIPreview.arrivalOverlayReady")
    static let arrivalOverlayAccessibilityID = "FocusUIPreview.ArrivalOverlay"

    /// 車内放送の TTS はスクショ起動では鳴らさない（シミュレーターで描画が止まることがある）。
    static var skipsDriverVoice: Bool { isActive }

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
        try manager.startService()
        let ticket = Ticket(title: "スクショ用", estimatedSeconds: 45 * 60, sortOrder: 0)
        context.insert(ticket)
        try context.save()
        try manager.board(ticket: ticket)
        guard let session = manager.activeSession else { return }

        switch state {
        case "reestimateProgress":
            session.accumulatedActiveSeconds = 12 * 60
            manager.presentReestimate(trigger: .manual, surface: .iphonePortrait)
            manager.focusReestimatePreview = FocusReestimatePreviewConfiguration(
                stage: .progress,
                progressValue: 40,
                remainingMinutes: 0
            )
            manager.uiPreviewForcesFocusCover = true

        case "reestimateMinutes":
            session.accumulatedActiveSeconds = 12 * 60
            manager.presentReestimate(trigger: .manual, surface: .iphonePortrait)
            manager.focusReestimatePreview = FocusReestimatePreviewConfiguration(
                stage: .remaining,
                progressValue: 40,
                remainingMinutes: 0
            )
            manager.uiPreviewForcesFocusCover = true

        case "reestimateMinutesOnly":
            session.accumulatedActiveSeconds = 4 * 60
            manager.presentReestimate(trigger: .manual, surface: .iphonePortrait)
            manager.focusReestimatePreview = FocusReestimatePreviewConfiguration(
                stage: .remaining,
                progressValue: 0,
                remainingMinutes: 20
            )
            manager.uiPreviewForcesFocusCover = true

        case "planEnd":
            session.currentBudgetSeconds = 45 * 60
            session.accumulatedActiveSeconds = 46 * 60
            session.segmentStartedAt = manager.clock.now.addingTimeInterval(-46 * 60)
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
