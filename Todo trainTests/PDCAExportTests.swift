//
//  PDCAExportTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct PDCAExportTests {
    @Test func exportJSON_containsNoTitlesReasonsPromptsTagNamesCalendarOrDeviceIDs() throws {
        let fixture = try PDCAFixture.make()
        let data = try fixture.jsonData()
        let text = try #require(String(data: data, encoding: .utf8))
        for secret in PDCAFixture.secrets {
            #expect(!text.contains(secret))
        }

        let object = try jsonObject(data)
        var keys = Set<String>()
        collectKeys(object, into: &keys)
        #expect(keys.isDisjoint(with: PDCAFixture.forbiddenKeys))
    }

    @Test func exportJSON_hasPDCASchemaKeys() throws {
        let fixture = try PDCAFixture.make()
        let object = try jsonObject(try fixture.jsonData())

        #expect(Set(object.keys) == PDCAContract.rootKeys)
        #expect(object["schema"] as? String == "todotrain.pdca.v0")
        #expect(date(object, "exportedAt") == PDCAFixture.exportedAt)

        let serviceDays = try rows(object, "serviceDays")
        let tickets = try rows(object, "tickets")
        let rides = try rows(object, "rides")
        let pauses = try rows(object, "pauses")
        let extensions = try rows(object, "extensions")
        let lineages = try rows(object, "lineages")
        let checkIns = try rows(object, "checkIns")
        let blocks = try rows(object, "timetableBlocks")
        let guards = try rows(object, "timetableGuards")
        let passengerRides = try rows(object, "passengerRides")
        let passengerSummary = try #require(object["passengerSummary"] as? [String: Any])

        expectExactKeys(serviceDays, PDCAContract.serviceDayKeys)
        expectExactKeys(tickets, PDCAContract.ticketKeys)
        expectExactKeys(pauses, PDCAContract.pauseKeys)
        expectExactKeys(extensions, PDCAContract.extensionKeys)
        expectExactKeys(lineages, PDCAContract.lineageKeys)
        expectExactKeys(checkIns, PDCAContract.checkInKeys)
        expectExactKeys(blocks, PDCAContract.blockKeys)
        expectExactKeys(guards, PDCAContract.guardKeys)
        for ride in rides {
            expectRideKeys(ride)
        }
        expectExactKeys(passengerRides, PDCAContract.passengerRideKeys)
        #expect(Set(passengerSummary.keys) == PDCAContract.passengerSummaryKeys)

        let day = try #require(row(serviceDays, id: fixture.serviceDayID))
        #expect(day["calendarDayKey"] as? String == "1999-01-01")
        #expect(date(day, "startedAt") == PDCAFixture.dayStart)
        #expect(date(day, "endedAt") == PDCAFixture.dayEnd)

        let arrived = try #require(row(tickets, id: fixture.arrivedTicketID))
        #expect(date(arrived, "createdAt") == PDCAFixture.dayStart)
        #expect(date(arrived, "dueDate") == PDCAFixture.dayStart.addingTimeInterval(86_400))
        #expect(date(arrived, "closedAt") == PDCAFixture.dayStart.addingTimeInterval(2_000))
        #expect(arrived["closureKind"] as? String == "arrived")
        #expect(number(arrived, "estimatedSeconds") == 1_800)
        #expect(number(arrived, "tagCount") == 1)
        #expect(number(arrived, "rideCount") == 1)

        let open = try #require(row(tickets, id: fixture.openTicketID))
        #expect(isNull(open["dueDate"]))
        #expect(isNull(open["closedAt"]))
        #expect(isNull(open["closureKind"]))
        #expect(number(open, "tagCount") == 0)
        #expect(number(open, "rideCount") == 0)

        let resumed = try #require(row(rides, id: fixture.resumedRideID))
        #expect(resumed["ticketId"] as? String == fixture.arrivedTicketID.uuidString)
        #expect(resumed["serviceDayId"] as? String == fixture.serviceDayID.uuidString)
        #expect(date(resumed, "startedAt") == PDCAFixture.dayStart.addingTimeInterval(60))
        #expect(number(resumed, "accumulatedActiveSeconds") == 1_234)
        #expect(number(resumed, "estimatedSecondsAtStart") == 1_800)
        #expect(number(resumed, "budgetSecondsAtStart") == 2_400)
        #expect(resumed["outcome"] as? String == "arrived")
        #expect(resumed["overtimeResolution"] as? String == "alreadyDone")
        #expect(resumed["timetableHeld"] as? Bool == true)
        #expect(number(resumed, "checkInFiredCount") == 2)

        let orphan = try #require(row(rides, id: fixture.orphanRideID))
        #expect(isNull(orphan["ticketId"]))
        #expect(isNull(orphan["outcome"]))
        #expect(isNull(orphan["overtimeResolution"]))

        let boundary = try #require(row(rides, id: fixture.boundaryRideID))
        #expect(boundary["serviceDayId"] == nil)
        #expect(boundary["outcome"] as? String == "arrived")

        let pause = try #require(row(pauses, id: fixture.pauseID))
        #expect(pause["rideId"] as? String == fixture.resumedRideID.uuidString)
        #expect(date(pause, "endedAt") == PDCAFixture.dayStart.addingTimeInterval(900))

        let extensionRow = try #require(row(extensions, id: fixture.extensionID))
        #expect(extensionRow["rideId"] as? String == fixture.resumedRideID.uuidString)
        #expect(number(extensionRow, "addedSeconds") == 600)

        let lineage = try #require(row(lineages, id: fixture.lineageID))
        #expect(lineage["kind"] as? String == "continuation")
        #expect(lineage["fromRideId"] as? String == fixture.boundaryRideID.uuidString)
        #expect(lineage["parentTicketId"] as? String == fixture.partialTicketID.uuidString)
        #expect(lineage["childTicketId"] as? String == fixture.openTicketID.uuidString)
        #expect(lineage["aiGenerated"] as? Bool == true)

        #expect(checkIns.count == 2)
        let progress = try #require(checkIns.first { $0["kind"] as? String == "progress" })
        #expect(progress["rideId"] as? String == fixture.resumedRideID.uuidString)
        #expect(progress["answer"] as? String == "stillOnIt")
        #expect(date(progress, "answeredAt") == PDCAFixture.dayStart.addingTimeInterval(120))
        let away = try #require(checkIns.first { $0["kind"] as? String == "away" })
        #expect(away["answer"] as? String == "paused")
        #expect(away["rideId"] as? String == fixture.boundaryRideID.uuidString)

        let block = try #require(row(blocks, id: fixture.blockID))
        #expect(block["source"] as? String == "calendar")
        #expect(block["adoptionScope"] as? String == "series")
        #expect(block["isCancelled"] as? Bool == true)
        #expect(block["needsReview"] as? Bool == true)

        let guardRow = try #require(row(guards, id: fixture.guardID))
        #expect(guardRow["rideId"] as? String == fixture.resumedRideID.uuidString)
        #expect(guardRow["blockId"] as? String == fixture.blockID.uuidString)
        #expect(date(guardRow, "resolvedAt") == PDCAFixture.dayStart.addingTimeInterval(1_500))
        #expect(isNull(guardRow["invalidatedAt"]))

        #expect(passengerRides.count == 3)
        let arrivedPassenger = try #require(row(passengerRides, id: fixture.passengerArrivedRideID))
        #expect(arrivedPassenger["endReason"] as? String == "arrived")
        #expect(arrivedPassenger["source"] as? String == "manualInterval")
        #expect(number(passengerSummary, "aboardCount") == 3)
        #expect(number(passengerSummary, "openAboardCount") == 1)
        #expect(number(passengerSummary, "endReasonArrived") == 1)
        #expect(number(passengerSummary, "endReasonEmergency") == 1)
        #expect(number(passengerSummary, "endReasonCancelled") == 0)
        #expect(number(passengerSummary, "totalAboardSeconds") == 2_000)
        #expect(number(passengerSummary, "minAboardSeconds") == 500)
        #expect(number(passengerSummary, "maxAboardSeconds") == 1_500)
    }

    @Test func exportJSON_passengerSummaryEmptyWhenNoRides() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let object = try jsonObject(
            try PDCAExport.jsonData(in: context, exportedAt: PDCAFixture.exportedAt)
        )
        let summary = try #require(object["passengerSummary"] as? [String: Any])
        #expect(number(summary, "aboardCount") == 0)
        #expect(number(summary, "openAboardCount") == 0)
        #expect((object["passengerRides"] as? [Any])?.isEmpty == true)
    }

    @Test func exportJSON_countsIssuedTicketsAndArrivedClosures() throws {
        let fixture = try PDCAFixture.make()
        let tickets = try rows(try jsonObject(try fixture.jsonData()), "tickets")
        #expect(tickets.count == 4)
        let arrived = tickets.filter { $0["closureKind"] as? String == "arrived" }
        #expect(arrived.count == 1)
        #expect(arrived.first?["id"] as? String == fixture.arrivedTicketID.uuidString)
    }

    @Test func exportJSON_recordsResumeAsPauseNotExtraRide() throws {
        let fixture = try PDCAFixture.make()
        let object = try jsonObject(try fixture.jsonData())
        let rides = try rows(object, "rides")
        let pauses = try rows(object, "pauses")
        let resumedTicketRides = rides.filter {
            $0["ticketId"] as? String == fixture.arrivedTicketID.uuidString
        }
        #expect(resumedTicketRides.count == 1)
        #expect(resumedTicketRides.first?["id"] as? String == fixture.resumedRideID.uuidString)
        let resumedPauses = pauses.filter {
            $0["rideId"] as? String == fixture.resumedRideID.uuidString
        }
        #expect(resumedPauses.count == 1)
        #expect(resumedPauses.first?["id"] as? String == fixture.pauseID.uuidString)
        #expect(!isNull(resumedPauses.first?["endedAt"]))
        #expect(rides.count == 3)
    }

    @Test func exportJSON_assignsServiceDayByContainingInterval() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let closed = ServiceDay(startedAt: start.addingTimeInterval(-500), calendarDayKey: "closed-key")
        closed.endedAt = start
        let earlier = ServiceDay(startedAt: start, calendarDayKey: "earlier-key")
        let later = ServiceDay(startedAt: start.addingTimeInterval(100), calendarDayKey: "later-key")
        context.insert(closed)
        context.insert(earlier)
        context.insert(later)

        let beforeClosed = WorkSession(
            startedAt: start.addingTimeInterval(-600),
            estimatedSecondsAtStart: 60
        )
        let insideClosed = WorkSession(
            startedAt: start.addingTimeInterval(-1),
            estimatedSecondsAtStart: 60
        )
        let atEarlierStart = WorkSession(
            startedAt: start,
            estimatedSecondsAtStart: 60
        )
        let inBoth = WorkSession(
            startedAt: start.addingTimeInterval(150),
            estimatedSecondsAtStart: 60
        )
        for session in [beforeClosed, insideClosed, atEarlierStart, inBoth] {
            context.insert(session)
        }
        try context.save()

        let rides = try rows(
            try jsonObject(try PDCAExport.jsonData(in: context, exportedAt: start)),
            "rides"
        )
        let before = try #require(row(rides, id: beforeClosed.id))
        let inside = try #require(row(rides, id: insideClosed.id))
        let atStart = try #require(row(rides, id: atEarlierStart.id))
        let overlap = try #require(row(rides, id: inBoth.id))

        #expect(before["serviceDayId"] == nil)
        #expect(inside["serviceDayId"] as? String == closed.id.uuidString)
        #expect(atStart["serviceDayId"] as? String == earlier.id.uuidString)
        #expect(overlap["serviceDayId"] as? String == later.id.uuidString)
    }

    @Test func exportJSON_emptyStoreHasContractKeys() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let object = try jsonObject(
            try PDCAExport.jsonData(in: context, exportedAt: PDCAFixture.exportedAt)
        )
        #expect(Set(object.keys) == PDCAContract.rootKeys)
        #expect(object["schema"] as? String == PDCAExport.schema)
        for key in PDCAContract.arrayKeys {
            let list = try #require(object[key] as? [Any])
            #expect(list.isEmpty)
        }
        let summary = try #require(object["passengerSummary"] as? [String: Any])
        #expect(Set(summary.keys) == PDCAContract.passengerSummaryKeys)
        #expect(number(summary, "aboardCount") == 0)
    }
}

@MainActor
private struct PDCAFixture {
    static let secrets = [
        "SECRET_TICKET_TITLE_ZX9",
        "SECRET_TAG_NAME_ZX9",
        "SECRET_EXTEND_REASON_ZX9",
        "SECRET_CHECKIN_PROMPT_ZX9",
        "SECRET_ANSWER_PROMPT_ZX9",
        "SECRET_BLOCK_TITLE_ZX9",
        "SECRET_CAL_EVENT_ZX9",
        "SECRET_CAL_RECUR_ZX9",
        "SECRET_DEVICE_IDFV_ZX9",
        "SECRET_SERIES_TITLE_ZX9",
        "SECRET_SERIES_RECUR_ZX9",
        "SECRET_PASSENGER_TITLE_ZX9",
        "not-a-closure",
        "not-an-outcome",
        "#SECRETTAG",
    ]

    static let forbiddenKeys: Set<String> = [
        "title",
        "name",
        "reason",
        "checkInPromptLine",
        "boardedDeviceID",
        "calendarEventIdentifier",
        "calendarRecurrenceIdentifier",
        "recurrenceIdentifier",
        "prompt",
        "deviceId",
        "intervalId",
    ]

    static let exportedAt = Date(timeIntervalSince1970: 1_700_100_000)
    static let dayStart = Date(timeIntervalSince1970: 1_700_000_000)
    static let dayEnd = dayStart.addingTimeInterval(3_600)

    var context: ModelContext
    var serviceDayID: UUID
    var arrivedTicketID: UUID
    var partialTicketID: UUID
    var openTicketID: UUID
    var abandonedTicketID: UUID
    var resumedRideID: UUID
    var boundaryRideID: UUID
    var orphanRideID: UUID
    var pauseID: UUID
    var extensionID: UUID
    var lineageID: UUID
    var blockID: UUID
    var guardID: UUID
    var passengerArrivedRideID: UUID
    var passengerEmergencyRideID: UUID
    var passengerOpenRideID: UUID

    func jsonData() throws -> Data {
        try PDCAExport.jsonData(in: context, exportedAt: Self.exportedAt)
    }

    static func make() throws -> PDCAFixture {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let stamp = ISO8601DateFormatter().string(from: dayStart.addingTimeInterval(120))

        let serviceDayID = UUID()
        let arrivedTicketID = UUID()
        let partialTicketID = UUID()
        let openTicketID = UUID()
        let abandonedTicketID = UUID()
        let resumedRideID = UUID()
        let boundaryRideID = UUID()
        let orphanRideID = UUID()
        let pauseID = UUID()
        let extensionID = UUID()
        let lineageID = UUID()
        let blockID = UUID()
        let guardID = UUID()
        let passengerArrivedRideID = UUID()
        let passengerEmergencyRideID = UUID()
        let passengerOpenRideID = UUID()

        let day = ServiceDay(id: serviceDayID, startedAt: dayStart, calendarDayKey: "1999-01-01")
        day.endedAt = dayEnd
        context.insert(day)

        let arrived = Ticket(
            id: arrivedTicketID,
            title: "SECRET_TICKET_TITLE_ZX9",
            estimatedSeconds: 1_800,
            createdAt: dayStart
        )
        arrived.dueDate = dayStart.addingTimeInterval(86_400)
        arrived.closedAt = dayStart.addingTimeInterval(2_000)
        arrived.closureKind = .arrived
        let tag = Tag(name: "SECRET_TAG_NAME_ZX9", colorHex: "#SECRETTAG")
        context.insert(tag)
        arrived.tags = [tag]
        context.insert(arrived)

        let partial = Ticket(
            id: partialTicketID,
            title: "SECRET_TICKET_TITLE_ZX9",
            estimatedSeconds: 900,
            createdAt: dayStart.addingTimeInterval(1)
        )
        partial.closedAt = dayEnd
        partial.closureKind = .partialDisembark
        context.insert(partial)

        let open = Ticket(
            id: openTicketID,
            title: "SECRET_TICKET_TITLE_ZX9",
            estimatedSeconds: 600,
            createdAt: dayStart.addingTimeInterval(2)
        )
        open.closureKindRaw = "not-a-closure"
        context.insert(open)

        let abandoned = Ticket(
            id: abandonedTicketID,
            title: "SECRET_TICKET_TITLE_ZX9",
            estimatedSeconds: 300,
            createdAt: dayStart.addingTimeInterval(3)
        )
        abandoned.closedAt = dayStart.addingTimeInterval(4)
        abandoned.closureKind = .abandoned
        context.insert(abandoned)

        let resumed = WorkSession(
            id: resumedRideID,
            startedAt: dayStart.addingTimeInterval(60),
            estimatedSecondsAtStart: 1_800,
            ticket: arrived,
            boardedDeviceID: "SECRET_DEVICE_IDFV_ZX9"
        )
        resumed.endedAt = dayStart.addingTimeInterval(2_000)
        resumed.accumulatedActiveSeconds = 1_234
        resumed.budgetSecondsAtStart = 2_400
        resumed.outcome = .arrived
        resumed.overtimeResolution = .alreadyDone
        resumed.timetableHeld = true
        resumed.checkInFiredCount = 2
        resumed.checkInPromptLine = "SECRET_CHECKIN_PROMPT_ZX9"
        resumed.checkInAnswersJSON = """
        [{"kind":"progress","answer":"stillOnIt","answeredAt":"\(stamp)","prompt":"SECRET_ANSWER_PROMPT_ZX9"},{"kind":"bogus","answer":"stillOnIt","answeredAt":"\(stamp)","prompt":"SECRET_ANSWER_PROMPT_ZX9"}]
        """
        context.insert(resumed)
        context.insert(
            SessionPause(
                id: pauseID,
                startedAt: dayStart.addingTimeInterval(600),
                endedAt: dayStart.addingTimeInterval(900),
                session: resumed
            )
        )
        context.insert(
            SessionExtension(
                id: extensionID,
                addedSeconds: 600,
                reason: "SECRET_EXTEND_REASON_ZX9",
                createdAt: dayStart.addingTimeInterval(500),
                session: resumed
            )
        )

        let boundary = WorkSession(
            id: boundaryRideID,
            startedAt: dayEnd,
            estimatedSecondsAtStart: 900,
            ticket: partial,
            boardedDeviceID: "SECRET_DEVICE_IDFV_ZX9"
        )
        boundary.endedAt = dayEnd.addingTimeInterval(100)
        boundary.accumulatedActiveSeconds = 100
        boundary.outcome = .arrived
        boundary.checkInPromptLine = "SECRET_CHECKIN_PROMPT_ZX9"
        boundary.checkInAnswersJSON = """
        [{"kind":"away","answer":"paused","answeredAt":"\(stamp)","prompt":"SECRET_ANSWER_PROMPT_ZX9"}]
        """
        context.insert(boundary)

        let orphan = WorkSession(
            id: orphanRideID,
            startedAt: dayStart.addingTimeInterval(10),
            estimatedSecondsAtStart: 60
        )
        orphan.outcomeRaw = "not-an-outcome"
        orphan.checkInPromptLine = "SECRET_CHECKIN_PROMPT_ZX9"
        orphan.boardedDeviceID = "SECRET_DEVICE_IDFV_ZX9"
        context.insert(orphan)

        context.insert(
            TaskLineage(
                id: lineageID,
                kind: .continuation,
                parent: partial,
                child: open,
                createdAt: dayEnd,
                fromSessionID: boundaryRideID,
                aiGenerated: true
            )
        )

        let block = TimetableBlock(
            id: blockID,
            title: "SECRET_BLOCK_TITLE_ZX9",
            startsAt: dayStart,
            endsAt: dayEnd,
            source: .calendar,
            adoptionScope: .series,
            calendarEventIdentifier: "SECRET_CAL_EVENT_ZX9",
            calendarRecurrenceIdentifier: "SECRET_CAL_RECUR_ZX9"
        )
        block.isCancelled = true
        block.needsReview = true
        context.insert(block)

        let timetableGuard = TimetableGuard(
            id: guardID,
            sessionID: resumedRideID,
            blockID: blockID,
            notifiedAt: dayStart.addingTimeInterval(60),
            protectionBoundary: dayEnd
        )
        timetableGuard.resolvedAt = dayStart.addingTimeInterval(1_500)
        context.insert(timetableGuard)

        context.insert(
            TimetableSeriesRule(
                recurrenceIdentifier: "SECRET_SERIES_RECUR_ZX9",
                title: "SECRET_SERIES_TITLE_ZX9",
                adopted: true
            )
        )

        let passengerArrived = PassengerRide(
            id: passengerArrivedRideID,
            intervalId: "passenger-interval-arrived",
            title: "SECRET_PASSENGER_TITLE_ZX9",
            intervalStart: dayStart,
            intervalEnd: dayStart.addingTimeInterval(3_600),
            boardedAt: dayStart.addingTimeInterval(100),
            source: .manualInterval,
            deviceId: "SECRET_DEVICE_IDFV_ZX9"
        )
        passengerArrived.endedAt = dayStart.addingTimeInterval(1_600)
        passengerArrived.endReason = .arrived
        context.insert(passengerArrived)

        let passengerEmergency = PassengerRide(
            id: passengerEmergencyRideID,
            intervalId: "passenger-interval-emergency",
            title: "SECRET_PASSENGER_TITLE_ZX9",
            intervalStart: dayStart.addingTimeInterval(3_600),
            intervalEnd: dayStart.addingTimeInterval(7_200),
            boardedAt: dayStart.addingTimeInterval(3_700),
            source: .adoptedBlock,
            deviceId: "SECRET_DEVICE_IDFV_ZX9"
        )
        passengerEmergency.endedAt = dayStart.addingTimeInterval(4_200)
        passengerEmergency.endReason = .emergency
        context.insert(passengerEmergency)

        let passengerOpen = PassengerRide(
            id: passengerOpenRideID,
            intervalId: "passenger-interval-open",
            title: "SECRET_PASSENGER_TITLE_ZX9",
            intervalStart: dayStart.addingTimeInterval(8_000),
            intervalEnd: dayStart.addingTimeInterval(10_000),
            boardedAt: dayStart.addingTimeInterval(8_100),
            source: .manualInterval,
            deviceId: "SECRET_DEVICE_IDFV_ZX9"
        )
        context.insert(passengerOpen)

        try context.save()
        return PDCAFixture(
            context: context,
            serviceDayID: serviceDayID,
            arrivedTicketID: arrivedTicketID,
            partialTicketID: partialTicketID,
            openTicketID: openTicketID,
            abandonedTicketID: abandonedTicketID,
            resumedRideID: resumedRideID,
            boundaryRideID: boundaryRideID,
            orphanRideID: orphanRideID,
            pauseID: pauseID,
            extensionID: extensionID,
            lineageID: lineageID,
            blockID: blockID,
            guardID: guardID,
            passengerArrivedRideID: passengerArrivedRideID,
            passengerEmergencyRideID: passengerEmergencyRideID,
            passengerOpenRideID: passengerOpenRideID
        )
    }
}

private enum PDCAContract {
    static let rootKeys: Set<String> = [
        "schema",
        "exportedAt",
        "serviceDays",
        "tickets",
        "rides",
        "pauses",
        "extensions",
        "lineages",
        "checkIns",
        "timetableBlocks",
        "timetableGuards",
        "passengerRides",
        "passengerSummary",
    ]

    static let arrayKeys: [String] = [
        "serviceDays",
        "tickets",
        "rides",
        "pauses",
        "extensions",
        "lineages",
        "checkIns",
        "timetableBlocks",
        "timetableGuards",
        "passengerRides",
    ]

    static let serviceDayKeys: Set<String> = ["id", "startedAt", "endedAt", "calendarDayKey"]
    static let ticketKeys: Set<String> = [
        "id", "createdAt", "dueDate", "closedAt", "closureKind",
        "estimatedSeconds", "tagCount", "rideCount",
    ]
    static let rideKeys: Set<String> = [
        "id", "ticketId", "startedAt", "endedAt", "accumulatedActiveSeconds",
        "estimatedSecondsAtStart", "budgetSecondsAtStart", "outcome",
        "overtimeResolution", "timetableHeld", "checkInFiredCount",
    ]
    static let pauseKeys: Set<String> = ["id", "rideId", "startedAt", "endedAt"]
    static let extensionKeys: Set<String> = ["id", "rideId", "addedSeconds", "createdAt"]
    static let lineageKeys: Set<String> = [
        "id", "kind", "createdAt", "fromRideId", "parentTicketId", "childTicketId", "aiGenerated",
    ]
    static let checkInKeys: Set<String> = ["rideId", "kind", "answer", "answeredAt"]
    static let blockKeys: Set<String> = [
        "id", "startsAt", "endsAt", "source", "adoptionScope", "isCancelled", "needsReview",
    ]
    static let guardKeys: Set<String> = [
        "id", "rideId", "blockId", "notifiedAt", "protectionBoundary", "resolvedAt", "invalidatedAt",
    ]
    static let passengerRideKeys: Set<String> = [
        "id", "boardedAt", "endedAt", "endReason", "source",
        "intervalStart", "intervalEnd", "aboardSeconds",
    ]
    static let passengerSummaryKeys: Set<String> = [
        "aboardCount", "openAboardCount", "endReasonArrived", "endReasonEmergency",
        "endReasonCancelled", "totalAboardSeconds", "minAboardSeconds", "maxAboardSeconds",
    ]
}

private func jsonObject(_ data: Data) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}

private func rows(_ object: [String: Any], _ key: String) throws -> [[String: Any]] {
    try #require(object[key] as? [[String: Any]])
}

private func row(_ rows: [[String: Any]], id: UUID) -> [String: Any]? {
    rows.first { $0["id"] as? String == id.uuidString }
}

private func expectExactKeys(_ rows: [[String: Any]], _ keys: Set<String>) {
    #expect(!rows.isEmpty)
    for row in rows {
        #expect(Set(row.keys) == keys)
    }
}

private func expectRideKeys(_ ride: [String: Any]) {
    var keys = Set(ride.keys)
    keys.remove("serviceDayId")
    #expect(keys == PDCAContract.rideKeys)
}

private func date(_ row: [String: Any], _ key: String) -> Date? {
    guard let value = row[key] as? String else { return nil }
    return ISO8601DateFormatter().date(from: value)
}

private func number(_ row: [String: Any], _ key: String) -> Int? {
    (row[key] as? NSNumber)?.intValue
}

private func isNull(_ value: Any?) -> Bool {
    value is NSNull
}

private func collectKeys(_ value: Any, into keys: inout Set<String>) {
    switch value {
    case let object as [String: Any]:
        for (key, nested) in object {
            keys.insert(key)
            collectKeys(nested, into: &keys)
        }
    case let list as [Any]:
        for nested in list {
            collectKeys(nested, into: &keys)
        }
    default:
        break
    }
}
