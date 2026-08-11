//
//  WidgetSnapshot.swift
//  Shared by app + TodoTrainWidget (Home Screen Widget).
//

import Foundation
import WidgetKit

enum WidgetSnapshotStore {
    static let appGroupID = "group.dev.hibiki-cube.Todo-train"
    static let suiteKey = "widget.snapshot"
    static let homeWidgetKind = "TodoTrainWidget"

    struct Snapshot: Codable, Equatable {
        var isInService: Bool
        var pausedCount: Int
        var focusMinutesToday: Int
        var updatedAt: Date
    }

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func load() -> Snapshot? {
        guard let data = defaults?.data(forKey: suiteKey) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: suiteKey)
        WidgetCenter.shared.reloadTimelines(ofKind: homeWidgetKind)
    }

    static func publish(
        isInService: Bool,
        pausedCount: Int,
        focusMinutesToday: Int,
        now: Date = .now
    ) {
        save(
            Snapshot(
                isInService: isInService,
                pausedCount: pausedCount,
                focusMinutesToday: focusMinutesToday,
                updatedAt: now
            )
        )
    }
}
