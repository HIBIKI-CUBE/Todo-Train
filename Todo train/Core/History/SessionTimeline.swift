//
//  SessionTimeline.swift
//  Todo train
//
//  Day-clock layout for 履歴. Wall-clock minutes are equal — idle between
//  rides is never collapsed.
//

import Foundation

struct TimelineExtension: Equatable, Sendable {
    var id: UUID
    var addedSeconds: Int
    var reason: String?
    var createdAt: Date
}

struct TimelinePause: Equatable, Sendable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date

    var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }
}

struct TimelineTransfer: Equatable, Sendable, Identifiable {
    var id: UUID
    var title: String
    var isOpen: Bool
}

struct TimelineRide: Equatable, Sendable, Identifiable {
    var id: UUID
    var title: String
    var startedAt: Date
    var endedAt: Date
    var estimatedSecondsAtStart: Int
    var outcome: SessionOutcome?
    var punctuality: ArrivalPunctuality
    var extensions: [TimelineExtension]
    var pauses: [TimelinePause]
    var transfers: [TimelineTransfer]

    var originalScheduleAt: Date {
        startedAt.addingTimeInterval(TimeInterval(max(estimatedSecondsAtStart, 0)))
    }
}

enum TimelineMarkerKind: Equatable, Sendable {
    case boarded
    case originalSchedule
    case extensionStep(index: Int, addedSeconds: Int, reason: String?)
    case pause
    case arrived
    case partialDisembark
    case abandoned
}

struct TimelineMarker: Equatable, Sendable, Identifiable {
    var id: String
    var rideID: UUID
    var kind: TimelineMarkerKind
    var at: Date
    var until: Date?
}

struct DayClockLayout: Equatable, Sendable {
    var start: Date
    var end: Date
    var pointsPerMinute: Double
    var laneByRideID: [UUID: Int]
    var laneCount: Int
    var hourTicks: [Date]

    var height: Double {
        y(for: end)
    }

    func y(for date: Date) -> Double {
        max(0, date.timeIntervalSince(start) / 60.0 * pointsPerMinute)
    }

    func height(from: Date, to: Date) -> Double {
        max(0, y(for: to) - y(for: from))
    }

    func laneIndex(for rideID: UUID) -> Int {
        laneByRideID[rideID] ?? 0
    }
}

enum SessionTimeline {
    /// Wall-clock minutes share one scale — idle is never folded.
    /// 2pt/min (120pt/hour) is a slightly zoomed Calendar day, so 15–30分の切符が読める。
    static let pointsPerMinute: Double = 2.0

    static func rides(from sessions: [WorkSession]) -> [TimelineRide] {
        sessions.compactMap { session -> TimelineRide? in
            guard let endedAt = session.endedAt else { return nil }
            let extensions = session.extensions
                .sorted { $0.createdAt < $1.createdAt }
                .map {
                    TimelineExtension(
                        id: $0.id,
                        addedSeconds: $0.addedSeconds,
                        reason: $0.reason,
                        createdAt: $0.createdAt
                    )
                }
            let pauses = session.pauses.compactMap { pause -> TimelinePause? in
                guard let pauseEnded = pause.endedAt else { return nil }
                return TimelinePause(
                    id: pause.id,
                    startedAt: pause.startedAt,
                    endedAt: pauseEnded
                )
            }
            .sorted { $0.startedAt < $1.startedAt }

            let transfers: [TimelineTransfer]
            if session.outcome == .partialDisembark {
                transfers = (session.ticket?.childLineages ?? []).compactMap { lineage in
                    guard let child = lineage.child else { return nil }
                    return TimelineTransfer(
                        id: child.id,
                        title: child.title,
                        isOpen: child.isOpen
                    )
                }
            } else {
                transfers = []
            }

            return TimelineRide(
                id: session.id,
                title: session.ticket?.title ?? "不明な切符",
                startedAt: session.startedAt,
                endedAt: endedAt,
                estimatedSecondsAtStart: session.estimatedSecondsAtStart,
                outcome: session.outcome,
                punctuality: Punctuality.classify(session),
                extensions: extensions,
                pauses: pauses,
                transfers: transfers
            )
        }
        .sorted {
            if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    static func markers(for ride: TimelineRide) -> [TimelineMarker] {
        var items: [TimelineMarker] = [
            TimelineMarker(
                id: "\(ride.id.uuidString)-boarded",
                rideID: ride.id,
                kind: .boarded,
                at: ride.startedAt
            ),
            TimelineMarker(
                id: "\(ride.id.uuidString)-schedule",
                rideID: ride.id,
                kind: .originalSchedule,
                at: ride.originalScheduleAt
            )
        ]

        for (index, ext) in ride.extensions.enumerated() {
            items.append(
                TimelineMarker(
                    id: "\(ride.id.uuidString)-ext-\(ext.id.uuidString)",
                    rideID: ride.id,
                    kind: .extensionStep(
                        index: index + 1,
                        addedSeconds: ext.addedSeconds,
                        reason: ext.reason
                    ),
                    at: ext.createdAt
                )
            )
        }

        for pause in ride.pauses {
            items.append(
                TimelineMarker(
                    id: "\(ride.id.uuidString)-pause-\(pause.id.uuidString)",
                    rideID: ride.id,
                    kind: .pause,
                    at: pause.startedAt,
                    until: pause.endedAt
                )
            )
        }

        let terminal: TimelineMarkerKind
        switch ride.outcome {
        case .partialDisembark:
            terminal = .partialDisembark
        case .abandoned:
            terminal = .abandoned
        default:
            terminal = .arrived
        }
        items.append(
            TimelineMarker(
                id: "\(ride.id.uuidString)-end",
                rideID: ride.id,
                kind: terminal,
                at: ride.endedAt
            )
        )

        return items.sorted {
            if $0.at != $1.at { return $0.at < $1.at }
            return $0.id < $1.id
        }
    }

    static func layout(
        rides: [TimelineRide],
        calendar: Calendar = .current,
        pointsPerMinute: Double = pointsPerMinute,
        minHeight: Double = 0
    ) -> DayClockLayout? {
        guard let range = timeRange(rides: rides) else { return nil }
        let aligned = hourAlignedRange(start: range.start, end: range.end, calendar: calendar)
        let end = stretchedEnd(
            start: aligned.start,
            end: aligned.end,
            minHeight: minHeight,
            pointsPerMinute: pointsPerMinute
        )
        let lanes = packLanes(rides)
        let laneCount = max(1, Set(lanes.values).count)
        return DayClockLayout(
            start: aligned.start,
            end: end,
            pointsPerMinute: pointsPerMinute,
            laneByRideID: lanes,
            laneCount: laneCount,
            hourTicks: hourTicks(from: aligned.start, to: end, calendar: calendar)
        )
    }

    /// Fill leftover viewport with empty hour rows so a short day is a page, not a stub.
    static func stretchedEnd(
        start: Date,
        end: Date,
        minHeight: Double,
        pointsPerMinute: Double
    ) -> Date {
        guard minHeight > 0, pointsPerMinute > 0 else { return end }
        let current = max(0, end.timeIntervalSince(start) / 60.0 * pointsPerMinute)
        guard current < minHeight else { return end }
        let extraMinutes = (minHeight - current) / pointsPerMinute
        return end.addingTimeInterval(extraMinutes * 60)
    }

    /// Snap the canvas to hour marks so the gutter reads like a calendar.
    static func hourAlignedRange(
        start: Date,
        end: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        let alignedStart = calendar.dateInterval(of: .hour, for: start)?.start ?? start
        guard let endHour = calendar.dateInterval(of: .hour, for: end)?.start else {
            return (alignedStart, end)
        }
        let alignedEnd: Date
        if end <= endHour {
            alignedEnd = endHour
        } else if let next = calendar.date(byAdding: .hour, value: 1, to: endHour) {
            alignedEnd = next
        } else {
            alignedEnd = end
        }
        if alignedEnd <= alignedStart {
            let fallback = calendar.date(byAdding: .hour, value: 1, to: alignedStart)
                ?? alignedStart.addingTimeInterval(3600)
            return (alignedStart, fallback)
        }
        return (alignedStart, alignedEnd)
    }

    static func timeRange(rides: [TimelineRide]) -> (start: Date, end: Date)? {
        guard let firstStart = rides.map(\.startedAt).min() else { return nil }
        var start = firstStart
        var end = firstStart
        for ride in rides {
            start = min(start, ride.startedAt)
            end = max(end, ride.endedAt)
            end = max(end, ride.originalScheduleAt)
            for ext in ride.extensions {
                start = min(start, ext.createdAt)
                end = max(end, ext.createdAt)
            }
            for pause in ride.pauses {
                start = min(start, pause.startedAt)
                end = max(end, pause.endedAt)
            }
        }
        if end < start { return nil }
        return (start, end)
    }

    static func ridesOverlap(_ a: TimelineRide, _ b: TimelineRide) -> Bool {
        a.startedAt < b.endedAt && b.startedAt < a.endedAt
    }

    static func rideIsIsolated(_ ride: TimelineRide, among rides: [TimelineRide]) -> Bool {
        !rides.contains { other in
            other.id != ride.id && ridesOverlap(ride, other)
        }
    }

    static func packLanes(_ rides: [TimelineRide]) -> [UUID: Int] {
        let sorted = rides.sorted {
            if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        var laneEnds: [Date] = []
        var map: [UUID: Int] = [:]
        for ride in sorted {
            if let index = laneEnds.firstIndex(where: { $0 <= ride.startedAt }) {
                map[ride.id] = index
                laneEnds[index] = ride.endedAt
            } else {
                map[ride.id] = laneEnds.count
                laneEnds.append(ride.endedAt)
            }
        }
        return map
    }

    static func hourTicks(from start: Date, to end: Date, calendar: Calendar) -> [Date] {
        guard end >= start else { return [] }
        guard let startHour = calendar.dateInterval(of: .hour, for: start)?.start else {
            return []
        }
        var ticks: [Date] = []
        var tick = startHour
        while tick <= end {
            if tick >= start {
                ticks.append(tick)
            }
            guard let next = calendar.date(byAdding: .hour, value: 1, to: tick) else { break }
            tick = next
        }
        return ticks
    }

    static func markerLabel(_ marker: TimelineMarker) -> String {
        switch marker.kind {
        case .boarded:
            return "発車"
        case .originalSchedule:
            return "元の予定"
        case .extensionStep(let index, let addedSeconds, _):
            return "延長\(index) +\(max(0, addedSeconds) / 60)分"
        case .pause:
            if let until = marker.until {
                let minutes = Int((until.timeIntervalSince(marker.at) / 60).rounded())
                return "停車 \(max(0, minutes))分"
            }
            return "停車"
        case .arrived:
            return "到着"
        case .partialDisembark:
            return "途中下車"
        case .abandoned:
            return "放棄"
        }
    }

    static func spokenSummary(for ride: TimelineRide, timeFormatter: DateFormatter) -> String {
        var parts: [String] = [
            "\(ride.title)、\(timeFormatter.string(from: ride.startedAt))発車",
            "元の予定 \(timeFormatter.string(from: ride.originalScheduleAt))"
        ]
        for (index, ext) in ride.extensions.enumerated() {
            var line = "延長\(index + 1) \(timeFormatter.string(from: ext.createdAt)) +\(max(0, ext.addedSeconds) / 60)分"
            if let reason = ext.reason, !reason.isEmpty {
                line += "（\(reason)）"
            }
            parts.append(line)
        }
        for pause in ride.pauses {
            let minutes = Int((pause.duration / 60).rounded())
            parts.append(
                "停車 \(timeFormatter.string(from: pause.startedAt))から\(max(0, minutes))分"
            )
        }
        let terminal: String
        switch ride.outcome {
        case .partialDisembark:
            terminal = "途中下車"
        case .abandoned:
            terminal = "放棄"
        default:
            switch ride.punctuality {
            case .onTime: terminal = "定時到着"
            case .early: terminal = "早着"
            default: terminal = "到着"
            }
        }
        parts.append("\(timeFormatter.string(from: ride.endedAt))\(terminal)")
        return parts.joined(separator: "。")
    }
}
