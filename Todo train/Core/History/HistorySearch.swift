//
//  HistorySearch.swift
//  Todo train
//

import Foundation

enum HistorySearch {
    static func matches(session: WorkSession, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let title = session.ticket?.title ?? ""
        return title.range(
            of: trimmed,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    static func filter(sessions: [WorkSession], query: String) -> [WorkSession] {
        sessions.filter { matches(session: $0, query: query) }
    }
}
