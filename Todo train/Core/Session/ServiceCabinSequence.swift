//
//  ServiceCabinSequence.swift
//  Todo train
//
//  Boot / shutdown lamps for 運行. Pure timing — no wizard, no score.
//  Once a day: hold the dark, then light wells slowly.
//

import Foundation

enum ServiceCabinLamp: Int, Comparable, CaseIterable, Sendable {
    case dark = 0
    case lamp = 1
    case occupancy = 2
    case phosphor = 3
    case boardReady = 4
    case circuits = 5

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ServiceCabinSequence {
    /// Silence before the first lamp — the machine is still asleep.
    static let darkHoldSeconds: TimeInterval = 0.80
    static let stepSeconds: TimeInterval = 0.72
    static let powerOffHoldSeconds: TimeInterval = 0.45
    static let extendReasons = ["仕事が膨らんだ", "割り込みが入った", "まだかかる", "その他"]

    static func lamp(elapsed: TimeInterval, reduceMotion: Bool) -> ServiceCabinLamp {
        if reduceMotion { return .circuits }
        let t = max(0, elapsed)
        if t < darkHoldSeconds { return .dark }
        let step = Int(((t - darkHoldSeconds) / stepSeconds).rounded(.down)) + 1
        let raw = min(max(step, 0), ServiceCabinLamp.circuits.rawValue)
        return ServiceCabinLamp(rawValue: raw) ?? .circuits
    }

    static func shutdownLamp(elapsed: TimeInterval, reduceMotion: Bool) -> ServiceCabinLamp {
        if reduceMotion { return .dark }
        let step = Int((max(0, elapsed) / stepSeconds).rounded(.down))
        let raw = max(ServiceCabinLamp.circuits.rawValue - step, ServiceCabinLamp.dark.rawValue)
        return ServiceCabinLamp(rawValue: raw) ?? .dark
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
}
