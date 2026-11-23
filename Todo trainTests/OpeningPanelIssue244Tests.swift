//
//  OpeningPanelIssue244Tests.swift
//  Todo trainTests
//
//  予定表の AUTO/24H、LOAD の追従、ハブからの入口、盤の空枠。
//

import SwiftData
import SwiftUI
import UIKit
import Testing
@testable import Todo_train

extension OpeningPanelTimedSuites {
@MainActor
struct OpeningPanelIssue244Tests {
    @Test func timetableScaleStaysOnAutoWhenTheClockChanges() {
        let state = OpeningPanelState(
            scheduler: Issue244Scheduler(),
            feedback: OpeningPanelFeedbackSilent()
        )
        #expect(state.hourCycle == .twentyFour)
        #expect(!state.timetableTwentyFour)

        state.pressTimetableScale()
        #expect(!state.timetableTwentyFour)

        state.pressMaster()
        state.pressHourMode()
        #expect(state.hourCycle == .twelve)
        #expect(!state.timetableTwentyFour)

        state.pressTimetableScale()
        #expect(state.timetableTwentyFour)
        #expect(state.hourCycle == .twelve)

        state.pressHourMode()
        #expect(state.hourCycle == .twentyFour)
        #expect(state.timetableTwentyFour)

        let day = Date(timeIntervalSince1970: 1_699_920_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let auto = TimetableRangeLogic.compute(
            scheduledBlocks: [],
            referenceDay: day,
            isTwentyFourHour: false,
            calendar: calendar
        )
        let full = TimetableRangeLogic.compute(
            scheduledBlocks: [],
            referenceDay: day,
            isTwentyFourHour: true,
            calendar: calendar
        )
        #expect(auto.windowLabel != full.windowLabel)
        let shown = TimetableRangeLogic.compute(
            scheduledBlocks: [],
            referenceDay: day,
            isTwentyFourHour: state.timetableTwentyFour,
            calendar: calendar
        )
        #expect(shown == full)
    }

    @Test func loadTakesTheFirstTargetThenFollowsTheCutoffAndAdoption() {
        let scheduler = Issue244Scheduler()
        let player = OpeningPanelLoadPlayer(scheduler: scheduler)
        #expect(player.sample == .dark)

        let now = Issue244Day.at(hour: 13)
        let passing = Issue244Day.board(now: now, stops: false)
        let adopted = Issue244Day.board(now: now, stops: true)
        #expect(adopted.load.freeMinutes < passing.load.freeMinutes)

        let hidden = OpeningPanelLoadWire.target(
            lit: false,
            now: now,
            rangeEndsAt: passing.range.endsAt,
            freeMinutes: passing.load.freeMinutes,
            ticketMinutes: [20, 30, 40]
        )
        #expect(!hidden.lit)
        #expect(hidden.tickets.isEmpty)

        var pushes = 0
        player.onSample = { pushes += 1 }
        let first = OpeningPanelLoadWire.target(
            lit: true,
            now: now,
            rangeEndsAt: passing.range.endsAt,
            freeMinutes: passing.load.freeMinutes,
            ticketMinutes: [20, 30, 40]
        )
        player.set(first)
        #expect(pushes == 1)
        #expect(player.sample == first)
        #expect(OpeningPanelLoadLogic.drawing(player.sample).lit)
        #expect(OpeningPanelLoadLogic.drawing(player.sample).slabs.count == 3)

        let cut = OpeningPanelLoadWire.target(
            lit: true,
            now: now,
            rangeEndsAt: passing.range.endsAt,
            freeMinutes: passing.load.freeMinutes,
            ticketMinutes: [20]
        )
        player.set(cut)
        scheduler.advance(by: OpeningPanelTiming.loadStep * Double(OpeningPanelTiming.loadSteps))
        #expect(player.sample.tickets == [20])
        #expect(player.sample.freeMinutes == Double(passing.load.freeMinutes))

        let afterAdopt = OpeningPanelLoadWire.target(
            lit: true,
            now: now,
            rangeEndsAt: adopted.range.endsAt,
            freeMinutes: adopted.load.freeMinutes,
            ticketMinutes: [20]
        )
        player.set(afterAdopt)
        scheduler.advance(by: OpeningPanelTiming.loadStep * Double(OpeningPanelTiming.loadSteps))
        #expect(player.sample.tickets == [20])
        #expect(player.sample.freeMinutes == Double(adopted.load.freeMinutes))
    }

    @Test func panelEntryOpensDuringServiceWithoutRestartingIt() throws {
        #expect(
            OpeningPanelHubFlow.panelEntry(isInService: false)
                == OpeningPanelHubFlow.PanelEntry(serviceAlreadyRunning: false)
        )
        #expect(
            OpeningPanelHubFlow.panelEntry(isInService: true)
                == OpeningPanelHubFlow.PanelEntry(serviceAlreadyRunning: true)
        )

        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let manager = SessionManager(
            modelContext: context,
            settings: AppSettings.makeForTesting(),
            calendarBoard: NoOpCalendarBoard()
        )
        try manager.startService()
        let startedAt = manager.activeServiceDay?.startedAt
        let scheduler = Issue244Scheduler()
        var starts = 0
        var hubs = 0
        let reviewing = OpeningPanelState(
            scheduler: scheduler,
            feedback: OpeningPanelFeedbackSilent(),
            serviceAlreadyRunning: OpeningPanelHubFlow.panelEntry(isInService: true).serviceAlreadyRunning,
            onStartService: {
                starts += 1
                _ = OpeningPanelServiceStart.begin(sessionManager: manager)
            },
            onShowHub: { hubs += 1 }
        )
        reviewing.pressMaster()
        #expect(starts == 0)
        #expect(reviewing.isPowered)
        reviewing.pressMaster()
        #expect(!reviewing.isPowered)
        reviewing.pressMaster()
        #expect(starts == 0)
        reviewing.pressDepart()
        scheduler.advance(by: OpeningPanelTiming.hubSwitch + 0.05)
        #expect(hubs == 1)
        #expect(reviewing.hasDeparted)
        #expect(manager.isInService)
        #expect(manager.activeServiceDay?.startedAt == startedAt)
        #expect(manager.activeServiceDay?.endedAt == nil)

        var freshStarts = 0
        let fresh = OpeningPanelState(
            scheduler: Issue244Scheduler(),
            feedback: OpeningPanelFeedbackSilent(),
            serviceAlreadyRunning: OpeningPanelHubFlow.panelEntry(isInService: false).serviceAlreadyRunning,
            onStartService: { freshStarts += 1 }
        )
        fresh.pressMaster()
        #expect(freshStarts == 1)
        #expect(fresh.isPowered)
    }

    @Test func hubOffersThePanelBeforeAndDuringService() async throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let manager = SessionManager(
            modelContext: context,
            settings: AppSettings.makeForTesting(),
            calendarBoard: NoOpCalendarBoard()
        )
        let host = Issue244Host()
        host.install()
        defer { host.release() }

        host.show(panelBar(manager: manager))
        try await Task.sleep(for: .milliseconds(300))
        var labels = host.labels()
        #expect(labels.contains("運行開始"), Comment(rawValue: labels.joined(separator: " | ")))
        #expect(labels.contains("運行の盤"), Comment(rawValue: labels.joined(separator: " | ")))

        try manager.startService()
        host.show(panelBar(manager: manager))
        try await Task.sleep(for: .milliseconds(300))
        labels = host.labels()
        #expect(labels.contains("運行終了"), Comment(rawValue: labels.joined(separator: " | ")))
        #expect(labels.contains("運行の盤"), Comment(rawValue: labels.joined(separator: " | ")))
    }

    @Test func coverPassesEverySlotAndKeepsTheTimetableOnAuto() async throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let manager = SessionManager(
            modelContext: context,
            settings: AppSettings.makeForTesting(),
            calendarBoard: NoOpCalendarBoard()
        )
        let settings = AppSettings.makeForTesting()
        OpeningPanelSlotProbe.reset()
        OpeningPanelSlotProbe.enabled = true
        let host = Issue244Host()
        host.install()
        defer {
            OpeningPanelSlotProbe.enabled = false
            OpeningPanelSlotProbe.reset()
            host.release()
        }

        host.show(
            OpeningPanelCover(onServiceDayNeedsEnd: {})
                .environment(manager)
                .environment(settings)
                .environment(CompanionSyncRuntime())
                .modelContainer(container)
        )

        let deadline = Date().addingTimeInterval(3)
        var slots: Set<String> = []
        var labels: [String] = []
        while Date() < deadline {
            slots = OpeningPanelSlotProbe.snapshot()
            labels = host.labels()
            if slots == Set(OpeningPanelSlotProbe.names), labels.contains("自動") {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(slots == Set(OpeningPanelSlotProbe.names))
        #expect(labels.contains("自動"), Comment(rawValue: labels.joined(separator: " | ")))
        #expect(!labels.contains("24時間"), Comment(rawValue: labels.joined(separator: " | ")))
    }

    private func panelBar(manager: SessionManager) -> some View {
        ServiceSummaryBar(
            onRequestStartService: {},
            onRequestEndService: {},
            onOpenPanel: {}
        )
        .environment(manager)
        .frame(width: 390)
    }
}
}

private enum Issue244Day {
    static let start = Date(timeIntervalSince1970: 1_699_920_000)
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    static func at(hour: Int, minute: Int = 0) -> Date {
        calendar.date(byAdding: .minute, value: hour * 60 + minute, to: start)!
    }

    static func board(now: Date, stops: Bool) -> OpeningTimetableBoard {
        let id = UUID()
        let entry = OpeningTimetableEntry(
            kind: stops ? .stop(blockID: id) : .passManual(blockID: id),
            title: "歯医者",
            startsAt: at(hour: 16, minute: 30),
            endsAt: at(hour: 18, minute: 30)
        )
        return OpeningTimetableBoard.make(
            entries: [entry],
            now: now,
            isTwentyFourHour: false,
            referenceDay: start,
            ticketsAboveCutoff: [],
            calendar: calendar
        )
    }
}

@MainActor
private final class Issue244Scheduler: OpeningPanelScheduling {
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

@MainActor
private final class Issue244Host {
    private var window: UIWindow?

    func install() {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = UIHostingController(rootView: Color.black)
        window.makeKeyAndVisible()
        self.window = window
    }

    func show<V: View>(_ view: V) {
        window?.rootViewController = UIHostingController(rootView: view)
        window?.makeKeyAndVisible()
        window?.layoutIfNeeded()
    }

    func release() {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    func labels() -> [String] {
        guard let root = window?.rootViewController?.view else { return [] }
        root.layoutIfNeeded()
        var found: [String] = []
        var seen = Set<ObjectIdentifier>()
        func walk(_ object: NSObject) {
            let identity = ObjectIdentifier(object)
            guard seen.insert(identity).inserted else { return }
            if let label = object.accessibilityLabel, !label.isEmpty {
                found.append(label)
            }
            if let view = object as? UIView {
                for child in view.subviews {
                    walk(child)
                }
            }
            let selector = NSSelectorFromString("_accessibilityUserTestingChildren")
            if object.responds(to: selector),
               let result = object.perform(selector)?.takeUnretainedValue() as? [NSObject] {
                for child in result {
                    walk(child)
                }
            }
        }
        walk(root)
        return found
    }
}
