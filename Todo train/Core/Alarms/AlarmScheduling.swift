//
//  AlarmScheduling.swift
//  Todo train
//

import Foundation

struct EndBellRequest: Equatable, Sendable {
    let sessionID: UUID
    let ticketTitle: String
    let fireAt: Date
}

protocol AlarmScheduling: Sendable {
    /// AlarmKit authorization is granted (false for NoOp / unauthorized).
    var isAuthorized: Bool { get }
    func requestAuthorizationIfNeeded()
    func scheduleEndBell(sessionID: UUID, ticketTitle: String, fireAt: Date, budgetSeconds: Int)
    /// Freeze the countdown Live Activity without tearing it down.
    func pause(sessionID: UUID)
    /// Resume a paused countdown. Returns false when no paused alarm remains (caller should schedule).
    @discardableResult
    func resume(sessionID: UUID) -> Bool
    func hasAlarm(sessionID: UUID) -> Bool
    func cancel(sessionID: UUID)
    func cancelAll()
    /// Cancel every tracked alarm except the given session (running or paused).
    func cancelAllExcept(sessionID: UUID?)
}

struct NoOpAlarmScheduler: AlarmScheduling {
    var isAuthorized: Bool { false }
    func requestAuthorizationIfNeeded() {}
    func scheduleEndBell(sessionID: UUID, ticketTitle: String, fireAt: Date, budgetSeconds: Int) {}
    func pause(sessionID: UUID) {}
    func resume(sessionID: UUID) -> Bool { false }
    func hasAlarm(sessionID: UUID) -> Bool { false }
    func cancel(sessionID: UUID) {}
    func cancelAll() {}
    func cancelAllExcept(sessionID: UUID?) {}
}

/// Test double — records scheduled bells without AlarmKit.
final class InMemoryAlarmScheduler: AlarmScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requests: [EndBellRequest] = []
    private(set) var pausedSessionIDs: Set<UUID> = []
    private(set) var resumedSessionIDs: [UUID] = []
    private(set) var cancelledSessionIDs: [UUID] = []
    private(set) var cancelAllCount = 0
    private(set) var authorizationRequestCount = 0
    /// Simulated AlarmKit authorization (default true so end-bell tests use AlarmKit channel).
    var isAuthorized: Bool = true

    func requestAuthorizationIfNeeded() {
        lock.withLock { authorizationRequestCount += 1 }
    }

    func scheduleEndBell(sessionID: UUID, ticketTitle: String, fireAt: Date, budgetSeconds: Int) {
        lock.withLock {
            pausedSessionIDs.remove(sessionID)
            requests.removeAll { $0.sessionID == sessionID }
            requests.append(EndBellRequest(sessionID: sessionID, ticketTitle: ticketTitle, fireAt: fireAt))
        }
    }

    func pause(sessionID: UUID) {
        lock.withLock {
            if requests.contains(where: { $0.sessionID == sessionID }) {
                pausedSessionIDs.insert(sessionID)
            }
        }
    }

    @discardableResult
    func resume(sessionID: UUID) -> Bool {
        lock.withLock {
            guard pausedSessionIDs.contains(sessionID),
                  requests.contains(where: { $0.sessionID == sessionID }) else {
                return false
            }
            pausedSessionIDs.remove(sessionID)
            resumedSessionIDs.append(sessionID)
            return true
        }
    }

    func hasAlarm(sessionID: UUID) -> Bool {
        lock.withLock {
            requests.contains { $0.sessionID == sessionID }
        }
    }

    func cancel(sessionID: UUID) {
        lock.withLock {
            cancelledSessionIDs.append(sessionID)
            pausedSessionIDs.remove(sessionID)
            requests.removeAll { $0.sessionID == sessionID }
        }
    }

    func cancelAll() {
        lock.withLock {
            cancelAllCount += 1
            for request in requests {
                cancelledSessionIDs.append(request.sessionID)
            }
            pausedSessionIDs.removeAll()
            requests.removeAll()
        }
    }

    func cancelAllExcept(sessionID: UUID?) {
        lock.withLock {
            let kept = sessionID
            let doomed = requests.filter { $0.sessionID != kept }
            for request in doomed {
                cancelledSessionIDs.append(request.sessionID)
                pausedSessionIDs.remove(request.sessionID)
            }
            requests.removeAll { $0.sessionID != kept }
            if let kept {
                pausedSessionIDs = pausedSessionIDs.filter { $0 == kept }
            } else {
                pausedSessionIDs.removeAll()
            }
        }
    }
}
