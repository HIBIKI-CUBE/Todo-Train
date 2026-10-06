//
//  SessionManager+Passenger.swift
//  Todo train
//
//  乗客レーンの永続化。走行中の［乗る］は timetableHeld 待避のあと aboard。
//

import Foundation
import SwiftData

extension SessionManager {
    func boardPassenger(now: Date? = nil) {
        let now = now ?? clock.now
        applyPassengerEffects(now: now)
        guard case .offer(let interval, _) = passengerChrome else { return }

        if let session = activeSession, session.isOpen, !session.isPaused {
            try? pause(now: now, timetableHeld: true)
        }

        let snapshot = PassengerLane.ride(
            on: interval,
            now: now,
            deviceID: deviceIdentity.id
        )
        modelContext.insert(PassengerRide(snapshot: snapshot))
        passengerMemory.offerAnchor = nil
        passengerMemory.offerAnchorIntervalID = nil
        passengerMemory.collapsedIntervalID = nil
        try? save()
        reconcile(now: now)
    }

    func openEmergencyDoor(now: Date? = nil) {
        let now = now ?? clock.now
        guard let ride = fetchOpenPassengerRide() else { return }
        let opened = PassengerLane.emergency(ride: ride.snapshot, now: now)
        ride.endedAt = opened.ride.endedAt
        ride.endReason = .emergency
        passengerMemory.greeting = opened.greeting
        passengerMemory.offerAnchor = nil
        passengerMemory.offerAnchorIntervalID = nil
        passengerMemory.collapsedIntervalID = nil
        try? save()
        reconcile(now: now)
    }

    func refusePassengerDriving() throws {
        if passengerChrome.locksDriving || fetchOpenPassengerRide() != nil {
            throw SessionError.passengerAboard
        }
    }

    func applyPassengerEffects(now: Date) {
        let open = fetchOpenPassengerRide()
        let effect = PassengerLane.resolve(
            intervals: passengerIntervals(keeping: open?.intervalId),
            openRide: open?.snapshot,
            now: now,
            memory: passengerMemory,
            ticketRunning: ticketIsRunning
        )

        var changed = false
        if let open {
            if let follow = effect.follow {
                if open.title != follow.title { open.title = follow.title; changed = true }
                if open.intervalStart != follow.startsAt { open.intervalStart = follow.startsAt; changed = true }
                if open.intervalEnd != follow.endsAt { open.intervalEnd = follow.endsAt; changed = true }
            }
            if let close = effect.close {
                open.endedAt = close.at
                open.endReason = close.reason
                changed = true
            }
        }
        if changed { try? save() }

        switch effect.notify {
        case .none:
            break
        case .schedule(let intervalID, let title, let fireAt):
            checkInNotifier.schedulePassengerBoard(intervalID: intervalID, title: title, fireAt: fireAt)
        case .cancel:
            checkInNotifier.cancelPassengerBoard()
        }

        if passengerMemory != effect.memory {
            passengerMemory = effect.memory
        }
        if passengerChrome != effect.chrome {
            passengerChrome = effect.chrome
        }
    }

    func fetchOpenPassengerRide() -> PassengerRide? {
        let descriptor = FetchDescriptor<PassengerRide>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.boardedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    private var ticketIsRunning: Bool {
        guard let session = activeSession, session.isOpen, !session.isPaused else { return false }
        return true
    }

    private func passengerIntervals(keeping openID: String?) -> [PassengerInterval] {
        let authorized = calendarBoard.authorizationStatus() == .authorized
        let blocks = fetchTimetableBlocks().map { block in
            PassengerBlockInput(
                id: block.id.uuidString,
                title: block.title,
                startsAt: block.startsAt,
                endsAt: block.endsAt,
                source: block.source == .manual ? .manualInterval : .adoptedBlock,
                isCancelled: block.isCancelled
            )
        }
        return PassengerEligibility.intervals(
            from: blocks,
            calendarAuthorized: authorized,
            keepingIntervalID: openID
        )
    }
}
