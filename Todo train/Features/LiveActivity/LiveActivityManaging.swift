//
//  LiveActivityManaging.swift
//  Todo train
//

import Foundation

protocol LiveActivityManaging: Sendable {
    func startOrUpdate(
        sessionID: UUID,
        title: String,
        deadline: Date,
        isOvertime: Bool,
        budgetSeconds: Int,
        isPaused: Bool,
        pausedAt: Date?
    )
    func end()
}

struct NoOpLiveActivityManager: LiveActivityManaging {
    func startOrUpdate(
        sessionID: UUID,
        title: String,
        deadline: Date,
        isOvertime: Bool,
        budgetSeconds: Int,
        isPaused: Bool,
        pausedAt: Date?
    ) {}
    func end() {}
}

#if canImport(ActivityKit)
import ActivityKit

@MainActor
final class LiveActivityManager: LiveActivityManaging {
    static let shared = LiveActivityManager()

    private var currentSessionID: UUID?

    private init() {}

    func startOrUpdate(
        sessionID: UUID,
        title: String,
        deadline: Date,
        isOvertime: Bool,
        budgetSeconds: Int,
        isPaused: Bool,
        pausedAt: Date?
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = TodoTrainActivityAttributes.ContentState(
            title: title,
            deadline: deadline,
            isOvertime: isOvertime,
            budgetSeconds: max(budgetSeconds, 1),
            isPaused: isPaused
        )

        // Keep the activity active while paused so StandBy / Island resume still work.
        // staleDate marks it after 2h; SessionManager.end() on the next launch actually removes it.
        let staleDate: Date?
        if isPaused {
            staleDate = PauseLiveActivityRetention.keepUntil(pausedAt: pausedAt ?? Date.now)
        } else {
            staleDate = isOvertime ? nil : deadline.addingTimeInterval(30)
        }
        let content = ActivityContent(state: state, staleDate: staleDate)

        if currentSessionID == sessionID,
           let activity = Activity<TodoTrainActivityAttributes>.activities.first {
            Task {
                await activity.update(content)
            }
            return
        }

        end()
        currentSessionID = sessionID

        let attributes = TodoTrainActivityAttributes(sessionID: sessionID)
        do {
            _ = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            currentSessionID = nil
        }
    }

    func end() {
        currentSessionID = nil
        for activity in Activity<TodoTrainActivityAttributes>.activities {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
#endif
