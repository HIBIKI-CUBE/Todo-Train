//
//  ServiceCabinSequence.swift
//  Todo train
//
//  Glass-cockpit BIT: lamps click on, tapes sweep on their own clocks, then live.
//  ため sits on all-on. Clock lock is the peak.
//

import Foundation

enum ServiceCabinLamp: Int, Comparable, CaseIterable, Sendable {
    case dark = 0
    case test = 1
    case live = 2
    case ready = 3

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ServiceCabinAnnunciator: String, CaseIterable, Sendable {
    case service = "運行"
    case occupancy = "占有"
    case paused = "停車"
}

struct ServiceCabinConsistItem: Equatable, Sendable, Identifiable {
    var id: UUID
    var title: String
    var minutes: Int
}

struct ServiceCabinDayFact: Equatable, Sendable, Identifiable {
    var label: String
    var value: String

    var id: String { label }
}

enum ServiceCabinSequence {
    static let darkHoldSeconds: TimeInterval = 0.88
    static let testHoldSeconds: TimeInterval = 1.18
    static let liveHoldSeconds: TimeInterval = 0.90
    /// Shutdown steps. Boot uses the holds above.
    static let stepSeconds: TimeInterval = 0.70
    static let powerOffHoldSeconds: TimeInterval = 0.58
    static let sweepOutSeconds: TimeInterval = 0.62
    static let sweepSettleSeconds: TimeInterval = 0.56
    static let secondsSweepOutSeconds: TimeInterval = 0.88
    static let tapeSettleDelaySeconds: TimeInterval = 0.12
    static let clockArmDelaySeconds: TimeInterval = 0.10
    static let lampTestStaggerSeconds: TimeInterval = 0.12
    static let lampSettleHoldSeconds: TimeInterval = 0.24
    static let lampSettleStaggerSeconds: TimeInterval = 0.15
    static let morningNoticeLimit = 4
    static let extendReasons = ["仕事が膨らんだ", "割り込みが入った", "まだかかる", "その他"]

    static func lamp(elapsed: TimeInterval, reduceMotion: Bool) -> ServiceCabinLamp {
        if reduceMotion { return .ready }
        let t = max(0, elapsed)
        if t < darkHoldSeconds { return .dark }
        if t < darkHoldSeconds + testHoldSeconds { return .test }
        if t < darkHoldSeconds + testHoldSeconds + liveHoldSeconds { return .live }
        return .ready
    }

    static func shutdownLamp(elapsed: TimeInterval, reduceMotion: Bool) -> ServiceCabinLamp {
        if reduceMotion { return .dark }
        let step = Int((max(0, elapsed) / stepSeconds).rounded(.down))
        let raw = max(ServiceCabinLamp.ready.rawValue - step, ServiceCabinLamp.dark.rawValue)
        return ServiceCabinLamp(rawValue: raw) ?? .dark
    }

    /// BIT: lamps click on in order, hold all-on, then each cell drops to the real state.
    static func annunciatorLit(
        _ id: ServiceCabinAnnunciator,
        lamp: ServiceCabinLamp,
        serviceOn: Bool,
        hasOccupancy: Bool,
        paused: Bool,
        testCount: Int = ServiceCabinAnnunciator.allCases.count,
        settledCount: Int = ServiceCabinAnnunciator.allCases.count
    ) -> Bool {
        if lamp == .dark { return false }
        let index = ServiceCabinAnnunciator.allCases.firstIndex(of: id) ?? 0
        if lamp == .test {
            return testCount > index
        }
        if settledCount <= index { return true }
        switch id {
        case .service: return serviceOn
        case .occupancy: return hasOccupancy
        case .paused: return paused
        }
    }

    static func secondsRailRest(
        at date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> CGFloat {
        let second = calendar.component(.second, from: date)
        let nano = calendar.component(.nanosecond, from: date)
        return CGFloat((Double(second) + Double(nano) / 1_000_000_000) / 60)
    }

    static func tapeRest(marks: [TimetableOccupancyMark]) -> CGFloat {
        if let current = marks.first(where: \.isCurrent) {
            let value = current.span > 0 ? current.span : current.position
            return CGFloat(min(1, max(0, value)))
        }
        if let next = marks.min(by: { $0.position < $1.position }) {
            return CGFloat(min(1, max(0, next.position)))
        }
        return 0
    }

    static func clockDigits(
        at now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> (hourMinute: String, second: String) {
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let second = calendar.component(.second, from: now)
        return (
            String(format: "%02d:%02d", hour, minute),
            String(format: "%02d", second)
        )
    }

    static func unlabeledExtensions(in sessions: [WorkSession]) -> [SessionExtension] {
        sessions
            .flatMap(\.extensions)
            .filter { extensionRecord in
                let reason = extensionRecord.reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return reason.isEmpty
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    static func extensionMinutes(in sessions: [WorkSession]) -> Int {
        let seconds = sessions
            .flatMap(\.extensions)
            .reduce(0) { $0 + max(0, $1.addedSeconds) }
        return Int((TimeInterval(seconds) / 60).rounded())
    }

    /// Remaining 掲示 that are not already いま／次. Cap so the boot face stays an instrument.
    static func morningNotices(
        remaining: [CalendarOccurrence],
        occupancyRows: [TimetableOccupancyRow],
        now: Date
    ) -> [CalendarOccurrence] {
        let shown = Set(occupancyRows.map(\.id))
        return remaining
            .filter { occurrence in
                occurrence.endsAt > now
                    && !shown.contains(TimetableFit.noticeBlockID(occurrence.id))
            }
            .sorted { $0.startsAt < $1.startsAt }
            .prefix(morningNoticeLimit)
            .map { $0 }
    }

    static func dayFacts(in sessions: [WorkSession]) -> [ServiceCabinDayFact] {
        let aggregate = HistoryStats.aggregate(sessions: sessions)
        let extensionTotal = extensionMinutes(in: sessions)
        var facts = [
            ServiceCabinDayFact(label: "集中", value: "\(aggregate.focusMinutes)分")
        ]
        if extensionTotal > 0 {
            facts.append(ServiceCabinDayFact(label: "延長", value: "\(extensionTotal)分"))
        }
        if aggregate.arrived > 0 {
            facts.append(ServiceCabinDayFact(label: "到着", value: "\(aggregate.arrived)"))
        }
        if aggregate.partialDisembark > 0 {
            facts.append(ServiceCabinDayFact(label: "途中下車", value: "\(aggregate.partialDisembark)"))
        }
        if aggregate.abandoned > 0 {
            facts.append(ServiceCabinDayFact(label: "放棄", value: "\(aggregate.abandoned)"))
        }
        return facts
    }

    static func consistItems(from tickets: [Ticket]) -> [ServiceCabinConsistItem] {
        tickets
            .filter(\.isOpen)
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { ticket in
                ServiceCabinConsistItem(
                    id: ticket.id,
                    title: ticket.title,
                    minutes: max(ticket.estimatedSeconds / 60, 1)
                )
            }
    }
}
