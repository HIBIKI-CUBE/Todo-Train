//
//  TimetableAdoption.swift
//  Todo train
//
//  EventKit 発生 + 系列ルール → ダイヤの insert / update / cancel。
//  終日・辞退は対象外。手動枠はカレンダーが空でも消さない。
//

import Foundation

nonisolated struct CalendarOccurrence: Equatable, Sendable, Identifiable {
    var eventIdentifier: String
    var recurrenceIdentifier: String?
    var title: String
    var startsAt: Date
    var endsAt: Date
    var isAllDay: Bool
    var isDeclined: Bool
    var calendarIdentifier: String
    var calendarTitle: String

    init(
        eventIdentifier: String,
        recurrenceIdentifier: String? = nil,
        title: String,
        startsAt: Date,
        endsAt: Date,
        isAllDay: Bool,
        isDeclined: Bool,
        calendarIdentifier: String = "",
        calendarTitle: String = ""
    ) {
        self.eventIdentifier = eventIdentifier
        self.recurrenceIdentifier = recurrenceIdentifier
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.isAllDay = isAllDay
        self.isDeclined = isDeclined
        self.calendarIdentifier = calendarIdentifier
        self.calendarTitle = calendarTitle
    }

    var id: String {
        if let recurrenceIdentifier {
            return "\(eventIdentifier)|\(recurrenceIdentifier)|\(startsAt.timeIntervalSince1970)"
        }
        return "\(eventIdentifier)|\(startsAt.timeIntervalSince1970)"
    }

    var occurrenceStartKey: Double { startsAt.timeIntervalSince1970 }
}

nonisolated struct TimetableBlockRecord: Equatable, Sendable, Identifiable {
    var id: UUID
    var title: String
    var startsAt: Date
    var endsAt: Date
    var source: TimetableSource
    var adoptionScope: TimetableAdoptionScope
    var isCancelled: Bool
    var needsReview: Bool
    var calendarEventIdentifier: String?
    var calendarRecurrenceIdentifier: String?
    var occurrenceStartKey: Double?

    var isActive: Bool { !isCancelled }

    static func occurrenceKey(eventIdentifier: String, start: Date) -> String {
        "\(eventIdentifier)|\(start.timeIntervalSince1970)"
    }
}

nonisolated struct TimetableSeriesRecord: Equatable, Sendable, Identifiable {
    var id: UUID
    var recurrenceIdentifier: String
    var title: String
    var adopted: Bool
    var excludedOccurrenceStarts: [Double]

    func excludes(start: Date) -> Bool {
        let key = start.timeIntervalSince1970
        return excludedOccurrenceStarts.contains { abs($0 - key) < 0.5 }
    }
}

nonisolated struct TimetableMembership: Equatable, Sendable {
    var blocks: [TimetableBlockRecord]
    var rules: [TimetableSeriesRecord]
}

nonisolated enum TimetableAdoption {
    static func isEligible(_ occurrence: CalendarOccurrence) -> Bool {
        !occurrence.isAllDay
            && !occurrence.isDeclined
            && occurrence.endsAt > occurrence.startsAt
    }

    static func isAdopted(
        occurrence: CalendarOccurrence,
        membership: TimetableMembership
    ) -> Bool {
        if let block = matchingBlock(occurrence: occurrence, in: membership.blocks), block.isActive {
            return true
        }
        guard let recurrence = occurrence.recurrenceIdentifier,
              let rule = membership.rules.first(where: { $0.recurrenceIdentifier == recurrence }),
              rule.adopted,
              !rule.excludes(start: occurrence.startsAt)
        else {
            return false
        }
        return true
    }

    static func refreshCalendarMembership(
        occurrences: [CalendarOccurrence],
        membership: TimetableMembership
    ) -> TimetableMembership {
        var blocks = membership.blocks
        let rules = membership.rules
        let eligible = occurrences.filter(isEligible)

        for occurrence in eligible {
            let shouldInsert = shouldKeepCalendarBlock(occurrence: occurrence, rules: rules, blocks: blocks)
            if shouldInsert {
                upsertCalendarBlock(occurrence: occurrence, into: &blocks, rules: rules)
            }
        }

        for index in blocks.indices where blocks[index].source == .calendar && blocks[index].isActive {
            let block = blocks[index]
            let stillPresent = eligible.contains { matches(occurrence: $0, block: block) }
            if !stillPresent {
                blocks[index].isCancelled = true
                continue
            }
            if let occurrence = eligible.first(where: { matches(occurrence: $0, block: block) }),
               !shouldKeepCalendarBlock(occurrence: occurrence, rules: rules, blocks: blocks) {
                blocks[index].isCancelled = true
            }
        }

        return TimetableMembership(blocks: blocks, rules: rules)
    }

    static func adoptOccurrence(
        _ occurrence: CalendarOccurrence,
        scope: TimetableAdoptionScope,
        membership: TimetableMembership
    ) -> TimetableMembership {
        guard isEligible(occurrence) else { return membership }
        var blocks = membership.blocks
        var rules = membership.rules

        switch scope {
        case .occurrence:
            upsertCalendarBlock(occurrence: occurrence, into: &blocks, rules: rules, forceScope: .occurrence)
            if let recurrence = occurrence.recurrenceIdentifier,
               let index = rules.firstIndex(where: { $0.recurrenceIdentifier == recurrence }) {
                rules[index].excludedOccurrenceStarts.removeAll {
                    abs($0 - occurrence.occurrenceStartKey) < 0.5
                }
            }
        case .series:
            guard let recurrence = occurrence.recurrenceIdentifier else {
                upsertCalendarBlock(occurrence: occurrence, into: &blocks, rules: rules, forceScope: .occurrence)
                return TimetableMembership(blocks: blocks, rules: rules)
            }
            if let index = rules.firstIndex(where: { $0.recurrenceIdentifier == recurrence }) {
                rules[index].adopted = true
                rules[index].title = occurrence.title
                rules[index].excludedOccurrenceStarts.removeAll {
                    abs($0 - occurrence.occurrenceStartKey) < 0.5
                }
            } else {
                rules.append(
                    TimetableSeriesRecord(
                        id: UUID(),
                        recurrenceIdentifier: recurrence,
                        title: occurrence.title,
                        adopted: true,
                        excludedOccurrenceStarts: []
                    )
                )
            }
            upsertCalendarBlock(occurrence: occurrence, into: &blocks, rules: rules, forceScope: .series)
        }

        return TimetableMembership(blocks: blocks, rules: rules)
    }

    static func unadopt(
        blockID: UUID,
        scope: TimetableAdoptionScope,
        membership: TimetableMembership
    ) -> TimetableMembership {
        var blocks = membership.blocks
        var rules = membership.rules
        guard let index = blocks.firstIndex(where: { $0.id == blockID }) else {
            return membership
        }
        let block = blocks[index]

        switch scope {
        case .occurrence:
            blocks[index].isCancelled = true
            if let recurrence = block.calendarRecurrenceIdentifier,
               let ruleIndex = rules.firstIndex(where: { $0.recurrenceIdentifier == recurrence }),
               rules[ruleIndex].adopted {
                let key = block.occurrenceStartKey ?? block.startsAt.timeIntervalSince1970
                if !rules[ruleIndex].excludedOccurrenceStarts.contains(where: { abs($0 - key) < 0.5 }) {
                    rules[ruleIndex].excludedOccurrenceStarts.append(key)
                }
            }
        case .series:
            blocks[index].isCancelled = true
            if let recurrence = block.calendarRecurrenceIdentifier {
                if let ruleIndex = rules.firstIndex(where: { $0.recurrenceIdentifier == recurrence }) {
                    rules[ruleIndex].adopted = false
                    rules[ruleIndex].excludedOccurrenceStarts = []
                }
                for i in blocks.indices where blocks[i].calendarRecurrenceIdentifier == recurrence {
                    blocks[i].isCancelled = true
                }
            }
        }

        return TimetableMembership(blocks: blocks, rules: rules)
    }

    static func unadoptOccurrence(
        _ occurrence: CalendarOccurrence,
        scope: TimetableAdoptionScope,
        membership: TimetableMembership
    ) -> TimetableMembership {
        if let block = matchingBlock(occurrence: occurrence, in: membership.blocks) {
            return unadopt(blockID: block.id, scope: scope, membership: membership)
        }
        guard scope == .series, let recurrence = occurrence.recurrenceIdentifier else {
            return membership
        }
        var rules = membership.rules
        var blocks = membership.blocks
        if let ruleIndex = rules.firstIndex(where: { $0.recurrenceIdentifier == recurrence }) {
            rules[ruleIndex].adopted = false
            rules[ruleIndex].excludedOccurrenceStarts = []
        }
        for i in blocks.indices where blocks[i].calendarRecurrenceIdentifier == recurrence {
            blocks[i].isCancelled = true
        }
        return TimetableMembership(blocks: blocks, rules: rules)
    }

    static func adoptManual(
        title: String,
        startsAt: Date,
        endsAt: Date,
        membership: TimetableMembership
    ) -> TimetableMembership {
        guard endsAt > startsAt else { return membership }
        var blocks = membership.blocks
        blocks.append(
            TimetableBlockRecord(
                id: UUID(),
                title: title,
                startsAt: startsAt,
                endsAt: endsAt,
                source: .manual,
                adoptionScope: .occurrence,
                isCancelled: false,
                needsReview: false,
                calendarEventIdentifier: nil,
                calendarRecurrenceIdentifier: nil,
                occurrenceStartKey: startsAt.timeIntervalSince1970
            )
        )
        return TimetableMembership(blocks: blocks, rules: membership.rules)
    }

    static func matchingBlock(
        occurrence: CalendarOccurrence,
        in blocks: [TimetableBlockRecord]
    ) -> TimetableBlockRecord? {
        blocks.first { matches(occurrence: occurrence, block: $0) }
    }

    private static func shouldKeepCalendarBlock(
        occurrence: CalendarOccurrence,
        rules: [TimetableSeriesRecord],
        blocks: [TimetableBlockRecord]
    ) -> Bool {
        if let block = matchingBlock(occurrence: occurrence, in: blocks), block.isActive {
            return true
        }
        guard let recurrence = occurrence.recurrenceIdentifier,
              let rule = rules.first(where: { $0.recurrenceIdentifier == recurrence }),
              rule.adopted
        else {
            return false
        }
        return !rule.excludes(start: occurrence.startsAt)
    }

    private static func matches(occurrence: CalendarOccurrence, block: TimetableBlockRecord) -> Bool {
        guard block.source == .calendar else { return false }
        guard block.calendarEventIdentifier == occurrence.eventIdentifier else { return false }
        if occurrence.recurrenceIdentifier == nil, block.calendarRecurrenceIdentifier == nil {
            return true
        }
        let key = block.occurrenceStartKey ?? block.startsAt.timeIntervalSince1970
        return abs(key - occurrence.occurrenceStartKey) < 0.5
    }

    private static func upsertCalendarBlock(
        occurrence: CalendarOccurrence,
        into blocks: inout [TimetableBlockRecord],
        rules: [TimetableSeriesRecord],
        forceScope: TimetableAdoptionScope? = nil
    ) {
        let scope = forceScope ?? inferredScope(occurrence: occurrence, rules: rules)
        if let index = blocks.firstIndex(where: { matches(occurrence: occurrence, block: $0) }) {
            let previous = blocks[index]
            let changed = previous.title != occurrence.title
                || previous.startsAt != occurrence.startsAt
                || previous.endsAt != occurrence.endsAt
            blocks[index].title = occurrence.title
            blocks[index].startsAt = occurrence.startsAt
            blocks[index].endsAt = occurrence.endsAt
            blocks[index].occurrenceStartKey = occurrence.occurrenceStartKey
            blocks[index].isCancelled = false
            blocks[index].adoptionScope = scope
            blocks[index].calendarRecurrenceIdentifier = occurrence.recurrenceIdentifier
            if changed {
                blocks[index].needsReview = true
            }
            return
        }
        blocks.append(
            TimetableBlockRecord(
                id: UUID(),
                title: occurrence.title,
                startsAt: occurrence.startsAt,
                endsAt: occurrence.endsAt,
                source: .calendar,
                adoptionScope: scope,
                isCancelled: false,
                needsReview: false,
                calendarEventIdentifier: occurrence.eventIdentifier,
                calendarRecurrenceIdentifier: occurrence.recurrenceIdentifier,
                occurrenceStartKey: occurrence.occurrenceStartKey
            )
        )
    }

    private static func inferredScope(
        occurrence: CalendarOccurrence,
        rules: [TimetableSeriesRecord]
    ) -> TimetableAdoptionScope {
        guard let recurrence = occurrence.recurrenceIdentifier,
              let rule = rules.first(where: { $0.recurrenceIdentifier == recurrence }),
              rule.adopted
        else {
            return .occurrence
        }
        return .series
    }
}
