//
//  PDCAExportTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
import TodoTrainSync
@testable import Todo_train

@MainActor
struct PDCAExportTests {
    @Test func exportJSON_containsNoTitlesPromptsTagNamesCalendarOrDeviceIDs() throws {
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

    @Test func exportJSON_extensionReasonsAreAllowedVocabularyOrNull() throws {
        let fixture = try PDCAFixture.make()
        let object = try jsonObject(try fixture.jsonData())
        let extensions = try rows(object, "extensions")
        let allowed = Set(ServiceCabinSequence.extendReasons)
        for extensionRow in extensions {
            if let reason = extensionRow["reason"] as? String {
                #expect(allowed.contains(reason))
            } else {
                #expect(isNull(extensionRow["reason"]))
            }
        }
    }

    @Test func exportJSON_buildUsesContainerSchemaAndOmitsPeerUntilMacSendsOne() throws {
        let fixture = try PDCAFixture.make()
        let object = try jsonObject(try fixture.jsonData())
        let build = try #require(object["build"] as? [String: Any])
        #expect(Set(build.keys) == [
            "sha", "branch", "dirty", "builtAt", "schemaVersion", "marketingVersion",
        ])
        #expect(build["schemaVersion"] as? String == StoreSchemaVersion.wire)
        #expect(build["schemaVersion"] as? String == {
            let version = AppModelContainer.schema.version
            return "\(version.major).\(version.minor).\(version.patch)"
        }())
        #expect(object["pairedBuild"] is NSNull)

        let paired = PDCAExport.PairedBuildRow(
            sha: "abcdef1",
            dirty: false,
            schema: "3.0.0",
            builtAt: "2026-10-12T16:20:00+09:00"
        )
        let stamped = try jsonObject(
            try PDCAExport.jsonData(
                in: fixture.context,
                exportedAt: PDCAFixture.exportedAt,
                build: PDCAExport.BuildRow(
                    sha: "1047101",
                    branch: "develop",
                    dirty: true,
                    builtAt: "2026-10-12T16:20:00+09:00",
                    schemaVersion: StoreSchemaVersion.wire,
                    marketingVersion: "1.0"
                ),
                pairedBuild: paired
            )
        )
        let written = try #require(stamped["build"] as? [String: Any])
        #expect(written["sha"] as? String == "1047101")
        #expect(written["dirty"] as? Bool == true)
        #expect(written["marketingVersion"] as? String == "1.0")
        let peer = try #require(stamped["pairedBuild"] as? [String: Any])
        #expect(Set(peer.keys) == ["builtAt", "dirty", "schema", "sha"])
        #expect(peer["sha"] as? String == "abcdef1")
        #expect(stamped["schema"] as? String == "todotrain.pdca.v0")
        #expect(ContractVersion.contract == 15)
        #expect(AppSchemaV6.versionIdentifier == Schema.Version(6, 0, 0))
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
        #expect(isNull(open["reservedAt"]))
        #expect(isNull(open["reservedFromRideId"]))
        #expect(isNull(open["reservedVia"]))

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
        #expect(isNull(resumed["arrivalAction"]))
        #expect(isNull(resumed["arrivalStampedAt"]))
        #expect(resumed["startedFrom"] as? String == "other")
        #expect(number(resumed, "pauseInputSeconds") == 0)
        #expect(resumed["excludedFromForecast"] as? Bool == false)
        #expect(resumed["tagIds"] as? [String] == [fixture.tagID.uuidString])
        #expect(number(resumed, "ordinalInDay") == 2)
        #expect(number(resumed, "cumulativeActiveSecondsBefore") == 0)
        #expect(isNull(resumed["secondsSincePreviousArrival"]))
        #expect(resumed["previousRideId"] as? String == fixture.orphanRideID.uuidString)
        #expect(isNull(resumed["nextRideId"]))
        #expect(number(resumed, "issueToDepartSeconds") == 60)
        #expect(resumed["batchId"] as? String == fixture.arrivedTicketID.uuidString)
        #expect(isNull(resumed["slackToNextTimetableBlockSeconds"]))
        #expect(resumed["lineageGroupId"] as? String == fixture.arrivedTicketID.uuidString)
        #expect((resumed["similarityCandidates"] as? [Any])?.isEmpty == true)

        let orphan = try #require(row(rides, id: fixture.orphanRideID))
        #expect(isNull(orphan["ticketId"]))
        #expect(isNull(orphan["outcome"]))
        #expect(isNull(orphan["overtimeResolution"]))

        let boundary = try #require(row(rides, id: fixture.boundaryRideID))
        #expect(boundary["serviceDayId"] == nil)
        #expect(boundary["outcome"] as? String == "arrived")
        #expect((boundary["tagIds"] as? [String])?.isEmpty == true)
        #expect(isNull(boundary["ordinalInDay"]))
        #expect(isNull(boundary["cumulativeActiveSecondsBefore"]))
        #expect(isNull(boundary["previousRideId"]))
        #expect(isNull(boundary["nextRideId"]))
        #expect(number(boundary, "issueToDepartSeconds") == 3_599)
        #expect(boundary["batchId"] as? String == fixture.arrivedTicketID.uuidString)
        let lineageGroup = [fixture.partialTicketID, fixture.openTicketID].min {
            $0.uuidString < $1.uuidString
        }
        #expect(boundary["lineageGroupId"] as? String == lineageGroup?.uuidString)
        let candidates = try #require(boundary["similarityCandidates"] as? [[String: Any]])
        #expect(candidates.count == 1)
        let candidate = try #require(candidates.first)
        #expect(Set(candidate.keys) == PDCAContract.similarityCandidateKeys)
        #expect(candidate["rideId"] as? String == fixture.resumedRideID.uuidString)
        #expect(double(candidate, "titleNGram") == 1)
        #expect(double(candidate, "tag") == 0)
        #expect(double(candidate, "lineage") == 0)

        let orphanRide = try #require(row(rides, id: fixture.orphanRideID))
        #expect(number(orphanRide, "ordinalInDay") == 1)
        #expect(isNull(orphanRide["previousRideId"]))
        #expect(orphanRide["nextRideId"] as? String == fixture.resumedRideID.uuidString)
        #expect(isNull(orphanRide["issueToDepartSeconds"]))
        #expect(isNull(orphanRide["batchId"]))
        #expect(isNull(orphanRide["lineageGroupId"]))

        let pause = try #require(row(pauses, id: fixture.pauseID))
        #expect(pause["rideId"] as? String == fixture.resumedRideID.uuidString)
        #expect(date(pause, "endedAt") == PDCAFixture.dayStart.addingTimeInterval(900))
        #expect(isNull(pause["heldBy"]))
        #expect(isNull(pause["pausedOn"]))
        #expect(pause["heldByInferred"] as? Bool == false)
        #expect(number(pause, "macSampledSeconds") == 0)
        #expect(number(pause, "macActiveSeconds") == 0)
        #expect(isNull(pause["promptedAt"]))
        #expect(isNull(pause["promptAnswer"]))

        let extensionRow = try #require(row(extensions, id: fixture.extensionID))
        #expect(extensionRow["rideId"] as? String == fixture.resumedRideID.uuidString)
        #expect(number(extensionRow, "addedSeconds") == 600)
        #expect(number(extensionRow, "workingSeconds") == 1_100)
        #expect(extensionRow["reason"] as? String == "作業増")

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

    @Test func exportJSON_exportsReestimateRowsAndPauseUndoneAt() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let ticket = Ticket(title: "見積もり", estimatedSeconds: 1_800)
        context.insert(ticket)
        let rideID = UUID()
        let started = PDCAFixture.dayStart
        let session = WorkSession(
            id: rideID,
            startedAt: started,
            estimatedSecondsAtStart: 1_800,
            ticket: ticket
        )
        let committed = started.addingTimeInterval(400)
        let undoneAt = started.addingTimeInterval(500)
        session.reestimateEvents = [
            ReestimateEventRecord(
                reestimateIndex: 1,
                trigger: .manual,
                surface: .iphonePortrait,
                input: .touch,
                promptId: ReestimatePromptID.remainingV1,
                mode: .minutesOnly,
                committedAt: committed,
                activeSeconds: 400,
                overrunSeconds: 0,
                progressAnswer: nil,
                committedRemainingSeconds: 900,
                shownBandLowSeconds: 1_000,
                shownBandHighSeconds: 1_200,
                detailsOpened: false
            ),
            ReestimateEventRecord(
                reestimateIndex: 2,
                trigger: .checkIn,
                surface: .iphoneLandscape,
                input: .touch,
                promptId: ReestimatePromptID.progressV1,
                mode: .progress,
                committedAt: committed.addingTimeInterval(60),
                activeSeconds: 460,
                overrunSeconds: 10,
                progressAnswer: 0.5,
                committedRemainingSeconds: 600,
                shownBandLowSeconds: 1_100,
                shownBandHighSeconds: 1_300,
                detailsOpened: true,
                undoneAt: undoneAt
            ),
        ]
        context.insert(session)
        let pause = SessionPause(
            startedAt: started.addingTimeInterval(100),
            endedAt: started.addingTimeInterval(200),
            session: session
        )
        pause.undoneAt = undoneAt
        context.insert(pause)
        try context.save()

        let object = try jsonObject(
            try PDCAExport.jsonData(in: context, exportedAt: PDCAFixture.exportedAt)
        )
        let reestimates = try rows(object, "reestimates")
        #expect(reestimates.count == 2)
        expectExactKeys(reestimates, PDCAContract.reestimateKeys)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let sample = PDCAExport.ReestimateRow(
            rideId: rideID,
            reestimateIndex: 1,
            trigger: ReestimateTrigger.manual.rawValue,
            surface: ReestimateSurface.iphonePortrait.rawValue,
            input: ReestimateInput.touch.rawValue,
            promptId: ReestimatePromptID.remainingV1,
            mode: ReestimateMode.minutesOnly.rawValue,
            committedAt: committed,
            activeSeconds: 0,
            overrunSeconds: 0,
            progressAnswer: PDCANull<Double>(nil),
            committedRemainingSeconds: 0,
            shownBandLowSeconds: PDCANull<Int>(nil),
            shownBandHighSeconds: PDCANull<Int>(nil),
            detailsOpened: false,
            undoneAt: PDCANull<Date>(nil),
            remoteWillExtendReceived: false,
            declaration: PDCANull<String>(nil),
            projectedTotalSeconds: PDCANull<Int>(nil)
        )
        let sampleKeys = Set(
            try #require(
                JSONSerialization.jsonObject(with: try encoder.encode(sample)) as? [String: Any]
            ).keys
        )
        #expect(PDCAContract.reestimateKeys == sampleKeys)
        for row in reestimates {
            #expect(Set(row.keys) == sampleKeys)
        }

        let active = try #require(reestimates.first { isNull($0["undoneAt"]) })
        #expect(active["rideId"] as? String == rideID.uuidString)
        #expect(number(active, "reestimateIndex") == 1)
        #expect(active["mode"] as? String == "minutesOnly")

        let undone = try #require(reestimates.first { !isNull($0["undoneAt"]) })
        #expect(number(undone, "reestimateIndex") == 2)
        #expect(date(undone, "undoneAt") == undoneAt)

        let pauses = try rows(object, "pauses")
        #expect(pauses.count == 1)
        #expect(date(pauses[0], "undoneAt") == undoneAt)
    }

    @Test func exportJSON_sealLuxuryAndLegacyTierOnArrivedRide() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let ticket = Ticket(title: "定時", estimatedSeconds: 1_800)
        context.insert(ticket)
        let session = WorkSession(startedAt: PDCAFixture.dayStart, estimatedSecondsAtStart: 1_800, ticket: ticket)
        session.endedAt = PDCAFixture.dayStart.addingTimeInterval(1_780)
        session.outcome = .arrived
        session.accumulatedActiveSeconds = 1_480
        session.reestimateEvents = [
            ReestimateEventRecord(
                reestimateIndex: 1,
                trigger: .manual,
                surface: .iphonePortrait,
                input: .touch,
                promptId: ReestimatePromptID.positionV1,
                mode: .positionReport,
                committedAt: PDCAFixture.dayStart.addingTimeInterval(600),
                activeSeconds: 600,
                overrunSeconds: 0,
                progressAnswer: 0.4,
                committedRemainingSeconds: 900,
                shownBandLowSeconds: nil,
                shownBandHighSeconds: nil,
                detailsOpened: false,
                declaration: .adjust,
                projectedTotalSeconds: 1_500
            ),
        ]
        context.insert(session)
        try context.save()

        let rides = try rows(
            try jsonObject(try PDCAExport.jsonData(in: context, exportedAt: PDCAFixture.exportedAt)),
            "rides"
        )
        let ride = try #require(rides.first)
        #expect(ride["sealLuxury"] as? Double == 0.54)
        #expect(ride["onTimeSealTier"] as? String == "earlyReestimate")

        let reestimates = try rows(
            try jsonObject(try PDCAExport.jsonData(in: context, exportedAt: PDCAFixture.exportedAt)),
            "reestimates"
        )
        #expect(reestimates.count == 1)
        #expect(reestimates[0]["declaration"] as? String == "adjust")
        #expect(number(reestimates[0], "projectedTotalSeconds") == 1_500)
    }

    @Test func reestimateEvents_decodeWithoutNewOptionalFields() throws {
        let id = UUID()
        let json = """
        [{"id":"\(id.uuidString)","reestimateIndex":1,"trigger":"manual","surface":"iphonePortrait",\
        "input":"touch","promptId":"reestimate.progress.v1","mode":"progress","committedAt":"2026-01-01T00:00:00Z",\
        "activeSeconds":120,"overrunSeconds":0,"committedRemainingSeconds":480,"detailsOpened":false,\
        "remoteWillExtendReceived":false}]
        """
        let session = WorkSession(startedAt: .now, estimatedSecondsAtStart: 600)
        session.reestimateEventsJSON = json
        #expect(session.reestimateEvents.count == 1)
        #expect(session.reestimateEvents[0].declaration == nil)
        #expect(session.reestimateEvents[0].projectedTotalSeconds == nil)
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

    @Test func exportJSON_addsNextRideColumnsWithoutExperimentPhases() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(now: start)
        try manager.startService()
        let riding = try SessionManagerFixtures.makeTicket(context, title: "今", seconds: 600)
        let next = try SessionManagerFixtures.makeTicket(context, title: "次", seconds: 900)
        try manager.board(ticket: riding)
        let arrivedID = try #require(manager.activeSession?.id)
        try manager.reserveNextRide(ticket: next, via: .riding)
        try manager.arrive()
        clock.advance(by: 12)
        try manager.recordArrivalStamp(sessionID: arrivedID, action: .nextRide)
        try manager.boardFromArrivalSwipe(ticketID: next.id)
        let nextRideID = try #require(manager.activeSession?.id)

        let object = try jsonObject(try PDCAExport.jsonData(in: context, exportedAt: start))
        #expect(object["experimentPhases"] == nil)
        let tickets = try rows(object, "tickets")
        let rides = try rows(object, "rides")
        let reserved = try #require(row(tickets, id: next.id))
        let arrived = try #require(row(rides, id: arrivedID))
        let swiped = try #require(row(rides, id: nextRideID))

        #expect(date(reserved, "reservedAt") == start)
        #expect(reserved["reservedFromRideId"] as? String == arrivedID.uuidString)
        #expect(reserved["reservedVia"] as? String == "riding")
        #expect(arrived["arrivalAction"] as? String == "nextRide")
        #expect(date(arrived, "arrivalStampedAt") == start.addingTimeInterval(12))
        #expect(arrived["startedFrom"] as? String == "other")
        #expect(arrived["outcome"] as? String == "arrived")
        #expect(swiped["startedFrom"] as? String == "arrivalSwipe")
        #expect(isNull(swiped["arrivalAction"]))
        #expect(isNull(swiped["arrivalStampedAt"]))
    }

    @Test func exportJSON_writesRawPauseReadingsAndLeavesRideTime() throws {
        let fixture = try PDCAFixture.make()
        let context = fixture.context
        let pauses = try context.fetch(FetchDescriptor<SessionPause>())
        let recorded = try #require(pauses.first { $0.id == fixture.pauseID })
        recorded.heldByRaw = "timetable"
        recorded.pausedOnRaw = "mac"
        recorded.heldByInferred = true
        recorded.macSampledSeconds = 600
        recorded.macActiveSeconds = 480
        recorded.promptedAt = PDCAFixture.dayStart.addingTimeInterval(700)
        recorded.promptAnswerRaw = "keepPaused"

        let userPause = SessionPause(
            startedAt: PDCAFixture.dayStart.addingTimeInterval(910),
            endedAt: PDCAFixture.dayStart.addingTimeInterval(1_200),
            session: try #require(context.fetch(FetchDescriptor<WorkSession>()).first { $0.id == fixture.resumedRideID })
        )
        userPause.heldByRaw = "user"
        userPause.pausedOnRaw = "iphone"
        userPause.heldByInferred = false
        userPause.macSampledSeconds = 300
        userPause.macActiveSeconds = 300
        userPause.promptAnswerRaw = "none"
        context.insert(userPause)

        let sessions = try context.fetch(FetchDescriptor<WorkSession>())
        let resumed = try #require(sessions.first { $0.id == fixture.resumedRideID })
        let active = resumed.accumulatedActiveSeconds
        resumed.timetableHeld = false
        resumed.nudgeEvents = [
            NudgeEventRecord(
                stage: "estimate",
                firedAt: PDCAFixture.dayStart.addingTimeInterval(1_300),
                surface: "iphone",
                rang: true,
                skipped: false,
                cancelledAt: nil
            ),
            NudgeEventRecord(
                stage: "gap1",
                firedAt: PDCAFixture.dayStart.addingTimeInterval(2_100),
                surface: "mac",
                rang: false,
                skipped: true,
                cancelledAt: PDCAFixture.dayStart.addingTimeInterval(2_200)
            ),
        ]
        resumed.checkInAnswers = [
            CheckInAnswerRecord(
                kind: .overrun,
                answer: .stillOnIt,
                answeredAt: PDCAFixture.dayStart.addingTimeInterval(1_300),
                answeredOn: "iphone",
                answeredStage: "estimate"
            ),
            CheckInAnswerRecord(
                kind: .gap,
                answer: .board,
                answeredAt: PDCAFixture.dayStart.addingTimeInterval(2_200),
                answeredOn: "mac",
                answeredStage: "gap1"
            ),
        ]
        try context.save()

        let object = try jsonObject(try fixture.jsonData())
        #expect(object["schema"] as? String == "todotrain.pdca.v0")
        let rides = try rows(object, "rides")
        let ride = try #require(row(rides, id: fixture.resumedRideID))
        #expect(number(ride, "accumulatedActiveSeconds") == Int(active))
        #expect(number(ride, "pauseInputSeconds") == 300)
        #expect(ride["excludedFromForecast"] as? Bool == false)
        #expect(ride["timetableHeld"] as? Bool == false)

        let pauseRows = try rows(object, "pauses")
        let timetable = try #require(row(pauseRows, id: fixture.pauseID))
        #expect(timetable["heldBy"] as? String == "timetable")
        #expect(timetable["pausedOn"] as? String == "mac")
        #expect(timetable["heldByInferred"] as? Bool == true)
        #expect(number(timetable, "macSampledSeconds") == 600)
        #expect(number(timetable, "macActiveSeconds") == 480)
        #expect(date(timetable, "promptedAt") == PDCAFixture.dayStart.addingTimeInterval(700))
        #expect(timetable["promptAnswer"] as? String == "keepPaused")
        let user = try #require(row(pauseRows, id: userPause.id))
        #expect(user["heldBy"] as? String == "user")
        #expect(user["promptAnswer"] as? String == "none")
        #expect(isNull(user["promptedAt"]))

        let nudges = try rows(object, "nudges")
        expectExactKeys(nudges, PDCAContract.nudgeKeys)
        #expect(nudges.count == 2)
        #expect(nudges[0]["stage"] as? String == "estimate")
        #expect(nudges[0]["rang"] as? Bool == true)
        #expect(nudges[0]["skipped"] as? Bool == false)
        #expect(isNull(nudges[0]["cancelledAt"]))
        #expect(nudges[1]["stage"] as? String == "gap1")
        #expect(nudges[1]["surface"] as? String == "mac")
        #expect(date(nudges[1], "cancelledAt") == PDCAFixture.dayStart.addingTimeInterval(2_200))

        let checkIns = try rows(object, "checkIns")
        let overrun = try #require(checkIns.first { $0["kind"] as? String == "overrun" })
        #expect(overrun["answer"] as? String == "stillOnIt")
        #expect(overrun["answeredStage"] as? String == "estimate")
        #expect(overrun["answeredOn"] as? String == "iphone")
        let boarded = try #require(checkIns.first { $0["answer"] as? String == "board" })
        #expect(boarded["kind"] as? String == "gap")
        #expect(boarded["answeredStage"] as? String == "gap1")

        var keys = Set<String>()
        collectKeys(object, into: &keys)
        #expect(keys.isDisjoint(with: ["pauseInputRatio", "inputShare", "ratio", "percent"]))
    }

    @Test func exportJSON_excludesForecastWhenUserInputIsLongAndLarge() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let session = WorkSession(
            startedAt: PDCAFixture.dayStart,
            estimatedSecondsAtStart: 1_200
        )
        session.endedAt = PDCAFixture.dayStart.addingTimeInterval(1_000)
        session.accumulatedActiveSeconds = 1_000
        session.outcome = .arrived
        context.insert(session)
        let pause = SessionPause(
            startedAt: PDCAFixture.dayStart,
            endedAt: PDCAFixture.dayStart.addingTimeInterval(400),
            session: session
        )
        pause.heldByRaw = "user"
        pause.macSampledSeconds = 400
        pause.macActiveSeconds = 400
        context.insert(pause)
        try context.save()

        let ride = try #require(row(try rows(
            try jsonObject(try PDCAExport.jsonData(in: context, exportedAt: PDCAFixture.exportedAt)),
            "rides"
        ), id: session.id))
        #expect(number(ride, "accumulatedActiveSeconds") == 1_000)
        #expect(number(ride, "pauseInputSeconds") == 400)
        #expect(ride["excludedFromForecast"] as? Bool == true)
    }
}

@MainActor
private struct PDCAFixture {
    static let secrets = [
        "SECRET_TICKET_TITLE_ZX9",
        "SECRET_TAG_NAME_ZX9",
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
    var tagID: UUID
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

        let tagID = UUID()
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
        let tag = Tag(id: tagID, name: "SECRET_TAG_NAME_ZX9", colorHex: "#SECRETTAG")
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
                reason: "作業増",
                createdAt: dayStart.addingTimeInterval(500),
                workingSeconds: 1_100,
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
            tagID: tagID,
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
        "nudges",
        "reestimates",
        "timetableBlocks",
        "timetableGuards",
        "passengerRides",
        "passengerSummary",
        "build",
        "pairedBuild",
    ]

    static let arrayKeys: [String] = [
        "serviceDays",
        "tickets",
        "rides",
        "pauses",
        "extensions",
        "lineages",
        "checkIns",
        "nudges",
        "reestimates",
        "timetableBlocks",
        "timetableGuards",
        "passengerRides",
    ]

    static let serviceDayKeys: Set<String> = ["id", "startedAt", "endedAt", "calendarDayKey"]
    static let ticketKeys: Set<String> = [
        "id", "createdAt", "dueDate", "closedAt", "closureKind",
        "estimatedSeconds", "tagCount", "rideCount",
        "reservedAt", "reservedFromRideId", "reservedVia",
    ]
    static let rideKeys: Set<String> = [
        "id", "ticketId", "startedAt", "endedAt", "accumulatedActiveSeconds",
        "estimatedSecondsAtStart", "budgetSecondsAtStart",
        "currentBudgetSeconds", "preArrivalIdleSeconds", "outcome",
        "overtimeResolution", "timetableHeld", "checkInFiredCount",
        "arrivalAction", "arrivalStampedAt", "startedFrom",
        "pauseInputSeconds", "excludedFromForecast",
        "tagIds", "ordinalInDay", "cumulativeActiveSecondsBefore",
        "secondsSincePreviousArrival", "previousRideId", "nextRideId",
        "issueToDepartSeconds", "batchId", "slackToNextTimetableBlockSeconds",
        "lineageGroupId", "similarityCandidates",
        "judgedEstimateSource", "judgmentBandHalfWidthSeconds", "arrivalJudgement",
        "onTimeSealTier", "sealLuxury", "stampSeason", "stampTimeOfDay",
    ]
    static let similarityCandidateKeys: Set<String> = [
        "rideId", "score", "titleNGram", "tag", "lineage", "hourBand", "dayKind",
    ]
    static let pauseKeys: Set<String> = [
        "id", "rideId", "startedAt", "endedAt",
        "heldBy", "pausedOn", "heldByInferred",
        "macSampledSeconds", "macActiveSeconds", "promptedAt", "promptAnswer",
        "undoneAt",
    ]
    static let nudgeKeys: Set<String> = [
        "rideId", "stage", "firedAt", "surface", "rang", "skipped", "cancelledAt",
    ]
    static let extensionKeys: Set<String> = [
        "id", "rideId", "addedSeconds", "createdAt", "workingSeconds", "reason",
    ]
    static let lineageKeys: Set<String> = [
        "id", "kind", "createdAt", "fromRideId", "parentTicketId", "childTicketId", "aiGenerated",
    ]
    static let checkInKeys: Set<String> = ["rideId", "kind", "answer", "answeredAt"]
    static let reestimateKeys: Set<String> = [
        "rideId", "reestimateIndex", "trigger", "surface", "input", "promptId", "mode",
        "committedAt", "activeSeconds", "overrunSeconds", "progressAnswer",
        "committedRemainingSeconds", "shownBandLowSeconds", "shownBandHighSeconds",
        "detailsOpened", "undoneAt", "remoteWillExtendReceived",
        "declaration", "projectedTotalSeconds",
    ]
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

private func double(_ row: [String: Any], _ key: String) -> Double? {
    (row[key] as? NSNumber)?.doubleValue
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
