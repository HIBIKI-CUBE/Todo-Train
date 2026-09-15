//
//  CalendarBoard.swift
//  Todo train
//
//  Calendar is a reference board, never the source of ダイヤ membership.
//

import Foundation

enum CalendarBoardAuth: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
}

struct CalendarOccurrence: Equatable, Sendable, Identifiable {
    var eventIdentifier: String
    var recurrenceIdentifier: String?
    var title: String
    var startsAt: Date
    var endsAt: Date
    var isAllDay: Bool
    var isDeclined: Bool

    var id: String {
        "\(eventIdentifier)|\(startsAt.timeIntervalSince1970)"
    }

    var isAdoptable: Bool {
        !isAllDay && !isDeclined && endsAt > startsAt
    }
}

@MainActor
protocol CalendarBoardReading: AnyObject {
    var authorization: CalendarBoardAuth { get }
    func requestAccess() async -> CalendarBoardAuth
    func occurrences(from start: Date, to end: Date) async -> [CalendarOccurrence]
}

@MainActor
final class NoOpCalendarBoard: CalendarBoardReading {
    var authorization: CalendarBoardAuth = .denied
    var canned: [CalendarOccurrence] = []

    func requestAccess() async -> CalendarBoardAuth { authorization }

    func occurrences(from start: Date, to end: Date) async -> [CalendarOccurrence] {
        canned.filter { $0.startsAt < end && $0.endsAt > start }
    }
}
