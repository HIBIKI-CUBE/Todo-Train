//
//  ForecastReserveStore.swift
//  Todo train
//
//  控えの読み書き。SwiftData の走査は ModelActor、似たきっぷ探しはその外で行う。
//

import Foundation
import SwiftData
import TodoTrainSync

@ModelActor
actor ForecastReserveReader {
    func snapshot(now: Date, calendar: Calendar) -> ForecastSnapshot {
        let context = modelContext
        let tickets = (try? context.fetch(FetchDescriptor<Ticket>())) ?? []
        let sessions = (try? context.fetch(FetchDescriptor<WorkSession>())) ?? []
        let lineages = (try? context.fetch(FetchDescriptor<TaskLineage>())) ?? []
        let summaries = (try? context.fetch(FetchDescriptor<RideSummaryCache>())) ?? []
        let arrivals = (try? context.fetch(FetchDescriptor<ArrivalForecastCache>())) ?? []

        let ticketSources = tickets.map { ticket in
            ForecastTicketSource(
                id: ticket.id,
                title: ticket.title,
                tagIDs: ForecastReserve.sortedTagIDs(ticket.tags.map(\.id)),
                tagNames: ticket.tags.sorted { lhs, rhs in
                    if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                    return lhs.id.uuidString < rhs.id.uuidString
                }.map(\.name),
                estimatedSeconds: ticket.estimatedSeconds,
                isOpen: ticket.isOpen,
                sortOrder: ticket.sortOrder,
                createdAt: ticket.createdAt
            )
        }
        let rideSources = sessions.compactMap { session -> ForecastRideSource? in
            guard session.endedAt != nil, session.outcome == .arrived else { return nil }
            let reasons = session.extensions.compactMap { record -> String? in
                let reason = record.reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return reason.isEmpty ? nil : String(reason.prefix(40))
            }
            let pauses = session.pauses.map { pause in
                ForecastPauseSource(
                    id: pause.id,
                    startedAt: pause.startedAt,
                    endedAt: pause.endedAt,
                    heldByRaw: pause.heldByRaw ?? "",
                    macActiveSeconds: pause.macActiveSeconds,
                    undoneAt: pause.undoneAt
                )
            }
            return ForecastRideSource(
                sessionID: session.id,
                ticketID: session.ticket?.id,
                title: session.ticket?.title ?? "",
                tagIDs: ForecastReserve.sortedTagIDs(session.ticket?.tags.map(\.id) ?? []),
                startedAt: session.startedAt,
                endedAt: session.endedAt,
                activeSeconds: session.accumulatedActiveSeconds,
                estimatedSeconds: session.estimatedSecondsAtStart,
                budgetSeconds: session.activeBudgetSeconds,
                extensionAddedSeconds: session.extensions.reduce(0) { $0 + $1.addedSeconds },
                extensionReasons: reasons,
                punctuality: Punctuality.classify(session),
                pauseInputSeconds: ForecastExclusion.pauseInputSeconds(
                    session.pauses.map {
                        PauseInputReading(heldByRaw: $0.heldByRaw, macActiveSeconds: $0.macActiveSeconds)
                    }
                ),
                outcomeArrived: true,
                pauses: pauses
            )
        }
        let links = lineages.compactMap { lineage -> ForecastLink? in
            guard let parentID = lineage.parent?.id, let childID = lineage.child?.id else { return nil }
            return ForecastLink(parentID: parentID, childID: childID)
        }
        return ForecastSnapshot(
            tickets: ticketSources,
            rides: rideSources,
            links: links,
            summaries: summaries.map(Self.storedSummary),
            arrivals: arrivals.map(Self.storedArrival),
            now: now,
            calendar: calendar
        )
    }

    func replaceSummaries(
        _ payloads: [(RideSummaryPayload, Date)],
        deletes: [UUID],
        methodVersion: Int
    ) {
        let context = modelContext
        let existing = (try? context.fetch(FetchDescriptor<RideSummaryCache>())) ?? []
        var bySession: [UUID: [RideSummaryCache]] = [:]
        for item in existing {
            bySession[item.sessionID, default: []].append(item)
        }
        for id in Set(deletes) {
            for item in bySession[id] ?? [] {
                context.delete(item)
            }
            bySession[id] = nil
        }
        for (payload, updated) in payloads {
            guard let text = ForecastReserve.encode(payload) else { continue }
            let rows = bySession[payload.sessionID] ?? []
            let row = rows.first ?? RideSummaryCache(
                sessionID: payload.sessionID,
                payload: text,
                sourceUpdatedAt: updated,
                methodVersion: methodVersion
            )
            if rows.isEmpty {
                context.insert(row)
            }
            row.payload = text
            row.sourceUpdatedAt = updated
            row.methodVersion = methodVersion
            for extra in rows.dropFirst() {
                context.delete(extra)
            }
        }
        if context.hasChanges {
            try? context.save()
        }
    }

    func writeArrival(
        _ payload: ArrivalForecastPayload,
        sourceUpdatedAt: Date,
        methodVersion: Int
    ) {
        guard let text = ForecastReserve.encode(payload) else { return }
        let context = modelContext
        let existing = (try? context.fetch(FetchDescriptor<ArrivalForecastCache>())) ?? []
        let rows = existing.filter { $0.ticketID == payload.ticketID }
        let row = rows.first ?? ArrivalForecastCache(
            ticketID: payload.ticketID,
            payload: text,
            sourceUpdatedAt: sourceUpdatedAt,
            methodVersion: methodVersion
        )
        if rows.isEmpty {
            context.insert(row)
        }
        row.payload = text
        row.sourceUpdatedAt = sourceUpdatedAt
        row.methodVersion = methodVersion
        for extra in rows.dropFirst() {
            context.delete(extra)
        }
        if context.hasChanges {
            try? context.save()
        }
    }

    private static func storedSummary(_ model: RideSummaryCache) -> StoredRideSummary {
        StoredRideSummary(
            sessionID: model.sessionID,
            payload: ForecastReserve.decode(RideSummaryPayload.self, from: model.payload),
            sourceUpdatedAt: model.sourceUpdatedAt,
            methodVersion: model.methodVersion,
            readable: ForecastReserve.decode(RideSummaryPayload.self, from: model.payload) != nil
        )
    }

    private static func storedArrival(_ model: ArrivalForecastCache) -> StoredArrivalForecast {
        let payload = ForecastReserve.decode(ArrivalForecastPayload.self, from: model.payload)
        return StoredArrivalForecast(
            ticketID: model.ticketID,
            payload: payload,
            sourceUpdatedAt: model.sourceUpdatedAt,
            methodVersion: model.methodVersion,
            readable: payload != nil
        )
    }

}

@MainActor
enum ForecastReserveStore {
    static func savedByUs(_ notification: Notification) -> Bool {
        let keys = [
            ModelContext.NotificationKey.insertedIdentifiers,
            ModelContext.NotificationKey.updatedIdentifiers,
            ModelContext.NotificationKey.deletedIdentifiers,
        ]
        var sawReserve = false
        for key in keys {
            guard let identifiers = notification.userInfo?[key.rawValue] as? Set<PersistentIdentifier> else {
                continue
            }
            for identifier in identifiers {
                sawReserve = true
                let name = identifier.entityName
                if name != String(describing: RideSummaryCache.self),
                   name != String(describing: ArrivalForecastCache.self) {
                    return false
                }
            }
        }
        return sawReserve
    }

    static func tentativePlaces(
        in context: ModelContext,
        tickets: [Ticket]
    ) -> [UUID: OpeningPanelArrivalPlace] {
        let caches = (try? context.fetch(FetchDescriptor<ArrivalForecastCache>())) ?? []
        var byTicket: [UUID: ArrivalForecastCache] = [:]
        for cache in caches where byTicket[cache.ticketID] == nil {
            byTicket[cache.ticketID] = cache
        }
        var places: [UUID: OpeningPanelArrivalPlace] = [:]
        for ticket in tickets where ticket.isOpen {
            let shown = byTicket[ticket.id].flatMap {
                ForecastReserve.decode(ArrivalForecastPayload.self, from: $0.payload)?.shownMinutes
            }
            places[ticket.id] = shown.map { .previous($0) } ?? .empty
        }
        return places
    }

    static func refresh(
        in context: ModelContext,
        rowOrder: [UUID],
        cut: Int,
        now: Date = .now,
        calendar: Calendar = .current,
        refine: (@MainActor (ArrivalForecastContext, UUID) async -> ForecastRefineResult)? = nil,
        onPlace: @MainActor (UUID, OpeningPanelArrivalPlace) -> Void
    ) async {
        let reader = ForecastReserveReader(modelContainer: context.container)
        let snapshot = await reader.snapshot(now: now, calendar: calendar)
        if Task.isCancelled { return }
        let plan = ForecastReserve.plan(snapshot: snapshot, rowOrder: rowOrder, cut: cut)
        let ridesByID = Dictionary(uniqueKeysWithValues: snapshot.rides.map { ($0.sessionID, $0) })
        let summaryPayloads = plan.summaryWrites.compactMap { id -> (RideSummaryPayload, Date)? in
            guard let ride = ridesByID[id] else { return nil }
            return (ForecastReserve.summaryPayload(ride), ForecastReserve.sourceUpdatedAt(ride))
        }
        if !summaryPayloads.isEmpty || !plan.summaryDeletes.isEmpty {
            await reader.replaceSummaries(
                summaryPayloads,
                deletes: plan.summaryDeletes,
                methodVersion: ForecastReserve.rideSummaryMethod
            )
        }
        if Task.isCancelled { return }
        for id in plan.displayOrder {
            onPlace(id, plan.places[id] ?? .empty)
        }
        let ticketsByID = Dictionary(uniqueKeysWithValues: snapshot.tickets.map { ($0.id, $0) })
        for id in plan.arrivalWrites {
            if Task.isCancelled { return }
            guard let ticket = ticketsByID[id] else { continue }
            let output = await ForecastComputation.evaluate(
                ForecastComputation.Input(
                    ticket: ticket,
                    rides: snapshot.rides,
                    ticketIDs: snapshot.tickets.map(\.id),
                    links: snapshot.links,
                    now: snapshot.now,
                    calendar: snapshot.calendar
                )
            )
            if Task.isCancelled { return }
            var payload = ArrivalForecastPayload(
                ticketID: id,
                title: ticket.title,
                tagIDs: ForecastReserve.sortedTagIDs(ticket.tagIDs),
                medianMinutes: output.prediction.medianMinutes,
                refinedMinutes: nil,
                modelRefined: false,
                poolStamp: plan.poolStamp
            )
            if let refine, let forecastContext = output.prediction.context {
                switch await refine(forecastContext, id) {
                case .skipped:
                    break
                case .finished(let minutes):
                    if Task.isCancelled { return }
                    payload.refinedMinutes = minutes
                    payload.modelRefined = true
                }
            }
            if Task.isCancelled { return }
            await reader.writeArrival(
                payload,
                sourceUpdatedAt: plan.arrivalSourceDates[id] ?? ticket.createdAt,
                methodVersion: ForecastReserve.arrivalMethod
            )
            let place: OpeningPanelArrivalPlace = payload.shownMinutes.map { .current($0) } ?? .empty
            onPlace(id, place)
        }
    }
}
