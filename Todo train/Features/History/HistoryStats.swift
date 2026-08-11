//
//  HistoryStats.swift
//  Todo train
//

import Foundation

struct DayAggregate: Equatable, Sendable {
    var focusSeconds: TimeInterval
    var arrived: Int
    var partialDisembark: Int
    var abandoned: Int

    var focusMinutes: Int {
        Int((focusSeconds / 60).rounded())
    }
}

enum HistoryStats {
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        ServiceDay.dayKey(for: date, calendar: calendar)
    }

    static func aggregate(sessions: [WorkSession]) -> DayAggregate {
        var focus: TimeInterval = 0
        var arrived = 0
        var partial = 0
        var abandoned = 0

        for session in sessions {
            focus += session.accumulatedActiveSeconds
            switch session.outcome {
            case .arrived:
                arrived += 1
            case .partialDisembark:
                partial += 1
            case .abandoned:
                abandoned += 1
            case .recoveryConflict, .none:
                break
            }
        }

        return DayAggregate(
            focusSeconds: focus,
            arrived: arrived,
            partialDisembark: partial,
            abandoned: abandoned
        )
    }

    /// Groups ended sessions by day key, newest day first. Sessions within a day are newest-first.
    static func groupByDay(
        sessions: [WorkSession],
        calendar: Calendar = .current
    ) -> [(dayKey: String, sessions: [WorkSession])] {
        let ended = sessions
            .filter { $0.endedAt != nil }
            .sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }

        var order: [String] = []
        var buckets: [String: [WorkSession]] = [:]

        for session in ended {
            guard let endedAt = session.endedAt else { continue }
            let key = dayKey(for: endedAt, calendar: calendar)
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(session)
        }

        return order.map { key in
            (dayKey: key, sessions: buckets[key] ?? [])
        }
    }

    static func outcomeLabel(_ outcome: SessionOutcome?) -> String {
        switch outcome {
        case .arrived: "到着"
        case .partialDisembark: "途中下車"
        case .abandoned: "放棄"
        case .recoveryConflict: "復旧"
        case .none: "—"
        }
    }
}
