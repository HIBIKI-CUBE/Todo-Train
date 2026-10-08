//
//  SessionManager+NextRide.swift
//  Todo train
//
//  次の一本の予約。乗車は始めない。乗客 aboard 中は拒否する。
//

import Foundation
import SwiftData

extension SessionManager {
    /// 開いている切符のうち、まだ発車していない予約 1 枚。
    /// 予約後にその切符で発車済みなら、到着画面では予約なし。記録自体は export に残す。
    func reservedNextTicket() -> Ticket? {
        openTicketsInHubOrder()
            .filter { ticket in
                guard ticket.isReservedAsNextRide else { return false }
                return !hasBoardedSinceReservation(ticket)
            }
            .max { lhs, rhs in
                (lhs.reservedAt ?? .distantPast) < (rhs.reservedAt ?? .distantPast)
            }
    }

    /// 予約よりあとに発車した乗車、または予約よりあとに再乗車した区間がある。
    func hasBoardedSinceReservation(_ ticket: Ticket) -> Bool {
        guard let reservedAt = ticket.reservedAt else { return false }
        return ticket.sessions.contains { session in
            if session.startedAt >= reservedAt { return true }
            if let segmentStartedAt = session.segmentStartedAt, segmentStartedAt >= reservedAt {
                return true
            }
            return false
        }
    }

    /// Hub の `sortOrder`。閉じた切符は含まない。
    func openTicketsInHubOrder() -> [Ticket] {
        let descriptor = FetchDescriptor<Ticket>(sortBy: [SortDescriptor(\.sortOrder)])
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.filter(\.isOpen)
    }

    /// 予約欄に出せる開いている切符。いま乗っている切符と、すでに予約中の切符は除く。
    func ticketsAvailableToReserve() -> [Ticket] {
        let ridingID = activeSession?.ticket?.id
        let reservedID = reservedNextTicket()?.id
        return openTicketsInHubOrder().filter { ticket in
            ticket.id != ridingID && ticket.id != reservedID
        }
    }

    /// 次の一本を 1 枚に差し替える。発車しない。
    func reserveNextRide(ticket: Ticket, via: ReservationVia, now: Date? = nil) throws {
        let now = now ?? clock.now
        try refusePassengerDriving()
        guard let ride = activeSession, ride.isOpen else {
            throw SessionError.noActiveSession
        }
        guard ticket.isOpen else {
            throw SessionError.ticketAlreadyClosed
        }
        guard ticket.id != ride.ticket?.id else {
            throw SessionError.cannotReserveCurrentRide
        }

        for other in openTicketsInHubOrder() where other.id != ticket.id && other.isReservedAsNextRide {
            clearReservationFields(other)
        }
        ticket.reservedAt = now
        ticket.reservedFromRideId = ride.id
        ticket.reservedVia = via
        try save()
    }

    /// 予約を外す。発車しない。
    func clearNextRideReservation() throws {
        try refusePassengerDriving()
        guard activeSession?.isOpen == true else {
            throw SessionError.noActiveSession
        }
        var changed = false
        for ticket in openTicketsInHubOrder() where ticket.isReservedAsNextRide {
            clearReservationFields(ticket)
            changed = true
        }
        if changed {
            try save()
        }
    }

    func clearReservationFields(_ ticket: Ticket) {
        ticket.reservedAt = nil
        ticket.reservedFromRideId = nil
        ticket.reservedViaRaw = nil
    }
}
