//
//  ServiceGateSequence.swift
//  Todo train
//
//  運行開始の門. 進行の主人はここ。演出の正本は Issue #53。
//

import Foundation

nonisolated enum ServiceGatePhase: Int, Comparable, CaseIterable, Sendable {
    case entering
    case awaitingIgnition
    case illuminating
    case readyToPrime
    case priming
    case departing
    case done

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

nonisolated enum ServiceGateEvent: Equatable, Sendable {
    case enterElapsed
    case ignited(skipIlluminate: Bool)
    case illuminateElapsed
    case primeBegan
    case primeCancelled
    case primeCompleted
    case departElapsed
}

nonisolated enum ServiceGateDepartBeat: Equatable, Sendable {
    case sealed
    case unlocking
    case opening
}

nonisolated enum ServiceGateSequence {
    static let enterHoldSeconds: TimeInterval = 0.42
    static let primeHoldSeconds: TimeInterval = 0.58
    static let departUnlockSeconds: TimeInterval = 0.28
    static let departOpenSeconds: TimeInterval = 0.32
    static let departHoldSeconds: TimeInterval = departUnlockSeconds + departOpenSeconds
    static let reduceMotionDepartUnlockSeconds: TimeInterval = 0.10
    static let reduceMotionDepartOpenSeconds: TimeInterval = 0.14
    static let reduceMotionDepartHoldSeconds: TimeInterval =
        reduceMotionDepartUnlockSeconds + reduceMotionDepartOpenSeconds
    static let richIlluminateSeconds: TimeInterval = 2.28
    static let emptyIlluminateSeconds: TimeInterval = 1.22
    static let reduceMotionIlluminateSeconds: TimeInterval = 0.08
    static let occupancyHandLimit = 4
    static let consistLeadLimit = 4
    static let theatricalLampLimit = 5

    struct Context: Equatable, Sendable {
        var occupancyCount: Int
        var consistCount: Int
        var reduceMotion: Bool
        var skipIlluminate: Bool

        var isEmptyMorning: Bool {
            occupancyCount == 0 && consistCount == 0
        }
    }

    struct Reveal: Equatable, Sendable {
        var rise: Double
        var wash: Double
        var bloom: Double
        var theatricalLampCount: Int
        var plaque: String?
        var serviceLit: Bool
        var dateLit: Bool
        var clockProgress: Double
        var occupancyLive: Int
        var consistLive: Int
        var tapeLive: Bool
        var canInteract: Bool
        var canPrime: Bool
        var isPeak: Bool
        var fullLit: Bool
    }

    static func advance(_ phase: ServiceGatePhase, _ event: ServiceGateEvent) -> ServiceGatePhase {
        switch (phase, event) {
        case (.entering, .enterElapsed):
            return .awaitingIgnition
        case (.awaitingIgnition, .ignited(true)):
            return .readyToPrime
        case (.awaitingIgnition, .ignited(false)):
            return .illuminating
        case (.illuminating, .illuminateElapsed):
            return .readyToPrime
        case (.readyToPrime, .primeBegan):
            return .priming
        case (.priming, .primeCancelled):
            return .readyToPrime
        case (.priming, .primeCompleted):
            return .departing
        case (.departing, .departElapsed):
            return .done
        default:
            return phase
        }
    }

    static func illuminateDuration(context: Context) -> TimeInterval {
        if context.reduceMotion || context.skipIlluminate {
            return reduceMotionIlluminateSeconds
        }
        return context.isEmptyMorning ? emptyIlluminateSeconds : richIlluminateSeconds
    }

    static func departDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reduceMotionDepartHoldSeconds : departHoldSeconds
    }

    static func departUnlockDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reduceMotionDepartUnlockSeconds : departUnlockSeconds
    }

    static func departBeat(elapsed: TimeInterval, reduceMotion: Bool) -> ServiceGateDepartBeat {
        if elapsed < 0 { return .sealed }
        return elapsed < departUnlockDuration(reduceMotion: reduceMotion) ? .unlocking : .opening
    }

    static func reveal(elapsed: TimeInterval, context: Context) -> Reveal {
        if context.reduceMotion || context.skipIlluminate {
            return filledReveal(context: context, canPrime: true)
        }
        let t = max(0, elapsed)
        return context.isEmptyMorning
            ? emptyReveal(elapsed: t)
            : richReveal(elapsed: t, context: context)
    }

    static func rollingClockDigits(
        at now: Date,
        progress: Double,
        salt: Int,
        calendar: Calendar = .autoupdatingCurrent
    ) -> (hourMinute: String, second: String) {
        let live = ServiceCabinSequence.clockDigits(at: now, calendar: calendar)
        if progress >= 1 { return live }
        let scramble = abs(salt &* 1_103_515_245 &+ 12_345)
        let hour = (scramble / 100) % 24
        let minute = (scramble / 10) % 60
        let second = scramble % 60
        let mixedHour = blendDigits(
            live: live.hourMinute,
            fake: String(format: "%02d:%02d", hour, minute),
            progress: progress
        )
        let mixedSecond = blendDigits(
            live: live.second,
            fake: String(format: "%02d", second),
            progress: progress
        )
        return (mixedHour, mixedSecond)
    }

    static func occupancyHands<T>(_ rows: [T]) -> [T] {
        Array(rows.prefix(occupancyHandLimit))
    }

    static func consistLead<T>(_ items: [T]) -> [T] {
        Array(items.prefix(consistLeadLimit))
    }

    private static func filledReveal(context: Context, canPrime: Bool) -> Reveal {
        let occupancy = min(max(context.occupancyCount, 0), occupancyHandLimit)
        let consist = min(max(context.consistCount, 0), consistLeadLimit)
        return Reveal(
            rise: 1,
            wash: 1,
            bloom: 1,
            theatricalLampCount: theatricalLampLimit,
            plaque: nil,
            serviceLit: true,
            dateLit: true,
            clockProgress: 1,
            occupancyLive: occupancy,
            consistLive: consist,
            tapeLive: occupancy > 0,
            canInteract: true,
            canPrime: canPrime,
            isPeak: true,
            fullLit: true
        )
    }

    private static func richReveal(elapsed t: TimeInterval, context: Context) -> Reveal {
        let occupancyCap = min(max(context.occupancyCount, 0), occupancyHandLimit)
        let consistCap = min(max(context.consistCount, 0), consistLeadLimit)

        let theatrical: Int
        if t < 0.12 {
            theatrical = 1
        } else if t < 0.28 {
            theatrical = 3
        } else {
            theatrical = theatricalLampLimit
        }

        let plaque: String?
        if t >= 0.30, t < 0.55 {
            plaque = "運行"
        } else if t >= 0.92, t < 1.18, occupancyCap > 0 {
            plaque = "占有"
        } else if t >= 1.28, t < 1.50, consistCap > 0 {
            plaque = "編成"
        } else {
            plaque = nil
        }

        let serviceLit = t >= 0.28
        let dateLit = t >= 0.40
        let clockProgress: Double
        if t < 0.38 {
            clockProgress = 0
        } else if t < 0.78 {
            clockProgress = min(1, (t - 0.38) / 0.40)
        } else {
            clockProgress = 1
        }

        let occupancyLive: Int
        if occupancyCap == 0 || t < 0.82 {
            occupancyLive = 0
        } else {
            occupancyLive = cascadedCount(elapsed: t, start: 0.82, stagger: 0.11, total: occupancyCap)
        }

        let consistLive: Int
        if consistCap == 0 || t < 1.22 {
            consistLive = 0
        } else {
            consistLive = cascadedCount(elapsed: t, start: 1.22, stagger: 0.10, total: consistCap)
        }

        let isPeak = serviceLit && dateLit && clockProgress >= 1 && (occupancyCap == 0 || occupancyLive >= 1)
        let fullLit = t >= 1.58
        let canPrime = t >= 2.04

        return Reveal(
            rise: richRise(t),
            wash: richWash(t),
            bloom: richBloom(t),
            theatricalLampCount: theatrical,
            plaque: plaque,
            serviceLit: serviceLit,
            dateLit: dateLit,
            clockProgress: clockProgress,
            occupancyLive: occupancyLive,
            consistLive: consistLive,
            tapeLive: occupancyLive > 0,
            canInteract: occupancyLive > 0 || consistLive > 0,
            canPrime: canPrime,
            isPeak: isPeak,
            fullLit: fullLit
        )
    }

    private static func emptyReveal(elapsed t: TimeInterval) -> Reveal {
        let theatrical: Int
        if t < 0.10 {
            theatrical = 2
        } else if t < 0.24 {
            theatrical = 4
        } else {
            theatrical = theatricalLampLimit
        }
        let plaque: String? = (t >= 0.18 && t < 0.44) ? "運行" : nil
        let serviceLit = t >= 0.26
        let dateLit = t >= 0.34
        let clockProgress: Double
        if t < 0.34 {
            clockProgress = 0
        } else if t < 0.56 {
            clockProgress = min(1, (t - 0.34) / 0.22)
        } else {
            clockProgress = 1
        }
        let isPeak = serviceLit && dateLit && clockProgress >= 1
        let fullLit = t >= 0.78
        return Reveal(
            rise: min(1, t < 0.22 ? 0.10 + t * 0.8 : 0.28 + (t - 0.22) / 0.70 * 0.72),
            wash: min(1, 0.18 + t / 0.85),
            bloom: min(1, t < 0.22 ? 0.20 + t : 0.42 + (t - 0.22) / 0.70 * 0.58),
            theatricalLampCount: theatrical,
            plaque: plaque,
            serviceLit: serviceLit,
            dateLit: dateLit,
            clockProgress: clockProgress,
            occupancyLive: 0,
            consistLive: 0,
            tapeLive: false,
            canInteract: t >= 0.56,
            canPrime: t >= 1.06,
            isPeak: isPeak,
            fullLit: fullLit
        )
    }

    private static func richRise(_ t: TimeInterval) -> Double {
        if t < 0.22 { return 0.06 + t * 0.45 }
        if t < 0.50 { return 0.16 + (t - 0.22) / 0.28 * 0.58 }
        return min(1, 0.74 + (t - 0.50) / 1.50 * 0.26)
    }

    private static func richWash(_ t: TimeInterval) -> Double {
        if t < 0.22 { return 0.08 + t * 0.5 }
        if t < 0.50 { return 0.19 + (t - 0.22) / 0.28 * 0.42 }
        if t < 1.58 { return 0.61 + (t - 0.50) / 1.08 * 0.22 }
        return min(1, 0.83 + (t - 1.58) / 0.50 * 0.17)
    }

    private static func richBloom(_ t: TimeInterval) -> Double {
        if t < 0.22 { return 0.10 + t * 0.7 }
        if t < 0.50 { return 0.25 + (t - 0.22) / 0.28 * 0.38 }
        if t < 1.58 { return 0.63 + (t - 0.50) / 1.08 * 0.20 }
        return min(1, 0.83 + (t - 1.58) / 0.46 * 0.17)
    }

    private static func cascadedCount(
        elapsed: TimeInterval,
        start: TimeInterval,
        stagger: TimeInterval,
        total: Int
    ) -> Int {
        guard total > 0, elapsed >= start else { return 0 }
        let count = Int((elapsed - start) / stagger) + 1
        return min(total, count)
    }

    private static func blendDigits(live: String, fake: String, progress: Double) -> String {
        zip(live, fake).map { liveChar, fakeChar in
            liveChar == ":" ? ":" : (progress > 0.72 ? liveChar : fakeChar)
        }
        .map(String.init)
        .joined()
    }
}
