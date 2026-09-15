//
//  EventKitCalendarBoard.swift
//  Todo train
//

import Foundation

#if canImport(EventKit)
import EventKit

@MainActor
final class EventKitCalendarBoard: CalendarBoard {
    private let store = EKEventStore()

    func authorizationStatus() -> CalendarBoardAuthorization {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            return .authorized
        case .denied, .restricted, .writeOnly:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    func requestAccess() async -> Bool {
        do {
            if #available(iOS 17.0, macOS 14.0, *) {
                return try await store.requestFullAccessToEvents()
            }
            return try await store.requestAccess(to: .event)
        } catch {
            return false
        }
    }

    func availableCalendars() -> [CalendarSource] {
        guard authorizationStatus() == .authorized else { return [] }
        return store.calendars(for: .event)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            .map { CalendarSource(identifier: $0.calendarIdentifier, title: $0.title) }
    }

    func occurrences(from start: Date, to end: Date) async throws -> [CalendarOccurrence] {
        guard authorizationStatus() == .authorized else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
        return events.map { event in
            let identifier = event.eventIdentifier ?? event.calendarItemIdentifier
            let calendar = event.calendar
            return CalendarOccurrence(
                eventIdentifier: identifier,
                recurrenceIdentifier: event.hasRecurrenceRules ? identifier : nil,
                title: event.title ?? "",
                startsAt: event.startDate,
                endsAt: event.endDate,
                isAllDay: event.isAllDay,
                isDeclined: isDeclined(event),
                calendarIdentifier: calendar?.calendarIdentifier ?? "",
                calendarTitle: calendar?.title ?? ""
            )
        }
    }

    private func isDeclined(_ event: EKEvent) -> Bool {
        if event.status == .canceled { return true }
        guard let attendees = event.attendees else { return false }
        return attendees.contains { attendee in
            attendee.isCurrentUser && attendee.participantStatus == .declined
        }
    }
}
#else
@MainActor
final class EventKitCalendarBoard: CalendarBoard {
    private let inner = NoOpCalendarBoard()

    func authorizationStatus() -> CalendarBoardAuthorization { inner.authorizationStatus() }
    func requestAccess() async -> Bool { await inner.requestAccess() }
    func availableCalendars() -> [CalendarSource] { inner.availableCalendars() }
    func occurrences(from start: Date, to end: Date) async throws -> [CalendarOccurrence] {
        try await inner.occurrences(from: start, to: end)
    }
}
#endif
