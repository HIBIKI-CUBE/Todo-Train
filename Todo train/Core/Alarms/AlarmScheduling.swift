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
    func cancel(sessionID: UUID)
    func cancelAll()
}

struct NoOpAlarmScheduler: AlarmScheduling {
    func requestAuthorizationIfNeeded() {}
    func scheduleEndBell(sessionID: UUID, ticketTitle: String, fireAt: Date) {}
    func cancel(sessionID: UUID) {}
    func cancelAll() {}
}

/// Test double — records scheduled bells without AlarmKit.
final class InMemoryAlarmScheduler: AlarmScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requests: [EndBellRequest] = []
    private(set) var cancelledSessionIDs: [UUID] = []
    private(set) var cancelAllCount = 0
    private(set) var authorizationRequestCount = 0

    func requestAuthorizationIfNeeded() {
        lock.withLock { authorizationRequestCount += 1 }
    }

    func scheduleEndBell(sessionID: UUID, ticketTitle: String, fireAt: Date) {
        lock.withLock {
            requests.removeAll { $0.sessionID == sessionID }
            requests.append(EndBellRequest(sessionID: sessionID, ticketTitle: ticketTitle, fireAt: fireAt))
        }
    }

    func cancel(sessionID: UUID) {
        lock.withLock {
            cancelledSessionIDs.append(sessionID)
            requests.removeAll { $0.sessionID == sessionID }
        }
    }

    func cancelAll() {
        lock.withLock {
            cancelAllCount += 1
            requests.removeAll()
        }
    }
}

#if canImport(AlarmKit)
import AlarmKit

@MainActor
final class AlarmKitScheduler: AlarmScheduling {
    static let shared = AlarmKitScheduler()

    private var trackedAlarmIDs: Set<UUID> = []

    private init() {}

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

    func cancel(sessionID: UUID) {
        let alarmID = SessionEndSchedule.alarmID(sessionID: sessionID)
        trackedAlarmIDs.remove(alarmID)
        try? AlarmManager.shared.cancel(id: alarmID)
    }

    func cancelAll() {
        let ids = trackedAlarmIDs
        trackedAlarmIDs.removeAll()
        for id in ids {
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

        // iOS 26.1+: stop is system-provided; custom stopButton is deprecated.
        let alertPresentation = AlarmPresentation.Alert(
            title: LocalizedStringResource("見積もり終了")
        )
        let countdownPresentation = AlarmPresentation.Countdown(
            title: LocalizedStringResource(stringLiteral: ticketTitle)
        )
        let metadata = TodoTrainAlarmMetadata(ticketTitle: ticketTitle)

        let attributes = AlarmAttributes<TodoTrainAlarmMetadata>(
            presentation: AlarmPresentation(
                alert: alertPresentation,
                countdown: countdownPresentation
            ),
            metadata: metadata,
            tintColor: .orange
        )
        let configuration = AlarmManager.AlarmConfiguration<TodoTrainAlarmMetadata>(
            countdownDuration: duration,
            attributes: attributes
        )

        do {
            _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
        } catch {
            trackedAlarmIDs.remove(alarmID)
        }
    }
}
#endif
