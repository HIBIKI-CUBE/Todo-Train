//
//  FocusUIPreview+TicketBundle.swift
//  Todo train
//

import Foundation
import SwiftData
import TodoTrainSync

#if DEBUG
extension FocusUIPreview {
    @MainActor
    static func configureTicketBundlePreview(
        manager: SessionManager,
        context: ModelContext,
        state: String
    ) throws {
        let calendar = manager.calendar
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 9)) ?? manager.clock.now
        let dayKey = ServiceDay.dayKey(for: base, calendar: calendar)

        if state == "historyEmptyBundle" {
            let empty = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 9))!
            let day = ServiceDay(startedAt: empty, calendarDayKey: ServiceDay.dayKey(for: empty, calendar: calendar))
            context.insert(day)
            try context.save()
            manager.activeServiceDay = day
            manager.uiPreviewSelectHistoryTab = true
            manager.uiPreviewSuppressMotion = true
            return
        }

        let serviceDay = ServiceDay(startedAt: base, calendarDayKey: dayKey)
        context.insert(serviceDay)
        manager.activeServiceDay = serviceDay

        func insertStamped(
            title: String,
            estimate: Int,
            active: TimeInterval,
            offset: TimeInterval,
            reestimate: ReestimateEventRecord? = nil
        ) {
            let ticket = Ticket(title: title, estimatedSeconds: estimate, sortOrder: Int(offset))
            context.insert(ticket)
            let start = base.addingTimeInterval(offset)
            let end = start.addingTimeInterval(active)
            let session = WorkSession(startedAt: start, estimatedSecondsAtStart: estimate, ticket: ticket)
            session.endedAt = end
            session.accumulatedActiveSeconds = active
            session.outcome = .arrived
            session.arrivalStampedAt = end
            session.arrivalAction = .nextRide
            if let reestimate {
                session.reestimateEvents = [reestimate]
            }
            context.insert(session)
            ticket.closedAt = end
            ticket.closureKind = .arrived
        }

        insertStamped(title: "発券定時", estimate: 30 * 60, active: 30 * 60, offset: 0)
        insertStamped(
            title: "前半の見積もり直しを長くした切符",
            estimate: 30 * 60,
            active: 50 * 60,
            offset: 3600,
            reestimate: ReestimateEventRecord(
                reestimateIndex: 1,
                trigger: .manual,
                surface: .iphonePortrait,
                input: .touch,
                promptId: ReestimatePromptID.remainingV1,
                mode: .minutesOnly,
                committedAt: base.addingTimeInterval(3700),
                activeSeconds: 10 * 60,
                overrunSeconds: 0,
                progressAnswer: nil,
                committedRemainingSeconds: 40 * 60,
                shownBandLowSeconds: nil,
                shownBandHighSeconds: nil,
                detailsOpened: false,
                undoneAt: nil,
                remoteWillExtendReceived: false
            )
        )
        insertStamped(
            title: "後半見積もり直し",
            estimate: 30 * 60,
            active: 40 * 60,
            offset: 7200,
            reestimate: ReestimateEventRecord(
                reestimateIndex: 1,
                trigger: .manual,
                surface: .iphonePortrait,
                input: .touch,
                promptId: ReestimatePromptID.remainingV1,
                mode: .minutesOnly,
                committedAt: base.addingTimeInterval(7300),
                activeSeconds: 25 * 60,
                overrunSeconds: 0,
                progressAnswer: nil,
                committedRemainingSeconds: 15 * 60,
                shownBandLowSeconds: nil,
                shownBandHighSeconds: nil,
                detailsOpened: false,
                undoneAt: nil,
                remoteWillExtendReceived: false
            )
        )
        insertStamped(title: "早着", estimate: 30 * 60, active: 5 * 60, offset: 10_800)
        insertStamped(title: "到着", estimate: 30 * 60, active: 50 * 60, offset: 14_400)

        let partial = WorkSession(
            startedAt: base.addingTimeInterval(18_000),
            estimatedSecondsAtStart: 20 * 60,
            ticket: Ticket(title: "途中下車", estimatedSeconds: 20 * 60, sortOrder: 99)
        )
        context.insert(partial.ticket!)
        partial.endedAt = partial.startedAt.addingTimeInterval(600)
        partial.outcome = .partialDisembark
        context.insert(partial)

        let unstamped = WorkSession(
            startedAt: base.addingTimeInterval(19_000),
            estimatedSecondsAtStart: 15 * 60,
            ticket: Ticket(title: "印なし", estimatedSeconds: 15 * 60, sortOrder: 100)
        )
        context.insert(unstamped.ticket!)
        unstamped.endedAt = unstamped.startedAt.addingTimeInterval(900)
        unstamped.outcome = .arrived
        context.insert(unstamped)

        try context.save()
        manager.activeSession = nil
        manager.phase = .idle
        manager.uiPreviewSuppressMotion = true
        manager.uiPreviewBundleViewerFlatIndex = nil

        switch state {
        case "shutdownBundle", "shutdownBundleLandscape":
            manager.uiPreviewShowsServiceShutdown = true
            manager.uiPreviewBundleFocusIndex = .max
        case "shutdownBundlePeel", "shutdownBundlePeelLandscape":
            manager.uiPreviewShowsServiceShutdown = true
            manager.uiPreviewBundleFocusIndex = 1
        case "historyBundle", "historyBundleLandscape":
            manager.uiPreviewSelectHistoryTab = true
        case "historyBundleViewer", "historyBundleViewerLandscape":
            manager.uiPreviewSelectHistoryTab = true
            manager.uiPreviewShowsBundleViewer = true
            manager.uiPreviewBundleViewerDayKey = dayKey
            manager.uiPreviewBundleViewerFlatIndex = .max
        case "historyBundleViewerBoundary", "historyBundleViewerBoundaryLandscape":
            insertPriorDayBundle(context: context, calendar: calendar)
            try context.save()
            manager.uiPreviewSelectHistoryTab = true
            manager.uiPreviewShowsBundleViewer = true
            manager.uiPreviewBundleViewerDayKey = dayKey
            manager.uiPreviewBundleViewerFlatIndex = 0
        default:
            break
        }
    }

    @MainActor
    private static func insertPriorDayBundle(context: ModelContext, calendar: Calendar) {
        let prior = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 9))
            ?? Date()
        let key = ServiceDay.dayKey(for: prior, calendar: calendar)
        let day = ServiceDay(startedAt: prior, calendarDayKey: key)
        context.insert(day)
        let ticket = Ticket(title: "前日の切符", estimatedSeconds: 20 * 60, sortOrder: 0)
        context.insert(ticket)
        let start = prior.addingTimeInterval(3600)
        let session = WorkSession(startedAt: start, estimatedSecondsAtStart: 20 * 60, ticket: ticket)
        session.endedAt = start.addingTimeInterval(20 * 60)
        session.accumulatedActiveSeconds = 20 * 60
        session.outcome = .arrived
        session.arrivalStampedAt = session.endedAt
        session.arrivalAction = .nextRide
        context.insert(session)
        ticket.closedAt = session.endedAt
        ticket.closureKind = .arrived
    }
}
#endif
