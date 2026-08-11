//
//  WeeklyReport.swift
//  Todo train
//

import Foundation

struct WeekAggregate: Equatable, Sendable {
    var weekStart: Date
    var focusSeconds: TimeInterval
    var arrived: Int
    var partialDisembark: Int
    var abandoned: Int

    var focusMinutes: Int {
        Int((focusSeconds / 60).rounded())
    }
}

enum WeeklyReport {
    static func weekInterval(
        containing date: Date,
        calendar: Calendar = .current
    ) -> DateInterval {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? date
        return DateInterval(start: start, end: end)
    }

    static func aggregate(
        sessions: [WorkSession],
        weekContaining date: Date,
        calendar: Calendar = .current
    ) -> WeekAggregate {
        let interval = weekInterval(containing: date, calendar: calendar)
        let inWeek = sessions.filter { session in
            guard let endedAt = session.endedAt else { return false }
            return interval.contains(endedAt)
        }
        let dayAggregate = HistoryStats.aggregate(sessions: inWeek)
        return WeekAggregate(
            weekStart: interval.start,
            focusSeconds: dayAggregate.focusSeconds,
            arrived: dayAggregate.arrived,
            partialDisembark: dayAggregate.partialDisembark,
            abandoned: dayAggregate.abandoned
        )
    }

    static func groupByWeek(
        sessions: [WorkSession],
        calendar: Calendar = .current
    ) -> [(weekStart: Date, sessions: [WorkSession])] {
        let ended = sessions
            .filter { $0.endedAt != nil }
            .sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }

        var order: [Date] = []
        var buckets: [Date: [WorkSession]] = [:]

        for session in ended {
            guard let endedAt = session.endedAt else { continue }
            let weekStart = weekInterval(containing: endedAt, calendar: calendar).start
            if buckets[weekStart] == nil {
                order.append(weekStart)
                buckets[weekStart] = []
            }
            buckets[weekStart]?.append(session)
        }

        return order.map { start in
            (weekStart: start, sessions: buckets[start] ?? [])
        }
    }

    static func weekTitle(for weekStart: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(formatter.string(from: weekStart)) – \(formatter.string(from: end))"
    }
}
