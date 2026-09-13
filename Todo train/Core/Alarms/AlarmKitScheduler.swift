//
//  AlarmKitScheduler.swift
//  Todo train
//

#if canImport(AlarmKit)
import ActivityKit
import AlarmKit
import AppIntents
import Foundation
import OSLog
import SwiftUI

@MainActor
final class AlarmKitScheduler: AlarmScheduling {
    static let shared = AlarmKitScheduler()

    private static let log = Logger(subsystem: "dev.hibiki-cube.Todo-train", category: "AlarmKit")

    private var trackedAlarmIDs: Set<UUID> = []
    private var previousAlarmStates: [UUID: Alarm.State] = [:]
    /// Alarm IDs whose next state change was initiated by SessionManager (avoid echo).
    private var sessionOriginatedIDs: Set<UUID> = []
    private weak var sessionManager: SessionManager?
    private var updatesTask: Task<Void, Never>?
    /// One in-flight schedule per alarm — overlapping refreshEndBell must not race cancel/schedule.
    private var scheduleTasks: [UUID: Task<Void, Never>] = [:]

    private init() {}

    var isAuthorized: Bool {
        AlarmManager.shared.authorizationState == .authorized
    }

    /// Start observing StandBy / system pause·resume and mirror into SessionManager.
    func bind(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            guard let self else { return }
            for await alarms in AlarmManager.shared.alarmUpdates {
                if Task.isCancelled { break }
                await self.handleAlarmUpdates(alarms)
            }
        }
    }

    func requestAuthorizationIfNeeded() {
        Task {
            _ = try? await AlarmManager.shared.requestAuthorization()
        }
    }

    func scheduleEndBell(sessionID: UUID, ticketTitle: String, fireAt: Date, budgetSeconds: Int) {
        let alarmID = SessionEndSchedule.alarmID(sessionID: sessionID)
        scheduleTasks[alarmID]?.cancel()
        scheduleTasks[alarmID] = Task { [weak self] in
            await self?.scheduleEndBellAsync(
                sessionID: sessionID,
                ticketTitle: ticketTitle,
                fireAt: fireAt,
                budgetSeconds: budgetSeconds
            )
        }
    }

    func pause(sessionID: UUID) {
        let alarmID = SessionEndSchedule.alarmID(sessionID: sessionID)
        sessionOriginatedIDs.insert(alarmID)
        try? AlarmManager.shared.pause(id: alarmID)
    }

    @discardableResult
    func resume(sessionID: UUID) -> Bool {
        let alarmID = SessionEndSchedule.alarmID(sessionID: sessionID)
        sessionOriginatedIDs.insert(alarmID)
        do {
            try AlarmManager.shared.resume(id: alarmID)
            return true
        } catch {
            Self.log.error("Alarm resume failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    func hasAlarm(sessionID: UUID) -> Bool {
        let alarmID = SessionEndSchedule.alarmID(sessionID: sessionID)
        if trackedAlarmIDs.contains(alarmID) { return true }
        if let systemAlarms = try? AlarmManager.shared.alarms {
            return systemAlarms.contains { $0.id == alarmID }
        }
        return false
    }

    func cancel(sessionID: UUID) {
        let alarmID = SessionEndSchedule.alarmID(sessionID: sessionID)
        scheduleTasks.removeValue(forKey: alarmID)?.cancel()
        // Mark before cancel so alarmUpdates stale handling does not treat this as user dismiss.
        sessionOriginatedIDs.insert(alarmID)
        trackedAlarmIDs.remove(alarmID)
        try? AlarmManager.shared.cancel(id: alarmID)
    }

    func cancelAll() {
        let ids = trackedAlarmIDs.union(previousAlarmStates.keys).union(scheduleTasks.keys)
        for task in scheduleTasks.values { task.cancel() }
        scheduleTasks.removeAll()
        trackedAlarmIDs.removeAll()
        for id in ids {
            sessionOriginatedIDs.insert(id)
            try? AlarmManager.shared.cancel(id: id)
        }
    }

    func cancelAllExcept(sessionID: UUID?) {
        let keep = sessionID.map { SessionEndSchedule.alarmID(sessionID: $0) }
        let ids = trackedAlarmIDs.union(previousAlarmStates.keys).union(scheduleTasks.keys)
        for id in ids where id != keep {
            scheduleTasks.removeValue(forKey: id)?.cancel()
            sessionOriginatedIDs.insert(id)
            trackedAlarmIDs.remove(id)
            previousAlarmStates.removeValue(forKey: id)
            try? AlarmManager.shared.cancel(id: id)
        }
        // Also cancel any system-visible alarms we may have lost track of.
        if let systemAlarms = try? AlarmManager.shared.alarms {
            for alarm in systemAlarms where alarm.id != keep {
                sessionOriginatedIDs.insert(alarm.id)
                trackedAlarmIDs.remove(alarm.id)
                previousAlarmStates.removeValue(forKey: alarm.id)
                try? AlarmManager.shared.cancel(id: alarm.id)
            }
        }
    }

    private func scheduleEndBellAsync(
        sessionID: UUID,
        ticketTitle: String,
        fireAt: Date,
        budgetSeconds: Int
    ) async {
        if AlarmManager.shared.authorizationState == .notDetermined {
            _ = try? await AlarmManager.shared.requestAuthorization()
        }
        guard !Task.isCancelled else { return }
        guard AlarmManager.shared.authorizationState == .authorized else {
            Self.log.error("End bell not scheduled — AlarmKit unauthorized")
            return
        }

        // Only one running alarm: drop every other tracked / system alarm first.
        cancelAllExcept(sessionID: sessionID)

        let alarmID = SessionEndSchedule.alarmID(sessionID: sessionID)
        trackedAlarmIDs.insert(alarmID)
        // Cancel without this mark is treated as StandBy dismiss → suppressEndBell,
        // which can wipe the alarm we are about to schedule.
        sessionOriginatedIDs.insert(alarmID)
        try? AlarmManager.shared.cancel(id: alarmID)

        let remaining = max(1 as TimeInterval, fireAt.timeIntervalSinceNow)
        let duration = Alarm.CountdownDuration(preAlert: remaining, postAlert: nil)

        let pauseButton = AlarmButton(
            text: "停車",
            textColor: .white,
            systemImageName: "pause.fill"
        )

        // iOS 26.1+: stop is system-provided; custom stopButton is deprecated.
        // Paused presentation is the StandBy / Lock Screen resume UI.
        // tintColor tints the system alert title/countdown — must not match black background.
        let alertTitle = ticketTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "見積もり終了"
            : ticketTitle
        let alertPresentation = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: alertTitle)
        )
        let countdownPresentation = AlarmPresentation.Countdown(
            title: LocalizedStringResource(stringLiteral: ticketTitle),
            pauseButton: pauseButton
        )
        let pausedPresentation = AlarmPresentation.Paused(
            title: LocalizedStringResource("停車中"),
            resumeButton: AlarmButton(
                text: "再乗車",
                textColor: .white,
                systemImageName: "play.fill"
            )
        )
        let metadata = TodoTrainAlarmMetadata(
            sessionID: sessionID,
            ticketTitle: ticketTitle,
            budgetSeconds: budgetSeconds
        )

        let attributes = AlarmAttributes<TodoTrainAlarmMetadata>(
            presentation: AlarmPresentation(
                alert: alertPresentation,
                countdown: countdownPresentation,
                paused: pausedPresentation
            ),
            metadata: metadata,
            tintColor: CockpitColors.amber
        )
        let configuration = AlarmManager.AlarmConfiguration<TodoTrainAlarmMetadata>(
            countdownDuration: duration,
            attributes: attributes,
            stopIntent: EndBellStopIntent(alarmID: alarmID, sessionID: sessionID),
            sound: .default
        )

        guard !Task.isCancelled else { return }

        do {
            _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
            guard !Task.isCancelled else {
                sessionOriginatedIDs.insert(alarmID)
                trackedAlarmIDs.remove(alarmID)
                try? AlarmManager.shared.cancel(id: alarmID)
                return
            }
            trackedAlarmIDs.insert(alarmID)
            previousAlarmStates[alarmID] = .countdown
            Self.log.info("Scheduled end bell \(alarmID.uuidString, privacy: .public) in \(remaining, format: .fixed(precision: 1))s")
        } catch {
            trackedAlarmIDs.remove(alarmID)
            previousAlarmStates.removeValue(forKey: alarmID)
            Self.log.error("Failed to schedule end bell: \(String(describing: error), privacy: .public)")
        }
    }

    private func handleAlarmUpdates(_ alarms: [Alarm]) async {
        let activeIDs = Set(alarms.map(\.id))
        for staleID in Array(previousAlarmStates.keys) where !activeIDs.contains(staleID) {
            let previous = previousAlarmStates.removeValue(forKey: staleID)
            trackedAlarmIDs.remove(staleID)
            // App-initiated cancel/reschedule — do not suppress.
            if sessionOriginatedIDs.remove(staleID) != nil {
                continue
            }
            // StandBy dismiss during countdown — keep bell off across recover.
            // Paused dismiss only drops the LA; the session stays paused and can resume from Hub.
            if previous == .countdown {
                sessionManager?.suppressEndBell(sessionID: staleID)
            }
        }

        for alarm in alarms {
            let previous = previousAlarmStates[alarm.id]
            previousAlarmStates[alarm.id] = alarm.state

            if sessionOriginatedIDs.remove(alarm.id) != nil {
                continue
            }

            guard let manager = sessionManager,
                  manager.activeSession?.id == alarm.id
            else {
                // Orphan / non-active ride alarm — tear down so only one session keeps an LA.
                if alarm.state == .paused || alarm.state == .countdown {
                    cancel(sessionID: alarm.id)
                }
                continue
            }

            switch alarm.state {
            case .paused:
                if previous != .paused {
                    try? manager.pauseFromAlarmKit()
                }
            case .countdown:
                if previous == .paused {
                    try? manager.resumeFromAlarmKit()
                }
            default:
                break
            }
        }
    }
}
#endif
