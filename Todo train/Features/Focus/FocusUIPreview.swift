//
//  FocusUIPreview.swift
//  Todo train
//
//  DEBUG のみ。`-uiPreviewState` で Focus / 見積もり直しのスクショ用状態を作る。
//

import Foundation
import SwiftData

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

        default:
            break
        }
        manager.uiPreviewLandscape = wantsLandscape
        manager.uiPreviewSuppressMotion = true
    }
}
#endif
