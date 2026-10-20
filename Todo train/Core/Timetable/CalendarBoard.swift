//
//  CalendarBoard.swift
//  Todo train
//
//  Live 掲示. EventKit は所属の正ではない。着発するまで網にしない。
//

import Foundation

enum CalendarBoardAuthorization: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
}

nonisolated struct CalendarSource: Equatable, Sendable, Identifiable {
    var identifier: String
    var title: String

    var id: String { identifier }
}

@MainActor
protocol CalendarBoard: AnyObject {
    func authorizationStatus() -> CalendarBoardAuthorization
    func requestAccess() async -> Bool
    func availableCalendars() -> [CalendarSource]
    func occurrences(from start: Date, to end: Date) async throws -> [CalendarOccurrence]
}

@MainActor
final class NoOpCalendarBoard: CalendarBoard {
    func authorizationStatus() -> CalendarBoardAuthorization { .denied }
    func requestAccess() async -> Bool { false }
    func availableCalendars() -> [CalendarSource] { [] }
    func occurrences(from start: Date, to end: Date) async throws -> [CalendarOccurrence] { [] }
}

@MainActor
final class InMemoryCalendarBoard: CalendarBoard {
    var status: CalendarBoardAuthorization = .authorized
    var calendars: [CalendarSource] = []
    var events: [CalendarOccurrence] = []
    private(set) var requestCount = 0
    private(set) var fetchCount = 0

    func authorizationStatus() -> CalendarBoardAuthorization { status }

    func requestAccess() async -> Bool {
        requestCount += 1
        if status == .notDetermined {
            status = .authorized
        }
        return status == .authorized
    }

    func availableCalendars() -> [CalendarSource] { calendars }

    func occurrences(from start: Date, to end: Date) async throws -> [CalendarOccurrence] {
        fetchCount += 1
        return events.filter { $0.startsAt < end && $0.endsAt > start }
    }
}
