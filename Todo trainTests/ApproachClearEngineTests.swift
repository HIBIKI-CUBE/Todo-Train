//
//  ApproachClearEngineTests.swift
//  Todo trainTests
//

import Testing
@testable import Todo_train

struct ApproachClearEngineTests {
    @Test func tierZeroWindowMatchesFrozenWidths() {
        let bands = ApproachClearBands.roll(tier: 0) { 0.5 }
        #expect(bands.approachMs == 1_180)
        #expect(abs(bands.goodEarlyMs - 56) < 0.2)
        #expect(abs(bands.goodLateMs - 78) < 0.2)
        #expect(abs(bands.perfEarlyMs - 13.0) < 0.15)
        #expect(abs(bands.perfLateMs - 15.3) < 0.15)
        #expect(bands.goodEarlyMs < bands.goodLateMs)
        #expect(bands.perfEarlyMs < bands.perfLateMs)
    }

    @Test func heatMultipliersMatchFrozenTable() {
        let expected: [(Double, Double, Double, Double)] = [
            (1_180, 56, 78, 15.3),
            (1_086, 46, 65, 13.0),
            (1_003, 38, 53, 12.0),
            (944, 32, 45, 12.0),
        ]
        for tier in 0..<4 {
            let bands = ApproachClearBands.roll(tier: tier) { 0.5 }
            let row = expected[tier]
            #expect(bands.approachMs == row.0, "tier \(tier) approach \(bands.approachMs)")
            #expect(abs(bands.goodEarlyMs - row.1) < 0.6, "tier \(tier) early \(bands.goodEarlyMs)")
            #expect(abs(bands.goodLateMs - row.2) < 0.6, "tier \(tier) late \(bands.goodLateMs)")
            #expect(abs(bands.perfLateMs - row.3) < 0.2, "tier \(tier) perf \(bands.perfLateMs)")
            if tier >= 2 {
                #expect(bands.perfLateMs >= 11.999)
            }
        }
    }

    @Test func pressTimeJudgesNotTheNeedle() {
        var engine = makeEngine()
        _ = engine.touchDown(at: 0)
        #expect(engine.snapshot.phase == .idle)
        _ = engine.touchUp(at: 40)
        _ = engine.tick(at: engine.snapshot.gapUntil)
        #expect(engine.snapshot.phase == .approach)
        let late = engine.snapshot.approachStart + engine.snapshot.bands.approachMs * 0.72
        _ = engine.tick(at: late)
        #expect(engine.snapshot.needle > engine.snapshot.bands.goodR)
        #expect(engine.snapshot.phase == .approach)
        let press = engine.snapshot.approachStart + engine.snapshot.bands.center * engine.snapshot.bands.approachMs
        let cues = engine.touchDown(at: press)
        #expect(engine.snapshot.label == "良")
        #expect(cues.contains(.perfect(tier: 0)))
        #expect(engine.snapshot.phase == .resolved)
        #expect(engine.touchUp(at: press + 30).isEmpty)
        #expect(engine.snapshot.phase == .resolved)
    }

    @Test func heldFingerDoesNotJudgeWhenApproachArms() {
        var engine = makeEngine()
        _ = engine.touchDown(at: 0)
        _ = engine.tick(at: engine.snapshot.gapUntil)
        let center = engine.snapshot.approachStart
            + engine.snapshot.bands.center * engine.snapshot.bands.approachMs
        _ = engine.tick(at: center)
        #expect(engine.snapshot.phase == .approach)
        #expect(engine.snapshot.label.isEmpty)
        #expect(engine.touchUp(at: center + 10).isEmpty)
        #expect(engine.snapshot.phase == .approach)
    }

    @Test func touchCancelDoesNotJudgeOrJam() {
        var engine = makeEngine()
        _ = engine.touchDown(at: 0)
        _ = engine.tick(at: engine.snapshot.gapUntil)
        engine.touchCancel()
        let center = engine.snapshot.approachStart + engine.snapshot.bands.center * engine.snapshot.bands.approachMs
        #expect(engine.touchUp(at: center).isEmpty)
        #expect(engine.snapshot.phase == .approach)
        #expect(engine.snapshot.pressLockedUntil == 0)
        #expect(engine.snapshot.label.isEmpty)
        _ = engine.tick(at: engine.snapshot.approachStart + engine.snapshot.bands.approachMs)
        #expect(engine.snapshot.label == "見送り")
    }

    @Test func openingPressStartsTheClockWithoutJam() {
        var engine = makeEngine()
        let cues = engine.touchDown(at: 0)
        #expect(cues.isEmpty)
        #expect(engine.snapshot.phase == .idle)
        #expect(engine.snapshot.label != "早")
        #expect(engine.snapshot.pressLockedUntil == 0)
        #expect(engine.touchUp(at: 100).isEmpty)
        #expect(engine.snapshot.phase == .idle)
        _ = engine.tick(at: 260)
        #expect(engine.snapshot.phase == .approach)
    }

    @Test func secondPressDuringBootJams() {
        var engine = makeEngine()
        _ = engine.touchDown(at: 0)
        _ = engine.touchUp(at: 40)
        let cues = engine.touchDown(at: 80)
        #expect(cues.contains(.jam))
        #expect(engine.snapshot.label == "早")
        #expect(engine.snapshot.pressLockedUntil == 80 + ApproachClearTuning.earlyJamMs)
    }

    @Test func laterIdlePressJamsAndLocksInput() {
        var engine = makeEngine()
        _ = engine.touchDown(at: 0)
        _ = engine.touchUp(at: 100)
        _ = engine.tick(at: 260)
        let end = engine.snapshot.approachStart + engine.snapshot.bands.approachMs
        _ = engine.tick(at: end)
        #expect(engine.snapshot.phase == .resolved)
        _ = engine.tick(at: engine.snapshot.pendingUntil)
        #expect(engine.snapshot.phase == .idle)
        let when = engine.snapshot.gapUntil - 20
        let cues = engine.touchDown(at: when)
        #expect(cues.contains(.jam))
        #expect(engine.snapshot.label == "早")
        #expect(engine.snapshot.pressLockedUntil == when + ApproachClearTuning.earlyJamMs)
    }

    @Test func pressLockIgnoresTheNextPress() {
        var engine = makeEngine()
        let press = clearPerfect(&engine, now: 0)
        let ignored = engine.touchDown(at: press + 20)
        #expect(ignored.isEmpty)
        #expect(engine.snapshot.phase == .resolved)
        #expect(engine.snapshot.label == "良")
        _ = engine.touchUp(at: press + 30)
        let jammed = engine.touchDown(at: press + 60)
        #expect(jammed.contains(.jam))
    }

    @Test func deadTimeUsesLingerPlusNextAfter() {
        var engine = makeEngine()
        let release = clearPerfect(&engine, now: 0)
        _ = engine.tick(at: release + ApproachClearTuning.lingerPerfectMs)
        #expect(engine.snapshot.phase == .idle)
        #expect(engine.snapshot.scheduledStandbyMs == ApproachClearTuning.nextAfterPerfectMs)
        #expect(engine.snapshot.gapUntil == release + ApproachClearTuning.lingerPerfectMs + ApproachClearTuning.nextAfterPerfectMs)

        var miss = makeEngine()
        _ = miss.touchDown(at: 0)
        _ = miss.touchUp(at: 40)
        _ = miss.tick(at: 260)
        let early = miss.snapshot.approachStart + miss.snapshot.bands.goodL * 0.5 * miss.snapshot.bands.approachMs
        _ = miss.touchDown(at: early)
        #expect(miss.snapshot.label == "早")
        _ = miss.tick(at: early + ApproachClearTuning.lingerMissMs)
        #expect(miss.snapshot.scheduledStandbyMs == ApproachClearTuning.nextAfterMissMs)

        var timeout = makeEngine()
        _ = timeout.touchDown(at: 0)
        _ = timeout.touchUp(at: 50)
        _ = timeout.tick(at: 260)
        let end = timeout.snapshot.approachStart + timeout.snapshot.bands.approachMs
        _ = timeout.tick(at: end)
        #expect(timeout.snapshot.label == "見送り")
        _ = timeout.tick(at: end + ApproachClearTuning.lingerTimeoutMs)
        #expect(timeout.snapshot.scheduledStandbyMs == ApproachClearTuning.nextAfterTimeoutMs)
    }

    @Test func goodPressIsInsideTheWideBandOnly() {
        var engine = makeEngine()
        _ = engine.touchDown(at: 0)
        _ = engine.touchUp(at: 40)
        _ = engine.tick(at: 260)
        let bands = engine.snapshot.bands
        let goodU = (bands.goodL + bands.perfL) / 2
        let press = engine.snapshot.approachStart + goodU * bands.approachMs
        let cues = engine.touchDown(at: press)
        #expect(engine.snapshot.label == "可")
        #expect(cues.contains(.good(tier: 0)))
        #expect(engine.snapshot.heat == ApproachClearTuning.heatPerGood)
    }

    @Test func missContinuesTheLoop() {
        var engine = makeEngine()
        _ = engine.touchDown(at: 0)
        _ = engine.touchUp(at: 40)
        _ = engine.tick(at: 260)
        let early = engine.snapshot.approachStart
        _ = engine.touchDown(at: early + 1)
        #expect(engine.snapshot.phase == .resolved)
        #expect(engine.snapshot.calm == nil)
        _ = engine.tick(at: engine.snapshot.pendingUntil)
        _ = engine.tick(at: engine.snapshot.gapUntil)
        #expect(engine.snapshot.phase == .approach)
    }

    @Test func heatThresholdsAndEaseDown() {
        #expect(ApproachClearTuning.tier(for: 1.49) == 0)
        #expect(ApproachClearTuning.tier(for: 1.5) == 1)
        #expect(ApproachClearTuning.tier(for: 3) == 2)
        #expect(ApproachClearTuning.tier(for: 5) == 3)

        var engine = makeEngine()
        var now = 0.0
        _ = clearPerfect(&engine, now: now)
        #expect(engine.snapshot.tier == 0)
        #expect(engine.snapshot.heat == 1)
        now = engine.snapshot.pendingUntil
        _ = engine.tick(at: now)
        let broken = engine.tick(at: engine.snapshot.comboDeadline + 1)
        #expect(engine.snapshot.heat == 0)
        #expect(!broken.contains(.easeDown))

        var hot = makeEngine()
        _ = clearPerfect(&hot, now: 0)
        let second = clearPerfect(&hot, now: hot.snapshot.pendingUntil)
        #expect(hot.snapshot.tier == 1)
        let eased = hot.tick(at: second + ApproachClearTuning.comboIdleMs + 1)
        #expect(hot.snapshot.heat == 0)
        #expect(hot.snapshot.tier == 0)
        #expect(eased.contains(.easeDown))
    }

    @Test func interlockRejectKeepsHeatAndBarrierJams() {
        var engine = makeEngine(units: script(direct: 1, then: 0.01))
        let release = clearPerfect(&engine, now: 0)
        _ = engine.tick(at: release + ApproachClearTuning.lingerPerfectMs)
        _ = engine.tick(at: engine.snapshot.gapUntil)
        #expect(engine.snapshot.phase == .interlock)
        let heat = engine.snapshot.heat
        let cues = engine.touchDown(at: engine.snapshot.gapUntil + 10)
        #expect(cues == [.interlockReject])
        #expect(engine.snapshot.heat == heat)
        #expect(engine.snapshot.phase == .interlock)

        var barrier = makeEngine(units: script(direct: 0, then: 0.05))
        _ = barrier.touchDown(at: 0)
        _ = barrier.touchUp(at: 40)
        _ = barrier.tick(at: 260)
        #expect(barrier.snapshot.phase == .barrier)
        let jammed = barrier.touchDown(at: 280)
        #expect(jammed.contains(.jam))
        _ = barrier.tick(at: barrier.snapshot.pendingUntil)
        #expect(barrier.snapshot.phase == .approach)
    }

    @Test func interlockAndTightenHoldTheComboClock() {
        var engine = makeEngine(units: script(direct: 1, then: 0.01))
        let release = clearPerfect(&engine, now: 0)
        _ = engine.tick(at: release + ApproachClearTuning.lingerPerfectMs)
        _ = engine.tick(at: engine.snapshot.gapUntil)
        #expect(engine.snapshot.phase == .interlock)
        let cues = engine.tick(at: engine.snapshot.comboDeadline + 5_000)
        #expect(engine.snapshot.heat == 1)
        #expect(!cues.contains(.easeDown))

        var tighten = makeEngine()
        _ = clearPerfect(&tighten, now: 0)
        let second = clearPerfect(&tighten, now: tighten.snapshot.pendingUntil)
        _ = tighten.tick(at: second + ApproachClearTuning.lingerPerfectMs)
        _ = tighten.tick(at: tighten.snapshot.gapUntil)
        #expect(tighten.snapshot.phase == .easedown)
        let ignored = tighten.touchDown(at: tighten.snapshot.pendingUntil - 20)
        #expect(ignored.isEmpty)
        #expect(tighten.snapshot.phase == .easedown)
        #expect(tighten.snapshot.tier == 1)
        let held = tighten.tick(at: second + ApproachClearTuning.comboIdleMs + 10)
        #expect(tighten.snapshot.heat == 2)
        #expect(!held.contains(.easeDown))
    }

    @Test func suspendedStandbyStretchesAndAbortsInterlock() {
        var engine = makeEngine()
        engine.world.inService = false
        let release = clearPerfect(&engine, now: 0)
        _ = engine.tick(at: release + ApproachClearTuning.lingerPerfectMs)
        #expect(engine.snapshot.scheduledStandbyMs == ApproachClearTuning.suspendedStandbyMs)

        var interlock = makeEngine(units: script(direct: 0, then: 0.01))
        _ = interlock.touchDown(at: 0)
        _ = interlock.touchUp(at: 20)
        _ = interlock.tick(at: 260)
        #expect(interlock.snapshot.phase == .interlock)
        interlock.world.inService = false
        _ = interlock.tick(at: 300)
        #expect(interlock.snapshot.phase == .idle)
        #expect(interlock.snapshot.scheduledStandbyMs == ApproachClearTuning.suspendedStandbyMs)
    }

    @Test func fourteenClearsOrFortySecondsEndQuietly() {
        var engine = makeEngine()
        var now = 0.0
        var release = 0.0
        for _ in 0..<ApproachClearTuning.sessionFullClears {
            release = clearPerfect(&engine, now: now)
            now = engine.snapshot.pendingUntil
            if engine.snapshot.phase == .resolved {
                _ = engine.tick(at: now)
            }
        }
        #expect(engine.snapshot.clears == ApproachClearTuning.sessionFullClears)
        if engine.snapshot.phase != .calm {
            _ = engine.tick(at: engine.snapshot.pendingUntil)
        }
        #expect(engine.snapshot.phase == .calm)
        #expect(engine.snapshot.calm == .full)
        #expect(engine.snapshot.label == "満線")
        _ = engine.tick(at: release + 30_000)
        #expect(engine.snapshot.phase == .calm)

        var quiet = makeEngine()
        _ = quiet.touchDown(at: 0)
        let cues = quiet.tick(at: ApproachClearTuning.sessionMs)
        #expect(quiet.snapshot.phase == .calm)
        #expect(quiet.snapshot.calm == .quiet)
        #expect(quiet.snapshot.label == "閑散")
        #expect(!cues.contains(.sessionFull))
        _ = quiet.tick(at: ApproachClearTuning.sessionMs + 10_000)
        #expect(quiet.snapshot.phase == .calm)
        quiet.restart(at: 60_000)
        #expect(quiet.snapshot.phase == .idle)
        #expect(quiet.snapshot.clears == 0)
        #expect(quiet.snapshot.heat == 0)
        _ = quiet.tick(at: 60_000 + ApproachClearTuning.bootGapMs)
        #expect(quiet.snapshot.phase == .approach)
    }

    @Test func returningToTierZeroDoesNotKeepANarrowPerfectBand() {
        var engine = makeEngine()
        _ = clearPerfect(&engine, now: 0)
        _ = clearPerfect(&engine, now: engine.snapshot.pendingUntil)
        #expect(engine.snapshot.tier == 1)
        let early = engine.snapshot.approachStart
        _ = engine.tick(at: engine.snapshot.pendingUntil)
        _ = engine.tick(at: engine.snapshot.gapUntil)
        if engine.snapshot.phase == .easedown {
            _ = engine.tick(at: engine.snapshot.pendingUntil)
        }
        #expect(engine.snapshot.phase == .approach)
        _ = engine.touchDown(at: engine.snapshot.approachStart + 1)
        #expect(engine.snapshot.label == "早")
        #expect(engine.snapshot.tier == 0)
        _ = engine.tick(at: engine.snapshot.pendingUntil)
        _ = engine.tick(at: engine.snapshot.gapUntil)
        #expect(engine.snapshot.phase == .approach)
        #expect(abs(engine.snapshot.bands.perfLateMs - 15.3) < 0.2)
        _ = early
    }

    @Test func theSamePressLandsLeftWhenLatencyIsRemoved() {
        var raw = makeEngine()
        var compensated = makeEngine()
        armApproach(&raw)
        armApproach(&compensated)
        #expect(raw.snapshot.phase == .approach)
        #expect(compensated.snapshot.approachStart == raw.snapshot.approachStart)
        let duration = raw.snapshot.bands.approachMs
        let physical = raw.snapshot.approachStart + duration * raw.snapshot.bands.center
        _ = raw.touchDown(at: ApproachClearLatency.judgementMs(touchMs: physical, inputLatencyMs: 0))
        _ = compensated.touchDown(
            at: ApproachClearLatency.judgementMs(touchMs: physical, inputLatencyMs: 40)
        )
        let rawU = raw.snapshot.pressU ?? 1
        let shiftedU = compensated.snapshot.pressU ?? 1
        #expect(shiftedU < rawU)
        #expect(abs((rawU - shiftedU) * duration - 40) < 0.01)
        #expect(raw.snapshot.label == "良")
    }

    @Test func upWithoutDownIsIgnored() {
        var engine = makeEngine()
        #expect(engine.touchUp(at: 500).isEmpty)
        #expect(engine.snapshot.phase == .dormant)
    }
}

private func armApproach(_ engine: inout ApproachClearEngine) {
    _ = engine.touchDown(at: 0)
    _ = engine.touchUp(at: 40)
    _ = engine.tick(at: engine.snapshot.gapUntil)
}

private func makeEngine(units: [Double] = []) -> ApproachClearEngine {
    var engine = ApproachClearEngine()
    engine.world = ApproachClearWorld(inService: true, dayEndPrompt: false, paused: false)
    engine.randomUnits = units
    return engine
}

private func script(direct: Int, then variant: Double) -> [Double] {
    var units: [Double] = []
    for draw in 0..<(direct + 1) {
        for _ in 0..<6 {
            units.append(0.5)
        }
        units.append(draw == direct ? variant : 0.5)
    }
    return units
}

@discardableResult
private func clearPerfect(_ engine: inout ApproachClearEngine, now: Double) -> Double {
    var cursor = now
    if engine.snapshot.phase == .dormant {
        _ = engine.touchDown(at: cursor)
    }
    var safety = 0
    while engine.snapshot.phase != .approach && engine.snapshot.phase != .calm && safety < 8 {
        safety += 1
        switch engine.snapshot.phase {
        case .idle:
            cursor = engine.snapshot.gapUntil
        case .easedown, .barrier, .interlock, .resolved:
            cursor = engine.snapshot.pendingUntil
        default:
            cursor += 1
        }
        _ = engine.tick(at: cursor)
    }
    let release = engine.snapshot.approachStart
        + engine.snapshot.bands.center * engine.snapshot.bands.approachMs
    if engine.snapshot.contactDown {
        _ = engine.touchUp(at: cursor)
    }
    _ = engine.touchDown(at: release)
    _ = engine.touchUp(at: release)
    return release
}
