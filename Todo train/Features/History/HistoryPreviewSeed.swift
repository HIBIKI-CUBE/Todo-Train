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

    /// Several days around the sample Tuesday, for the calendar week strip.
    static func insertSampleWeek(into context: ModelContext, calendar: Calendar = .current) {
        insertSampleDay(into: context, calendar: calendar)

        let tuesday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 9))
            ?? Date(timeIntervalSince1970: 1_778_284_800)

        let interrupt = Ticket(title: "割り込み確認", estimatedSeconds: 25 * 60, sortOrder: 2)
        context.insert(interrupt)
        let interruptStart = tuesday.addingTimeInterval(40 * 60)
        let interruptRide = WorkSession(
            startedAt: interruptStart,
            estimatedSecondsAtStart: 25 * 60,
            ticket: interrupt
        )
        interruptRide.endedAt = interruptStart.addingTimeInterval(25 * 60)
        interruptRide.accumulatedActiveSeconds = 25 * 60
        interruptRide.outcome = .arrived
        context.insert(interruptRide)
        interrupt.closedAt = interruptRide.endedAt
        interrupt.closureKind = .arrived

        let wednesday = calendar.date(byAdding: .day, value: 1, to: tuesday) ?? tuesday.addingTimeInterval(86_400)
        let short = Ticket(title: "短い確認", estimatedSeconds: 15 * 60, sortOrder: 3)
        context.insert(short)
        let shortRide = WorkSession(
            startedAt: wednesday.addingTimeInterval(60 * 60),
            estimatedSecondsAtStart: 15 * 60,
            ticket: short
        )
        shortRide.endedAt = wednesday.addingTimeInterval(75 * 60)
        shortRide.accumulatedActiveSeconds = 15 * 60
        shortRide.outcome = .arrived
        context.insert(shortRide)
        short.closedAt = shortRide.endedAt
        short.closureKind = .arrived

        let memo = Ticket(title: "週次メモ", estimatedSeconds: 45 * 60, sortOrder: 4)
        context.insert(memo)
        let memoStart = wednesday.addingTimeInterval(6 * 3600)
        let memoRide = WorkSession(
            startedAt: memoStart,
            estimatedSecondsAtStart: 45 * 60,
            ticket: memo
        )
        memoRide.endedAt = memoStart.addingTimeInterval(40 * 60)
        memoRide.accumulatedActiveSeconds = 40 * 60
        memoRide.outcome = .arrived
        context.insert(memoRide)
        memo.closedAt = memoRide.endedAt
        memo.closureKind = .arrived

        let friday = calendar.date(byAdding: .day, value: 3, to: tuesday) ?? tuesday.addingTimeInterval(3 * 86_400)
        let standup = Ticket(title: "朝の確認", estimatedSeconds: 20 * 60, sortOrder: 5)
        context.insert(standup)
        let standupStart = friday.addingTimeInterval(30 * 60)
        let standupRide = WorkSession(
            startedAt: standupStart,
            estimatedSecondsAtStart: 20 * 60,
            ticket: standup
        )
        standupRide.endedAt = standupStart.addingTimeInterval(25 * 60)
        standupRide.accumulatedActiveSeconds = 25 * 60
        standupRide.outcome = .arrived
        context.insert(standupRide)
        standup.closedAt = standupRide.endedAt
        standup.closureKind = .arrived

        let review = Ticket(title: "設計レビュー", estimatedSeconds: 45 * 60, sortOrder: 6)
        let leftover = Ticket(title: "残りデザイン", estimatedSeconds: 30 * 60, sortOrder: 7)
        context.insert(review)
        context.insert(leftover)
        let reviewStart = friday.addingTimeInterval(4 * 3600)
        let reviewRide = WorkSession(
            startedAt: reviewStart,
            estimatedSecondsAtStart: 45 * 60,
            ticket: review
        )
        reviewRide.endedAt = reviewStart.addingTimeInterval(45 * 60)
        reviewRide.accumulatedActiveSeconds = 40 * 60
        reviewRide.outcome = .partialDisembark
        context.insert(reviewRide)
        review.closedAt = reviewRide.endedAt
        review.closureKind = .partialDisembark
        leftover.createdAt = reviewRide.endedAt ?? friday
        context.insert(
            TaskLineage(
                kind: .continuation,
                parent: review,
                child: leftover,
                createdAt: reviewRide.endedAt ?? friday,
                fromSessionID: reviewRide.id
            )
        )

        try? context.save()
    }
}
