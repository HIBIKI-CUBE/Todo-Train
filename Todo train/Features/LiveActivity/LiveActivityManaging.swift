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
    /// Approach color for stage 2. Absent leaves the timer's own phase.
    var instrumentPhaseRaw: String? = nil
    /// Stage 1 keeps the timer color and shows the question as the header.
    var promptKeepsTimerColor: Bool = false
}

/// Whether a Live Activity has anything to draw. A blank title starts an
/// activity whose Dynamic Island and Lock Screen presentations are empty.
enum LiveActivityLifecycle {
    static func shouldPresent(_ content: LiveActivitySessionContent) -> Bool {
        !content.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
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
        guard LiveActivityLifecycle.shouldPresent(content) else {
            end()
            return
        }
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
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class LiveActivityManager: LiveActivityManaging {
    static let shared = LiveActivityManager()

    private var currentSessionID: UUID?
    private var currentActivityID: String?
    private var updatesTask: Task<Void, Never>?

    private init() {
        // `Activity.activities` is often empty during the first moments of launch.
        // Activities restored after that still have to be ended, or a ride that
        // already finished stays on the island and the Lock Screen.
        updatesTask = Task { @MainActor [weak self] in
            for await activity in Activity<TodoTrainActivityAttributes>.activityUpdates {
                self?.enforce(activity)
            }
        }
    }

    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func startOrUpdate(_ content: LiveActivitySessionContent) {
        guard LiveActivityLifecycle.shouldPresent(content) else {
            end()
            return
        }
        guard areActivitiesEnabled else { return }

        let state = TodoTrainActivityAttributes.ContentState(
            title: content.title,
            deadline: content.deadline,
            isOvertime: content.isOvertime,
            budgetSeconds: max(content.budgetSeconds, 1),
            isPaused: content.isPaused,
            checkInPrompt: content.checkInPrompt,
            instrumentPhaseRaw: content.instrumentPhaseRaw,
            promptKeepsTimerColor: content.promptKeepsTimerColor
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

        let running = runningActivities()
        if let activity = running.first(where: {
            $0.id == currentActivityID && $0.attributes.sessionID == content.sessionID
        }) ?? running.first(where: { $0.attributes.sessionID == content.sessionID }) {
            currentSessionID = content.sessionID
            currentActivityID = activity.id
            endActivities(running.filter { $0.id != activity.id } + lingeringActivities())
            Task {
                await activity.update(activityContent, alertConfiguration: alert)
            }
            return
        }

        endActivities(running + lingeringActivities())
        currentSessionID = content.sessionID

        let attributes = TodoTrainActivityAttributes(sessionID: content.sessionID)
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: activityContent,
                pushType: nil
            )
            currentActivityID = activity.id
        } catch {
            currentSessionID = nil
            currentActivityID = nil
        }
    }

    func end() {
        currentSessionID = nil
        currentActivityID = nil
        endActivities(runningActivities() + lingeringActivities())
    }

    /// `end(nil)` clears the content and the island stays at width 0 when the
    /// unstructured task is suspended before dismissal. Pass the last content
    /// and keep the process up until ActivityKit finishes.
    private func endActivities(_ activities: [Activity<TodoTrainActivityAttributes>]) {
        let finals = activities.map { activity in
            (activity, ActivityContent(state: activity.content.state, staleDate: nil as Date?))
        }
        guard !finals.isEmpty else { return }
        #if canImport(UIKit)
        let token = UIApplication.shared.beginBackgroundTask(withName: "todotrain.live-activity.end")
        #endif
        Task {
            for (activity, content) in finals {
                await activity.end(content, dismissalPolicy: .immediate)
            }
            #if canImport(UIKit)
            if token != .invalid {
                UIApplication.shared.endBackgroundTask(token)
            }
            #endif
        }
    }

    private func enforce(_ activity: Activity<TodoTrainActivityAttributes>) {
        guard activity.id != currentActivityID else { return }
        switch activity.activityState {
        case .dismissed:
            return
        case .active, .ended, .stale:
            endActivities([activity])
        @unknown default:
            endActivities([activity])
        }
    }

    private func runningActivities() -> [Activity<TodoTrainActivityAttributes>] {
        Activity<TodoTrainActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    private func lingeringActivities() -> [Activity<TodoTrainActivityAttributes>] {
        Activity<TodoTrainActivityAttributes>.activities.filter {
            $0.activityState == .ended
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
