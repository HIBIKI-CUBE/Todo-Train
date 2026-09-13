//
//  LiveActivityManaging.swift
//  Todo train
//

import Foundation

struct LiveActivitySessionContent: Equatable, Sendable {
    var sessionID: UUID
    var title: String
    var deadline: Date
    var isOvertime: Bool
    var budgetSeconds: Int
    var isPaused: Bool = false
    var pausedAt: Date? = nil
    var checkInPrompt: String? = nil
    /// When set, the next update presents an ActivityKit alert on this LA.
    var alertTitle: String? = nil
    var alertBody: String? = nil
}

protocol LiveActivityManaging: Sendable {
    var areActivitiesEnabled: Bool { get }
    func startOrUpdate(_ content: LiveActivitySessionContent)
    func end()
}

struct NoOpLiveActivityManager: LiveActivityManaging {
    var areActivitiesEnabled: Bool { false }

    func startOrUpdate(_ content: LiveActivitySessionContent) {}
    func end() {}
}

@MainActor
final class InMemoryLiveActivityManager: LiveActivityManaging {
    var areActivitiesEnabled: Bool
    private(set) var current: LiveActivitySessionContent?
    private(set) var alertCount: Int = 0
    private(set) var endCount: Int = 0

    init(areActivitiesEnabled: Bool = true) {
        self.areActivitiesEnabled = areActivitiesEnabled
    }

    func startOrUpdate(_ content: LiveActivitySessionContent) {
        current = content
        if content.alertTitle != nil {
            alertCount += 1
        }
    }

    func end() {
        current = nil
        endCount += 1
    }
}

#if canImport(ActivityKit)
import ActivityKit

@MainActor
final class LiveActivityManager: LiveActivityManaging {
    static let shared = LiveActivityManager()

    private var currentSessionID: UUID?

    private init() {}

    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func startOrUpdate(_ content: LiveActivitySessionContent) {
        guard areActivitiesEnabled else { return }

        let state = TodoTrainActivityAttributes.ContentState(
            title: content.title,
            deadline: content.deadline,
            isOvertime: content.isOvertime,
            budgetSeconds: max(content.budgetSeconds, 1),
            isPaused: content.isPaused,
            checkInPrompt: content.checkInPrompt
        )

        // Keep the activity active while paused so StandBy / Island resume still work.
        // staleDate marks it after 2h; SessionManager.end() on the next launch actually removes it.
        let staleDate: Date?
        if content.isPaused {
            staleDate = PauseLiveActivityRetention.keepUntil(pausedAt: content.pausedAt ?? Date.now)
        } else {
            staleDate = content.isOvertime ? nil : content.deadline.addingTimeInterval(30)
        }
        let activityContent = ActivityContent(state: state, staleDate: staleDate)
        let alert = Self.alertConfiguration(title: content.alertTitle, body: content.alertBody)

        if currentSessionID == content.sessionID,
           let activity = Activity<TodoTrainActivityAttributes>.activities.first {
            Task {
                await activity.update(activityContent, alertConfiguration: alert)
            }
            return
        }

        end()
        currentSessionID = content.sessionID

        let attributes = TodoTrainActivityAttributes(sessionID: content.sessionID)
        do {
            _ = try Activity.request(
                attributes: attributes,
                content: activityContent,
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

    private static func alertConfiguration(title: String?, body: String?) -> AlertConfiguration? {
        guard let title, let body else { return nil }
        return AlertConfiguration(
            title: LocalizedStringResource(stringLiteral: title),
            body: LocalizedStringResource(stringLiteral: body),
            sound: .default
        )
    }
}
#endif
