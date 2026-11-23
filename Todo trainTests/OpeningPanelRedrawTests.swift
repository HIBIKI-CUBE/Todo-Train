//
//  OpeningPanelRedrawTests.swift
//  Todo trainTests
//
//  盤を出しているあいだ、描き直しが必要な部品だけに限られているか。
//

import QuartzCore
import SwiftUI
import UIKit
import Testing
@testable import Todo_train

@Suite(.serialized)
@MainActor
struct OpeningPanelRedrawTests {
    @Test func steadyPhases_redrawOnlyWhatMoves() async {
        let host = OpeningPanelRedrawHost()
        host.install()
        let window = 2.0

        let link = await host.countDisplayLink(seconds: 0.5)
        print("REDRAW displayLink=\(link) app=\(UIApplication.shared.applicationState.rawValue)")

        let darkState = host.makeState()
        let dark = await host.measure(seconds: window) {
            OpeningPanelRedrawScene(state: darkState, phase: .dark)
        }
        print("STATE dark powered=\(darkState.isPowered) clock=\(String(describing: darkState.clockStage)) ready=\(darkState.isReady)")
        printRedraw("dark", dark)

        let clockPack = host.makePacked()
        clockPack.state.pressMaster()
        clockPack.state.pressConfirm(.clock)
        clockPack.scheduler.advance(until: {
            clockPack.state.clockStage == .live && clockPack.state.powerSettled
        })
        host.show(OpeningPanelRedrawScene(state: clockPack.state, phase: .clock))
        await host.pump(0.2)
        let clockCounts = await host.measureExisting(seconds: window)
        print("STATE clock powered=\(clockPack.state.isPowered) clock=\(String(describing: clockPack.state.clockStage)) flowing=\(clockPack.state.chevronsFlowing)")
        printRedraw("clock", clockCounts)

        let readyPack = host.makePacked()
        readyPack.state.pressMaster()
        readyPack.state.pressConfirm(.clock)
        readyPack.state.pressConfirm(.timetable)
        readyPack.state.pressConfirm(.tickets)
        readyPack.scheduler.advance(until: {
            readyPack.state.powerSettled
                && readyPack.state.isReady
                && readyPack.state.clockStage == .live
                && readyPack.state.ticketGrowthStep == OpeningPanelTiming.ticketGrowthSteps
        })
        host.show(OpeningPanelRedrawScene(state: readyPack.state, phase: .ready))
        await host.pump(0.2)
        let ready = await host.measureExisting(seconds: window)
        print("STATE ready ready=\(readyPack.state.isReady) clock=\(String(describing: readyPack.state.clockStage)) flowing=\(readyPack.state.chevronsFlowing) growth=\(readyPack.state.ticketGrowthStep)")
        printRedraw("ready", ready)

        host.release()

        expectQuiet(dark, label: "dark")
        expectClockOnly(clockCounts)
        expectReadyWave(ready)
    }
}

@MainActor
private func printRedraw(_ label: String, _ counts: [String: Int]) {
    let lines = counts.keys.sorted().map { "\($0)=\(counts[$0] ?? 0)" }.joined(separator: " ")
    print("REDRAW \(label) \(lines)")
}

@MainActor
private func expectQuiet(_ counts: [String: Int], label: String) {
    #expect(counts["ClockTick", default: 0] == 0, "\(label) clock")
    #expect(counts["ClockColonTick", default: 0] == 0, "\(label) colon")
    #expect(counts["DepartChevronTick", default: 0] == 0, "\(label) chevron")
    #expect(counts["DepartColumnRing", default: 0] == 0, "\(label) column")
    #expect(counts["departFace", default: 0] <= 4, "\(label) depart face")
    #expect(counts["TicketsModule", default: 0] <= 4, "\(label) tickets")
    #expect(counts["OpeningPanelGrid", default: 0] <= 4, "\(label) grid")
    #expect(counts["PanelHost", default: 0] <= 4, "\(label) host")
}

@MainActor
private func expectClockOnly(_ counts: [String: Int]) {
    let ticks = counts["ClockTick", default: 0]
    let colon = counts["ClockColonTick", default: 0]
    #expect(ticks >= 1)
    #expect(ticks <= 5)
    #expect(colon >= 2)
    #expect(colon <= 8)
    #expect(counts["OpeningPanelClockDigits", default: 0] <= 3)
    #expect(counts["DepartChevronTick", default: 0] == 0)
    #expect(counts["departFace", default: 0] <= 4)
    #expect(counts["TicketsModule", default: 0] <= 4)
    #expect(counts["OpeningPanelGrid", default: 0] <= 4)
    #expect(counts["PanelHost", default: 0] <= 4)
}

@MainActor
private func expectReadyWave(_ counts: [String: Int]) {
    let wave = counts["DepartChevronTick", default: 0]
    let canvas = counts["DepartChevronCanvas", default: 0]
    #expect(wave >= 8)
    #expect(wave <= 40)
    #expect(canvas >= 8)
    #expect(canvas <= 40)
    #expect(counts["departFace", default: 0] <= 4)
    #expect(counts["OpeningPanelPushBar", default: 0] <= 4)
    #expect(counts["TicketsModule", default: 0] <= 4)
    #expect(counts["OpeningPanelGrid", default: 0] <= 4)
    #expect(counts["PanelHost", default: 0] <= 4)
    let ring = counts["DepartColumnRing", default: 0]
    #expect(ring >= 1)
    #expect(ring <= 12)
    #expect(counts["ClockTick", default: 0] <= 5)
    #expect(counts["ClockColonTick", default: 0] <= 8)
}

private enum OpeningPanelRedrawPhase {
    case dark
    case clock
    case ready
}

@MainActor
private struct OpeningPanelRedrawScene: View {
    var state: OpeningPanelState
    var phase: OpeningPanelRedrawPhase
    @State private var model = OpeningPanelTicketsModel()

    var body: some View {
        let _ = OpeningPanelRedrawProbe.bump("PanelHost")
        let _ = state.isPowered
        let _ = state.clockStage
        let _ = state.hourCycle
        let _ = state.chevronsFlowing
        let _ = state.departColumnLit
        let _ = state.glowingFaces
        let _ = state.sequenceLampLit
        let _ = state.ticketGrowthStep
        let _ = state.isSequencing
        let _ = state.hasDeparted
        let _ = state.confirmation(of: .clock)
        let _ = state.confirmation(of: .timetable)
        let _ = state.confirmation(of: .tickets)
        OpeningPanelGrid(
            clock: { ClockModule(state: state) },
            tickets: { TicketsModule(state: state, model: model) },
            departChevrons: { DepartChevronField(state: state) },
            departBar: { DepartModule(state: state, onPress: { state.pressDepart() }) },
            departLocks: OpeningPanelLockPicture(state: state),
            chevronsFlowing: state.chevronsFlowing,
            departColumnLit: state.departColumnLit,
            glowingModules: Set(state.glowingFaces.map(\.panelModule))
        )
        .frame(width: 402, height: 874)
        .background(Color.black)
    }
}

@MainActor
private final class OpeningPanelRedrawHost {
    private var window: UIWindow?

    func install() {
        let controller = UIHostingController(rootView: Color.black.frame(width: 402, height: 874))
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
    }

    func makeState() -> OpeningPanelState {
        makePacked().state
    }

    func makePacked() -> (state: OpeningPanelState, scheduler: OpeningPanelRedrawScheduler) {
        let scheduler = OpeningPanelRedrawScheduler()
        let state = OpeningPanelState(
            scheduler: scheduler,
            feedback: OpeningPanelFeedbackSilent(),
            ticketCount: 0,
            reduceMotion: false
        )
        return (state, scheduler)
    }

    func countDisplayLink(seconds: TimeInterval) async -> Int {
        let counter = OpeningPanelDisplayLinkCounter()
        let link = CADisplayLink(target: counter, selector: #selector(OpeningPanelDisplayLinkCounter.tick))
        link.add(to: .main, forMode: .common)
        await pump(seconds)
        link.invalidate()
        return counter.fires
    }

    func show<V: View>(_ view: V) {
        window?.rootViewController = UIHostingController(rootView: view)
        window?.makeKeyAndVisible()
    }

    func measure(seconds: TimeInterval, view: () -> OpeningPanelRedrawScene) async -> [String: Int] {
        show(view())
        await pump(0.25)
        return await measureExisting(seconds: seconds)
    }

    func measureExisting(seconds: TimeInterval) async -> [String: Int] {
        OpeningPanelRedrawProbe.reset()
        OpeningPanelRedrawProbe.enabled = true
        OpeningPanelRedrawProbe.trace = true
        await pump(0.2)
        OpeningPanelRedrawProbe.trace = false
        await pump(seconds - 0.2)
        let counts = OpeningPanelRedrawProbe.snapshot()
        OpeningPanelRedrawProbe.enabled = false
        return counts
    }

    func pump(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

}

@MainActor
private final class OpeningPanelDisplayLinkCounter: NSObject {
    var fires = 0
    @objc func tick() { fires += 1 }
}

@MainActor
private final class OpeningPanelRedrawScheduler: OpeningPanelScheduling {
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

    func advance(until done: () -> Bool) {
        var steps = 0
        while !done(), steps < 8_000 {
            guard let index = items.indices.min(by: { items[$0].due < items[$1].due }) else { return }
            let item = items.remove(at: index)
            now = item.due
            item.action()
            steps += 1
        }
    }
}

@MainActor
private extension OpeningPanelRedrawHost {
    func release() {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }
}
