//
//  TimelineModels.swift
//  Todo train
//
//  Day-clock models for 履歴. Wall-clock minutes are equal — idle between rides is never collapsed.
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

struct DayClockStrip: Equatable, Sendable, Identifiable {
    enum Style: Equatable, Sendable {
        /// 掲示 — live calendar, not adopted.
        case notice
        /// ダイヤ — adopted occupancy.
        case adopted
        /// 履歴 — adopted only, thinner.
        case history
    }

    var id: UUID
    var title: String
    var startsAt: Date
    var endsAt: Date
    var style: Style
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
