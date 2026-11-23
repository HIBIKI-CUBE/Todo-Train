//
//  OpeningPanelTimetableWireTests.swift
//  Todo trainTests
//
//  盤の 5 枠が本物の予定を出し、読み直しが盤の .task から呼ばれること。
//

import SwiftData
import SwiftUI
import UIKit
import Testing
@testable import Todo_train

extension OpeningPanelTimedSuites {
@Suite(.serialized)
@MainActor
struct OpeningPanelTimetableWireTests {
    @Test func coverTaskRefreshesWithoutAskingAndFillsTheFiveSlots() async throws {
        let calendar = Calendar.current
        let day = OpeningPanelWireClock.sameDay(calendar: calendar)
        let board = InMemoryCalendarBoard()
        board.events = [
            CalendarOccurrence(
                eventIdentifier: "morning",
                title: "朝会",
                startsAt: day.start,
                endsAt: day.end,
                isAllDay: false,
                isDeclined: false,
                calendarIdentifier: "work",
                calendarTitle: "仕事"
            )
        ]
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let settings = AppSettings.makeForTesting()
        let manager = SessionManager(
            modelContext: context,
            settings: settings,
            calendarBoard: board
        )
        let host = OpeningPanelWireHost()
        host.install()
        defer { host.release() }

        host.show(
            OpeningPanelCover(onServiceDayNeedsEnd: {})
                .environment(manager)
                .environment(settings)
                .environment(CompanionSyncRuntime())
                .environment(ArrivalForecastStore())
                .modelContainer(container)
        )
        try await Task.sleep(for: .milliseconds(700))
        #expect(board.fetchCount >= 1)
        #expect(board.requestCount == 0)
        let loaded = manager.openingTimetableBoard(now: day.now)
        #expect(loaded.entries.contains { $0.title == "朝会" })

        let pressed = host.activate(label: "MASTER OFF")
        #expect(pressed, Comment(rawValue: host.debugTree()))
        try await Task.sleep(for: .seconds(5))
        let labels = host.labels()
        #expect(labels.contains { $0.contains("朝会") }, Comment(rawValue: labels.joined(separator: " | ")))
        #expect(labels.contains("TT"), Comment(rawValue: labels.joined(separator: " | ")))
        #expect(labels.contains { $0.contains("範囲") || $0.contains("H") }, Comment(rawValue: labels.joined(separator: " | ")))
        #expect(
            labels.contains { $0.contains("運転状況") || $0.contains("平常") || $0.contains("過密") || $0.contains("見合") },
            Comment(rawValue: labels.joined(separator: " | "))
        )
    }

    @Test func arrivingEventsRefreshTheSlotsWithoutAnotherRedraw() async throws {
        let calendar = Calendar.current
        let day = OpeningPanelWireClock.sameDay(calendar: calendar)
        let now = day.now
        let board = InMemoryCalendarBoard()
        let (manager, _, _, _) = try SessionManagerFixtures.makeHarness(
            now: now,
            calendar: calendar,
            calendarBoard: board
        )
        let scheduler = OpeningPanelWireScheduler()
        let state = OpeningPanelState(
            scheduler: scheduler,
            feedback: OpeningPanelFeedbackSilent(),
            reduceMotion: true
        )
        state.pressMaster()
        state.pressConfirm(.timetable)
        scheduler.advance {
            state.timetableStage == .drawn && state.confirmation(of: .timetable) == .confirmed
        }

        let host = OpeningPanelWireHost()
        host.install()
        defer { host.release() }
        host.show(OpeningPanelTimetableWireHost(now: now, state: state).environment(manager))
        try await Task.sleep(for: .milliseconds(200))
        #expect(!host.labels().contains { $0.contains("定例") })

        board.events = [
            CalendarOccurrence(
                eventIdentifier: "weekly",
                title: "定例",
                startsAt: day.start,
                endsAt: day.end,
                isAllDay: false,
                isDeclined: false
            )
        ]
        await manager.refreshCalendarBoardIfAuthorized()
        try await Task.sleep(for: .milliseconds(400))
        let loaded = manager.openingTimetableBoard(
            now: now,
            isTwentyFourHour: state.timetableTwentyFour
        )
        #expect(loaded.entries.contains { $0.title == "定例" })
        let labels = host.labels()
        #expect(labels.contains { $0.contains("定例") }, Comment(rawValue: labels.joined(separator: " | ")))
        #expect(loaded.load.freeMinutes > 0)
        let beforeAdopt = loaded.load.freeMinutes
        if let entry = loaded.entries.first(where: { $0.title == "定例" }) {
            manager.toggleOpeningTimetableStop(entry)
        }
        try await Task.sleep(for: .milliseconds(300))
        let adopted = manager.openingTimetableBoard(
            now: now,
            isTwentyFourHour: state.timetableTwentyFour
        )
        #expect(adopted.entries.contains { $0.title == "定例" && $0.stops })
        #expect(adopted.load.freeMinutes < beforeAdopt)
        #expect(host.labels().contains { $0.contains("着") && $0.contains("定例") })
    }

    @Test func drawnClockDoesNotRedrawTheGrid() async throws {
        let now = Date()
        let (manager, _, _, _) = try SessionManagerFixtures.makeHarness(now: now)
        let scheduler = OpeningPanelWireScheduler()
        let state = OpeningPanelState(
            scheduler: scheduler,
            feedback: OpeningPanelFeedbackSilent(),
            reduceMotion: true
        )
        state.pressMaster()
        state.pressConfirm(.timetable)
        scheduler.advance { state.timetableStage == .drawn }
        let board = manager.openingTimetableBoard(
            now: now,
            isTwentyFourHour: state.timetableTwentyFour
        )

        let host = OpeningPanelWireHost()
        host.install()
        defer { host.release() }
        host.show(
            OpeningPanelGrid(
                scaleToggle: { TimetableScaleKey { state.pressTimetableScale() } },
                timetableTitle: {
                    TimetableSlotMark(
                        label: "範囲",
                        value: board.range.windowLabel
                    )
                },
                range: { TimetableRangeReadout(board: board, drawn: true) },
                runStatusTitle: {
                    TimetableSlotMark(
                        label: "運転状況",
                        value: OpeningPanelTimetableSpeech.runStatus(board.reading)
                    )
                },
                timetable: {
                    TimetableColumnClock(
                        stage: state.timetableStage,
                        board: board,
                        now: now,
                        calendar: manager.calendar,
                        onToggleEntry: { _ in }
                    )
                },
                runStatus: {
                    RunStatusColumnClock(
                        stage: state.timetableStage,
                        board: board,
                        calendar: manager.calendar
                    )
                },
                timetableKey: {
                    TimetableConfirmKey(state: state) { state.pressConfirm(.timetable) }
                },
                timetableTwentyFour: state.timetableTwentyFour
            )
            .frame(width: 402, height: 874)
        )
        try await Task.sleep(for: .milliseconds(250))
        OpeningPanelRedrawProbe.reset()
        OpeningPanelRedrawProbe.enabled = true
        try await Task.sleep(for: .seconds(2))
        OpeningPanelRedrawProbe.enabled = false
        let counts = OpeningPanelRedrawProbe.snapshot()
        #expect(counts["OpeningPanelGrid", default: 0] <= 4)
        #expect(counts["OpeningPanelCover", default: 0] == 0)
    }
}
}

private struct OpeningPanelTimetableWireHost: View {
    @Environment(SessionManager.self) private var sessionManager
    var now: Date
    var state: OpeningPanelState

    var body: some View {
        let board = sessionManager.openingTimetableBoard(
            now: now,
            isTwentyFourHour: state.timetableTwentyFour
        )
        let drawn = state.timetableStage == .drawn
        OpeningPanelGrid(
            scaleToggle: { TimetableScaleKey { state.pressTimetableScale() } },
            timetableTitle: {
                TimetableSlotMark(label: "範囲", value: drawn ? board.range.windowLabel : "")
            },
            range: { TimetableRangeReadout(board: board, drawn: drawn) },
            runStatusTitle: {
                TimetableSlotMark(
                    label: "運転状況",
                    value: drawn ? OpeningPanelTimetableSpeech.runStatus(board.reading) : ""
                )
            },
            timetable: {
                TimetableColumnClock(
                    stage: state.timetableStage,
                    board: board,
                    now: now,
                    calendar: sessionManager.calendar
                ) { entry in
                    sessionManager.toggleOpeningTimetableStop(entry)
                }
            },
            runStatus: {
                RunStatusColumnClock(
                    stage: state.timetableStage,
                    board: board,
                    calendar: sessionManager.calendar
                )
            },
            timetableKey: {
                TimetableConfirmKey(state: state) { state.pressConfirm(.timetable) }
            },
            timetableTwentyFour: state.timetableTwentyFour
        )
        .frame(width: 402, height: 874)
        .background(Color.black)
    }
}

@MainActor
private final class OpeningPanelWireHost {
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
        accessibilityNodes().compactMap(\.text)
    }

    func debugTree() -> String {
        let nodes = accessibilityNodes()
        if nodes.isEmpty { return "accessibility tree empty" }
        return nodes.map(\.debug).joined(separator: "\n")
    }

    func activate(label: String) -> Bool {
        for node in accessibilityNodes() where node.label == label {
            if node.object.accessibilityActivate() { return true }
        }
        return false
    }

    private func accessibilityNodes() -> [OpeningPanelAccessibilityNode] {
        guard let root = window?.rootViewController?.view else { return [] }
        root.layoutIfNeeded()
        var nodes: [OpeningPanelAccessibilityNode] = []
        var seen = Set<ObjectIdentifier>()
        func walk(_ object: NSObject) {
            let identity = ObjectIdentifier(object)
            guard seen.insert(identity).inserted else { return }
            let label = object.accessibilityLabel ?? ""
            let value = object.accessibilityValue ?? ""
            if !label.isEmpty || !value.isEmpty {
                nodes.append(OpeningPanelAccessibilityNode(object: object, label: label, value: value))
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
            let count = object.accessibilityElementCount()
            guard count > 0, count < 800 else { return }
            for index in 0..<count {
                guard let child = object.accessibilityElement(at: index) as? NSObject else { continue }
                walk(child)
            }
        }
        walk(root)
        return nodes
    }
}

private struct OpeningPanelAccessibilityNode {
    var object: NSObject
    var label: String
    var value: String

    var text: String? {
        if !label.isEmpty { return label }
        if !value.isEmpty { return value }
        return nil
    }

    var debug: String {
        "\(type(of: object)) label=\(label) value=\(value)"
    }
}

private enum OpeningPanelWireClock {
    static func sameDay(calendar: Calendar) -> (now: Date, start: Date, end: Date) {
        let day = calendar.startOfDay(for: Date())
        let now = calendar.date(byAdding: .hour, value: 8, to: day) ?? day
        let start = calendar.date(byAdding: .minute, value: 90, to: now) ?? now
        let end = calendar.date(byAdding: .minute, value: 15, to: start) ?? start
        return (now, start, end)
    }
}

@MainActor
private final class OpeningPanelWireScheduler: OpeningPanelScheduling {
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

    func advance(until ready: () -> Bool) {
        var guardrail = 0
        while !ready(), guardrail < 400 {
            guardrail += 1
            guard let index = items.indices.min(by: { items[$0].due < items[$1].due }) else { return }
            let item = items.remove(at: index)
            now = item.due
            item.action()
        }
    }
}
