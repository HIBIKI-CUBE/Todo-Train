//
//  OpeningPanelSystemTests.swift
//  Todo trainTests
//
//  CHK の点滅、PHONE の窓、COMM の出し分け、LOAD の点灯と段。
//

import Foundation
import Testing
import TodoTrainSync
import UIKit
@testable import Todo_train

@MainActor
struct OpeningPanelSystemTests {
    @Test func checkBlinkEndsGreen() {
        let harness = SystemHarness()
        harness.state.pressMaster()
        harness.advance(by: OpeningPanelTiming.lampCheck)
        for _ in 1...OpeningPanelTiming.ledCount {
            harness.advance(by: OpeningPanelTiming.powerLEDStep)
        }
        harness.advance(by: OpeningPanelTiming.powerLEDSettle)
        #expect(harness.state.checkStep(for: .master) == 0)
        #expect(OpeningPanelSystem.checkLamp(powered: true, lit: harness.state.checkIsLit(.master)) == .green)

        for step in 1...OpeningPanelTiming.checkBlinkLast {
            harness.advance(by: OpeningPanelTiming.checkBlink)
            let lit = harness.state.checkIsLit(.master)
            #expect(lit == step.isMultiple(of: 2))
            let style = OpeningPanelSystem.checkLamp(powered: true, lit: lit)
            #expect(style == (lit ? .green : .off))
        }
        harness.advance(by: OpeningPanelTiming.checkBlink)
        #expect(harness.state.checkStep(for: .master) == OpeningPanelTiming.checkBlinkLast)
        #expect(OpeningPanelSystem.checkLamp(powered: true, lit: harness.state.checkIsLit(.master)) == .green)

        harness.state.pressMaster()
        #expect(OpeningPanelSystem.checkLamp(powered: harness.state.isPowered, lit: harness.state.checkIsLit(.master)) == .off)
    }

    @Test func phoneWindowFollowsTheSourceTable() {
        #expect(OpeningPanelSystem.monitorsBattery(panelVisible: true, powered: true))
        #expect(!OpeningPanelSystem.monitorsBattery(panelVisible: true, powered: false))
        #expect(!OpeningPanelSystem.monitorsBattery(panelVisible: false, powered: true))

        let full = OpeningPanelPhone.reading(powered: true, supply: .full, keepAwake: true)
        #expect(full.text == "FULL")
        #expect(full.extLit)
        #expect(full.awakeLit)

        let chargingAsleep = OpeningPanelPhone.reading(powered: true, supply: .charging, keepAwake: false)
        #expect(chargingAsleep.text == "CHG")
        #expect(chargingAsleep.extLit)
        #expect(!chargingAsleep.awakeLit)

        let low = OpeningPanelPhone.reading(powered: true, supply: .unplugged(percent: 20), keepAwake: true)
        #expect(low.text == "LO 20%")
        #expect(!low.extLit)
        #expect(!low.awakeLit)

        let above = OpeningPanelPhone.reading(powered: true, supply: .unplugged(percent: 21), keepAwake: true)
        #expect(above.text == "21%")

        let unknown = OpeningPanelPhone.reading(powered: true, supply: .unknown, keepAwake: true)
        #expect(unknown.text == "----")
        #expect(!unknown.extLit)

        let dark = OpeningPanelPhone.reading(powered: false, supply: .charging, keepAwake: true)
        #expect(dark == .hidden)

        #expect(OpeningPanelSystem.phoneSupply(state: .unknown, level: -1) == .unknown)
        #expect(OpeningPanelSystem.phoneSupply(state: .full, level: 1) == .full)
        #expect(OpeningPanelSystem.phoneSupply(state: .charging, level: 0.64) == .charging)
        #expect(OpeningPanelSystem.phoneSupply(state: .unplugged, level: 0.64) == .unplugged(percent: 64))
        #expect(
            FocusIdleTimerPolicy.shouldDisableIdleTimer(settingEnabled: true, batteryState: .full)
                == OpeningPanelPhone.reading(powered: true, supply: .full, keepAwake: true).awakeLit
        )
    }

    @Test func commDisplayFollowsTheFailureTable() {
        #expect(OpeningPanelCommLogic.waitMilliseconds == 1500)
        #expect(OpeningPanelCommLogic.usesControlFrames(relayContract: 16))
        #expect(!OpeningPanelCommLogic.usesControlFrames(relayContract: 15))

        #expect(OpeningPanelCommLogic.display(for: .unpaired).text == "NO PAIR")
        #expect(OpeningPanelCommLogic.display(for: .unpaired).relay == .off)
        #expect(OpeningPanelCommLogic.display(for: .unpaired).mac == .off)
        #expect(OpeningPanelCommLogic.display(for: .unpaired).failed)

        let noRelay = OpeningPanelCommLogic.display(for: .noRelay)
        #expect(noRelay.text == "NO RELAY")
        #expect(noRelay.relay == .yellow)
        #expect(noRelay.mac == .off)

        let noMac = OpeningPanelCommLogic.display(for: .noMac)
        #expect(noMac.text == "NO MAC")
        #expect(noMac.relay == .green)
        #expect(noMac.mac == .amber)

        let mac = OpeningPanelCommLogic.display(for: .reachedMac(milliseconds: 90))
        #expect(mac.text == "MAC \u{2007}90MS")
        #expect(mac.relay == .green)
        #expect(mac.mac == .green)
        #expect(!mac.failed)
        #expect(OpeningPanelCommLogic.timed("MAC", milliseconds: 123) == "MAC 123MS")
        #expect(OpeningPanelCommLogic.timed("MAC", milliseconds: 1500) == "MAC 1500MS")

        let legacy = OpeningPanelCommLogic.display(
            for: .legacyRelay(milliseconds: 80, macPresent: true)
        )
        #expect(legacy.text == "RELAY \u{2007}80MS")
        #expect(legacy.relay == .green)
        #expect(legacy.mac == .green)
        #expect(!legacy.failed)
        let legacyAbsent = OpeningPanelCommLogic.display(
            for: .legacyRelay(milliseconds: 80, macPresent: false)
        )
        #expect(legacyAbsent.mac == .off)
        #expect(!legacyAbsent.failed)
    }

    @Test func commDeadlineTreatsLateFramesAsMissing() {
        #expect(
            OpeningPanelCommLogic.decide(pongMilliseconds: nil, echoMilliseconds: nil, echoMac: nil) == .noRelay
        )
        #expect(
            OpeningPanelCommLogic.decide(pongMilliseconds: 1501, echoMilliseconds: 1600, echoMac: true) == .noRelay
        )
        #expect(
            OpeningPanelCommLogic.decide(pongMilliseconds: 1500, echoMilliseconds: nil, echoMac: nil) == .noMac
        )
        #expect(
            OpeningPanelCommLogic.decide(pongMilliseconds: 40, echoMilliseconds: 1501, echoMac: true) == .noMac
        )
        #expect(
            OpeningPanelCommLogic.decide(pongMilliseconds: 40, echoMilliseconds: 80, echoMac: false) == .noMac
        )
        #expect(
            OpeningPanelCommLogic.decide(pongMilliseconds: 40, echoMilliseconds: 123, echoMac: true)
                == .reachedMac(milliseconds: 123)
        )
        #expect(
            OpeningPanelCommLogic.decide(pongMilliseconds: 1500, echoMilliseconds: 1500, echoMac: true)
                == .reachedMac(milliseconds: 1500)
        )
    }

    @Test func commTestDoesNotChangeReady() {
        let dark = SystemHarness()
        #expect(!dark.state.pressCommTest())
        #expect(dark.feedback.cues == [.dull])
        #expect(!dark.state.isReady)

        let harness = SystemHarness(reduceMotion: true)
        harness.state.pressMaster()
        harness.state.pressConfirm(.clock)
        harness.state.pressConfirm(.timetable)
        harness.state.pressConfirm(.tickets)
        harness.advance(by: OpeningPanelTiming.backlight)
        #expect(harness.state.isReady)
        #expect(harness.state.pressCommTest())
        harness.state.noteCommLamp()
        harness.state.noteCommFailure()
        #expect(harness.state.isReady)
        #expect(harness.state.confirmation(of: .clock) == .confirmed)
        #expect(harness.state.confirmation(of: .timetable) == .confirmed)
        #expect(harness.state.confirmation(of: .tickets) == .confirmed)
    }

    @Test func commMeasureUsesPingAndFallsBackForAnOlderRelay() async {
        let previous = UserDefaults.standard.string(forKey: "settings.companionRelayURL")
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: "settings.companionRelayURL")
            } else {
                UserDefaults.standard.removeObject(forKey: "settings.companionRelayURL")
            }
        }

        let unpaired = makeRuntime(paired: false)
        let trap = TrapConnector()
        let skipped = await unpaired.measureComm(macPresenceKnown: false, connector: trap)
        #expect(skipped == Optional(OpeningPanelCommExchange.unpaired))
        #expect(!trap.called)

        let id = UUID(uuidString: "a1a2a3a4-b1b2-4c3c-8d4d-e5e6e7e8e9ea")!
        let relay = RelayFlag()
        let live = ScriptedWebSocket(incoming: [
            .hello(ContractAnnouncement(contract: 16, minReadable: 3)),
            .pong(id),
            .echo(id: id, mac: true),
        ])
        let path = PathSocket(live)
        let runtime = makeRuntime(paired: true)
        let reached = await runtime.measureComm(
            macPresenceKnown: false,
            id: id,
            connector: path,
            onRelay: { relay.count += 1 }
        )
        guard let reached else {
            Issue.record("measurement was cancelled")
            return
        }
        guard case .reachedMac(let milliseconds) = reached else {
            Issue.record("expected a Mac round trip, got \(String(describing: reached))")
            return
        }
        #expect(milliseconds >= 0)
        #expect(relay.count == 1)
        #expect(path.seenPath == "/v1/ws")
        let sent = await live.sentText
        #expect(sent.count == 2)
        #expect(sent[0].contains("\"role\":\"iphone\""))
        #expect(sent[1] == WSControl.ping(id: id))

        let absent = ScriptedWebSocket(incoming: [
            .hello(ContractAnnouncement(contract: 16, minReadable: 3)),
            .pong(id),
            .echo(id: id, mac: false),
        ])
        let noMac = await runtime.measureComm(macPresenceKnown: true, id: id, connector: absent)
        #expect(noMac == Optional(OpeningPanelCommExchange.noMac))

        let old = ScriptedWebSocket(incoming: [
            .hello(ContractAnnouncement(contract: 15, minReadable: 3)),
        ])
        let hint = HintFlag()
        let legacy = await runtime.measureComm(
            macPresenceKnown: true,
            connector: old,
            hint: { await hint.mark() }
        )
        guard let legacy else {
            Issue.record("legacy measurement was cancelled")
            return
        }
        guard case .legacyRelay(_, true) = legacy else {
            Issue.record("expected a legacy relay measurement, got \(String(describing: legacy))")
            return
        }
        let oldSent = await old.sentText
        #expect(oldSent == [ContractHello.text(role: .iphone)])
        #expect(await hint.called)

        let failedHint = await runtime.measureComm(
            macPresenceKnown: false,
            connector: ScriptedWebSocket(incoming: [
                .hello(ContractAnnouncement(contract: 3, minReadable: 3)),
            ]),
            hint: { throw SyncError.transport(status: 503, code: "invalid") }
        )
        #expect(failedHint == Optional(OpeningPanelCommExchange.noRelay))

        let dropped = await runtime.measureComm(
            macPresenceKnown: false,
            wait: .milliseconds(40),
            connector: QueueThenHang(incoming: [
                .hello(ContractAnnouncement(contract: 16, minReadable: 3)),
            ])
        )
        #expect(dropped == Optional(OpeningPanelCommExchange.noRelay))

        let silent = await runtime.measureComm(
            macPresenceKnown: false,
            wait: .milliseconds(40),
            connector: QueueThenHang(incoming: [])
        )
        #expect(silent == Optional(OpeningPanelCommExchange.noRelay))

        let refused = await runtime.measureComm(
            macPresenceKnown: false,
            connector: FailingConnector()
        )
        #expect(refused == Optional(OpeningPanelCommExchange.noRelay))
    }

    @Test func loadLightsOnlyWhenBothModulesAreConfirmed() {
        #expect(!OpeningPanelLoadLogic.isLit(powered: true, timetableConfirmed: true, ticketsConfirmed: false))
        #expect(!OpeningPanelLoadLogic.isLit(powered: true, timetableConfirmed: false, ticketsConfirmed: true))
        #expect(!OpeningPanelLoadLogic.isLit(powered: false, timetableConfirmed: true, ticketsConfirmed: true))
        #expect(OpeningPanelLoadLogic.isLit(powered: true, timetableConfirmed: true, ticketsConfirmed: true))

        let dark = OpeningPanelLoadLogic.drawing(.dark)
        #expect(!dark.lit)
        #expect(dark.frameTop == 0.36)
        #expect(dark.slabs.isEmpty)
    }

    @Test func loadFrameKeepsAtLeastTwentyTwoPercentAndStacksOverflowInAmber() {
        let open = OpeningPanelLoadLogic.drawing(
            OpeningPanelLoadTarget(lit: true, freeMinutes: 100, spanMinutes: 100, tickets: [10])
        )
        #expect(abs(open.frameTop - 0.36) < 0.0001)
        #expect(open.slabs == [OpeningPanelLoadSlab(id: 0, bottom: 0.04, height: 0.06, overflow: false)])

        let tight = OpeningPanelLoadLogic.drawing(
            OpeningPanelLoadTarget(lit: true, freeMinutes: 10, spanMinutes: 600, tickets: [30])
        )
        #expect(abs((1 - tight.frameTop) - 0.04 - 0.22) < 0.0001)
        #expect(tight.slabs.count == 2)
        #expect(!tight.slabs[0].overflow)
        #expect(abs(tight.slabs[0].height - 0.22) < 0.0001)
        #expect(tight.slabs[1].overflow)
        #expect(abs(tight.slabs[1].height - 0.44) < 0.0001)

        let none = OpeningPanelLoadLogic.drawing(
            OpeningPanelLoadTarget(lit: true, freeMinutes: 0, spanMinutes: 1, tickets: [20])
        )
        #expect(none.slabs.allSatisfy { $0.overflow })
    }

    @Test func loadApproachesInFourSteps() {
        #expect(OpeningPanelTiming.loadSteps == 4)
        #expect(abs(OpeningPanelTiming.loadStep - OpeningPanelTiming.tempo(35)) < 1e-12)

        let from = OpeningPanelLoadTarget(lit: true, freeMinutes: 100, spanMinutes: 80, tickets: [10, 20])
        let to = OpeningPanelLoadTarget(lit: true, freeMinutes: 0, spanMinutes: 80, tickets: [10])
        #expect(OpeningPanelLoadLogic.interpolate(from: from, to: to, step: 1).freeMinutes == 75)
        #expect(OpeningPanelLoadLogic.interpolate(from: from, to: to, step: 2).freeMinutes == 50)
        #expect(OpeningPanelLoadLogic.interpolate(from: from, to: to, step: 3).freeMinutes == 25)
        #expect(OpeningPanelLoadLogic.interpolate(from: from, to: to, step: 1).tickets == [10])
        #expect(OpeningPanelLoadLogic.interpolate(from: from, to: to, step: 4) == to)
        #expect(OpeningPanelLoadLogic.interpolatedCount(from: 1, to: 5, step: 1) == 2)
        #expect(OpeningPanelLoadLogic.interpolatedCount(from: 1, to: 5, step: 3) == 4)
        #expect(OpeningPanelLoadLogic.interpolatedCount(from: 5, to: 1, step: 1) == 4)

        let scheduler = SystemScheduler()
        let player = OpeningPanelLoadPlayer(scheduler: scheduler)
        player.set(from)
        #expect(player.sample == from)
        player.set(to)
        #expect(player.sample.freeMinutes == 75)
        scheduler.advance(by: OpeningPanelTiming.loadStep)
        #expect(player.sample.freeMinutes == 50)
        scheduler.advance(by: OpeningPanelTiming.loadStep)
        #expect(player.sample.freeMinutes == 25)
        scheduler.advance(by: OpeningPanelTiming.loadStep)
        #expect(player.sample == to)

        player.set(OpeningPanelLoadTarget(lit: false, freeMinutes: 0, spanMinutes: 1, tickets: []))
        #expect(!player.sample.lit)
    }

    private func makeRuntime(paired: Bool) -> CompanionSyncRuntime {
        let secrets = InMemorySecretStore(
            secrets: paired
                ? PairingSecrets(
                    pairingId: UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")!,
                    masterKey: Data(repeating: 7, count: 32),
                    writeToken: Data(repeating: 9, count: 32),
                    companionName: "Mac"
                )
                : nil
        )
        let defaults = UserDefaults(suiteName: "OpeningPanelCommTests")!
        defaults.removePersistentDomain(forName: "OpeningPanelCommTests")
        return CompanionSyncRuntime(
            secrets: secrets,
            settings: AppSettings.makeForTesting(companionRelayURLString: "https://relay.test"),
            defaults: defaults
        )
    }
}

@MainActor
private final class SystemHarness {
    let scheduler = SystemScheduler()
    let feedback = SystemFeedback()
    let state: OpeningPanelState

    init(reduceMotion: Bool = false) {
        state = OpeningPanelState(
            scheduler: scheduler,
            feedback: feedback,
            reduceMotion: reduceMotion
        )
    }

    func advance(by seconds: TimeInterval) {
        scheduler.advance(by: seconds)
    }
}

@MainActor
private final class SystemScheduler: OpeningPanelScheduling {
    private struct Item {
        var id: Int
        var due: TimeInterval
        var action: () -> Void
    }

    private var now: TimeInterval = 0
    private var nextID = 0
    private var items: [Item] = []

    func schedule(after seconds: TimeInterval, execute: @escaping () -> Void) -> OpeningPanelTask {
        let id = nextID
        nextID += 1
        items.append(Item(id: id, due: now + seconds, action: execute))
        return OpeningPanelTask { [weak self] in
            self?.items.removeAll { $0.id == id }
        }
    }

    func advance(by seconds: TimeInterval) {
        let target = now + seconds
        while let index = items.indices.min(by: { items[$0].due < items[$1].due }),
              items[index].due <= target {
            let item = items.remove(at: index)
            now = item.due
            item.action()
        }
        now = target
    }
}

private final class SystemFeedback: OpeningPanelFeedback {
    var cues: [OpeningPanelCue] = []

    func play(_ cue: OpeningPanelCue) {
        cues.append(cue)
    }
}

private final class TrapConnector: WebSocketConnecting, @unchecked Sendable {
    var called = false

    func connect(path: String, headers: [String: String]) async throws -> any WebSocketConnection {
        called = true
        throw SyncError.notPaired
    }
}

private final class FailingConnector: WebSocketConnecting, @unchecked Sendable {
    func connect(path: String, headers: [String: String]) async throws -> any WebSocketConnection {
        throw SyncError.transport(status: 503, code: "invalid")
    }
}

private final class PathSocket: WebSocketConnecting, @unchecked Sendable {
    let base: ScriptedWebSocket
    var seenPath: String?

    init(_ base: ScriptedWebSocket) {
        self.base = base
    }

    func connect(path: String, headers: [String: String]) async throws -> any WebSocketConnection {
        seenPath = path
        return try await base.connect(path: path, headers: headers)
    }
}

private actor HintFlag {
    private(set) var called = false

    func mark() {
        called = true
    }
}

private final class RelayFlag: @unchecked Sendable {
    var count = 0
}

private actor QueueThenHang: WebSocketConnecting, WebSocketConnection {
    private var incoming: [WSIncoming]

    init(incoming: [WSIncoming]) {
        self.incoming = incoming
    }

    func connect(path: String, headers: [String: String]) async throws -> any WebSocketConnection {
        self
    }

    func receive() async throws -> WSFrame {
        throw SyncError.notPaired
    }

    func receiveIncoming() async throws -> WSIncoming {
        if !incoming.isEmpty {
            return incoming.removeFirst()
        }
        try await Task.sleep(for: .seconds(30))
        throw CancellationError()
    }

    func send(_ text: String) async throws {}

    func close() async {}
}
