//
//  PDCAExport.swift
//  Todo train
//
//  診断用の件数と時刻だけ。題名・理由・プロンプトは出さない。
//  乗客レーンも同契約: 題名・本文・deviceId は出さない。無視した offer は記録しないので件数も出さない。
//

import Foundation
import SwiftData

nonisolated enum PDCAExport {
    static let schema = "todotrain.pdca.v0"

    struct Document: Encodable {
        var schema: String
        var exportedAt: Date
        var serviceDays: [ServiceDayRow]
        var tickets: [TicketRow]
        var rides: [RideRow]
        var pauses: [PauseRow]
        var extensions: [ExtensionRow]
        var lineages: [LineageRow]
        var checkIns: [CheckInRow]
        var timetableBlocks: [TimetableBlockRow]
        var timetableGuards: [TimetableGuardRow]
        var passengerRides: [PassengerRideRow]
        var passengerSummary: PassengerSummaryRow
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
        /// 入る運行がなければキーごと省く。
        var serviceDayId: UUID?
    }

    struct PauseRow: Encodable {
        var id: UUID
        var rideId: UUID
        var startedAt: Date
        var endedAt: PDCANull<Date>
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
    static func jsonData(in context: ModelContext, exportedAt: Date = .now) throws -> Data {
        try encode(make(in: context, exportedAt: exportedAt))
    }

    @MainActor
    static func make(in context: ModelContext, exportedAt: Date = .now) throws -> Document {
        make(
            exportedAt: exportedAt,
            serviceDays: try context.fetch(FetchDescriptor<ServiceDay>()),
            tickets: try context.fetch(FetchDescriptor<Ticket>()),
            sessions: try context.fetch(FetchDescriptor<WorkSession>()),
            lineages: try context.fetch(FetchDescriptor<TaskLineage>()),
            timetableBlocks: try context.fetch(FetchDescriptor<TimetableBlock>()),
            timetableGuards: try context.fetch(FetchDescriptor<TimetableGuard>()),
            passengerRides: try context.fetch(FetchDescriptor<PassengerRide>())
        )
    }

    @MainActor
    static func make(
        exportedAt: Date,
        serviceDays: [ServiceDay],
        tickets: [Ticket],
        sessions: [WorkSession],
        lineages: [TaskLineage],
        timetableBlocks: [TimetableBlock],
        timetableGuards: [TimetableGuard],
        passengerRides: [PassengerRide]
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
                    rideCount: rideCountByTicket[ticket.id] ?? 0
                )
            }

        let orderedSessions = sessions.sorted { byDateThenID($0.startedAt, $0.id, $1.startedAt, $1.id) }
        var rideRows: [RideRow] = []
        var pauseRows: [PauseRow] = []
        var extensionRows: [ExtensionRow] = []
        var checkInRows: [CheckInRow] = []
        rideRows.reserveCapacity(orderedSessions.count)

        for session in orderedSessions {
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
                    serviceDayId: matchingServiceDayID(startedAt: session.startedAt, serviceDays: serviceDays)
                )
            )
            for pause in session.pauses {
                pauseRows.append(
                    PauseRow(
                        id: pause.id,
                        rideId: session.id,
                        startedAt: pause.startedAt,
                        endedAt: PDCANull(pause.endedAt)
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
        }

        pauseRows.sort { byDateThenID($0.startedAt, $0.id, $1.startedAt, $1.id) }
        extensionRows.sort { byDateThenID($0.createdAt, $0.id, $1.createdAt, $1.id) }

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
            serviceDays: serviceDayRows,
            tickets: ticketRows,
            rides: rideRows,
            pauses: pauseRows,
            extensions: extensionRows,
            lineages: lineageRows,
            checkIns: checkInRows,
            timetableBlocks: blockRows,
            timetableGuards: guardRows,
            passengerRides: passengerRideRows,
            passengerSummary: passengerSummary
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
                answeredAt: record.answeredAt
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
