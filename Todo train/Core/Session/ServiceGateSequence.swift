//
//  ServiceGateSequence.swift
//  Todo train
//
//  運行開始の門. 進行の主人はここ。表示灯試験は主人にしない。
//

import Foundation

enum ServiceGatePhase: Int, Comparable, CaseIterable, Sendable {
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

enum ServiceGateEvent: Equatable, Sendable {
    case enterElapsed
    case ignited(skipIlluminate: Bool)
    case illuminateElapsed
    case primeBegan
    case primeCancelled
    case primeCompleted
    case departElapsed
}

enum ServiceGateSequence {
    static let enterHoldSeconds: TimeInterval = 0.38
    static let primeHoldSeconds: TimeInterval = 0.55
    static let departHoldSeconds: TimeInterval = 0.58
    static let reduceMotionDepartHoldSeconds: TimeInterval = 0.26
    static let richIlluminateSeconds: TimeInterval = 2.40
    static let emptyIlluminateSeconds: TimeInterval = 1.28
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
        var edgeLift: Double
        var wash: Double
        var theatricalLampCount: Int
        var plaque: String?
        var serviceLit: Bool
        var dateLit: Bool
        var clockProgress: Double
        var occupancySilhouettes: Int
        var occupancyLive: Int
        var consistSilhouettes: Int
        var consistLive: Int
        var tapeLive: Bool
        var canInteract: Bool
        var canPrime: Bool
        var isPeak: Bool
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

    static func reveal(elapsed: TimeInterval, context: Context) -> Reveal {
        if context.reduceMotion || context.skipIlluminate {
            return filledReveal(context: context, canPrime: true)
        }
        let t = max(0, elapsed)
        return context.isEmptyMorning
            ? emptyReveal(elapsed: t, context: context)
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
        let mixedHour = blendDigits(live: live.hourMinute, fake: String(format: "%02d:%02d", hour, minute), progress: progress)
        let mixedSecond = blendDigits(live: live.second, fake: String(format: "%02d", second), progress: progress)
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
        let peak = true
        return Reveal(
            edgeLift: 1,
            wash: 1,
            theatricalLampCount: theatricalLampLimit,
            plaque: nil,
            serviceLit: true,
            dateLit: true,
            clockProgress: 1,
            occupancySilhouettes: 0,
            occupancyLive: occupancy,
            consistSilhouettes: 0,
            consistLive: consist,
            tapeLive: occupancy > 0,
            canInteract: true,
            canPrime: canPrime,
            isPeak: peak
        )
    }

    private static func richReveal(elapsed t: TimeInterval, context: Context) -> Reveal {
        let occupancyCap = min(max(context.occupancyCount, 0), occupancyHandLimit)
        let consistCap = min(max(context.consistCount, 0), consistLeadLimit)
        let theatrical: Int
        if t < 0.10 {
            theatrical = 1
        } else if t < 0.22 {
            theatrical = 3
        } else {
            theatrical = theatricalLampLimit
        }

        let plaque: String?
        if t >= 0.16, t < 0.42 {
            plaque = "運行"
        } else if t >= 1.08, t < 1.32, occupancyCap > 0 {
            plaque = "占有"
        } else if t >= 1.44, t < 1.68, consistCap > 0 {
            plaque = "編成"
        } else {
            plaque = nil
        }

        let serviceLit = t >= 0.30
        let dateLit = t >= 0.46
        let clockProgress: Double
        if t < 0.46 {
            clockProgress = 0
        } else if t < 0.96 {
            clockProgress = min(1, (t - 0.46) / 0.50)
        } else {
            clockProgress = 1
        }

        let occupancySilhouettes: Int
        let occupancyLive: Int
        if occupancyCap == 0 {
            occupancySilhouettes = 0
            occupancyLive = 0
        } else if t < 0.70 {
            occupancySilhouettes = 0
            occupancyLive = 0
        } else if t < 0.96 {
            occupancySilhouettes = min(occupancyCap, 2)
            occupancyLive = 0
        } else {
            occupancySilhouettes = 0
            occupancyLive = cascadedCount(elapsed: t, start: 0.96, stagger: 0.14, total: occupancyCap)
        }

        let consistSilhouettes: Int
        let consistLive: Int
        if consistCap == 0 {
            consistSilhouettes = 0
            consistLive = 0
        } else if t < 1.24 {
            consistSilhouettes = 0
            consistLive = 0
        } else if t < 1.44 {
            consistSilhouettes = min(consistCap, 2)
            consistLive = 0
        } else {
            consistSilhouettes = 0
            consistLive = cascadedCount(elapsed: t, start: 1.44, stagger: 0.12, total: consistCap)
        }

        let tapeLive = occupancyLive > 0
        let canInteract = occupancyLive > 0 || consistLive > 0
        let isPeak = serviceLit && dateLit && clockProgress >= 1 && (occupancyCap == 0 || occupancyLive >= 1)
        let canPrime = t >= 2.16
        let edgeLift = min(1, 0.08 + t / 1.6)
        let wash = min(1, 0.10 + t / 1.9)

        return Reveal(
            edgeLift: edgeLift,
            wash: wash,
            theatricalLampCount: theatrical,
            plaque: plaque,
            serviceLit: serviceLit,
            dateLit: dateLit,
            clockProgress: clockProgress,
            occupancySilhouettes: occupancySilhouettes,
            occupancyLive: occupancyLive,
            consistSilhouettes: consistSilhouettes,
            consistLive: consistLive,
            tapeLive: tapeLive,
            canInteract: canInteract,
            canPrime: canPrime,
            isPeak: isPeak
        )
    }

    private static func emptyReveal(elapsed t: TimeInterval, context: Context) -> Reveal {
        _ = context
        let theatrical: Int
        if t < 0.12 {
            theatrical = 2
        } else if t < 0.28 {
            theatrical = 4
        } else {
            theatrical = theatricalLampLimit
        }
        let plaque: String? = (t >= 0.16 && t < 0.40) ? "運行" : nil
        let serviceLit = t >= 0.32
        let dateLit = t >= 0.40
        let clockProgress: Double
        if t < 0.40 {
            clockProgress = 0
        } else if t < 0.62 {
            clockProgress = min(1, (t - 0.40) / 0.22)
        } else {
            clockProgress = 1
        }
        let occupancySilhouettes: Int
        if t >= 0.52, t < 0.82 {
            occupancySilhouettes = 2
        } else {
            occupancySilhouettes = 0
        }
        let isPeak = serviceLit && dateLit && clockProgress >= 1
        return Reveal(
            edgeLift: min(1, 0.12 + t / 1.1),
            wash: min(1, 0.16 + t / 1.2),
            theatricalLampCount: theatrical,
            plaque: plaque,
            serviceLit: serviceLit,
            dateLit: dateLit,
            clockProgress: clockProgress,
            occupancySilhouettes: occupancySilhouettes,
            occupancyLive: 0,
            consistSilhouettes: 0,
            consistLive: 0,
            tapeLive: false,
            canInteract: t >= 0.62,
            canPrime: t >= 1.12,
            isPeak: isPeak
        )
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
