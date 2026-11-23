//
//  OpeningPanelDepartTests.swift
//  Todo trainTests
//
//  DEPART を押したときの順と時刻。時計は差し替える。
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct OpeningPanelDepartTests {
    private let microsecond: TimeInterval = 0.000_001

    @Test func departBeforeMaster_playsDullAndStays() {
        let harness = DepartHarness()
        harness.state.pressDepart()
        #expect(harness.feedback.cues == [.dull])
        #expect(!harness.state.isPowered)
        #expect(!harness.state.hasDeparted)
        #expect(harness.state.departBarDepth == 0)
        #expect(!harness.state.departMarkLit)
        #expect(harness.log.hubs == 0)
        harness.advance(by: 2)
        #expect(harness.log.hubs == 0)
        #expect(harness.state.clockStage == .dark)
    }

    @Test func departBeforeReady_cutsOffTheBootAndStillReachesHub() {
        let harness = DepartHarness()
        harness.state.pressMaster()
        harness.state.pressConfirm(.clock)
        harness.advance(by: OpeningPanelTiming.backlight)
        harness.advance(by: OpeningPanelTiming.clockDigit)
        #expect(harness.state.clockStage == .digits("88"))
        #expect(harness.state.confirmation(of: .clock) == .confirming)
        let frozen = harness.state.clockStage
        let before = harness.feedback.cues.count
        harness.state.pressDepart()
        let added = Array(harness.feedback.cues.dropFirst(before))
        #expect(added == [.heavy, .haptic(.depart)])
        #expect(harness.state.hasDeparted)
        #expect(harness.state.departBarDepth == 1)
        #expect(!harness.state.isReady)
        #expect(harness.log.hubs == 0)

        harness.advance(by: OpeningPanelTiming.hubSwitch - microsecond)
        #expect(harness.state.clockStage == frozen)
        #expect(harness.state.confirmation(of: .clock) == .confirming)
        #expect(harness.state.confirmation(of: .timetable) == .unconfirmed)
        #expect(harness.state.confirmation(of: .tickets) == .unconfirmed)
        #expect(!harness.state.isLockLit(.timetable))
        #expect(!harness.state.isLockLit(.tickets))
        #expect(harness.log.hubs == 0)
        harness.advance(by: microsecond)
        #expect(harness.log.hubs == 1)
        #expect(harness.state.powerLEDCount == OpeningPanelTiming.ledCount)
    }

    @Test func departBeforeReady_dropsOnlyTheLocksThatAreLit() {
        let harness = DepartHarness()
        harness.state.pressMaster()
        harness.state.pressConfirm(.clock)
        harness.advance(until: {
            harness.state.isLockLit(.master) && harness.state.confirmation(of: .clock) == .confirmed
        })
        #expect(harness.state.isLockLit(.master))
        #expect(harness.state.isLockLit(.clock))
        #expect(!harness.state.isLockLit(.timetable))
        #expect(!harness.state.isLockLit(.tickets))

        harness.state.pressDepart()
        #expect(!harness.state.isLockLit(.master))
        #expect(harness.state.isLockLit(.clock))
        harness.advance(by: OpeningPanelTiming.departLockStagger - microsecond)
        #expect(harness.state.isLockLit(.clock))
        harness.advance(by: microsecond)
        #expect(!harness.state.isLockLit(.clock))
        harness.advance(by: 1)
        #expect(!harness.state.isLockLit(.timetable))
        #expect(!harness.state.isLockLit(.tickets))
        #expect(harness.state.confirmation(of: .timetable) == .unconfirmed)
    }

    @Test func departDuringSequence_commitsOrderBeforeTheSameMotion() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let tickets = (0..<3).map { index in
            Ticket(title: "切符\(index)", estimatedSeconds: 600, sortOrder: index)
        }
        tickets.forEach { context.insert($0) }
        let model = OpeningPanelTicketsModel()
        model.sync(tickets: tickets, sessions: [])
        #expect(model.beginSequence(sessions: [], freeMinutes: 1_000, in: context, seed: 1))
        #expect(model.chooseSequencePile(0))
        model.finishSequenceEarly()
        let expected = model.rows.map(\.id)

        let seen = DepartCommitProbe()
        let box = DepartStateBox()
        let harness = DepartHarness(ticketCount: 3) {
            seen.departed = box.state?.hasDeparted ?? true
            seen.depth = box.state?.departBarDepth ?? -1
            model.commitSequenceOrder(in: context)
        }
        box.state = harness.state

        harness.state.pressMaster()
        harness.state.pressConfirm(.tickets)
        harness.advance(until: { harness.state.confirmation(of: .tickets) == .confirmed })
        #expect(harness.state.confirmation(of: .tickets) == .confirmed)
        harness.state.pressSequence()
        #expect(harness.state.isSequencing)
        #expect(model.engine != nil)
        let before = harness.feedback.cues.count
        harness.state.pressDepart()
        let added = Array(harness.feedback.cues.dropFirst(before))

        #expect(seen.departed == false)
        #expect(seen.depth == 0)
        #expect(!harness.state.isSequencing)
        #expect(harness.state.hasDeparted)
        #expect(harness.state.departBarDepth == 1)
        #expect(added == [.heavy, .haptic(.depart)])
        #expect(model.engine == nil)
        #expect(model.rows.map(\.id) == expected)
        #expect(tickets.sorted { $0.sortOrder < $1.sortOrder }.map(\.id) == expected)
        #expect(harness.log.hubs == 0)
        harness.advance(by: OpeningPanelTiming.hubSwitch - microsecond)
        #expect(harness.log.hubs == 0)
        harness.advance(by: microsecond)
        #expect(harness.log.hubs == 1)
    }

    @Test func departPress_followsTheSpecClock() {
        let harness = DepartHarness(ticketCount: 1)
        harness.bringToReady()
        #expect(harness.state.isReady)
        #expect(harness.state.readyLampLit)
        #expect(harness.state.isLockLit(.master))
        #expect(harness.state.isLockLit(.clock))
        #expect(harness.state.isLockLit(.timetable))
        #expect(harness.state.isLockLit(.tickets))

        let before = harness.feedback.cues.count
        harness.state.pressDepart()
        #expect(Array(harness.feedback.cues.dropFirst(before)) == [.heavy, .haptic(.depart)])
        #expect(harness.state.departBarDepth == 1)
        #expect(!harness.state.departMarkLit)
        #expect(!harness.state.readyLampLit)
        #expect(!harness.state.isLockLit(.master))
        #expect(harness.state.isLockLit(.clock))
        #expect(harness.state.chevronFill == 0)
        #expect(!harness.state.departColumnLit)
        #expect(harness.state.glowingFaces.isEmpty)
        #expect(harness.state.powerLEDCount == OpeningPanelTiming.ledCount)

        var t: TimeInterval = 0
        func jump(_ target: TimeInterval) {
            harness.advance(by: target - t)
            t = target
        }

        jump(OpeningPanelTiming.departBarStep)
        #expect(harness.state.departBarDepth == 2)
        #expect(harness.state.isLockLit(.clock))
        jump(OpeningPanelTiming.departLockStagger)
        #expect(!harness.state.isLockLit(.clock))
        #expect(harness.state.isLockLit(.timetable))
        jump(OpeningPanelTiming.departBarStep * 2)
        #expect(harness.state.departBarDepth == 3)
        #expect(!harness.state.departMarkLit)
        jump(OpeningPanelTiming.departLockStagger * 2)
        #expect(!harness.state.isLockLit(.timetable))
        #expect(harness.state.isLockLit(.tickets))
        jump(OpeningPanelTiming.departMarkDelay)
        #expect(harness.state.departMarkLit)
        #expect(harness.state.isLockLit(.tickets))
        #expect(abs(OpeningPanelTiming.departMarkDelay - 0.066) < 0.000_001)
        jump(OpeningPanelTiming.departLockStagger * 3)
        #expect(!harness.state.isLockLit(.tickets))

        jump(OpeningPanelTiming.chevronLead)
        #expect(harness.state.chevronFill == 1)
        #expect(!harness.state.departColumnLit)
        var fire = OpeningPanelTiming.chevronLead
        for (index, step) in OpeningPanelTiming.chevronSteps.enumerated() {
            jump(fire + step - microsecond)
            #expect(harness.state.chevronFill == index + 1)
            #expect(!harness.state.departColumnLit)
            fire += step
            jump(fire)
            if index + 1 < OpeningPanelTiming.chevronSteps.count {
                #expect(harness.state.chevronFill == index + 2)
            }
        }
        #expect(harness.state.chevronFill == OpeningPanelTiming.chevronSteps.count)
        #expect(harness.state.departColumnLit)
        jump(fire + OpeningPanelTiming.departColumnFlash - microsecond)
        #expect(harness.state.departColumnLit)
        jump(fire + OpeningPanelTiming.departColumnFlash)
        #expect(!harness.state.departColumnLit)

        jump(OpeningPanelTiming.hubSwitch - microsecond)
        #expect(harness.log.hubs == 0)
        jump(OpeningPanelTiming.hubSwitch)
        #expect(harness.log.hubs == 1)
        #expect(harness.state.powerLEDCount == OpeningPanelTiming.ledCount)
    }

    @Test func departSweep_lightsEachModuleFromTheBottomForSixtyMilliseconds() {
        let harness = DepartHarness(ticketCount: 1)
        harness.bringToReady()
        harness.state.pressDepart()
        let faces = Array(OpeningPanelFace.allCases.reversed())
        #expect(faces == [
            .depart, .comm, .load, .tickets, .nowBoard, .timetable, .clockKey, .clock, .master, .sysbar,
        ])
        var t: TimeInterval = 0
        for (index, face) in faces.enumerated() {
            let start = OpeningPanelTiming.departSweepLead
                + Double(index) * OpeningPanelTiming.departModuleStagger
            harness.advance(by: start - t)
            t = start
            #expect(harness.state.glowingFaces.contains(face))
            #expect(harness.state.powerLEDCount == OpeningPanelTiming.ledCount)
            let end = start + OpeningPanelTiming.departModuleGlow
            harness.advance(by: end - t - microsecond)
            #expect(harness.state.glowingFaces.contains(face))
            harness.advance(by: microsecond)
            t = end
            #expect(!harness.state.glowingFaces.contains(face))
        }
    }

    @Test func chevronWave_matchesTheMockFrames() {
        #expect(DepartChevronWave.steps == [
            0.110, 0.090, 0.075, 0.062, 0.052, 0.044, 0.038, 0.033, 0.029, 0.026,
        ])
        #expect(OpeningPanelTiming.chevronSteps == [
            0.050, 0.040, 0.032, 0.026, 0.022, 0.019, 0.017, 0.015, 0.014, 0.014,
        ])
        let first = DepartChevronWave.draw(head: 0)
        #expect(first[0] == 0.85)
        #expect(first.dropFirst().allSatisfy { $0 == 0 })
        let second = DepartChevronWave.draw(head: 1)
        #expect(second[0] == 0.43)
        #expect(second[1] == 0.85)
        let hit = DepartChevronWave.sample(elapsed: DepartChevronWave.sweep)
        #expect(hit.columnHit)
        #expect(hit.alphas[9] == 0.85)
        #expect(hit.alphas[8] == 0.30)
        #expect(hit.alphas[7] == 0.30)
        #expect(hit.alphas[6] == 0)
        let resting = DepartChevronWave.sample(elapsed: DepartChevronWave.sweep + DepartChevronWave.hitHold)
        #expect(!resting.columnHit)
        #expect(resting.alphas.allSatisfy { $0 == 0 })
    }

    @Test func frameEdges_changeThePicture() {
        let origin = waveCycleStart()
        var date = origin
        let visits = DepartChevronWave.changePoints.count + 1
        for _ in 0..<visits {
            let next = DepartChevronWave.nextFrameEdge(after: date)
            #expect(next > date)
            #expect(DepartChevronWave.sample(at: next) != DepartChevronWave.sample(at: date))
            date = next
        }
        let elapsed = date.timeIntervalSince(origin)
        #expect(abs(elapsed - DepartChevronWave.period) < 0.02)
        var cursor = origin
        var fires = 0
        while cursor < origin.addingTimeInterval(2), fires < 80 {
            cursor = DepartChevronWave.nextFrameEdge(after: cursor)
            fires += 1
        }
        #expect(fires >= 18)
        #expect(fires <= 28)
    }

    @Test func columnEdges_toggleTheHit() {
        let origin = waveCycleStart()
        let first = DepartChevronWave.nextColumnEdge(after: origin)
        #expect(abs(first.timeIntervalSince(origin) - DepartChevronWave.sweep) < 0.01)
        #expect(DepartChevronWave.sample(at: first).columnHit)
        let second = DepartChevronWave.nextColumnEdge(after: first)
        #expect(abs(second.timeIntervalSince(first) - DepartChevronWave.hitHold) < 0.01)
        #expect(!DepartChevronWave.sample(at: second).columnHit)
        let third = DepartChevronWave.nextColumnEdge(after: second)
        #expect(DepartChevronWave.sample(at: third).columnHit)
        #expect(abs(third.timeIntervalSince(second) - (DepartChevronWave.rest + DepartChevronWave.sweep)) < 0.01)
    }
}

/// 周期の先頭（最初の段）に合わせた、桁が安定している時刻。
private func waveCycleStart() -> Date {
    let anchor = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let cycle = DepartChevronWave.period
    var phase = anchor.timeIntervalSince(.distantPast).truncatingRemainder(dividingBy: cycle)
    if phase < 0 { phase += cycle }
    let origin = anchor.addingTimeInterval(cycle - phase)
    let first = DepartChevronWave.sample(elapsed: 0)
    if DepartChevronWave.sample(at: origin) == first { return origin }
    return origin.addingTimeInterval(0.001)
}

@MainActor
private final class DepartCommitProbe {
    var departed = true
    var depth = -1
}

@MainActor
private final class DepartStateBox {
    var state: OpeningPanelState?
}

@MainActor
private final class DepartCueLog: OpeningPanelFeedback {
    private(set) var cues: [OpeningPanelCue] = []

    func play(_ cue: OpeningPanelCue) {
        cues.append(cue)
    }
}

@MainActor
private final class DepartLog {
    var hubs = 0
}

@MainActor
private final class DepartClock: OpeningPanelScheduling {
    private struct Item {
        var id: Int
        var due: Int64
        var action: () -> Void
    }

    private var now: Int64 = 0
    private var nextID = 0
    private var items: [Item] = []

    func schedule(after seconds: TimeInterval, execute: @escaping () -> Void) -> OpeningPanelTask {
        let id = nextID
        nextID += 1
        items.append(Item(id: id, due: now + microseconds(seconds), action: execute))
        return OpeningPanelTask { [weak self] in
            self?.items.removeAll { $0.id == id }
        }
    }

    func advance(by seconds: TimeInterval) {
        advance(to: now + microseconds(seconds))
    }

    private func advance(to target: Int64) {
        while true {
            guard let index = nextIndex(), items[index].due <= target else {
                now = target
                return
            }
            let item = items.remove(at: index)
            now = item.due
            item.action()
        }
    }

    private func nextIndex() -> Int? {
        items.indices.min { lhs, rhs in
            let left = items[lhs]
            let right = items[rhs]
            if left.due != right.due { return left.due < right.due }
            return left.id < right.id
        }
    }

    private func microseconds(_ seconds: TimeInterval) -> Int64 {
        Int64((seconds * 1_000_000).rounded())
    }
}

@MainActor
private final class DepartHarness {
    let clock: DepartClock
    let feedback: DepartCueLog
    let log: DepartLog
    let state: OpeningPanelState

    init(ticketCount: Int = 0, onCommit: @escaping () -> Void = {}) {
        let clock = DepartClock()
        let feedback = DepartCueLog()
        let log = DepartLog()
        self.clock = clock
        self.feedback = feedback
        self.log = log
        state = OpeningPanelState(
            scheduler: clock,
            feedback: feedback,
            ticketCount: ticketCount,
            onCommitSequence: onCommit,
            onShowHub: { log.hubs += 1 }
        )
    }

    func advance(by seconds: TimeInterval) {
        clock.advance(by: seconds)
    }

    func advance(until predicate: () -> Bool, limit: TimeInterval = 8) {
        var left = limit
        while !predicate(), left > 0 {
            advance(by: 0.001)
            left -= 0.001
        }
        #expect(predicate())
    }

    func bringToReady() {
        state.pressMaster()
        state.pressConfirm(.clock)
        state.pressConfirm(.timetable)
        state.pressConfirm(.tickets)
        advance(until: { state.isReady })
    }
}
