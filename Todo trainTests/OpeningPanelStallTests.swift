//
//  OpeningPanelStallTests.swift
//  Todo trainTests
//
//  盤を出しているあいだのフレーム間隔と、メインスレッドが戻るまでの待ち。
//

import QuartzCore
import SwiftData
import SwiftUI
import UIKit
import Testing
@testable import Todo_train

@Suite(.serialized)
@MainActor
struct OpeningPanelStallTests {
    @Test func panelShown_framesAndMainThread() async throws {
        let host = OpeningPanelStallHost()
        host.install()
        defer { host.release() }

        let darkState = OpeningPanelState(
            scheduler: OpeningPanelRedrawScheduler(),
            feedback: OpeningPanelFeedbackSilent(),
            ticketCount: 0,
            reduceMotion: false
        )
        let dark = await host.sample(seconds: 3) {
            OpeningPanelStallScene(state: darkState, liveClock: false, flowing: false)
        }
        printStall("dark", dark)
        #expect(pct(dark.frameGaps, 0.95) < 0.05)
        #expect(pct(dark.mainWaits, 0.95) < 0.02)
        #expect(dark.counts["gridGeometry", default: 0] <= 2)
        #expect(dark.counts["latticeLayout", default: 0] <= 4)
        #expect(dark.counts["DepartChevronTick", default: 0] == 0)

        let ready = await host.sample(seconds: 6) {
            OpeningPanelStallScene(state: host.readyState(), liveClock: true, flowing: true)
        }
        printStall("ready", ready)
        #expect(pct(ready.frameGaps, 0.95) < 0.05)
        #expect(pct(ready.mainWaits, 0.95) < 0.2)
        #expect(ready.counts["DepartChevronTick", default: 0] >= 40)
        #expect(ready.counts["DepartChevronCanvas", default: 0] >= 30)
        #expect(ready.counts["OpeningPanelGrid", default: 0] <= 4)
        #expect(ready.counts["TicketsModule", default: 0] <= 4)

        let cover = try await host.sampleCover(seconds: 3)
        printStall("cover", cover)
        #expect(pct(cover.frameGaps, 0.95) < 0.05)
        #expect(cover.counts["loadTarget", default: 0] <= 2)
        #expect(cover.counts["ticketSyncKey", default: 0] <= 2)
    }
}

@MainActor
private func printStall(_ label: String, _ sample: OpeningPanelStallSample) {
    let frames = sample.frameGaps
    let waits = sample.mainWaits
    print(
        "STALL \(label) frames=\(frames.count) gapP50=\(pct(frames, 0.50)) gapP95=\(pct(frames, 0.95)) gapMax=\(frames.max() ?? 0) waits=\(waits.count) waitP50=\(pct(waits, 0.50)) waitP95=\(pct(waits, 0.95)) waitMax=\(waits.max() ?? 0) \(probeLine(sample.counts))"
    )
}

private func pct(_ values: [Double], _ p: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let index = min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))
    return (sorted[index] * 1000).rounded() / 1000
}

private func probeLine(_ counts: [String: Int]) -> String {
    counts.keys.sorted().map { "\($0)=\(counts[$0] ?? 0)" }.joined(separator: " ")
}

private struct OpeningPanelStallSample {
    var frameGaps: [Double]
    var mainWaits: [Double]
    var counts: [String: Int]
}

@MainActor
private struct OpeningPanelStallScene: View {
    var state: OpeningPanelState
    var liveClock: Bool
    var flowing: Bool

    var body: some View {
        OpeningPanelGrid(
            clock: { ClockModule(state: state) },
            tickets: { TicketsModule(state: state, model: OpeningPanelTicketsModel()) },
            departChevrons: { DepartChevronField(state: state) },
            departBar: { DepartModule(state: state, onPress: {}) },
            departLocks: OpeningPanelLockPicture(state: state),
            chevronsFlowing: flowing && state.chevronsFlowing,
            departColumnLit: state.departColumnLit,
            glowingModules: Set(state.glowingFaces.map(\.panelModule))
        )
        .frame(width: 440, height: 956)
        .background(Color.black)
    }
}

@MainActor
private final class OpeningPanelStallHost {
    private var window: UIWindow?

    func install() {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        window.frame = CGRect(x: 0, y: 0, width: 440, height: 956)
        window.rootViewController = UIHostingController(rootView: Color.black)
        window.makeKeyAndVisible()
        self.window = window
    }

    func readyState() -> OpeningPanelState {
        let scheduler = OpeningPanelRedrawScheduler()
        let state = OpeningPanelState(
            scheduler: scheduler,
            feedback: OpeningPanelFeedbackSilent(),
            ticketCount: 4,
            reduceMotion: false
        )
        state.pressMaster()
        state.pressConfirm(.clock)
        state.pressConfirm(.timetable)
        state.pressConfirm(.tickets)
        scheduler.advance {
            state.powerSettled
                && state.isReady
                && state.clockStage == .live
                && state.ticketGrowthStep == OpeningPanelTiming.ticketGrowthSteps
        }
        return state
    }

    func sample<V: View>(seconds: TimeInterval, view: () -> V) async -> OpeningPanelStallSample {
        window?.rootViewController = UIHostingController(rootView: view())
        window?.makeKeyAndVisible()
        try? await Task.sleep(for: .milliseconds(300))
        return await capture(seconds: seconds)
    }

    func sampleCover(seconds: TimeInterval) async throws -> OpeningPanelStallSample {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let manager = SessionManager(
            modelContext: context,
            settings: .shared,
            calendarBoard: NoOpCalendarBoard()
        )
        let cover = OpeningPanelCover(onServiceDayNeedsEnd: {})
            .environment(manager)
            .environment(AppSettings.shared)
            .environment(CompanionSyncRuntime())
            .environment(ArrivalForecastStore())
            .modelContainer(container)
        window?.rootViewController = UIHostingController(rootView: cover)
        window?.makeKeyAndVisible()
        try? await Task.sleep(for: .milliseconds(500))
        return await capture(seconds: seconds)
    }

    func release() {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    private func capture(seconds: TimeInterval) async -> OpeningPanelStallSample {
        OpeningPanelRedrawProbe.reset()
        OpeningPanelRedrawProbe.enabled = true
        let frames = OpeningPanelFrameProbe()
        let link = CADisplayLink(target: frames, selector: #selector(OpeningPanelFrameProbe.tick(_:)))
        link.add(to: .main, forMode: .common)
        let waits = await pingMain(seconds: seconds)
        link.invalidate()
        OpeningPanelRedrawProbe.enabled = false
        return OpeningPanelStallSample(
            frameGaps: frames.gaps,
            mainWaits: waits,
            counts: OpeningPanelRedrawProbe.snapshot()
        )
    }
}

private func pingMain(seconds: TimeInterval) async -> [Double] {
    let end = Date().addingTimeInterval(seconds)
    var waits: [Double] = []
    while Date() < end {
        let start = CFAbsoluteTimeGetCurrent()
        await MainActor.run { }
        waits.append(CFAbsoluteTimeGetCurrent() - start)
        try? await Task.sleep(for: .milliseconds(40))
    }
    return waits
}

private final class OpeningPanelFrameProbe: NSObject {
    var last: CFTimeInterval?
    var gaps: [Double] = []

    @objc func tick(_ link: CADisplayLink) {
        if let last {
            gaps.append(link.timestamp - last)
        }
        last = link.timestamp
    }
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

    func advance(_ done: () -> Bool) {
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
