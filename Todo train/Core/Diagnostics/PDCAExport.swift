//
//  PDCAExport.swift
//  Todo train
//
//  診断用の件数と時刻、停車と声掛けの生の記録。題名・理由・プロンプトは出さない。
//  乗客レーンも同契約: 題名・本文・deviceId は出さない。無視した offer は記録しないので件数も出さない。
//  識別子 todotrain.pdca.v0 は上げない。足した欄は、古い書き出しには無い。
//  走行時間は書き出しても値を変えない。割合の欄は足さない。
//  確度の評価欄も書き出すときに計算する。題名の文字とタグの名前は入れない。
//

import Foundation
import SwiftData
import TodoTrainSync

nonisolated enum PDCAExport {
    static let schema = "todotrain.pdca.v0"

    struct Document: Encodable {
        var schema: String
        var exportedAt: Date
        var build: BuildRow
        /// 最後に Mac から受け取ったビルド。まだ無いときは null。
        var pairedBuild: PDCANull<PairedBuildRow>
        var serviceDays: [ServiceDayRow]
        var tickets: [TicketRow]
        var rides: [RideRow]
        var pauses: [PauseRow]
        var extensions: [ExtensionRow]
        var lineages: [LineageRow]
        var checkIns: [CheckInRow]
        var nudges: [NudgeRow]
        var timetableBlocks: [TimetableBlockRow]
        var timetableGuards: [TimetableGuardRow]
        var passengerRides: [PassengerRideRow]
        var passengerSummary: PassengerSummaryRow
    }

    struct BuildRow: Encodable, Equatable {
        var sha: String
        var branch: String
        var dirty: Bool
        var builtAt: String
        var schemaVersion: String
        var marketingVersion: String

        @MainActor
        static var current: BuildRow {
            let marketing = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            return BuildRow(
                sha: BuildInfo.sha,
                branch: BuildInfo.branch,
                dirty: BuildInfo.dirty,
                builtAt: BuildInfo.builtAt,
                schemaVersion: StoreSchemaVersion.wire,
                marketingVersion: marketing
            )
        }
    }

    struct PairedBuildRow: Encodable, Equatable {
        var sha: String
        var dirty: Bool
        var schema: String
        var builtAt: String
    }

    struct ServiceDayRow: Encodable {
        var id: UUID
        var startedAt: Date
        var endedAt: PDCANull<Date>
        var calendarDayKey: String
    }

    struct TicketRow: Encodable {
        var id: UUID
        var createdAt: Date
        var dueDate: PDCANull<Date>
        var closedAt: PDCANull<Date>
        var closureKind: PDCANull<String>
        var estimatedSeconds: Int
        var tagCount: Int
        var rideCount: Int
        var reservedAt: PDCANull<Date>
        var reservedFromRideId: PDCANull<UUID>
        var reservedVia: PDCANull<String>
    }

    struct RideRow: Encodable {
        var id: UUID
        var ticketId: PDCANull<UUID>
        var startedAt: Date
        var endedAt: PDCANull<Date>
        var accumulatedActiveSeconds: TimeInterval
        var estimatedSecondsAtStart: Int
        var budgetSecondsAtStart: Int
        var outcome: PDCANull<String>
        var overtimeResolution: PDCANull<String>
        var timetableHeld: Bool
        var checkInFiredCount: Int
        var arrivalAction: PDCANull<String>
        var arrivalStampedAt: PDCANull<Date>
        var startedFrom: String
        /// 入る運行がなければキーごと省く。
        var serviceDayId: UUID?
        /// `heldBy == user` の停車に残っている `macActiveSeconds` の合計。
        var pauseInputSeconds: TimeInterval
        /// 予測の到着から外す。走行時間はそのまま。
        var excludedFromForecast: Bool
        /// 切符のタグ UUID。名前は出さない。切符が無ければ空。
        var tagIds: [UUID]
        /// その運行の何本目か。運行に入らなければ null。
        var ordinalInDay: PDCANull<Int>
        /// 同じ運行で、それより前の乗車の走行時間の合計。運行に入らなければ null。
        var cumulativeActiveSecondsBefore: PDCANull<TimeInterval>
        /// 直前の乗車の終わりから発車までの秒。終わりが無い、または直前が無ければ null。
        var secondsSincePreviousArrival: PDCANull<TimeInterval>
        var previousRideId: PDCANull<UUID>
        var nextRideId: PDCANull<UUID>
        /// 切符の `createdAt` から発車までの秒。切符が無ければ null。
        var issueToDepartSeconds: PDCANull<TimeInterval>
        /// 発券が 15 分以内で続く切符の組。識別子は組で一番早い切符の id。
        var batchId: PDCANull<UUID>
        /// 発車以降に始まる有効な時刻表ブロックまでの秒。題名は読まない。無ければ null。
        var slackToNextTimetableBlockSeconds: PDCANull<TimeInterval>
        /// 乗り継ぎでつながる切符の組。孤立した切符は自分の id。切符が無ければ null。
        var lineageGroupId: PDCANull<UUID>
        /// それより前の、予測に使える乗車のうち点数の上位。文字は入れない。
        var similarityCandidates: [SimilarityCandidateRow]
    }

    struct SimilarityCandidateRow: Encodable, Equatable {
        var rideId: UUID
        var score: Double
        var titleNGram: Double
        var tag: Double
        var lineage: Double
        var hourBand: Double
        var dayKind: Double
    }

    struct PauseRow: Encodable {
        var id: UUID
        var rideId: UUID
        var startedAt: Date
        var endedAt: PDCANull<Date>
        /// 保存された理由。空のままなら null。`timetableHeld` からは作らない。
        var heldBy: PDCANull<String>
        var pausedOn: PDCANull<String>
        var heldByInferred: Bool
        var macSampledSeconds: Double
        var macActiveSeconds: Double
        var promptedAt: PDCANull<Date>
        /// `resume` / `keepPaused` / `none`、または保存されたままの文字列。
        var promptAnswer: PDCANull<String>
    }

    struct ExtensionRow: Encodable {
        var id: UUID
        var rideId: UUID
        var addedSeconds: Int
        var createdAt: Date
    }

    struct LineageRow: Encodable {
        var id: UUID
        var kind: String
        var createdAt: Date
        var fromRideId: PDCANull<UUID>
        var parentTicketId: PDCANull<UUID>
        var childTicketId: PDCANull<UUID>
        var aiGenerated: Bool
    }

    struct CheckInRow: Encodable {
        var rideId: UUID
        var kind: String
        var answer: String
        var answeredAt: Date
        var answeredStage: String?
        var answeredOn: String?

        enum CodingKeys: String, CodingKey {
            case rideId, kind, answer, answeredAt, answeredStage, answeredOn
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(rideId, forKey: .rideId)
            try container.encode(kind, forKey: .kind)
            try container.encode(answer, forKey: .answer)
            try container.encode(answeredAt, forKey: .answeredAt)
            try container.encodeIfPresent(answeredStage, forKey: .answeredStage)
            try container.encodeIfPresent(answeredOn, forKey: .answeredOn)
        }
    }

    struct NudgeRow: Encodable {
        var rideId: UUID
        var stage: String
        var firedAt: Date
        var surface: String
        var rang: Bool
        var skipped: Bool
        var cancelledAt: PDCANull<Date>
    }

    struct TimetableBlockRow: Encodable {
        var id: UUID
        var startsAt: Date
        var endsAt: Date
        var source: String
        var adoptionScope: String
        var isCancelled: Bool
        var needsReview: Bool
    }

    struct TimetableGuardRow: Encodable {
        var id: UUID
        var rideId: UUID
        var blockId: UUID
        var notifiedAt: Date
        var protectionBoundary: Date
        var resolvedAt: PDCANull<Date>
        var invalidatedAt: PDCANull<Date>
    }

    struct PassengerRideRow: Encodable {
        var id: UUID
        var boardedAt: Date
        var endedAt: PDCANull<Date>
        var endReason: PDCANull<String>
        var source: String
        var intervalStart: Date
        var intervalEnd: Date
        /// `endedAt` があるときだけ `endedAt - boardedAt`。
        var aboardSeconds: PDCANull<TimeInterval>
    }

    struct PassengerSummaryRow: Encodable {
        /// 乗車記録の件数（`PassengerRide` の総数）。
        var aboardCount: Int
        /// まだ `endedAt` がない乗車。
        var openAboardCount: Int
        var endReasonArrived: Int
        var endReasonEmergency: Int
        var endReasonCancelled: Int
        /// 終了済み乗車の aboard 秒の合計。
        var totalAboardSeconds: TimeInterval
        var minAboardSeconds: PDCANull<Int>
        var maxAboardSeconds: PDCANull<Int>
    }

    @MainActor
    static func jsonData(
        in context: ModelContext,
        exportedAt: Date = .now,
        build: BuildRow? = nil,
        pairedBuild: PairedBuildRow? = nil,
        calendar: Calendar = .current
    ) throws -> Data {
        try encode(make(
            in: context,
            exportedAt: exportedAt,
            build: build,
            pairedBuild: pairedBuild,
            calendar: calendar
        ))
    }

    @MainActor
    static func make(
        in context: ModelContext,
        exportedAt: Date = .now,
        build: BuildRow? = nil,
        pairedBuild: PairedBuildRow? = nil,
        calendar: Calendar = .current
    ) throws -> Document {
        make(
            exportedAt: exportedAt,
            build: build,
            pairedBuild: pairedBuild,
            serviceDays: try context.fetch(FetchDescriptor<ServiceDay>()),
            tickets: try context.fetch(FetchDescriptor<Ticket>()),
            sessions: try context.fetch(FetchDescriptor<WorkSession>()),
            lineages: try context.fetch(FetchDescriptor<TaskLineage>()),
            timetableBlocks: try context.fetch(FetchDescriptor<TimetableBlock>()),
            timetableGuards: try context.fetch(FetchDescriptor<TimetableGuard>()),
            passengerRides: try context.fetch(FetchDescriptor<PassengerRide>()),
            calendar: calendar
        )
    }

    @MainActor
    static func make(
        exportedAt: Date,
        build: BuildRow? = nil,
        pairedBuild: PairedBuildRow? = nil,
        serviceDays: [ServiceDay],
        tickets: [Ticket],
        sessions: [WorkSession],
        lineages: [TaskLineage],
        timetableBlocks: [TimetableBlock],
        timetableGuards: [TimetableGuard],
        passengerRides: [PassengerRide],
        calendar: Calendar = .current
    ) -> Document {
        var rideCountByTicket: [UUID: Int] = [:]
        for session in sessions {
            guard let ticketID = session.ticket?.id else { continue }
            rideCountByTicket[ticketID, default: 0] += 1
        }

        let serviceDayRows = serviceDays
            .sorted { byDateThenID($0.startedAt, $0.id, $1.startedAt, $1.id) }
            .map { day in
                ServiceDayRow(
                    id: day.id,
                    startedAt: day.startedAt,
                    endedAt: PDCANull(day.endedAt),
                    calendarDayKey: day.calendarDayKey
                )
            }

        let ticketRows = tickets
            .sorted { byDateThenID($0.createdAt, $0.id, $1.createdAt, $1.id) }
            .map { ticket in
                TicketRow(
                    id: ticket.id,
                    createdAt: ticket.createdAt,
                    dueDate: PDCANull(ticket.dueDate),
                    closedAt: PDCANull(ticket.closedAt),
                    closureKind: PDCANull(ticket.closureKind?.rawValue),
                    estimatedSeconds: ticket.estimatedSeconds,
                    tagCount: ticket.tags.count,
                    rideCount: rideCountByTicket[ticket.id] ?? 0,
                    reservedAt: PDCANull(ticket.reservedAt),
                    reservedFromRideId: PDCANull(ticket.reservedFromRideId),
                    reservedVia: PDCANull(ticket.reservedVia?.rawValue)
                )
            }

        let orderedSessions = sessions.sorted { byDateThenID($0.startedAt, $0.id, $1.startedAt, $1.id) }
        let annotations = rideAnnotations(
            sessions: orderedSessions,
            tickets: tickets,
            lineages: lineages,
            timetableBlocks: timetableBlocks,
            serviceDays: serviceDays,
            calendar: calendar
        )
        var rideRows: [RideRow] = []
        var pauseRows: [PauseRow] = []
        var extensionRows: [ExtensionRow] = []
        var checkInRows: [CheckInRow] = []
        var nudgeRows: [NudgeRow] = []
        rideRows.reserveCapacity(orderedSessions.count)

        for session in orderedSessions {
            let pauseInput = ForecastExclusion.pauseInputSeconds(
                session.pauses.map {
                    PauseInputReading(heldByRaw: $0.heldByRaw, macActiveSeconds: $0.macActiveSeconds)
                }
            )
            let note = annotations[session.id]
            rideRows.append(
                RideRow(
                    id: session.id,
                    ticketId: PDCANull(session.ticket?.id),
                    startedAt: session.startedAt,
                    endedAt: PDCANull(session.endedAt),
                    accumulatedActiveSeconds: session.accumulatedActiveSeconds,
                    estimatedSecondsAtStart: session.estimatedSecondsAtStart,
                    budgetSecondsAtStart: session.budgetSecondsAtStart,
                    outcome: PDCANull(session.outcome?.rawValue),
                    overtimeResolution: PDCANull(session.overtimeResolution?.rawValue),
                    timetableHeld: session.timetableHeld,
                    checkInFiredCount: session.checkInFiredCount,
                    arrivalAction: PDCANull(session.arrivalAction?.rawValue),
                    arrivalStampedAt: PDCANull(session.arrivalStampedAt),
                    startedFrom: session.startedFrom.rawValue,
                    serviceDayId: matchingServiceDayID(startedAt: session.startedAt, serviceDays: serviceDays),
                    pauseInputSeconds: pauseInput,
                    excludedFromForecast: ForecastExclusion.excludes(
                        pauseInputSeconds: pauseInput,
                        activeSeconds: session.accumulatedActiveSeconds
                    ),
                    tagIds: note?.tagIds ?? [],
                    ordinalInDay: PDCANull(note?.ordinalInDay),
                    cumulativeActiveSecondsBefore: PDCANull(note?.cumulativeActiveSecondsBefore),
                    secondsSincePreviousArrival: PDCANull(note?.secondsSincePreviousArrival),
                    previousRideId: PDCANull(note?.previousRideId),
                    nextRideId: PDCANull(note?.nextRideId),
                    issueToDepartSeconds: PDCANull(note?.issueToDepartSeconds),
                    batchId: PDCANull(note?.batchId),
                    slackToNextTimetableBlockSeconds: PDCANull(note?.slackToNextTimetableBlockSeconds),
                    lineageGroupId: PDCANull(note?.lineageGroupId),
                    similarityCandidates: note?.similarityCandidates ?? []
                )
            )
            for pause in session.pauses {
                pauseRows.append(
                    PauseRow(
                        id: pause.id,
                        rideId: session.id,
                        startedAt: pause.startedAt,
                        endedAt: PDCANull(pause.endedAt),
                        heldBy: PDCANull(pause.heldByRaw),
                        pausedOn: PDCANull(pause.pausedOnRaw),
                        heldByInferred: pause.heldByInferred,
                        macSampledSeconds: pause.macSampledSeconds,
                        macActiveSeconds: pause.macActiveSeconds,
                        promptedAt: PDCANull(pause.promptedAt),
                        promptAnswer: PDCANull(pause.promptAnswerRaw)
                    )
                )
            }
            for item in session.extensions {
                extensionRows.append(
                    ExtensionRow(
                        id: item.id,
                        rideId: session.id,
                        addedSeconds: item.addedSeconds,
                        createdAt: item.createdAt
                    )
                )
            }
            checkInRows.append(contentsOf: checkIns(from: session.checkInAnswersJSON, rideId: session.id))
            nudgeRows.append(contentsOf: nudges(from: session))
        }

        pauseRows.sort { byDateThenID($0.startedAt, $0.id, $1.startedAt, $1.id) }
        extensionRows.sort { byDateThenID($0.createdAt, $0.id, $1.createdAt, $1.id) }
        nudgeRows.sort { lhs, rhs in
            if lhs.firedAt != rhs.firedAt { return lhs.firedAt < rhs.firedAt }
            if lhs.rideId != rhs.rideId { return lhs.rideId.uuidString < rhs.rideId.uuidString }
            return lhs.stage < rhs.stage
        }

        let lineageRows = lineages
            .sorted { byDateThenID($0.createdAt, $0.id, $1.createdAt, $1.id) }
            .map { lineage in
                LineageRow(
                    id: lineage.id,
                    kind: lineage.kind.rawValue,
                    createdAt: lineage.createdAt,
                    fromRideId: PDCANull(lineage.fromSessionID),
                    parentTicketId: PDCANull(lineage.parent?.id),
                    childTicketId: PDCANull(lineage.child?.id),
                    aiGenerated: lineage.aiGenerated
                )
            }

        let blockRows = timetableBlocks
            .sorted { byDateThenID($0.startsAt, $0.id, $1.startsAt, $1.id) }
            .map { block in
                TimetableBlockRow(
                    id: block.id,
                    startsAt: block.startsAt,
                    endsAt: block.endsAt,
                    source: block.source.rawValue,
                    adoptionScope: block.adoptionScope.rawValue,
                    isCancelled: block.isCancelled,
                    needsReview: block.needsReview
                )
            }

        let guardRows = timetableGuards
            .sorted { byDateThenID($0.notifiedAt, $0.id, $1.notifiedAt, $1.id) }
            .map { item in
                TimetableGuardRow(
                    id: item.id,
                    rideId: item.sessionID,
                    blockId: item.blockID,
                    notifiedAt: item.notifiedAt,
                    protectionBoundary: item.protectionBoundary,
                    resolvedAt: PDCANull(item.resolvedAt),
                    invalidatedAt: PDCANull(item.invalidatedAt)
                )
            }

        let passengerRideRows = passengerRides
            .sorted { byDateThenID($0.boardedAt, $0.id, $1.boardedAt, $1.id) }
            .map(passengerRideRow)
        let passengerSummary = passengerSummary(from: passengerRides)

        return Document(
            schema: schema,
            exportedAt: exportedAt,
            build: build ?? .current,
            pairedBuild: PDCANull(pairedBuild),
            serviceDays: serviceDayRows,
            tickets: ticketRows,
            rides: rideRows,
            pauses: pauseRows,
            extensions: extensionRows,
            lineages: lineageRows,
            checkIns: checkInRows,
            nudges: nudgeRows,
            timetableBlocks: blockRows,
            timetableGuards: guardRows,
            passengerRides: passengerRideRows,
            passengerSummary: passengerSummary
        )
    }

    private struct RideAnnotation {
        var tagIds: [UUID]
        var ordinalInDay: Int?
        var cumulativeActiveSecondsBefore: TimeInterval?
        var secondsSincePreviousArrival: TimeInterval?
        var previousRideId: UUID?
        var nextRideId: UUID?
        var issueToDepartSeconds: TimeInterval?
        var batchId: UUID?
        var slackToNextTimetableBlockSeconds: TimeInterval?
        var lineageGroupId: UUID?
        var similarityCandidates: [SimilarityCandidateRow]
    }

    @MainActor
    private static func rideAnnotations(
        sessions: [WorkSession],
        tickets: [Ticket],
        lineages: [TaskLineage],
        timetableBlocks: [TimetableBlock],
        serviceDays: [ServiceDay],
        calendar: Calendar
    ) -> [UUID: RideAnnotation] {
        let groups = RideSimilarity.lineageGroups(
            ticketIDs: tickets.map(\.id),
            links: lineages.compactMap { lineage in
                guard let parent = lineage.parent?.id, let child = lineage.child?.id else { return nil }
                return (parent, child)
            }
        )
        let batches = RideSimilarity.batchIDs(
            tickets.map { RideSimilarity.IssuedTicket(id: $0.id, createdAt: $0.createdAt) }
        )
        let blocks = timetableBlocks.map {
            RideSimilarity.Occupancy(
                id: $0.id,
                startsAt: $0.startsAt,
                endsAt: $0.endsAt,
                isCancelled: $0.isCancelled
            )
        }
        let slots = RideSimilarity.daySlots(sessions.map { session in
            RideSimilarity.DayRide(
                id: session.id,
                serviceDayID: matchingServiceDayID(startedAt: session.startedAt, serviceDays: serviceDays),
                startedAt: session.startedAt,
                endedAt: session.endedAt,
                activeSeconds: session.accumulatedActiveSeconds
            )
        })
        let eligibleIDs = Set(
            ForecastSample.eligible(
                EstimateHeuristic.arrivedRides(from: sessions, matchingAnyTagIDs: nil)
            ).map(\.id)
        )
        let features = sessions.map { feature(for: $0, groups: groups) }
        let pool = features.filter { eligibleIDs.contains($0.id) }
        let candidates = RideSimilarity.priorCandidates(for: features, among: pool, calendar: calendar)

        var notes: [UUID: RideAnnotation] = [:]
        notes.reserveCapacity(sessions.count)
        for session in sessions {
            let ticketID = session.ticket?.id
            let slot = slots[session.id]
            let tagIds = (session.ticket?.tags.map(\.id) ?? []).sorted { $0.uuidString < $1.uuidString }
            notes[session.id] = RideAnnotation(
                tagIds: tagIds,
                ordinalInDay: slot?.ordinal,
                cumulativeActiveSecondsBefore: slot?.cumulativeActiveSecondsBefore,
                secondsSincePreviousArrival: slot?.secondsSincePreviousArrival,
                previousRideId: slot?.previousRideID,
                nextRideId: slot?.nextRideID,
                issueToDepartSeconds: session.ticket.map {
                    session.startedAt.timeIntervalSince($0.createdAt)
                },
                batchId: ticketID.flatMap { batches[$0] },
                slackToNextTimetableBlockSeconds: RideSimilarity.slack(
                    departedAt: session.startedAt,
                    blocks: blocks
                ),
                lineageGroupId: ticketID.map { groups[$0] ?? $0 },
                similarityCandidates: (candidates[session.id] ?? []).map(candidateRow)
            )
        }
        return notes
    }

    @MainActor
    private static func feature(
        for session: WorkSession,
        groups: [UUID: UUID]
    ) -> RideSimilarity.Ride {
        let ticketID = session.ticket?.id
        return RideSimilarity.Ride(
            id: session.id,
            ticketID: ticketID,
            title: session.ticket?.title ?? "",
            tagIDs: Set(session.ticket?.tags.map(\.id) ?? []),
            lineageGroupID: ticketID.map { groups[$0] ?? $0 },
            startedAt: session.startedAt,
            activeSeconds: session.accumulatedActiveSeconds
        )
    }

    private static func candidateRow(_ scored: RideSimilarity.ScoredRide) -> SimilarityCandidateRow {
        SimilarityCandidateRow(
            rideId: scored.ride.id,
            score: scored.score,
            titleNGram: scored.cues.titleNGram,
            tag: scored.cues.tag,
            lineage: scored.cues.lineage,
            hourBand: scored.cues.hourBand,
            dayKind: scored.cues.dayKind
        )
    }

    private static func passengerRideRow(_ ride: PassengerRide) -> PassengerRideRow {
        let aboardSeconds: TimeInterval? = {
            guard let endedAt = ride.endedAt else { return nil }
            return max(0, endedAt.timeIntervalSince(ride.boardedAt))
        }()
        return PassengerRideRow(
            id: ride.id,
            boardedAt: ride.boardedAt,
            endedAt: PDCANull(ride.endedAt),
            endReason: PDCANull(ride.endReason?.rawValue),
            source: ride.source.rawValue,
            intervalStart: ride.intervalStart,
            intervalEnd: ride.intervalEnd,
            aboardSeconds: PDCANull(aboardSeconds)
        )
    }

    private static func passengerSummary(from rides: [PassengerRide]) -> PassengerSummaryRow {
        var arrived = 0
        var emergency = 0
        var cancelled = 0
        var open = 0
        var totalSeconds: TimeInterval = 0
        var completedDurations: [Int] = []

        for ride in rides {
            guard let endedAt = ride.endedAt else {
                open += 1
                continue
            }
            let seconds = max(0, Int(endedAt.timeIntervalSince(ride.boardedAt).rounded()))
            totalSeconds += TimeInterval(seconds)
            completedDurations.append(seconds)
            switch ride.endReason {
            case .arrived: arrived += 1
            case .emergency: emergency += 1
            case .cancelled: cancelled += 1
            case nil: break
            }
        }

        let minSeconds = completedDurations.min()
        let maxSeconds = completedDurations.max()
        return PassengerSummaryRow(
            aboardCount: rides.count,
            openAboardCount: open,
            endReasonArrived: arrived,
            endReasonEmergency: emergency,
            endReasonCancelled: cancelled,
            totalAboardSeconds: totalSeconds,
            minAboardSeconds: PDCANull(minSeconds),
            maxAboardSeconds: PDCANull(maxSeconds)
        )
    }

    static func encode(_ document: Document) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    /// `startedAt` が `[ServiceDay.startedAt, endedAt)` に入る運行。重なれば開始が遅い方。暦日キーでは選ばない。
    @MainActor
    private static func matchingServiceDayID(startedAt: Date, serviceDays: [ServiceDay]) -> UUID? {
        serviceDays
            .filter { day in
                let end = day.endedAt ?? .distantFuture
                return startedAt >= day.startedAt && startedAt < end
            }
            .max { lhs, rhs in
                if lhs.startedAt != rhs.startedAt {
                    return lhs.startedAt < rhs.startedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }?
            .id
    }

    @MainActor
    private static func checkIns(from json: String, rideId: UUID) -> [CheckInRow] {
        records(from: json).map { record in
            CheckInRow(
                rideId: rideId,
                kind: record.kind.rawValue,
                answer: record.answer.rawValue,
                answeredAt: record.answeredAt,
                answeredStage: record.answeredStage,
                answeredOn: record.answeredOn
            )
        }
    }

    private static func nudges(from session: WorkSession) -> [NudgeRow] {
        session.nudgeEvents.map { event in
            NudgeRow(
                rideId: session.id,
                stage: event.stage,
                firedAt: event.firedAt,
                surface: event.surface,
                rang: event.rang,
                skipped: event.skipped,
                cancelledAt: PDCANull(event.cancelledAt)
            )
        }
    }

    /// 配列ごと読めなければ要素ごとに読み、壊れた要素は捨てる。未知のキー（プロンプトなど）は残さない。
    @MainActor
    private static func records(from json: String) -> [CheckInAnswerRecord] {
        guard let data = json.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let records = try? decoder.decode([CheckInAnswerRecord].self, from: data) {
            return records
        }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return []
        }
        return raw.compactMap { element in
            guard JSONSerialization.isValidJSONObject(element),
                  let elementData = try? JSONSerialization.data(withJSONObject: element) else {
                return nil
            }
            return try? decoder.decode(CheckInAnswerRecord.self, from: elementData)
        }
    }

    private static func byDateThenID(_ lhsDate: Date, _ lhsID: UUID, _ rhsDate: Date, _ rhsID: UUID) -> Bool {
        if lhsDate != rhsDate { return lhsDate < rhsDate }
        return lhsID.uuidString < rhsID.uuidString
    }
}

nonisolated struct PDCANull<Value: Encodable>: Encodable {
    var value: Value?

    init(_ value: Value?) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value {
            try container.encode(value)
        } else {
            try container.encodeNil()
        }
    }
}
