//
//  TimetableAdoption.swift
//  Todo train
//
//  Pure membership: EventKit occurrences + user rules → today's blocks.
//

import Foundation

enum TimetableAdoption {
    struct Rule: Equatable, Sendable {
        var recurrenceIdentifier: String
        var adopted: Bool
        var excludedOccurrenceStarts: [Date]
    }

    struct ExistingBlock: Equatable, Sendable {
        var id: UUID
        var calendarEventIdentifier: String?
        var calendarRecurrenceIdentifier: String?
        var occurrenceStartKey: Date?
        var source: TimetableSource
        var isCancelled: Bool
    }

    enum Decision: Equatable, Sendable {
        case keep(blockID: UUID)
        case insert(occurrence: CalendarOccurrence, scope: TimetableAdoptionScope)
        case update(blockID: UUID, occurrence: CalendarOccurrence)
        case cancel(blockID: UUID)
    }

    static func materialize(
        occurrences: [CalendarOccurrence],
        rules: [Rule],
        existing: [ExistingBlock]
    ) -> [Decision] {
        var decisions: [Decision] = []
        var claimed = Set<UUID>()

        for occurrence in occurrences where occurrence.isAdoptable {
            let rule = rules.first { $0.recurrenceIdentifier == occurrence.recurrenceIdentifier }
            let excluded = rule?.excludedOccurrenceStarts.contains(where: {
                abs($0.timeIntervalSince(occurrence.startsAt)) < 1
            }) ?? false
            let seriesAdopted = (rule?.adopted ?? false) && !excluded

            if let match = matchingBlock(for: occurrence, in: existing) {
                claimed.insert(match.id)
                if match.isCancelled, !seriesAdopted {
                    decisions.append(.keep(blockID: match.id))
                    continue
                }
                if match.isCancelled, seriesAdopted {
                    decisions.append(.update(blockID: match.id, occurrence: occurrence))
                    continue
                }
                decisions.append(.update(blockID: match.id, occurrence: occurrence))
                continue
            }

            if seriesAdopted {
                decisions.append(.insert(occurrence: occurrence, scope: .series))
            }
        }

        for block in existing where block.source == .calendar && !block.isCancelled && !claimed.contains(block.id) {
            decisions.append(.cancel(blockID: block.id))
        }
        return decisions
    }

    private static func matchingBlock(for occurrence: CalendarOccurrence, in existing: [ExistingBlock]) -> ExistingBlock? {
        if let byOccurrence = existing.first(where: { block in
            block.calendarEventIdentifier == occurrence.eventIdentifier
                && occurrenceKeyMatches(block.occurrenceStartKey, occurrence.startsAt)
        }) {
            return byOccurrence
        }
        return existing.first { block in
            block.calendarEventIdentifier == occurrence.eventIdentifier
                && block.occurrenceStartKey == nil
        }
    }

    private static func occurrenceKeyMatches(_ stored: Date?, _ start: Date) -> Bool {
        guard let stored else { return false }
        return abs(stored.timeIntervalSince(start)) < 1
    }
}
