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
        budgetSeconds: Int
    )
    func end()
}

struct NoOpLiveActivityManager: LiveActivityManaging {
    func startOrUpdate(
        sessionID: UUID,
        title: String,
        deadline: Date,
        isOvertime: Bool,
        budgetSeconds: Int
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
        budgetSeconds: Int
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = TodoTrainActivityAttributes.ContentState(
            title: title,
            deadline: deadline,
            isOvertime: isOvertime,
            budgetSeconds: max(budgetSeconds, 1)
        )

        // Become stale shortly after the deadline if we never push an overtime update.
        let staleDate = isOvertime ? nil : deadline.addingTimeInterval(30)

        if currentSessionID == sessionID,
           let activity = Activity<TodoTrainActivityAttributes>.activities.first {
            Task {
                await activity.update(ActivityContent(state: state, staleDate: staleDate))
            }
            return
        }

        end()
        currentSessionID = sessionID

        let attributes = TodoTrainActivityAttributes(sessionID: sessionID)
        do {
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: staleDate),
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
