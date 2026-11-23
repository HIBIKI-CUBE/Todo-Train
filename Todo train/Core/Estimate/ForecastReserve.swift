//
//  ForecastReserve.swift
//  Todo train
//
//  到着予想の控えを、元の記録と計算方法の版から作り直す条件。
//  似たきっぷ探しと中央値は、写し取った値だけでメインスレッドの外で計算する。
//

import Foundation
import TodoTrainSync

nonisolated enum OpeningPanelArrivalPlace: Equatable, Sendable {
    case empty
    case previous(Int)
    case current(Int)

    var minutes: Int? {
        switch self {
        case .empty:
            nil
        case .previous(let minutes), .current(let minutes):
            minutes
        }
    }

    var isFaint: Bool {
        if case .previous = self { return true }
        return false
    }
}

nonisolated enum ForecastRefineResult: Sendable {
    case skipped
    case finished(Int?)
}

nonisolated struct ForecastPauseSource: Equatable, Sendable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var heldByRaw: String
    var macActiveSeconds: Double
    var undoneAt: Date?
}

nonisolated struct ForecastRideSource: Equatable, Sendable {
    var sessionID: UUID
    var ticketID: UUID?
    var title: String
    var tagIDs: [UUID]
    var startedAt: Date
    var endedAt: Date?
    var activeSeconds: TimeInterval
    var estimatedSeconds: Int
    var budgetSeconds: Int
    var extensionAddedSeconds: Int
    var extensionReasons: [String]
    var punctuality: ArrivalPunctuality
    var pauseInputSeconds: TimeInterval
    var outcomeArrived: Bool
    var pauses: [ForecastPauseSource]
}

nonisolated struct ForecastTicketSource: Equatable, Sendable {
    var id: UUID
    var title: String
    var tagIDs: [UUID]
    var tagNames: [String]
    var estimatedSeconds: Int
    var isOpen: Bool
    var sortOrder: Int
    var createdAt: Date
}

nonisolated struct ForecastLink: Equatable, Sendable {
    var parentID: UUID
    var childID: UUID
}

nonisolated struct RideSummaryPayload: Codable, Equatable, Sendable {
    var sessionID: UUID
    var ticketID: UUID?
    var title: String
    var tagIDs: [UUID]
    var startedAt: Date
    var activeSeconds: TimeInterval
    var estimatedSeconds: Int
    var budgetSeconds: Int
    var extensionAddedSeconds: Int
    var extensionReasons: [String]
    var punctuality: String
    var pauseInputSeconds: TimeInterval
    var pauseStamp: String
    var contentStamp: String
}

nonisolated struct ArrivalForecastPayload: Codable, Equatable, Sendable {
    var ticketID: UUID
    var title: String
    var tagIDs: [UUID]
    var medianMinutes: Int?
    var refinedMinutes: Int?
    var modelRefined: Bool
    var poolStamp: String

    var shownMinutes: Int? {
        guard let medianMinutes else { return nil }
        if modelRefined, let refinedMinutes { return refinedMinutes }
        return medianMinutes
    }
}

nonisolated struct StoredRideSummary: Equatable, Sendable {
    var sessionID: UUID
    var payload: RideSummaryPayload?
    var sourceUpdatedAt: Date
    var methodVersion: Int
    var readable: Bool
}

nonisolated struct StoredArrivalForecast: Equatable, Sendable {
    var ticketID: UUID
    var payload: ArrivalForecastPayload?
    var sourceUpdatedAt: Date
    var methodVersion: Int
    var readable: Bool

    var shownMinutes: Int? {
        guard readable else { return nil }
        return payload?.shownMinutes
    }
}

nonisolated struct ForecastSnapshot: Sendable {
    var tickets: [ForecastTicketSource]
    var rides: [ForecastRideSource]
    var links: [ForecastLink]
    var summaries: [StoredRideSummary]
    var arrivals: [StoredArrivalForecast]
    var now: Date
    var calendar: Calendar
}

nonisolated struct ForecastReservePlan: Equatable, Sendable {
    var poolStamp: String
    var summaryWrites: [UUID]
    var summaryDeletes: [UUID]
    var arrivalWrites: [UUID]
    var displayOrder: [UUID]
    var places: [UUID: OpeningPanelArrivalPlace]
    var arrivalSourceDates: [UUID: Date]
}

nonisolated enum ForecastReserve {
    static let rideSummaryMethod = 1
    static let arrivalMethod = 1

    static func isEligible(_ ride: ForecastRideSource) -> Bool {
        guard ride.outcomeArrived, ride.endedAt != nil else { return false }
        guard ride.activeSeconds >= EstimateHeuristic.immediateArrivalLimitSeconds else { return false }
        return !ForecastExclusion.excludes(
            pauseInputSeconds: ride.pauseInputSeconds,
            activeSeconds: ride.activeSeconds
        )
    }

    static func sortedTagIDs(_ ids: [UUID]) -> [UUID] {
        ids.sorted { $0.uuidString < $1.uuidString }
    }

    static func pauseStamp(_ pauses: [ForecastPauseSource]) -> String {
        pauses
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { pause in
                [
                    pause.id.uuidString,
                    dateToken(pause.startedAt),
                    pause.endedAt.map(dateToken) ?? "",
                    pause.heldByRaw,
                    milliToken(pause.macActiveSeconds),
                    pause.undoneAt.map(dateToken) ?? "",
                ].joined(separator: "|")
            }
            .joined(separator: ";")
    }

    static func contentStamp(_ ride: ForecastRideSource) -> String {
        [
            ride.sessionID.uuidString,
            ride.ticketID?.uuidString ?? "",
            ride.title,
            sortedTagIDs(ride.tagIDs).map(\.uuidString).joined(separator: ","),
            dateToken(ride.startedAt),
            milliToken(ride.activeSeconds),
            String(ride.estimatedSeconds),
            String(ride.budgetSeconds),
            String(ride.extensionAddedSeconds),
            ride.extensionReasons.joined(separator: "\u{1}"),
            punctualityCode(ride.punctuality),
            milliToken(ride.pauseInputSeconds),
            pauseStamp(ride.pauses),
        ].joined(separator: "\u{1}")
    }

    static func sourceUpdatedAt(_ ride: ForecastRideSource) -> Date {
        var latest = ride.endedAt ?? ride.startedAt
        if ride.startedAt > latest { latest = ride.startedAt }
        for pause in ride.pauses {
            let mark = pause.endedAt ?? pause.startedAt
            if mark > latest { latest = mark }
            if let undoneAt = pause.undoneAt, undoneAt > latest { latest = undoneAt }
        }
        return latest
    }

    static func summaryPayload(_ ride: ForecastRideSource) -> RideSummaryPayload {
        RideSummaryPayload(
            sessionID: ride.sessionID,
            ticketID: ride.ticketID,
            title: ride.title,
            tagIDs: sortedTagIDs(ride.tagIDs),
            startedAt: ride.startedAt,
            activeSeconds: ride.activeSeconds,
            estimatedSeconds: ride.estimatedSeconds,
            budgetSeconds: ride.budgetSeconds,
            extensionAddedSeconds: ride.extensionAddedSeconds,
            extensionReasons: ride.extensionReasons,
            punctuality: punctualityCode(ride.punctuality),
            pauseInputSeconds: ride.pauseInputSeconds,
            pauseStamp: pauseStamp(ride.pauses),
            contentStamp: contentStamp(ride)
        )
    }

    static func summaryNeedsRebuild(
        stored: StoredRideSummary?,
        source: ForecastRideSource,
        methodVersion: Int
    ) -> Bool {
        guard let stored, stored.readable, stored.methodVersion == methodVersion,
              let payload = stored.payload else {
            return true
        }
        return payload.contentStamp != contentStamp(source)
    }

    static func arrivalNeedsRebuild(
        stored: StoredArrivalForecast?,
        ticket: ForecastTicketSource,
        poolStamp: String,
        methodVersion: Int
    ) -> Bool {
        guard let stored, stored.readable, stored.methodVersion == methodVersion,
              let payload = stored.payload else {
            return true
        }
        if payload.title != ticket.title { return true }
        if payload.tagIDs != sortedTagIDs(ticket.tagIDs) { return true }
        if payload.poolStamp != poolStamp { return true }
        return false
    }

    /// 区切りより上の切符を先に、そのあと下の切符。未完了だけを渡す。
    static func orderedWork(rowIDs: [UUID], cut: Int, stale: Set<UUID>) -> [UUID] {
        let bounded = min(max(cut, 0), rowIDs.count)
        let ordered = Array(rowIDs.prefix(bounded)) + Array(rowIDs.dropFirst(bounded))
        return ordered.filter { stale.contains($0) }
    }

    static func plan(
        snapshot: ForecastSnapshot,
        rowOrder: [UUID],
        cut: Int,
        rideMethod: Int = rideSummaryMethod,
        arrivalMethod: Int = arrivalMethod
    ) -> ForecastReservePlan {
        let eligible = snapshot.rides.filter(isEligible)
        let eligibleIDs = Set(eligible.map(\.sessionID))
        var storedSummaries: [UUID: StoredRideSummary] = [:]
        for summary in snapshot.summaries where storedSummaries[summary.sessionID] == nil {
            storedSummaries[summary.sessionID] = summary
        }

        var summaryWrites: [UUID] = []
        for ride in eligible where summaryNeedsRebuild(
            stored: storedSummaries[ride.sessionID],
            source: ride,
            methodVersion: rideMethod
        ) {
            summaryWrites.append(ride.sessionID)
        }
        let summaryDeletes = snapshot.summaries
            .map(\.sessionID)
            .filter { !eligibleIDs.contains($0) }

        var poolParts: [String] = []
        poolParts.reserveCapacity(eligible.count)
        for ride in eligible {
            poolParts.append(
                "\(ride.sessionID.uuidString)\u{1}\(contentStamp(ride))\u{1}\(dateToken(sourceUpdatedAt(ride)))"
            )
        }
        poolParts.sort()
        let poolStamp = poolParts.joined(separator: "\u{2}")

        let openTickets = snapshot.tickets.filter(\.isOpen)
        var storedArrivals: [UUID: StoredArrivalForecast] = [:]
        for arrival in snapshot.arrivals where storedArrivals[arrival.ticketID] == nil {
            storedArrivals[arrival.ticketID] = arrival
        }
        let ticketsByID = Dictionary(uniqueKeysWithValues: snapshot.tickets.map { ($0.id, $0) })
        var stale: Set<UUID> = []
        for ticket in openTickets {
            if arrivalNeedsRebuild(
                stored: storedArrivals[ticket.id],
                ticket: ticket,
                poolStamp: poolStamp,
                methodVersion: arrivalMethod
            ) {
                stale.insert(ticket.id)
            }
        }

        var ordered = rowOrder.filter { ticketsByID[$0]?.isOpen == true }
        let seen = Set(ordered)
        let extras = openTickets
            .filter { !seen.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map(\.id)
        ordered.append(contentsOf: extras)
        let arrivalWrites = orderedWork(rowIDs: ordered, cut: cut, stale: stale)

        let poolDates = eligible.map(sourceUpdatedAt)
        let poolDate = poolDates.max()
        var places: [UUID: OpeningPanelArrivalPlace] = [:]
        var sourceDates: [UUID: Date] = [:]
        for id in ordered {
            let shown = storedArrivals[id]?.shownMinutes
            if stale.contains(id) {
                places[id] = shown.map { .previous($0) } ?? .empty
            } else {
                places[id] = shown.map { .current($0) } ?? .empty
            }
            sourceDates[id] = poolDate ?? ticketsByID[id]?.createdAt ?? .distantPast
        }

        return ForecastReservePlan(
            poolStamp: poolStamp,
            summaryWrites: summaryWrites,
            summaryDeletes: summaryDeletes,
            arrivalWrites: arrivalWrites,
            displayOrder: ordered,
            places: places,
            arrivalSourceDates: sourceDates
        )
    }

    static func encode<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode<T: Decodable>(_ type: T.Type, from text: String) -> T? {
        guard let data = text.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(T.self, from: data)
    }

    static func punctualityCode(_ punctuality: ArrivalPunctuality) -> String {
        switch punctuality {
        case .onTime: "onTime"
        case .early: "early"
        case .late: "late"
        case .notApplicable: "notApplicable"
        }
    }

    static func punctuality(from code: String) -> ArrivalPunctuality {
        switch code {
        case "onTime": .onTime
        case "early": .early
        case "late": .late
        default: .notApplicable
        }
    }

    private static func dateToken(_ date: Date) -> String {
        String(Int((date.timeIntervalSinceReferenceDate * 1000).rounded()))
    }

    private static func milliToken(_ seconds: TimeInterval) -> String {
        String(Int((seconds * 1000).rounded()))
    }
}

nonisolated enum ForecastComputation {
    nonisolated struct Input: Sendable {
        var ticket: ForecastTicketSource
        var rides: [ForecastRideSource]
        var ticketIDs: [UUID]
        var links: [ForecastLink]
        var now: Date
        var calendar: Calendar
    }

    nonisolated struct Prediction: Equatable, Sendable {
        var medianMinutes: Int?
        var context: ArrivalForecastContext?
    }

    nonisolated struct Output: Sendable {
        var ranOnMainThread: Bool
        var prediction: Prediction
    }

    static func evaluate(_ input: Input) async -> Output {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let output = Output(
                    ranOnMainThread: Thread.isMainThread,
                    prediction: predict(input)
                )
                continuation.resume(returning: output)
            }
        }
    }

    static func predict(_ input: Input) -> Prediction {
        let eligible = input.rides.filter(ForecastReserve.isEligible)
        let groups = RideSimilarity.lineageGroups(
            ticketIDs: input.ticketIDs,
            links: input.links.map { ($0.parentID, $0.childID) }
        )
        let queryGroup = groups[input.ticket.id] ?? input.ticket.id
        let features: [RideSimilarity.Ride] = eligible.map { ride in
            let rideGroup: UUID?
            if let ticketID = ride.ticketID, groups[ticketID] == queryGroup {
                rideGroup = queryGroup
            } else {
                rideGroup = ride.ticketID
            }
            return RideSimilarity.Ride(
                id: ride.sessionID,
                ticketID: ride.ticketID,
                title: ride.title,
                tagIDs: Set(ride.tagIDs),
                lineageGroupID: rideGroup,
                startedAt: ride.startedAt,
                activeSeconds: ride.activeSeconds
            )
        }
        let ranked = RideSimilarity.rank(
            query: RideSimilarity.Query(
                title: input.ticket.title,
                tagIDs: Set(input.ticket.tagIDs),
                ticketID: input.ticket.id,
                lineageGroupID: queryGroup,
                at: input.now
            ),
            rides: features,
            calendar: input.calendar
        )
        let chosen = RideSimilarity.ridesForEstimate(ranked)
        let predicted = BoardingForecast.predictedDuration(from: chosen.map(\.ride.activeSeconds))
        guard let predicted else {
            return Prediction(medianMinutes: nil, context: nil)
        }
        let chosenIDs = Set(chosen.map(\.ride.id))
        let pooled = eligible.filter { chosenIDs.contains($0.sessionID) }.map(arrivedRide)
        let context = ArrivalForecast.context(
            title: input.ticket.title,
            tagNames: input.ticket.tagNames,
            estimatedSeconds: input.ticket.estimatedSeconds,
            rides: pooled,
            pooled: pooled,
            medianMinutes: predicted.minutes,
            now: input.now,
            calendar: input.calendar
        )
        return Prediction(medianMinutes: predicted.minutes, context: context)
    }

    private static func arrivedRide(_ ride: ForecastRideSource) -> EstimateHeuristic.ArrivedRide {
        EstimateHeuristic.ArrivedRide(
            id: ride.sessionID,
            ticketID: ride.ticketID,
            title: ride.title,
            tagIDs: Set(ride.tagIDs),
            startedAt: ride.startedAt,
            activeSeconds: ride.activeSeconds,
            estimatedSeconds: ride.estimatedSeconds,
            budgetSeconds: ride.budgetSeconds,
            extensionAddedSeconds: ride.extensionAddedSeconds,
            extensionReasons: ride.extensionReasons,
            punctuality: ride.punctuality,
            pauseInputSeconds: ride.pauseInputSeconds
        )
    }
}
