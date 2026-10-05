//
//  ApproachClearEngine.swift
//  Todo train
//
//  Timing state for the Hub clearance toy. Judgement uses the press
//  timestamp, never the frame needle or the release. The engine does not
//  start service, read ticket titles, or record arrivals.
//

import Foundation

nonisolated struct ApproachClearWorld: Equatable, Sendable {
    var inService: Bool
    var dayEndPrompt: Bool
    var paused: Bool

    static let outOfService = ApproachClearWorld(
        inService: false,
        dayEndPrompt: false,
        paused: false
    )
}

nonisolated enum ApproachClearPhase: Equatable, Sendable {
    case dormant
    case idle
    case approach
    case interlock
    case barrier
    case easedown
    case resolved
    case calm
}

nonisolated enum ApproachClearCalm: Equatable, Sendable {
    case quiet
    case full
}

nonisolated enum ApproachClearAccent: Equatable, Sendable {
    case cyan
    case warm
    case hot
    case blaze
}

nonisolated enum ApproachClearFlash: Equatable, Sendable {
    case none
    case perfect
    case good
    case miss
}

nonisolated enum ApproachClearPass: Equatable, Sendable {
    case perfect
    case good
}

nonisolated enum ApproachClearArm: Equatable, Sendable {
    case none
    case good
    case perfect
}

nonisolated struct ApproachClearLamps: Equatable, Sendable {
    var approach = false
    var perfect = false
    var good = false
    var clear = false
    var reject = false
    var interlock = false
}

nonisolated struct ApproachClearDebug: Equatable, Sendable {
    var phase = "dormant"
    var heat = 0.0
    var tier = 0
    var clears = 0
    var approachMs = 0.0
    var goodEarlyMs = 0.0
    var goodLateMs = 0.0
    var perfEarlyMs = 0.0
    var perfLateMs = 0.0

    var line: String {
        String(
            format: "phase=%@ heat=%.1f tier=%d clr=%d  approach=%.0f  good=-%.1f/+%.1f  perf=-%.1f/+%.1f",
            phase,
            heat,
            tier,
            clears,
            approachMs,
            goodEarlyMs,
            goodLateMs,
            perfEarlyMs,
            perfLateMs
        )
    }
}

nonisolated struct ApproachClearSnapshot: Equatable, Sendable {
    var phase: ApproachClearPhase = .dormant
    var needle = 0.0
    var needleVisible = false
    var needleRejected = false
    var pressU: Double?
    var bands = ApproachClearBands.hidden
    var label = ""
    var heat = 0.0
    var tier = 0
    var clears = 0
    var sessionProgress = 0.0
    var calm: ApproachClearCalm?
    var pipsLit = 0
    var accent: ApproachClearAccent = .cyan
    var flash: ApproachClearFlash = .none
    var shake = false
    var passing: ApproachClearPass?
    var easing = false
    var shrinking = false
    var idleBreath = false
    var jammed = false
    var interlockLit = 0
    var barrierOn = false
    var flashRunningLamp = false
    var lamps = ApproachClearLamps()
    var controlEnabled = true
    var armed: ApproachClearArm = .none
    var contactDown = false
    var approachStart = 0.0
    var pressLockedUntil = 0.0
    var comboDeadline = 0.0
    var gapUntil = 0.0
    var pendingUntil = 0.0
    var scheduledStandbyMs = 0.0
    var debug = ApproachClearDebug()
}

nonisolated enum ApproachClearCue: Equatable, Sendable {
    case approachPulse
    case perfect(tier: Int)
    case good(tier: Int)
    case miss
    case pass
    case jam
    case heatUp
    case easeDown
    case interlockStep
    case interlockDone
    case interlockReject
    case barrier
    case sessionFull
}

nonisolated struct ApproachClearEngine: Sendable {
    var world = ApproachClearWorld.outOfService
    /// Scripted 0..<1 draws. Past the end, tests stay at 0.5.
    var randomUnits: [Double] = []
    /// The panel turns this on so each approach rolls a new window.
    var liveRandom = false

    private(set) var snapshot = ApproachClearSnapshot()

    private var phase: ApproachClearPhase = .dormant
    private var sessionStart: Double?
    private var approachStart = 0.0
    private var gapUntil = 0.0
    private var pressLockedUntil = 0.0
    private var comboDeadline = 0.0
    private var pendingUntil = 0.0
    private var nextDelay = 0.0
    private var scheduledStandbyMs = 0.0
    private var heat = 0.0
    private var tier = 0
    private var clears = 0
    private var endPending = false
    private var easePendingUp = false
    private var bands = ApproachClearBands.hidden
    private var needle = 0.0
    private var needleVisible = false
    private var needleRejected = false
    private var pressU: Double?
    private var label = ""
    private var contact = false
    private var lastApproachCueAt = 0.0
    private var interlockLampsLit = 0
    private var interlockDoneSent = false
    private var flash: ApproachClearFlash = .none
    private var flashUntil = 0.0
    private var shakeUntil = 0.0
    private var pass: ApproachClearPass?
    private var passUntil = 0.0
    private var easeUntil = 0.0
    private var jamUntil = 0.0
    private var barrierUntil = 0.0
    private var flashRunUntil = 0.0
    private var lamps = ApproachClearLamps()
    private var armed: ApproachClearArm = .none
    private var idleBreath = false
    private var calm: ApproachClearCalm?
    private var frozen = false
    private var lastNow = 0.0
    private var randomCursor = 0

    mutating func tick(at now: Double) -> [ApproachClearCue] {
        lastNow = now
        guard !frozen, phase != .dormant, phase != .calm, let sessionStart else {
            publish(now)
            return []
        }
        if now - sessionStart >= ApproachClearTuning.sessionMs {
            let cues = enterCalm(.quiet, at: now)
            publish(now)
            return cues
        }

        var cues: [ApproachClearCue] = []
        if heat > 0 {
            if phase == .interlock || phase == .easedown {
                comboDeadline = max(comboDeadline, now + ApproachClearTuning.comboHoldMs)
            } else if now > comboDeadline {
                cues += breakCombo(at: now)
            }
        }

        switch phase {
        case .idle:
            if now >= gapUntil {
                cues += beginApproach(at: now)
            }
        case .interlock:
            cues += advanceInterlock(at: now)
        case .barrier:
            if now >= pendingUntil {
                cues += armApproach(at: now)
            }
        case .easedown:
            if now >= pendingUntil {
                cues += armApproach(at: now)
            }
        case .approach:
            cues += advanceApproach(at: now)
        case .resolved:
            cues += advanceLinger(at: now)
        case .dormant, .calm:
            break
        }

        publish(now)
        return cues
    }

    mutating func touchDown(at now: Double) -> [ApproachClearCue] {
        lastNow = now
        guard !frozen, phase != .calm else {
            publish(now)
            return []
        }
        // A finger already down is not a new press. Approach does not judge
        // a hold that began before the needle started moving.
        if contact {
            publish(now)
            return []
        }
        if phase == .dormant {
            startClock(at: now)
            contact = true
            publish(now)
            return []
        }
        contact = true
        guard now >= pressLockedUntil else {
            publish(now)
            return []
        }

        let cues: [ApproachClearCue]
        switch phase {
        case .approach:
            cues = judgePress(at: now)
        case .interlock:
            label = "連動"
            cues = [.interlockReject]
        case .easedown, .dormant, .calm:
            cues = []
        case .idle, .barrier, .resolved:
            cues = jam(at: now)
        }
        publish(now)
        return cues
    }

    mutating func touchUp(at now: Double) -> [ApproachClearCue] {
        lastNow = now
        contact = false
        publish(now)
        return []
    }

    mutating func touchCancel() {
        contact = false
        publish(lastNow)
    }

    mutating func restart(at now: Double) {
        let keptWorld = world
        let keptUnits = randomUnits
        let keptCursor = randomCursor
        let keptLive = liveRandom
        self = ApproachClearEngine()
        world = keptWorld
        randomUnits = keptUnits
        randomCursor = keptCursor
        liveRandom = keptLive
        startClock(at: now)
        lastNow = now
        publish(now)
    }

    mutating func freeze(at now: Double) {
        guard phase != .dormant, !frozen else { return }
        frozen = true
        lastNow = now
        publish(now)
    }

    mutating func thaw(at now: Double) {
        guard frozen else { return }
        let delta = now - lastNow
        if delta > 0 {
            shiftClock(by: delta)
        }
        frozen = false
        lastNow = now
        publish(now)
    }

    // MARK: - Clock

    private mutating func startClock(at now: Double) {
        sessionStart = now
        phase = .idle
        gapUntil = now + ApproachClearTuning.bootGapMs
        scheduledStandbyMs = ApproachClearTuning.bootGapMs
        idleBreath = false
        endPending = false
        easePendingUp = false
        heat = 0
        tier = 0
        clears = 0
        calm = nil
        comboDeadline = 0
        pressLockedUntil = 0
        label = ""
        needleVisible = false
        needleRejected = false
        pressU = nil
        lamps = ApproachClearLamps()
        armed = .none
        bands = ApproachClearBands.laidOut(
            center: ApproachClearTuning.goodCenter,
            goodHalfW: ApproachClearTuning.goodHalfW,
            perfectHalfW: ApproachClearTuning.perfectHalfW0,
            approachMs: ApproachClearTuning.approachMs,
            doubleBlip: false,
            ghostOffset: 0.14
        )
    }

    private mutating func shiftClock(by delta: Double) {
        if let sessionStart {
            self.sessionStart = sessionStart + delta
        }
        gapUntil += delta
        approachStart += delta
        pressLockedUntil += delta
        comboDeadline += delta
        pendingUntil += delta
        flashUntil += delta
        shakeUntil += delta
        passUntil += delta
        easeUntil += delta
        jamUntil += delta
        barrierUntil += delta
        flashRunUntil += delta
        lastApproachCueAt += delta
    }

    // MARK: - Approaches

    private mutating func beginApproach(at now: Double) -> [ApproachClearCue] {
        guard calm == nil else { return [] }
        if easePendingUp {
            easePendingUp = false
            return beginTighten(at: now)
        }
        bands = ApproachClearBands.roll(tier: tier) { nextUnit() }
        let roll = nextUnit()
        if roll < ApproachClearTuning.interlockChance {
            return beginInterlock(at: now)
        }
        if roll < ApproachClearTuning.interlockChance + ApproachClearTuning.barrierChance {
            return beginBarrier(at: now)
        }
        return armApproach(at: now)
    }

    private mutating func beginTighten(at now: Double) -> [ApproachClearCue] {
        let previousGood = bands.goodHalfW
        phase = .easedown
        bands = ApproachClearBands.roll(tier: tier) { nextUnit() }
        bands = ApproachClearBands.laidOut(
            center: bands.center,
            goodHalfW: min(bands.goodHalfW, previousGood * ApproachClearTuning.heatTightenGoodCap),
            perfectHalfW: bands.perfectHalfW,
            approachMs: bands.approachMs,
            doubleBlip: bands.doubleBlip,
            ghostOffset: bands.ghostOffset
        )
        pendingUntil = now + ApproachClearTuning.heatTightenMs
        comboDeadline += ApproachClearTuning.heatTightenMs
        label = ""
        lamps = ApproachClearLamps(approach: true)
        return []
    }

    private mutating func beginInterlock(at now: Double) -> [ApproachClearCue] {
        phase = .interlock
        pendingUntil = now + ApproachClearTuning.interlockSpanMs
        interlockLampsLit = 0
        interlockDoneSent = false
        label = "連動"
        lamps = ApproachClearLamps(approach: true, interlock: true)
        return []
    }

    private mutating func beginBarrier(at now: Double) -> [ApproachClearCue] {
        phase = .barrier
        pendingUntil = now + ApproachClearTuning.barrierHoldMs
        barrierUntil = pendingUntil
        comboDeadline += ApproachClearTuning.barrierHoldMs
        label = ""
        lamps = ApproachClearLamps(approach: true, interlock: true)
        return [.barrier]
    }

    private mutating func armApproach(at now: Double) -> [ApproachClearCue] {
        phase = .approach
        approachStart = now
        lastApproachCueAt = now
        needle = 0
        needleVisible = true
        needleRejected = false
        pressU = nil
        armed = .none
        label = ""
        idleBreath = false
        lamps = ApproachClearLamps(approach: true)
        return []
    }

    private mutating func advanceInterlock(at now: Double) -> [ApproachClearCue] {
        if !world.inService {
            scheduleNext(at: now, delay: ApproachClearTuning.suspendedStandbyMs)
            return []
        }
        var cues: [ApproachClearCue] = []
        let start = pendingUntil - ApproachClearTuning.interlockSpanMs
        while interlockLampsLit < ApproachClearTuning.interlockLamps {
            let at = start
                + ApproachClearTuning.interlockLeadMs
                + ApproachClearTuning.interlockStepMs * Double(interlockLampsLit)
            if now < at { break }
            interlockLampsLit += 1
            cues.append(.interlockStep)
        }
        let doneAt = start
            + ApproachClearTuning.interlockLeadMs
            + ApproachClearTuning.interlockStepMs * Double(ApproachClearTuning.interlockLamps)
        if !interlockDoneSent, now >= doneAt {
            interlockDoneSent = true
            cues.append(.interlockDone)
        }
        if now >= pendingUntil {
            cues += armApproach(at: now)
        }
        return cues
    }

    private mutating func advanceApproach(at now: Double) -> [ApproachClearCue] {
        let duration = max(bands.approachMs, 1)
        let u = (now - approachStart) / duration
        if u >= 1 {
            needle = 1
            return resolve(.timeout, at: now)
        }
        needle = min(1, max(0, u))
        armed = switch bands.zone(at: needle) {
        case .perfect: .perfect
        case .good: .good
        case .out: .none
        }
        if case .perfect = armed {
            lamps.perfect = true
            lamps.good = true
        } else if case .good = armed {
            lamps.perfect = false
            lamps.good = true
        } else {
            lamps.perfect = false
            lamps.good = false
        }
        guard needle >= ApproachClearTuning.vibeApproachNear, needle < bands.goodL else {
            return []
        }
        let interval = 70 + (bands.goodL - needle) * 280
        guard now - lastApproachCueAt >= interval else { return [] }
        lastApproachCueAt = now
        return [.approachPulse]
    }

    private mutating func advanceLinger(at now: Double) -> [ApproachClearCue] {
        guard now >= pendingUntil else { return [] }
        if endPending {
            return enterCalm(.full, at: now)
        }
        scheduleNext(at: pendingUntil, delay: nextDelay)
        if now >= gapUntil {
            return beginApproach(at: now)
        }
        return []
    }

    private mutating func scheduleNext(at now: Double, delay: Double) {
        var wait = delay
        if !world.inService {
            wait = max(wait, ApproachClearTuning.suspendedStandbyMs)
        }
        phase = .idle
        scheduledStandbyMs = wait
        gapUntil = now + wait
        idleBreath = wait >= ApproachClearTuning.idleBreathMinGapMs
        needleVisible = false
        needleRejected = false
        needle = 0
        armed = .none
        lamps = ApproachClearLamps()
        label = ""
    }

    // MARK: - Judgement

    private mutating func judgePress(at now: Double) -> [ApproachClearCue] {
        let duration = max(bands.approachMs, 1)
        let u = min(1, max(0, (now - approachStart) / duration))
        pressU = u
        needle = u
        switch bands.zone(at: u) {
        case .perfect:
            return resolve(.perfect, at: now)
        case .good:
            return resolve(.good, at: now)
        case .out:
            return resolve(u < bands.center ? .missEarly : .missLate, at: now)
        }
    }

    private enum Result {
        case perfect
        case good
        case missEarly
        case missLate
        case timeout
    }

    private mutating func resolve(_ result: Result, at now: Double) -> [ApproachClearCue] {
        phase = .resolved
        pressLockedUntil = now + ApproachClearTuning.pressLockMs
        armed = .none
        var cues: [ApproachClearCue] = []

        switch result {
        case .perfect, .good:
            let perfect = result == .perfect
            clears += 1
            comboDeadline = now + ApproachClearTuning.comboIdleMs
            let previous = tier
            heat += perfect ? ApproachClearTuning.heatPerPerfect : ApproachClearTuning.heatPerGood
            tier = ApproachClearTuning.tier(for: heat)
            if tier > previous {
                easePendingUp = true
                cues.append(.heatUp)
            }
            if clears >= ApproachClearTuning.sessionFullClears {
                endPending = true
            }
            label = perfect ? "良" : "可"
            lamps = ApproachClearLamps(
                approach: perfect,
                perfect: perfect,
                good: !perfect,
                clear: true
            )
            flash = perfect ? .perfect : .good
            flashUntil = now + (perfect ? 140 : 90)
            pass = perfect ? .perfect : .good
            passUntil = now + 280
            needleVisible = false
            needleRejected = false
            if perfect {
                cues.append(.perfect(tier: tier))
            } else {
                cues.append(.good(tier: tier))
            }
            if tier >= 3, world.inService {
                flashRunUntil = now + 320
            }
            let linger = (perfect ? ApproachClearTuning.lingerPerfectMs : ApproachClearTuning.lingerGoodMs)
                + ((endPending && perfect) ? ApproachClearTuning.fullClearBonusMs : 0)
            pendingUntil = now + linger
            nextDelay = perfect
                ? ApproachClearTuning.nextAfterPerfectMs
                : ApproachClearTuning.nextAfterGoodMs
        case .missEarly, .missLate:
            cues += breakCombo(at: now)
            label = result == .missEarly ? "早" : "遅"
            lamps = ApproachClearLamps(reject: true)
            needle = pressU ?? needle
            needleVisible = true
            needleRejected = true
            flash = .miss
            flashUntil = now + 160
            shakeUntil = now + 380
            cues.append(.miss)
            pendingUntil = now + ApproachClearTuning.lingerMissMs
            nextDelay = ApproachClearTuning.nextAfterMissMs
        case .timeout:
            cues += breakCombo(at: now)
            label = "見送り"
            lamps = ApproachClearLamps(reject: true)
            needleVisible = false
            needleRejected = false
            flash = .miss
            flashUntil = now + 140
            cues.append(.pass)
            pendingUntil = now + ApproachClearTuning.lingerTimeoutMs
            nextDelay = ApproachClearTuning.nextAfterTimeoutMs
        }
        return cues
    }

    private mutating func jam(at now: Double) -> [ApproachClearCue] {
        pressLockedUntil = now + ApproachClearTuning.earlyJamMs
        jamUntil = pressLockedUntil
        label = "早"
        lamps = ApproachClearLamps(reject: true)
        var cues = breakCombo(at: now)
        cues.append(.jam)
        return cues
    }

    private mutating func breakCombo(at now: Double) -> [ApproachClearCue] {
        let wasTier = tier
        guard heat > 0 else { return [] }
        heat = 0
        tier = 0
        easePendingUp = false
        guard wasTier >= 1 else { return [] }
        easeUntil = now + 240
        let easy = ApproachClearBands.roll(tier: 0, unit: { 0.5 })
        bands = ApproachClearBands.laidOut(
            center: bands.center,
            goodHalfW: max(bands.goodHalfW, easy.goodHalfW),
            perfectHalfW: max(bands.perfectHalfW, easy.perfectHalfW),
            approachMs: easy.approachMs,
            doubleBlip: bands.doubleBlip,
            ghostOffset: bands.ghostOffset
        )
        return [.easeDown]
    }

    private mutating func enterCalm(_ reason: ApproachClearCalm, at now: Double) -> [ApproachClearCue] {
        phase = .calm
        calm = reason
        heat = 0
        tier = 0
        easePendingUp = false
        endPending = false
        needleVisible = false
        needleRejected = false
        armed = .none
        lamps = ApproachClearLamps()
        label = reason == .full ? "満線" : "閑散"
        idleBreath = false
        if reason == .full {
            return [.sessionFull]
        }
        return []
    }

    // MARK: - Random

    private mutating func nextUnit() -> Double {
        guard randomCursor < randomUnits.count else {
            return liveRandom ? Double.random(in: 0..<1) : 0.5
        }
        let value = randomUnits[randomCursor]
        randomCursor += 1
        return value
    }

    private var phaseName: String {
        switch phase {
        case .dormant: "dormant"
        case .idle: "idle"
        case .approach: "approach"
        case .interlock: "interlock"
        case .barrier: "barrier"
        case .easedown: "easedown"
        case .resolved: "resolved"
        case .calm: "calm"
        }
    }

    // MARK: - Snapshot

    private mutating func publish(_ now: Double) {
        let progress: Double
        if let sessionStart, phase != .dormant {
            progress = min(1, max(0, 1 - (now - sessionStart) / ApproachClearTuning.sessionMs))
        } else {
            progress = 0
        }
        let accent: ApproachClearAccent = switch tier {
        case 1: .warm
        case 2: .hot
        case 3: .blaze
        default: .cyan
        }
        snapshot = ApproachClearSnapshot(
            phase: phase,
            needle: needle,
            needleVisible: needleVisible && phase == .approach || (needleRejected && phase == .resolved),
            needleRejected: needleRejected,
            pressU: pressU,
            bands: bands,
            label: label,
            heat: heat,
            tier: tier,
            clears: clears,
            sessionProgress: progress,
            calm: calm,
            pipsLit: tier,
            accent: accent,
            flash: now < flashUntil ? flash : .none,
            shake: now < shakeUntil,
            passing: now < passUntil ? pass : nil,
            easing: now < easeUntil,
            shrinking: phase == .easedown,
            idleBreath: idleBreath && phase == .idle,
            jammed: now < jamUntil,
            interlockLit: phase == .interlock ? interlockLampsLit : 0,
            barrierOn: phase == .barrier || now < barrierUntil,
            flashRunningLamp: now < flashRunUntil && world.inService,
            lamps: lamps,
            controlEnabled: phase != .calm,
            armed: armed,
            contactDown: contact,
            approachStart: approachStart,
            pressLockedUntil: pressLockedUntil,
            comboDeadline: comboDeadline,
            gapUntil: gapUntil,
            pendingUntil: pendingUntil,
            scheduledStandbyMs: scheduledStandbyMs,
            debug: ApproachClearDebug(
                phase: phaseName,
                heat: heat,
                tier: tier,
                clears: clears,
                approachMs: bands.approachMs,
                goodEarlyMs: bands.goodEarlyMs,
                goodLateMs: bands.goodLateMs,
                perfEarlyMs: bands.perfEarlyMs,
                perfLateMs: bands.perfLateMs
            )
        )
    }
}
