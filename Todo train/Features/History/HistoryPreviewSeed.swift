//
//  HistoryPreviewSeed.swift
//  Todo train
//

import Foundation
import SwiftData

enum HistoryPreviewSeed {
    static func insertSampleDay(into context: ModelContext, calendar: Calendar = .current) {
        let base = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 9))
            ?? Date(timeIntervalSince1970: 1_778_284_800)

        let report = Ticket(title: "報告書", estimatedSeconds: 45 * 60, sortOrder: 0)
        let mail = Ticket(title: "メール", estimatedSeconds: 20 * 60, sortOrder: 1)
        context.insert(report)
        context.insert(mail)

        let first = WorkSession(startedAt: base, estimatedSecondsAtStart: 45 * 60, ticket: report)
        first.endedAt = base.addingTimeInterval(90 * 60)
        first.accumulatedActiveSeconds = 50 * 60
        first.budgetSecondsAtStart = 55 * 60
        first.outcome = .arrived
        context.insert(first)
        context.insert(
            SessionExtension(
                addedSeconds: 10 * 60,
                reason: "割り込みが入った",
                createdAt: base.addingTimeInterval(40 * 60),
                session: first
            )
        )
        context.insert(
            SessionPause(
                startedAt: base.addingTimeInterval(50 * 60),
                endedAt: base.addingTimeInterval(70 * 60),
                session: first
            )
        )

        let secondStart = base.addingTimeInterval(3 * 3600)
        let second = WorkSession(
            startedAt: secondStart,
            estimatedSecondsAtStart: 20 * 60,
            ticket: mail
        )
        second.endedAt = secondStart.addingTimeInterval(25 * 60)
        second.accumulatedActiveSeconds = 25 * 60
        second.outcome = .arrived
        context.insert(second)

        report.closedAt = first.endedAt
        report.closureKind = .arrived
        mail.closedAt = second.endedAt
        mail.closureKind = .arrived
        try? context.save()
    }
}
