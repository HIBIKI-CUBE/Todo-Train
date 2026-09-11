//
//  TodoTrainActivityAttributes.swift
//  Shared by app + TodoTrainWidget (Session Live Activity).
//

import Foundation

#if canImport(ActivityKit)
import ActivityKit

struct TodoTrainActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var deadline: Date
        var isOvertime: Bool
        var budgetSeconds: Int
        var isPaused: Bool
        var checkInPrompt: String?

        init(
            title: String,
            deadline: Date,
            isOvertime: Bool,
            budgetSeconds: Int,
            isPaused: Bool = false,
            checkInPrompt: String? = nil
        ) {
            self.title = title
            self.deadline = deadline
            self.isOvertime = isOvertime
            self.budgetSeconds = budgetSeconds
            self.isPaused = isPaused
            self.checkInPrompt = checkInPrompt
        }
    }

    var sessionID: UUID
}
#endif
