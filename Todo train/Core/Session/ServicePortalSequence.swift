//
//  ServicePortalSequence.swift
//  Todo train
//
//  運行開始の門。閉じた場所の中で、短い手が機械を起こし、
//  運ばれながら緊張が乗り、最後の一手でホームへ開く。
//

import Foundation

nonisolated enum ServicePortalPhase: Int, Comparable, CaseIterable, Sendable {
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

nonisolated enum ServicePortalEvent: Equatable, Sendable {
    case enterElapsed
    case ignited(skipIlluminate: Bool)
    case illuminateElapsed
    case primeBegan
    case primeCancelled
    case primeCompleted
    case departElapsed
}

nonisolated enum ServicePortalDepartBeat: Equatable, Sendable {
    case sealed
    case slit
    case flood
}

nonisolated enum ServicePortalPace: Equatable, Sendable {
    case quiet
    case surge
    case still
    case primed
}

nonisolated enum ServicePortalSequence {
    static let enterHoldSeconds: TimeInterval = 0.12
    static let primeHoldSeconds: TimeInterval = 0.52
    static let departSlitSeconds: TimeInterval = 0.24
    static let departFloodSeconds: TimeInterval = 0.38
    static let primeChargeFloor: Double = 0.34
    /// How hard the cabin tightens while priming. Must be big enough to read as the room, not the button.
    static let primeRoomTighten: Double = 0.16
    static let departHoldSeconds: TimeInterval = departSlitSeconds + departFloodSeconds
    static let reduceMotionDepartSlitSeconds: TimeInterval = 0.10
    static let reduceMotionDepartFloodSeconds: TimeInterval = 0.16
    static let reduceMotionDepartHoldSeconds: TimeInterval =
        reduceMotionDepartSlitSeconds + reduceMotionDepartFloodSeconds
    static let richIlluminateSeconds: TimeInterval = 2.00
    static let emptyIlluminateSeconds: TimeInterval = 1.12
    static let reduceMotionIlluminateSeconds: TimeInterval = 0.10
    static let occupancyHandLimit = 4
    static let consistLeadLimit = 4
    static let beadLimit = 7
    static let ignitionHandoffSeconds: TimeInterval = 0.22

    struct Context: Equatable, Sendable {
        var occupancyCount: Int
        var consistCount: Int
        var reduceMotion: Bool
        var skipIlluminate: Bool

        var isEmptyMorning: Bool {
            occupancyCount == 0 && consistCount == 0
        }
    }

    struct DepartStaging: Equatable, Sendable {
        var aperture: Double
        var cabinScale: Double
        var cabinOpacity: Double
    }

    struct Presence: Equatable, Sendable {
        var horizon: Double
        var wake: Double
        var shelfRise: Double
        var shelfPitch: Double
        var washTravel: Double
        var volumeGlow: Double
        var beadCount: Int
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

    static func advance(_ phase: ServicePortalPhase, _ event: ServicePortalEvent) -> ServicePortalPhase {
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

    static func departSlitDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reduceMotionDepartSlitSeconds : departSlitSeconds
    }

    static func departBeat(elapsed: TimeInterval, reduceMotion: Bool) -> ServicePortalDepartBeat {
        if elapsed < 0 { return .sealed }
        return elapsed < departSlitDuration(reduceMotion: reduceMotion) ? .slit : .flood
    }

    /// Hold starts with a visible floor so the room jumps on the same beat, then fills.
    static func primeRoomCharge(progress: Double) -> Double {
        let p = min(max(progress, 0), 1)
        if p <= 0 { return 0 }
        return primeChargeFloor + (1 - primeChargeFloor) * p
    }

    /// Cover charge. Priming at progress 0 still jumps; the lip fill may stay at 0.
    static func roomCharge(isPriming: Bool, progress: Double) -> Double {
        guard isPriming else { return 0 }
        return max(primeChargeFloor, primeRoomCharge(progress: progress))
    }

    /// Opens toward the platform. Scale > 1 is the box opening, not a sheet sinking.
    static func departStaging(elapsed: TimeInterval, reduceMotion: Bool) -> DepartStaging {
        switch departBeat(elapsed: elapsed, reduceMotion: reduceMotion) {
        case .sealed:
            return DepartStaging(aperture: 0, cabinScale: 1, cabinOpacity: 1)
        case .slit:
            return DepartStaging(
                aperture: reduceMotion ? 0.32 : 0.36,
                cabinScale: reduceMotion ? 1.05 : 1.10,
                cabinOpacity: reduceMotion ? 0.52 : 0.56
            )
        case .flood:
            return DepartStaging(
                aperture: 1,
                cabinScale: reduceMotion ? 1.10 : 1.22,
                cabinOpacity: 0
            )
        }
    }

    static func pace(elapsed: TimeInterval, context: Context) -> ServicePortalPace {
        if context.reduceMotion || context.skipIlluminate { return .primed }
        let t = max(0, elapsed)
        if context.isEmptyMorning {
            if t < 0.14 { return .quiet }
            if t < 0.48 { return .surge }
            if t < 0.72 { return .still }
            return .primed
        }
        if t < 0.20 { return .quiet }
        if t < 0.95 { return .surge }
        if t < 1.35 { return .still }
        return .primed
    }

    static func sealedPlace() -> Presence {
        Presence(
            horizon: 0.28,
            wake: 0.05,
            shelfRise: 0.02,
            shelfPitch: 0.02,
            washTravel: 0,
            volumeGlow: 0.04,
            beadCount: 0,
            plaque: nil,
            serviceLit: false,
            dateLit: false,
            clockProgress: 0,
            occupancyLive: 0,
            consistLive: 0,
            tapeLive: false,
            canInteract: false,
            canPrime: false,
            isPeak: false,
            fullLit: false
        )
    }

    static func premonition(breath: Double) -> Presence {
        let b = min(max(breath, 0), 1)
        return Presence(
            horizon: 0.62 + 0.22 * b,
            wake: 0.12 + 0.10 * b,
            shelfRise: 0.06,
            shelfPitch: 0.05,
            washTravel: 0.04 * b,
            volumeGlow: 0.08 + 0.07 * b,
            beadCount: 0,
            plaque: nil,
            serviceLit: false,
            dateLit: false,
            clockProgress: 0,
            occupancyLive: 0,
            consistLive: 0,
            tapeLive: false,
            canInteract: false,
            canPrime: false,
            isPeak: false,
            fullLit: false
        )
    }

    static func reveal(elapsed: TimeInterval, context: Context) -> Presence {
        if context.reduceMotion || context.skipIlluminate {
            return filledPresence(context: context, canPrime: true)
        }
        let t = max(0, elapsed)
        return context.isEmptyMorning ? emptyReveal(elapsed: t) : richReveal(elapsed: t, context: context)
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

    private static func filledPresence(context: Context, canPrime: Bool) -> Presence {
        let occupancy = min(max(context.occupancyCount, 0), occupancyHandLimit)
        let consist = min(max(context.consistCount, 0), consistLeadLimit)
        return Presence(
            horizon: 1,
            wake: 1,
            shelfRise: 1,
            shelfPitch: 1,
            washTravel: 1,
            volumeGlow: 1,
            beadCount: beadLimit,
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

    private static func richReveal(elapsed t: TimeInterval, context: Context) -> Presence {
        let occupancyCap = min(max(context.occupancyCount, 0), occupancyHandLimit)
        let consistCap = min(max(context.consistCount, 0), consistLeadLimit)

        let occupancyLive: Int
        if occupancyCap == 0 || t < 0.58 {
            occupancyLive = 0
        } else {
            occupancyLive = cascadedCount(elapsed: t, start: 0.58, stagger: 0.10, total: occupancyCap)
        }

        let consistLive: Int
        if consistCap == 0 || t < 0.62 {
            consistLive = 0
        } else {
            consistLive = cascadedCount(elapsed: t, start: 0.62, stagger: 0.08, total: consistCap)
        }

        let clockProgress: Double
        if t < 0.28 {
            clockProgress = 0
        } else if t < 0.78 {
            clockProgress = ramp(t, from: 0.28, to: 0.78)
        } else {
            clockProgress = 1
        }

        let serviceLit = t >= 0.30
        let dateLit = t >= 0.42
        let isPeak = serviceLit && dateLit && clockProgress >= 1 && (occupancyCap == 0 || occupancyLive >= 1)
        let fullLit = t >= 1.18
        let canPrime = t >= 1.72

        let plaque: String?
        if t >= 0.28, t < 0.48 {
            plaque = "運行"
        } else if t >= 0.58, t < 0.78, occupancyCap > 0 {
            plaque = "占有"
        } else if t >= 0.62, t < 0.80, consistCap > 0 {
            plaque = "編成"
        } else {
            plaque = nil
        }

        return Presence(
            horizon: 1,
            wake: richWake(t),
            shelfRise: richRise(t),
            shelfPitch: richPitch(t),
            washTravel: richWash(t),
            volumeGlow: richVolume(t),
            beadCount: richBeads(t),
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

    private static func emptyReveal(elapsed t: TimeInterval) -> Presence {
        let clockProgress: Double
        if t < 0.22 {
            clockProgress = 0
        } else if t < 0.48 {
            clockProgress = ramp(t, from: 0.22, to: 0.48)
        } else {
            clockProgress = 1
        }
        let serviceLit = t >= 0.22
        let dateLit = t >= 0.30
        let isPeak = serviceLit && dateLit && clockProgress >= 1
        let fullLit = t >= 0.62
        let plaque: String? = (t >= 0.18 && t < 0.40) ? "運行" : nil
        return Presence(
            horizon: 1,
            wake: min(1, 0.70 + t * 0.35),
            shelfRise: min(1, 0.62 + t / 0.90),
            shelfPitch: min(1, 0.58 + t / 0.80),
            washTravel: min(1, 0.18 + t / 0.55),
            volumeGlow: min(1, 0.58 + t / 0.80),
            beadCount: t < 0.10 ? 3 : (t < 0.22 ? 5 : beadLimit),
            plaque: plaque,
            serviceLit: serviceLit,
            dateLit: dateLit,
            clockProgress: clockProgress,
            occupancyLive: 0,
            consistLive: 0,
            tapeLive: false,
            canInteract: t >= 0.48,
            canPrime: t >= 0.92,
            isPeak: isPeak,
            fullLit: fullLit
        )
    }

    /// Same beat as the press: the room is already up. Quiet is lit, not a climb from a sheet.
    private static func richWake(_ t: TimeInterval) -> Double {
        if t < 0.20 { return 0.72 + t * 0.35 }
        if t < 0.95 { return 0.79 + (t - 0.20) / 0.75 * 0.12 }
        return min(1, 0.91 + (t - 0.95) / 0.80 * 0.09)
    }

    private static func richRise(_ t: TimeInterval) -> Double {
        if t < 0.20 { return 0.70 + t * 0.40 }
        if t < 0.95 { return 0.78 + (t - 0.20) / 0.75 * 0.14 }
        return min(1, 0.92 + (t - 0.95) / 0.70 * 0.08)
    }

    private static func richPitch(_ t: TimeInterval) -> Double {
        if t < 0.20 { return 0.64 + t * 0.50 }
        if t < 0.95 { return 0.74 + (t - 0.20) / 0.75 * 0.16 }
        return min(1, 0.90 + (t - 0.95) / 0.55 * 0.10)
    }

    private static func richWash(_ t: TimeInterval) -> Double {
        if t < 0.20 { return 0.12 + t * 1.1 }
        if t < 0.95 { return 0.34 + (t - 0.20) / 0.75 * 0.58 }
        return 1
    }

    private static func richVolume(_ t: TimeInterval) -> Double {
        if t < 0.20 { return 0.58 + t * 0.55 }
        if t < 0.95 { return 0.69 + (t - 0.20) / 0.75 * 0.18 }
        return min(1, 0.87 + (t - 0.95) / 0.70 * 0.13)
    }

    private static func richBeads(_ t: TimeInterval) -> Int {
        if t < 0.08 { return 1 }
        if t < 0.18 { return 2 }
        if t < 0.34 { return 4 }
        if t < 0.58 { return 5 }
        return beadLimit
    }

    private static func ramp(_ t: TimeInterval, from: TimeInterval, to: TimeInterval) -> Double {
        guard to > from else { return t >= to ? 1 : 0 }
        return min(1, max(0, (t - from) / (to - from)))
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
