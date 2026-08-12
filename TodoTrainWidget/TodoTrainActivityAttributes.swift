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
    }

    var sessionID: UUID
}
#endif
