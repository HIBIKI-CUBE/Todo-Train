//
//  TodoTrainAlarmMetadata.swift
//  Shared by app + TodoTrainWidget (AlarmKit Live Activity).
//

import Foundation

#if canImport(AlarmKit)
import AlarmKit

/// AlarmKit metadata shared across the main app and the widget extension.
/// Must stay `nonisolated` under default MainActor isolation (Xcode 26+).
nonisolated struct TodoTrainAlarmMetadata: AlarmMetadata, Codable, Hashable, Sendable {
    var sessionID: UUID
    var ticketTitle: String
    /// Current session budget at schedule time (for phase thresholds + progress).
    var budgetSeconds: Int

    init(sessionID: UUID, ticketTitle: String, budgetSeconds: Int) {
        self.sessionID = sessionID
        self.ticketTitle = ticketTitle
        self.budgetSeconds = max(budgetSeconds, 1)
    }
}
#endif
