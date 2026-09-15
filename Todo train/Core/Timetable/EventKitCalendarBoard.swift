//
//  EventKitCalendarBoard.swift
//  Todo train
//

import Foundation
#if canImport(EventKit)
import EventKit
#endif

#if canImport(EventKit)
@MainActor
final class EventKitCalendarBoard: CalendarBoardReading {
    private let store = EKEventStore()

    var authorization: CalendarBoardAuth {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        default:
            return .denied
        }
    }

    func requestAccess() async -> CalendarBoardAuth {
        if authorization != .notDetermined { return authorization }
        _ = try? await store.requestFullAccessToEvents()
        return authorization
    }

    func occurrences(from start: Date, to end: Date) async -> [CalendarOccurrence] {
        guard authorization == .authorized else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).compactMap { event in
            CalendarOccurrence(
                eventIdentifier: event.eventIdentifier ?? event.calendarItemIdentifier,
                recurrenceIdentifier: event.calendarItemExternalIdentifier,
                title: event.title ?? "",
                startsAt: event.startDate,
                endsAt: event.endDate,
                isAllDay: event.isAllDay,
                isDeclined: event.status == .canceled || Self.isDeclined(event)
            )
        }
        .filter(\.isAdoptable)
        .sorted { $0.startsAt < $1.startsAt }
    }

    private static func isDeclined(_ event: EKEvent) -> Bool {
        guard let attendees = event.attendees else { return false }
        return attendees.contains { attendee in
            attendee.isCurrentUser && attendee.participantStatus == .declined
        }
    }
}
#endif
