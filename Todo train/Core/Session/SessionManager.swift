//
//  SessionManager.swift
//  Todo train
//

import Foundation
import Observation
import SwiftData
import TodoTrainSync
#if canImport(UIKit)
import UIKit
#endif

@Observable
@MainActor
final class SessionManager {
    var phase: SessionPhase = .idle
    /// Bumps when the open ride changes so the Mac companion and the Watch can push a snap.
    var companionSyncTick: Int = 0
    var activeServiceDay: ServiceDay?
    var activeSession: WorkSession?
    var needsServiceDayEndPrompt = false

    let modelContext: ModelContext
    /// Tests set this so `save()` throws before the store write.
    var saveErrorForTesting: Error?
    let clock: any SessionClock
    let calendar: Calendar
    let settings: AppSettings
    let overtimeNotifier: any OvertimeNotifying
    let checkInNotifier: any CheckInNotifying
    let coachingEngine: any CoachingEngine
    let liveActivityManager: any LiveActivityManaging
    let alarmScheduler: any AlarmScheduling
    let deviceIdentity: any DeviceIdentifying
    let deviceLock: any DeviceLockReading
    let calendarBoard: any CalendarBoard

    var awayFireTask: Task<Void, Never>?
    var idleWatchTask: Task<Void, Never>?
    /// Foreground 1 Hz reconcile while a ride or passenger lane needs wall time.
    var foregroundReconcileTask: Task<Void, Never>?
    /// Set by the app scene; the loop itself only runs with `SystemSessionClock`.
    var isForegroundForReconcile = false
    /// `.active` only. `.inactive` keeps the 1 Hz loop and is not Focus for a nudge.
    var iphoneSceneActive = false
    /// Mac presence. Until a presence command, Mac is not foreground.
    var macPipVisible = false
    var macAttending = false
    /// False until a presence op arrives, and again when the relay link drops.
    var macPresenceKnown = false
    /// Bumps when this iPhone should play the overrun presentation once.
    var nudgeRingTick = 0
    /// Hub is the front surface. Focus and other tabs are not.
    var iphoneHubVisible = false
    /// Focus cover is up. Background does not count as the desk.
    var iphoneFocusVisible = false
    /// Arrival stamp screen is still up. Gap stays down until it closes.
    var arrivalScreenOpen = false
    /// Bumps once when this iPhone's gap turn is fresh. Focus does not listen.
    var gapCueTick = 0
    /// Banner on Hub during the arrival blank. Nil on Focus.
    var arrivalGapBanner: ArrivalGapBannerState?
    var gapWatchTask: Task<Void, Never>?
    /// Working seconds at the previous nudge sample. A jump larger than the tick does not ring.
    var nudgeObservedElapsed: TimeInterval?
    var nudgeObservedSessionID: UUID?
    var nudgeObservedStageRaw: String?
    /// Avoid re-enqueueing the same idle banner on every `reconcile`.
    var idleLocalNotificationArmed = false
    #if canImport(UIKit)
    var awayBackgroundTask = UIBackgroundTaskIdentifier.invalid
    #endif

    /// Session IDs whose end bell was dismissed by the user (StandBy cancel).
    /// Prevents recover / foreground from silently re-scheduling the same bell.
    var suppressedEndBellSessionIDs: Set<UUID> = []

    /// Paired Mac. Progress questions are never local notifications.
    var suppressProgressLocalNotifications = false
    var lastNotifyOn: NotifyOn?
    var lastNotifyTurn: Int?
    var lastNotifyFireAt: Int?
    /// Calendar 掲示 (eligible, not necessarily adopted). Warmed from the ダイヤ tab, and Hub if already authorized.
    var noticeOccurrences: [CalendarOccurrence] = []
    /// Last AlarmKit / end-bell fire we scheduled, so reconcile does not hammer AlarmKit.
    var lastScheduledEndBellFireAt: Date?
    /// 乗客レーン。SessionPhase には混ぜない。
    var passengerChrome: PassengerChrome = .none
    var passengerMemory = PassengerLaneMemory.empty
    /// Ephemeral UI chrome (haptics, quiet line, punctuality queue).
    let presentation = SessionPresentation()

    var reestimateRequest: SessionManager.ReestimateRequest?
    var focusUndoOffer: SessionManager.FocusUndoOffer?
    var focusUndoTask: Task<Void, Never>?
    #if DEBUG
    var focusReestimatePreview: FocusReestimatePreviewConfiguration?
    var uiPreviewForcesFocusCover: Bool = false
    var uiPreviewLandscape: Bool = false
    var uiPreviewSuppressMotion: Bool = false
    var uiPreviewShowsServiceShutdown: Bool = false
    var uiPreviewSelectHistoryTab: Bool = false
    var uiPreviewShowsBundleViewer: Bool = false
    var uiPreviewBundleViewerDayKey: String?
    var uiPreviewBundleFocusIndex: Int = 0
    /// 印を押したあとの券面（穴・丸印・角判）を動きなしで出す。
    struct ArrivalUIPreviewStamp {
        var stampCommitted: Bool = true
    }
    var arrivalUIPreviewStamp: ArrivalUIPreviewStamp?
    #endif

    var pauseLimit: Int { settings.pauseLimit }

    func bumpCompanionSync() {
        companionSyncTick += 1
    }

    init(
        modelContext: ModelContext,
        clock: any SessionClock = SystemSessionClock(),
        calendar: Calendar = .current,
        settings: AppSettings? = nil,
        overtimeNotifier: (any OvertimeNotifying)? = nil,
        checkInNotifier: (any CheckInNotifying)? = nil,
        coachingEngine: (any CoachingEngine)? = nil,
        liveActivityManager: (any LiveActivityManaging)? = nil,
        alarmScheduler: (any AlarmScheduling)? = nil,
        deviceIdentity: (any DeviceIdentifying)? = nil,
        deviceLock: (any DeviceLockReading)? = nil,
        calendarBoard: (any CalendarBoard)? = nil
    ) {
        self.modelContext = modelContext
        self.clock = clock
        self.calendar = calendar
        self.settings = settings ?? .shared
        self.overtimeNotifier = overtimeNotifier ?? NoOpOvertimeNotifier()
        self.checkInNotifier = checkInNotifier ?? NoOpCheckInNotifier()
        self.coachingEngine = coachingEngine ?? HeuristicCoachingEngine()
        self.liveActivityManager = liveActivityManager ?? NoOpLiveActivityManager()
        self.alarmScheduler = alarmScheduler ?? NoOpAlarmScheduler()
        self.deviceIdentity = deviceIdentity ?? SystemDeviceIdentity()
        self.deviceLock = deviceLock ?? SystemDeviceLock()
        self.calendarBoard = calendarBoard ?? EventKitCalendarBoard()
    }
}

extension SessionManager: SessionRidePausing {}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
