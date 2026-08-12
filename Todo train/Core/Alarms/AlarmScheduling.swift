//
//  AlarmScheduling.swift
//  Todo train
//

import Foundation
import SwiftUI

struct EndBellRequest: Equatable, Sendable {
    let sessionID: UUID
    let ticketTitle: String
    let fireAt: Date
}

protocol AlarmScheduling: Sendable {
    func requestAuthorizationIfNeeded()
    func scheduleEndBell(sessionID: UUID, ticketTitle: String, fireAt: Date)
    /// Pause countdown without cancelling (StandBy / Focus 停車).
    func pause(sessionID: UUID)
    /// Resume a paused countdown. Returns false if nothing to resume (caller may reschedule).
    @discardableResult
    func resume(sessionID: UUID) -> Bool
    func cancel(sessionID: UUID)
    func cancelAll()
}

struct NoOpAlarmScheduler: AlarmScheduling {
    func requestAuthorizationIfNeeded() {}
    func scheduleEndBell(sessionID: UUID, ticketTitle: String, fireAt: Date) {}
    func pause(sessionID: UUID) {}
    func resume(sessionID: UUID) -> Bool { false }
    func cancel(sessionID: UUID) {}
    func cancelAll() {}
}

/// Test double — records scheduled bells without AlarmKit.
final class InMemoryAlarmScheduler: AlarmScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requests: [EndBellRequest] = []
    private(set) var pausedSessionIDs: [UUID] = []
    private(set) var resumedSessionIDs: [UUID] = []
    private(set) var cancelledSessionIDs: [UUID] = []
    private(set) var cancelAllCount = 0
    private(set) var authorizationRequestCount = 0
    private var pausedActive: Set<UUID> = []

    func requestAuthorizationIfNeeded() {
        lock.withLock { authorizationRequestCount += 1 }
    }

    func scheduleEndBell(sessionID: UUID, ticketTitle: String, fireAt: Date) {
        lock.withLock {
            pausedActive.remove(sessionID)
            requests.removeAll { $0.sessionID == sessionID }
            requests.append(EndBellRequest(sessionID: sessionID, ticketTitle: ticketTitle, fireAt: fireAt))
        }
    }

    func pause(sessionID: UUID) {
        lock.withLock {
            guard requests.contains(where: { $0.sessionID == sessionID }) || pausedActive.contains(sessionID) else { return }
            pausedActive.insert(sessionID)
            pausedSessionIDs.append(sessionID)
        }
    }

    func resume(sessionID: UUID) -> Bool {
        lock.withLock {
            guard pausedActive.contains(sessionID) else { return false }
            pausedActive.remove(sessionID)
            resumedSessionIDs.append(sessionID)
            return true
        }
    }

    func cancel(sessionID: UUID) {
        lock.withLock {
            cancelledSessionIDs.append(sessionID)
            pausedActive.remove(sessionID)
            requests.removeAll { $0.sessionID == sessionID }
        }
    }

    func cancelAll() {
        lock.withLock {
            cancelAllCount += 1
            pausedActive.removeAll()
            requests.removeAll()
        }
    }
}

#if canImport(AlarmKit)
import AlarmKit
import AppIntents

@MainActor
final class AlarmKitScheduler: AlarmScheduling {
    static let shared = AlarmKitScheduler()

    private var trackedAlarmIDs: Set<UUID> = []
    private var previousAlarmStates: [UUID: Alarm.State] = [:]
    /// Alarm IDs whose next state change was initiated by SessionManager (avoid echo).
    private var sessionOriginatedIDs: Set<UUID> = []
    private weak var sessionManager: SessionManager?
    private var updatesTask: Task<Void, Never>?

    private init() {}

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

    func scheduleEndBell(sessionID: UUID, ticketTitle: String, fireAt: Date) {
        Task {
            await scheduleEndBellAsync(sessionID: sessionID, ticketTitle: ticketTitle, fireAt: fireAt)
        }
    }

    func pause(sessionID: UUID) {
        let alarmID = SessionEndSchedule.alarmID(sessionID: sessionID)
        guard trackedAlarmIDs.contains(alarmID) else { return }
        sessionOriginatedIDs.insert(alarmID)
        try? AlarmManager.shared.pause(id: alarmID)
    }

    @discardableResult
    func resume(sessionID: UUID) -> Bool {
        let alarmID = SessionEndSchedule.alarmID(sessionID: sessionID)
        guard trackedAlarmIDs.contains(alarmID) else { return false }
        sessionOriginatedIDs.insert(alarmID)
        do {
            try AlarmManager.shared.resume(id: alarmID)
            return true
        } catch {
            sessionOriginatedIDs.remove(alarmID)
            return false
        }
    }

    func cancel(sessionID: UUID) {
        let alarmID = SessionEndSchedule.alarmID(sessionID: sessionID)
        // Mark before cancel so alarmUpdates stale handling does not treat this as user dismiss.
        sessionOriginatedIDs.insert(alarmID)
        trackedAlarmIDs.remove(alarmID)
        try? AlarmManager.shared.cancel(id: alarmID)
    }

    func cancelAll() {
        let ids = trackedAlarmIDs.union(previousAlarmStates.keys)
        trackedAlarmIDs.removeAll()
        for id in ids {
            sessionOriginatedIDs.insert(id)
            try? AlarmManager.shared.cancel(id: id)
        }
    }

    private func scheduleEndBellAsync(sessionID: UUID, ticketTitle: String, fireAt: Date) async {
        if AlarmManager.shared.authorizationState == .notDetermined {
            _ = try? await AlarmManager.shared.requestAuthorization()
        }
        guard AlarmManager.shared.authorizationState == .authorized else { return }

        let alarmID = SessionEndSchedule.alarmID(sessionID: sessionID)
        trackedAlarmIDs.insert(alarmID)
        try? AlarmManager.shared.cancel(id: alarmID)

        let remaining = max(1 as TimeInterval, fireAt.timeIntervalSinceNow)
        let duration = Alarm.CountdownDuration(preAlert: remaining, postAlert: nil)

        let pauseButton = AlarmButton(
            text: "停車",
            textColor: .white,
            systemImageName: "pause.fill"
        )
        let resumeButton = AlarmButton(
            text: "再乗車",
            textColor: .white,
            systemImageName: "play.fill"
        )

        // iOS 26.1+: stop is system-provided; custom stopButton is deprecated.
        let alertPresentation = AlarmPresentation.Alert(
            title: LocalizedStringResource("見積もり終了")
        )
        let countdownPresentation = AlarmPresentation.Countdown(
            title: LocalizedStringResource(stringLiteral: ticketTitle),
            pauseButton: pauseButton
        )
        let pausedPresentation = AlarmPresentation.Paused(
            title: LocalizedStringResource("停車中"),
            resumeButton: resumeButton
        )
        let metadata = TodoTrainAlarmMetadata(sessionID: sessionID, ticketTitle: ticketTitle)

        let attributes = AlarmAttributes<TodoTrainAlarmMetadata>(
            presentation: AlarmPresentation(
                alert: alertPresentation,
                countdown: countdownPresentation,
                paused: pausedPresentation
            ),
            metadata: metadata,
            tintColor: Color("AccentColor")
        )
        let configuration = AlarmManager.AlarmConfiguration<TodoTrainAlarmMetadata>(
            countdownDuration: duration,
            attributes: attributes,
            stopIntent: EndBellStopIntent(alarmID: alarmID, sessionID: sessionID)
        )

        do {
            _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
            previousAlarmStates[alarmID] = .countdown
        } catch {
            trackedAlarmIDs.remove(alarmID)
            previousAlarmStates.removeValue(forKey: alarmID)
        }
    }

    private func handleAlarmUpdates(_ alarms: [Alarm]) async {
        let activeIDs = Set(alarms.map(\.id))
        for staleID in previousAlarmStates.keys where !activeIDs.contains(staleID) {
            previousAlarmStates.removeValue(forKey: staleID)
            trackedAlarmIDs.remove(staleID)
            // External cancel (StandBy dismiss) — suppress so recover won't reschedule.
            if sessionOriginatedIDs.remove(staleID) == nil {
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
            else { continue }

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
