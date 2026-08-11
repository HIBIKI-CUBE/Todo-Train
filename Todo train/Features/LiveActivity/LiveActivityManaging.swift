//
//  LiveActivityManaging.swift
//  Todo train
//

import Foundation

protocol LiveActivityManaging: Sendable {
    func startOrUpdate(sessionID: UUID, title: String, deadline: Date, isOvertime: Bool)
    func end()
}

struct NoOpLiveActivityManager: LiveActivityManaging {
    func startOrUpdate(sessionID: UUID, title: String, deadline: Date, isOvertime: Bool) {}
    func end() {}
}

#if canImport(ActivityKit)
import ActivityKit

@MainActor
final class LiveActivityManager: LiveActivityManaging {
    static let shared = LiveActivityManager()

    private var currentSessionID: UUID?

    private init() {}

    func startOrUpdate(sessionID: UUID, title: String, deadline: Date, isOvertime: Bool) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = TodoTrainActivityAttributes.ContentState(
            title: title,
            deadline: deadline,
            isOvertime: isOvertime
        )

        if currentSessionID == sessionID,
           let activity = Activity<TodoTrainActivityAttributes>.activities.first {
            Task {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
            return
        }

        end()
        currentSessionID = sessionID

        let attributes = TodoTrainActivityAttributes(sessionID: sessionID)
        do {
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
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
