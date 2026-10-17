//
//  AppModelContainerMigrationTests.swift
//  Todo trainTests
//

import CoreData
import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct AppModelContainerMigrationTests {
    @Test func inMemory_canInsertTimetableModels() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let starts = Date(timeIntervalSince1970: 1_700_000_000)
        let block = TimetableBlock(
            title: "1on1",
            startsAt: starts,
            endsAt: starts.addingTimeInterval(1800),
            source: .manual
        )
        container.mainContext.insert(block)
        container.mainContext.insert(
            TimetableGuard(
                sessionID: UUID(),
                blockID: block.id,
                notifiedAt: starts,
                protectionBoundary: starts.addingTimeInterval(120)
            )
        )
        try container.mainContext.save()
        container.mainContext.insert(
            PassengerRide(
                intervalId: block.id.uuidString,
                title: "1on1",
                intervalStart: starts,
                intervalEnd: starts.addingTimeInterval(1800),
                boardedAt: starts,
                source: .manualInterval
            )
        )
        try container.mainContext.save()
        #expect(try container.mainContext.fetch(FetchDescriptor<TimetableBlock>()).count == 1)
        #expect(try container.mainContext.fetch(FetchDescriptor<TimetableGuard>()).count == 1)
        #expect(try container.mainContext.fetch(FetchDescriptor<PassengerRide>()).count == 1)
    }

    @Test func make_migratesUnversionedStoreWithoutLosingTickets() throws {
        let url = Self.temporaryStoreURL()
        defer { Self.removeStoreFiles(at: url) }
        AppModelContainer.rebuildCount = 0

        try autoreleasepool {
            let v1Schema = Schema(versionedSchema: AppSchemaV1.self)
            let v1Container = try ModelContainer(
                for: v1Schema,
                configurations: [ModelConfiguration(schema: v1Schema, url: url)]
            )
            let ticket = AppSchemaV3.Ticket(title: "残す切符", estimatedSeconds: 900, sortOrder: 3)
            v1Container.mainContext.insert(ticket)
            let session = AppSchemaV3.WorkSession(
                startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                estimatedSecondsAtStart: 900,
                ticket: ticket
            )
            session.endedAt = Date(timeIntervalSince1970: 1_700_000_600)
            v1Container.mainContext.insert(session)
            try v1Container.mainContext.save()
        }

        let created = try Self.creationDate(of: url)
        let migrated = try AppModelContainer.make(storeURL: url)
        #expect(AppModelContainer.rebuildCount == 0)
        #expect(try Self.creationDate(of: url) == created)
        let tickets = try migrated.mainContext.fetch(FetchDescriptor<Ticket>())
        let sessions = try migrated.mainContext.fetch(FetchDescriptor<WorkSession>())
        #expect(tickets.map(\.title) == ["残す切符"])
        #expect(tickets.first?.estimatedSeconds == 900)
        #expect(sessions.count == 1)
        #expect(sessions.first?.ticket?.title == "残す切符")
        try Self.expectNewColumnsAtDefaults(in: migrated.mainContext)

        let starts = Date(timeIntervalSince1970: 1_700_001_000)
        migrated.mainContext.insert(
            TimetableBlock(
                title: "レビュー",
                startsAt: starts,
                endsAt: starts.addingTimeInterval(3600),
                source: .calendar
            )
        )
        try migrated.mainContext.save()
        #expect(try migrated.mainContext.fetch(FetchDescriptor<TimetableBlock>()).count == 1)
    }

    @Test func make_migratesFrozenV3WithoutRebuild() throws {
        let url = Self.temporaryStoreURL()
        defer { Self.removeStoreFiles(at: url) }
        let seeded = try Self.seed(
            .v3,
            at: url,
            schema: Schema(versionedSchema: AppSchemaV3.self)
        )
        AppModelContainer.rebuildCount = 0
        let created = try Self.creationDate(of: url)
        let migrated = try AppModelContainer.make(storeURL: url)
        #expect(AppModelContainer.rebuildCount == 0)
        #expect(try Self.creationDate(of: url) == created)
        try Self.expectPreserved(seeded, in: migrated.mainContext, keepsReservation: false)
        try Self.expectNewColumnsAtDefaults(in: migrated.mainContext)
    }

    @Test func make_migratesFrozenV3_1WithoutRebuild() throws {
        let url = Self.temporaryStoreURL()
        defer { Self.removeStoreFiles(at: url) }
        let seeded = try Self.seed(
            .v3_1,
            at: url,
            schema: Schema(versionedSchema: AppSchemaV3_1.self)
        )
        AppModelContainer.rebuildCount = 0
        let created = try Self.creationDate(of: url)
        let migrated = try AppModelContainer.make(storeURL: url)
        #expect(AppModelContainer.rebuildCount == 0)
        #expect(try Self.creationDate(of: url) == created)
        try Self.expectPreserved(seeded, in: migrated.mainContext, keepsReservation: true)
        try Self.expectNewColumnsAtDefaults(in: migrated.mainContext)
    }

    /// PR #71 以後のビルドは版識別子 3.0.0 のまま V3_1 の列を書いた。
    @Test func make_migratesPostPR71StoreLabeledAsV3() throws {
        let url = Self.temporaryStoreURL()
        defer { Self.removeStoreFiles(at: url) }
        let seeded = try Self.seed(
            .v3_1,
            at: url,
            schema: Schema(versionedSchema: PostPR71LabeledV3.self)
        )
        AppModelContainer.rebuildCount = 0
        let migrated = try AppModelContainer.make(storeURL: url)
        #expect(AppModelContainer.rebuildCount == 0)
        try Self.expectPreserved(seeded, in: migrated.mainContext, keepsReservation: true)
        try Self.expectNewColumnsAtDefaults(in: migrated.mainContext)
    }

    @Test func make_migratesV5PauseReadingsWithoutRebuild() throws {
        let url = Self.temporaryStoreURL()
        defer { Self.removeStoreFiles(at: url) }
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        try autoreleasepool {
            let schema = Schema(versionedSchema: AppSchemaV5.self)
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: url)]
            )
            let ticket = AppSchemaV5.Ticket(title: "残す切符", estimatedSeconds: 1_200, sortOrder: 1)
            container.mainContext.insert(ticket)
            let session = AppSchemaV5.WorkSession(
                startedAt: started,
                estimatedSecondsAtStart: 1_200,
                ticket: ticket
            )
            session.accumulatedActiveSeconds = 1_000
            session.endedAt = started.addingTimeInterval(1_000)
            session.outcomeRaw = "arrived"
            session.timetableHeld = false
            container.mainContext.insert(session)
            let pause = AppSchemaV5.SessionPause(
                startedAt: started.addingTimeInterval(100),
                endedAt: started.addingTimeInterval(500),
                session: session
            )
            pause.heldByRaw = "timetable"
            pause.pausedOnRaw = "iphone"
            pause.heldByInferred = false
            pause.macSampledSeconds = 300
            pause.macActiveSeconds = 240
            container.mainContext.insert(pause)
            try container.mainContext.save()
        }
        AppModelContainer.rebuildCount = 0
        let migrated = try AppModelContainer.make(storeURL: url)
        #expect(AppModelContainer.rebuildCount == 0)
        let session = try #require(try migrated.mainContext.fetch(FetchDescriptor<WorkSession>()).first)
        #expect(session.ticket?.title == "残す切符")
        #expect(session.accumulatedActiveSeconds == 1_000)
        #expect(session.nudgeEventsJSON == "[]")
        #expect(session.timetableHeld == false)
        let pause = try #require(session.pauses.first)
        #expect(pause.heldByRaw == "timetable")
        #expect(pause.macSampledSeconds == 300)
        #expect(pause.macActiveSeconds == 240)
        #expect(pause.pausedOnRaw == "iphone")
    }

    @Test func make_migratesV6WithoutRebuild() throws {
        let url = Self.temporaryStoreURL()
        defer { Self.removeStoreFiles(at: url) }
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let endedTicketID = UUID()
        let runningTicketID = UUID()
        let endedSessionID = UUID()
        let runningSessionID = UUID()
        let guardSessionID = endedSessionID
        let dayKey = "2026-10-11"
        try autoreleasepool {
            let schema = Schema(versionedSchema: AppSchemaV6.self)
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: url)]
            )
            let context = container.mainContext
            let tag = AppSchemaV6.Tag(name: "青", colorHex: "#2255AA", sortOrder: 1)
            context.insert(tag)

            let endedTicket = AppSchemaV6.Ticket(
                id: endedTicketID,
                title: "終わった切符",
                estimatedSeconds: 1_200,
                sortOrder: 1
            )
            endedTicket.tags = [tag]
            context.insert(endedTicket)

            let child = AppSchemaV6.Ticket(title: "乗り継ぎ先", estimatedSeconds: 600, sortOrder: 2)
            context.insert(child)
            context.insert(
                AppSchemaV6.TaskLineage(
                    kindRaw: LineageKind.continuation.rawValue,
                    parent: endedTicket,
                    child: child,
                    createdAt: started.addingTimeInterval(600)
                )
            )

            let runningTicket = AppSchemaV6.Ticket(
                id: runningTicketID,
                title: "走行中",
                estimatedSeconds: 900,
                sortOrder: 3
            )
            context.insert(runningTicket)

            let day = ServiceDay(startedAt: started, calendarDayKey: dayKey)
            context.insert(day)

            let ended = AppSchemaV6.WorkSession(
                id: endedSessionID,
                startedAt: started,
                estimatedSecondsAtStart: 1_200,
                ticket: endedTicket
            )
            ended.endedAt = started.addingTimeInterval(1_000)
            ended.outcomeRaw = SessionOutcome.arrived.rawValue
            ended.budgetSecondsAtStart = 1_500
            ended.accumulatedActiveSeconds = 1_000
            ended.nudgeEventsJSON = "[{\"stage\":\"checkIn\"}]"
            context.insert(ended)
            context.insert(
                AppSchemaV6.SessionExtension(
                    addedSeconds: 300,
                    reason: "延長",
                    createdAt: started.addingTimeInterval(200),
                    workingSeconds: 200,
                    session: ended
                )
            )
            let endedPause = AppSchemaV6.SessionPause(
                startedAt: started.addingTimeInterval(100),
                endedAt: started.addingTimeInterval(200),
                session: ended
            )
            endedPause.heldByRaw = "timetable"
            context.insert(endedPause)

            let running = AppSchemaV6.WorkSession(
                id: runningSessionID,
                startedAt: started.addingTimeInterval(1_200),
                estimatedSecondsAtStart: 900,
                ticket: runningTicket
            )
            running.budgetSecondsAtStart = 1_200
            running.accumulatedActiveSeconds = 300
            context.insert(running)
            context.insert(
                AppSchemaV6.SessionExtension(
                    addedSeconds: 300,
                    reason: "割り込み",
                    createdAt: started.addingTimeInterval(1_400),
                    workingSeconds: 150,
                    session: running
                )
            )

            let blockStart = started.addingTimeInterval(3_600)
            let block = TimetableBlock(
                title: "1on1",
                startsAt: blockStart,
                endsAt: blockStart.addingTimeInterval(1_800),
                source: .manual
            )
            context.insert(block)
            context.insert(
                TimetableGuard(
                    sessionID: guardSessionID,
                    blockID: block.id,
                    notifiedAt: started,
                    protectionBoundary: blockStart.addingTimeInterval(120)
                )
            )
            context.insert(
                TimetableSeriesRule(
                    recurrenceIdentifier: "series-v6",
                    title: "毎週",
                    adopted: true
                )
            )
            context.insert(
                PassengerRide(
                    intervalId: "interval-1",
                    title: "客",
                    intervalStart: blockStart,
                    intervalEnd: blockStart.addingTimeInterval(1_800),
                    boardedAt: blockStart,
                    source: .manualInterval
                )
            )
            try context.save()
        }
        AppModelContainer.rebuildCount = 0
        let created = try Self.creationDate(of: url)
        let migrated = try AppModelContainer.make(storeURL: url)
        #expect(AppModelContainer.rebuildCount == 0)
        #expect(try Self.creationDate(of: url) == created)

        #expect(try migrated.mainContext.fetch(FetchDescriptor<Ticket>()).count == 3)
        #expect(try migrated.mainContext.fetch(FetchDescriptor<ServiceDay>()).count == 1)
        #expect(try migrated.mainContext.fetch(FetchDescriptor<TimetableBlock>()).count == 1)
        #expect(try migrated.mainContext.fetch(FetchDescriptor<TimetableGuard>()).count == 1)
        #expect(try migrated.mainContext.fetch(FetchDescriptor<TimetableSeriesRule>()).count == 1)
        #expect(try migrated.mainContext.fetch(FetchDescriptor<PassengerRide>()).count == 1)
        #expect(try migrated.mainContext.fetch(FetchDescriptor<Todo_train.Tag>()).count == 1)
        #expect(try migrated.mainContext.fetch(FetchDescriptor<TaskLineage>()).count == 1)
        #expect(try migrated.mainContext.fetch(FetchDescriptor<WorkSession>()).count == 2)

        let ended = try #require(
            try migrated.mainContext.fetch(FetchDescriptor<WorkSession>()).first { $0.id == endedSessionID }
        )
        let running = try #require(
            try migrated.mainContext.fetch(FetchDescriptor<WorkSession>()).first { $0.id == runningSessionID }
        )

        #expect(ended.ticket?.title == "終わった切符")
        #expect(ended.ticket?.tags.map(\.name) == ["青"])
        #expect(ended.endedAt != nil)
        #expect(ended.outcomeRaw == SessionOutcome.arrived.rawValue)
        #expect(ended.currentBudgetSeconds == 1_500)
        #expect(ended.budgetSecondsAtStart == 1_200)
        #expect(ended.estimatedSecondsAtStart == 1_200)
        #expect(ended.reestimateEventsJSON == "[]")
        #expect(ended.nudgeEventsJSON.contains("checkIn"))
        #expect(ended.extensions.count == 1)
        #expect(ended.extensions.first?.reason == "延長")
        #expect(ended.extensions.first?.workingSeconds == 200)
        #expect(ended.pauses.count == 1)
        #expect(ended.pauses.first?.heldByRaw == "timetable")
        #expect(ended.pauses.first?.undoneAt == nil)

        #expect(running.currentBudgetSeconds == 1_200)
        #expect(running.budgetSecondsAtStart == 900)
        #expect(running.estimatedSecondsAtStart == 900)
        #expect(running.extensions.first?.reason == "割り込み")
        #expect(running.extensions.first?.workingSeconds == 150)
    }

    @Test func frozenV3_1HashesMatchThePostPR71Store() throws {
        let url = Self.temporaryStoreURL()
        defer { Self.removeStoreFiles(at: url) }
        try autoreleasepool {
            let schema = Schema(versionedSchema: AppSchemaV3_1.self)
            _ = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: url)]
            )
        }
        let hashes = try Self.versionHashes(at: url)
        #expect(hashes == Self.postPR71Hashes)
    }

    @Test func rebuildPreservesTimetableAndPassengerRide() throws {
        let url = Self.temporaryStoreURL()
        defer { Self.removeStoreFiles(at: url) }
        let seeded = try Self.seed(
            .v3,
            at: url,
            schema: Schema(versionedSchema: AppSchemaV3.self)
        )
        AppModelContainer.rebuildCount = 0
        let rebuilt = try AppModelContainer.rebuildForTesting(at: url)
        #expect(AppModelContainer.rebuildCount == 1)
        try Self.expectPreserved(seeded, in: rebuilt.mainContext, keepsReservation: false)
    }

    private enum Era {
        case v3
        case v3_1
    }

    private struct Seeded: Equatable {
        var ticketTitle: String
        var estimatedSeconds: Int
        var sortOrder: Int
        var dueDate: Date
        var closedAt: Date?
        var closureKindRaw: String?
        var reservedAt: Date?
        var reservedFromRideId: UUID?
        var reservedViaRaw: String?
        var tagName: String
        var lineageKindRaw: String
        var dayKey: String
        var startedAt: Date
        var endedAt: Date
        var outcomeRaw: String
        var arrivalActionRaw: String?
        var arrivalStampedAt: Date?
        var startedFromRaw: String?
        var pauseStartedAt: Date
        var extensionSeconds: Int
        var blockTitle: String
        var guardBoundary: Date
        var seriesIdentifier: String
        var passengerTitle: String
    }

    private static func seed(_ era: Era, at url: URL, schema: Schema) throws -> Seeded {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let endedAt = startedAt.addingTimeInterval(600)
        let dueDate = startedAt.addingTimeInterval(86_400)
        let reservedAt = startedAt.addingTimeInterval(120)
        let reservedFromRideId = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let pauseStartedAt = startedAt.addingTimeInterval(300)
        let guardBoundary = startedAt.addingTimeInterval(1_200)
        let seeded = Seeded(
            ticketTitle: "残す切符",
            estimatedSeconds: 900,
            sortOrder: 3,
            dueDate: dueDate,
            closedAt: endedAt,
            closureKindRaw: ClosureKind.arrived.rawValue,
            reservedAt: era == .v3_1 ? reservedAt : nil,
            reservedFromRideId: era == .v3_1 ? reservedFromRideId : nil,
            reservedViaRaw: era == .v3_1 ? ReservationVia.riding.rawValue : nil,
            tagName: "青",
            lineageKindRaw: LineageKind.continuation.rawValue,
            dayKey: "2026-10-11",
            startedAt: startedAt,
            endedAt: endedAt,
            outcomeRaw: SessionOutcome.arrived.rawValue,
            arrivalActionRaw: era == .v3_1 ? ArrivalAction.nextRide.rawValue : nil,
            arrivalStampedAt: era == .v3_1 ? endedAt : nil,
            startedFromRaw: era == .v3_1 ? RideStartOrigin.arrivalSwipe.rawValue : nil,
            pauseStartedAt: pauseStartedAt,
            extensionSeconds: 300,
            blockTitle: "1on1",
            guardBoundary: guardBoundary,
            seriesIdentifier: "series-1",
            passengerTitle: "客の区間"
        )
        try autoreleasepool {
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: url)]
            )
            let context = container.mainContext
            switch era {
            case .v3:
                try insertV3(seeded, into: context)
            case .v3_1:
                try insertV3_1(seeded, into: context)
            }
            try context.save()
        }
        return seeded
    }

    private static func insertV3(_ seeded: Seeded, into context: ModelContext) throws {
        let tag = AppSchemaV3.Tag(name: seeded.tagName, colorHex: "#2255AA", sortOrder: 1)
        context.insert(tag)
        let ticket = AppSchemaV3.Ticket(
            title: seeded.ticketTitle,
            estimatedSeconds: seeded.estimatedSeconds,
            sortOrder: seeded.sortOrder,
            createdAt: seeded.startedAt
        )
        ticket.dueDate = seeded.dueDate
        ticket.closedAt = seeded.closedAt
        ticket.closureKindRaw = seeded.closureKindRaw
        ticket.tags = [tag]
        context.insert(ticket)
        let child = AppSchemaV3.Ticket(title: "乗り継ぎ先", estimatedSeconds: 600, sortOrder: 4)
        context.insert(child)
        context.insert(
            AppSchemaV3.TaskLineage(
                kindRaw: seeded.lineageKindRaw,
                parent: ticket,
                child: child,
                createdAt: seeded.endedAt
            )
        )
        let day = ServiceDay(startedAt: seeded.startedAt, calendarDayKey: seeded.dayKey)
        day.endedAt = seeded.endedAt
        context.insert(day)
        let session = AppSchemaV3.WorkSession(
            startedAt: seeded.startedAt,
            estimatedSecondsAtStart: seeded.estimatedSeconds,
            ticket: ticket,
            boardedDeviceID: "device-v3"
        )
        session.endedAt = seeded.endedAt
        session.outcomeRaw = seeded.outcomeRaw
        session.checkInAnswersJSON = "[\"v3\"]"
        context.insert(session)
        context.insert(
            AppSchemaV3.SessionPause(
                startedAt: seeded.pauseStartedAt,
                endedAt: seeded.endedAt,
                session: session
            )
        )
        context.insert(
            AppSchemaV3.SessionExtension(
                addedSeconds: seeded.extensionSeconds,
                reason: "延長",
                createdAt: seeded.endedAt,
                session: session
            )
        )
        try insertSharedRecords(seeded, into: context, sessionID: session.id)
    }

    private static func insertV3_1(_ seeded: Seeded, into context: ModelContext) throws {
        let tag = AppSchemaV3_1.Tag(name: seeded.tagName, colorHex: "#2255AA", sortOrder: 1)
        context.insert(tag)
        let ticket = AppSchemaV3_1.Ticket(
            title: seeded.ticketTitle,
            estimatedSeconds: seeded.estimatedSeconds,
            sortOrder: seeded.sortOrder,
            createdAt: seeded.startedAt
        )
        ticket.dueDate = seeded.dueDate
        ticket.closedAt = seeded.closedAt
        ticket.closureKindRaw = seeded.closureKindRaw
        ticket.reservedAt = seeded.reservedAt
        ticket.reservedFromRideId = seeded.reservedFromRideId
        ticket.reservedViaRaw = seeded.reservedViaRaw
        ticket.tags = [tag]
        context.insert(ticket)
        let child = AppSchemaV3_1.Ticket(title: "乗り継ぎ先", estimatedSeconds: 600, sortOrder: 4)
        context.insert(child)
        context.insert(
            AppSchemaV3_1.TaskLineage(
                kindRaw: seeded.lineageKindRaw,
                parent: ticket,
                child: child,
                createdAt: seeded.endedAt
            )
        )
        let day = ServiceDay(startedAt: seeded.startedAt, calendarDayKey: seeded.dayKey)
        day.endedAt = seeded.endedAt
        context.insert(day)
        let session = AppSchemaV3_1.WorkSession(
            startedAt: seeded.startedAt,
            estimatedSecondsAtStart: seeded.estimatedSeconds,
            ticket: ticket,
            boardedDeviceID: "device-v3"
        )
        session.endedAt = seeded.endedAt
        session.outcomeRaw = seeded.outcomeRaw
        session.arrivalActionRaw = seeded.arrivalActionRaw
        session.arrivalStampedAt = seeded.arrivalStampedAt
        if let startedFromRaw = seeded.startedFromRaw {
            session.startedFromRaw = startedFromRaw
        }
        session.checkInAnswersJSON = "[\"v3\"]"
        context.insert(session)
        context.insert(
            AppSchemaV3_1.SessionPause(
                startedAt: seeded.pauseStartedAt,
                endedAt: seeded.endedAt,
                session: session
            )
        )
        context.insert(
            AppSchemaV3_1.SessionExtension(
                addedSeconds: seeded.extensionSeconds,
                reason: "延長",
                createdAt: seeded.endedAt,
                session: session
            )
        )
        try insertSharedRecords(seeded, into: context, sessionID: session.id)
    }

    private static func insertSharedRecords(
        _ seeded: Seeded,
        into context: ModelContext,
        sessionID: UUID
    ) throws {
        let block = TimetableBlock(
            title: seeded.blockTitle,
            startsAt: seeded.startedAt,
            endsAt: seeded.endedAt,
            source: .manual,
            calendarEventIdentifier: "event-1"
        )
        block.needsReview = true
        context.insert(block)
        let item = TimetableGuard(
            sessionID: sessionID,
            blockID: block.id,
            notifiedAt: seeded.startedAt,
            protectionBoundary: seeded.guardBoundary
        )
        context.insert(item)
        let rule = TimetableSeriesRule(
            recurrenceIdentifier: seeded.seriesIdentifier,
            title: "毎週",
            adopted: true
        )
        rule.excludedOccurrenceStarts = [seeded.startedAt.timeIntervalSince1970]
        context.insert(rule)
        let ride = PassengerRide(
            intervalId: "interval-1",
            title: seeded.passengerTitle,
            intervalStart: seeded.startedAt,
            intervalEnd: seeded.endedAt,
            boardedAt: seeded.startedAt,
            source: .manualInterval,
            deviceId: "passenger-device"
        )
        ride.endedAt = seeded.endedAt
        ride.endReason = .arrived
        context.insert(ride)
    }

    private static func expectPreserved(
        _ seeded: Seeded,
        in context: ModelContext,
        keepsReservation: Bool
    ) throws {
        let tickets = try context.fetch(FetchDescriptor<Ticket>())
        #expect(tickets.count == 2)
        let ticket = try #require(tickets.first { $0.title == seeded.ticketTitle })
        #expect(ticket.estimatedSeconds == seeded.estimatedSeconds)
        #expect(ticket.sortOrder == seeded.sortOrder)
        #expect(ticket.dueDate == seeded.dueDate)
        #expect(ticket.closedAt == seeded.closedAt)
        #expect(ticket.closureKindRaw == seeded.closureKindRaw)
        #expect(ticket.tags.map(\.name) == [seeded.tagName])
        if keepsReservation {
            #expect(ticket.reservedAt == seeded.reservedAt)
            #expect(ticket.reservedFromRideId == seeded.reservedFromRideId)
            #expect(ticket.reservedViaRaw == seeded.reservedViaRaw)
        } else {
            #expect(ticket.reservedAt == nil)
            #expect(ticket.reservedFromRideId == nil)
            #expect(ticket.reservedViaRaw == nil)
        }

        let lineages = try context.fetch(FetchDescriptor<TaskLineage>())
        #expect(lineages.count == 1)
        #expect(lineages.first?.kindRaw == seeded.lineageKindRaw)
        #expect(lineages.first?.parent?.title == seeded.ticketTitle)
        #expect(lineages.first?.child?.title == "乗り継ぎ先")

        let days = try context.fetch(FetchDescriptor<ServiceDay>())
        #expect(days.map(\.calendarDayKey) == [seeded.dayKey])

        let sessions = try context.fetch(FetchDescriptor<WorkSession>())
        #expect(sessions.count == 1)
        let session = try #require(sessions.first)
        #expect(session.startedAt == seeded.startedAt)
        #expect(session.endedAt == seeded.endedAt)
        #expect(session.outcomeRaw == seeded.outcomeRaw)
        #expect(session.ticket?.title == seeded.ticketTitle)
        #expect(session.checkInAnswersJSON == "[\"v3\"]")
        #expect(session.boardedDeviceID == "device-v3")
        if keepsReservation {
            #expect(session.arrivalActionRaw == seeded.arrivalActionRaw)
            #expect(session.arrivalStampedAt == seeded.arrivalStampedAt)
            #expect(session.startedFromRaw == seeded.startedFromRaw)
        } else {
            #expect(session.arrivalActionRaw == nil)
            #expect(session.arrivalStampedAt == nil)
            #expect(session.startedFromRaw == RideStartOrigin.other.rawValue)
        }

        let pauses = try context.fetch(FetchDescriptor<SessionPause>())
        #expect(pauses.count == 1)
        #expect(pauses.first?.startedAt == seeded.pauseStartedAt)
        #expect(pauses.first?.session?.id == session.id)

        let extensions = try context.fetch(FetchDescriptor<SessionExtension>())
        #expect(extensions.map(\.addedSeconds) == [seeded.extensionSeconds])
        #expect(extensions.first?.session?.id == session.id)

        let blocks = try context.fetch(FetchDescriptor<TimetableBlock>())
        #expect(blocks.count == 1)
        #expect(blocks.first?.title == seeded.blockTitle)
        #expect(blocks.first?.calendarEventIdentifier == "event-1")
        #expect(blocks.first?.needsReview == true)

        let guards = try context.fetch(FetchDescriptor<TimetableGuard>())
        #expect(guards.count == 1)
        #expect(guards.first?.protectionBoundary == seeded.guardBoundary)
        #expect(guards.first?.sessionID == session.id)

        let rules = try context.fetch(FetchDescriptor<TimetableSeriesRule>())
        #expect(rules.count == 1)
        #expect(rules.first?.recurrenceIdentifier == seeded.seriesIdentifier)
        #expect(rules.first?.adopted == true)
        #expect(rules.first?.excludedOccurrenceStarts.count == 1)

        let rides = try context.fetch(FetchDescriptor<PassengerRide>())
        #expect(rides.count == 1)
        #expect(rides.first?.title == seeded.passengerTitle)
        #expect(rides.first?.intervalId == "interval-1")
        #expect(rides.first?.endReasonRaw == PassengerEndReason.arrived.rawValue)
        #expect(rides.first?.deviceId == "passenger-device")

        #expect(try context.fetch(FetchDescriptor<Todo_train.Tag>()).count == 1)
    }

    private static func expectNewColumnsAtDefaults(in context: ModelContext) throws {
        let sessions = try context.fetch(FetchDescriptor<WorkSession>())
        #expect(!sessions.isEmpty)
        for session in sessions {
            #expect(session.nudgeFiredStagesRaw == [])
            #expect(session.nudgePendingStageRaw == nil)
            #expect(session.nudgeAnsweredAt == nil)
            #expect(session.nudgeAnsweredOnRaw == nil)
            #expect(session.checkInFraction == nil)
            #expect(session.nudgeEventsJSON == "[]")
        }
        for pause in try context.fetch(FetchDescriptor<SessionPause>()) {
            #expect(pause.heldByRaw == nil)
            #expect(pause.pausedOnRaw == nil)
            #expect(pause.heldByInferred == false)
            #expect(pause.macSampledSeconds == 0)
            #expect(pause.macActiveSeconds == 0)
            #expect(pause.promptedAt == nil)
            #expect(pause.promptAnswerRaw == nil)
        }
    }

    /// develop の PR #71 以後（列追加前）が書いた entity ハッシュ。
    private static let postPR71Hashes: [String: String] = [
        "PassengerRide": "7CjuVWddXGHHZ8qKN7K30l5QaX/hmUohYSZ8wo7TNz4=",
        "ServiceDay": "Kc3d9k9z0jCdJ6fWcytZljkjcG8q8Y69VDJZuwI4H7Y=",
        "SessionExtension": "lQGhk9HQn2TjPYYHsOtaLcI456GOwpLH2LYxI0MOwbE=",
        "SessionPause": "rkN27inCOs91HxgOlO8xSe+L/y7H+sHCFV0nBrV4/fc=",
        "Tag": "55dqMZOeHVtyi4n1zah4rRIMMuN3slCXJBVqwZfIHdk=",
        "TaskLineage": "ZMBMgjT6ezmpzhAS/Y2frbX5Ssac6CBZH19aRXb0lRE=",
        "Ticket": "yi7M1Th10ZYXAAYyyMP1hhJdgUS7wvwm40qjeH/uh2I=",
        "TimetableBlock": "UnH6l4YqnyRukPfepphcWafMG9k69ehk3Gf5eHq+tA0=",
        "TimetableGuard": "ayyk0uuc3MWpUi6z+OnSKUY6XyT7HRqNUek4ppg4jg4=",
        "TimetableSeriesRule": "EG6OAAaUL/wzAhaw5Mi27AYqXEnIYlBRAxbwjO2DRi8=",
        "WorkSession": "EKG1yM3FZPuYPtoHe3NbdQeET1CHI9A5xQivbjQr3Rk=",
    ]

    private static func versionHashes(at url: URL) throws -> [String: String] {
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: url,
            options: nil
        )
        let hashes = try #require(metadata[NSStoreModelVersionHashesKey] as? [String: Data])
        return hashes.mapValues { $0.base64EncodedString() }
    }

    private static func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "todo-train-schema-\(UUID().uuidString).store")
    }

    private static func creationDate(of url: URL) throws -> Date {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.creationDate] as? Date)
    }

    private static func removeStoreFiles(at url: URL) {
        let fileManager = FileManager.default
        for extra in [url, URL(fileURLWithPath: url.path + "-shm"), URL(fileURLWithPath: url.path + "-wal")] {
            try? fileManager.removeItem(at: extra)
        }
    }
}

/// PR #71 以後のアプリが `AppSchemaV3`（3.0.0）に書いていた形。移行計画には入れない。
private enum PostPR71LabeledV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] { AppSchemaV3_1.models }
}
