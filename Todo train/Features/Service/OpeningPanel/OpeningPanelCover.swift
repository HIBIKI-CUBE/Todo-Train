//
//  OpeningPanelCover.swift
//  Todo train
//
//  盤の最小画面。MASTER、時計、TICKETS、CHK・PHONE・COMM・LOAD、DEPART を載せる。
//

import SwiftData
import SwiftUI
import UIKit

struct OpeningPanelCover: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(AppSettings.self) private var settings
    @Environment(CompanionSyncRuntime.self) private var companion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext

    /// 運行中に開いた盤。MASTER は運行を始め直さない。
    var serviceAlreadyRunning = false
    var onServiceDayNeedsEnd: () -> Void

    @State private var panelState: OpeningPanelState?
    @State private var ticketsModel = OpeningPanelTicketsModel()
    @State private var reserveGate = OpeningPanelReserveGate()
    @State private var commModel = OpeningPanelCommModel()
    @State private var loadPlayer = OpeningPanelLoadPlayer(scheduler: OpeningPanelDispatchScheduler())
    @State private var loadDrawing = OpeningPanelLoadDrawing.dark
    @State private var loadNow = Date()
    @State private var phoneSupply: OpeningPanelPhoneSupply = .unknown

    var body: some View {
        let _ = OpeningPanelRedrawProbe.bump("OpeningPanelCover")
        ZStack {
            Color.black
                .ignoresSafeArea()
            if let panelState {
                let phone = phoneReading(powered: panelState.isPowered)
                let live = liveBoard(for: panelState, now: loadNow)
                let board = live.board
                let loadTarget = live.target
                let drawn = panelState.timetableStage == .drawn
                let timetableLit = drawn
                    && panelState.isPowered
                    && panelState.confirmation(of: .timetable) == .confirmed
                OpeningPanelGrid(
                    phone: {
                        OpeningPanelPhoneWindow(reading: phone, powered: panelState.isPowered)
                    },
                    master: {
                        MasterModule(state: panelState) {
                            panelState.pressMaster()
                        }
                    },
                    clock: {
                        ClockModule(state: panelState)
                    },
                    clockKey: {
                        ClockConfirmKey(state: panelState) {
                            panelState.pressConfirm(.clock)
                        }
                    },
                    hourMode: {
                        ClockHourModeKey(state: panelState) {
                            panelState.pressHourMode()
                        }
                    },
                    scaleToggle: {
                        TimetableScaleKey {
                            panelState.pressTimetableScale()
                        }
                    },
                    timetableTitle: {
                        TimetableSlotMark(
                            label: "範囲",
                            value: drawn ? board.range.windowLabel : ""
                        )
                    },
                    range: {
                        TimetableRangeReadout(board: board, drawn: drawn)
                    },
                    runStatusTitle: {
                        TimetableSlotMark(
                            label: "運転状況",
                            value: drawn ? OpeningPanelTimetableSpeech.runStatus(board.reading) : ""
                        )
                    },
                    timetable: {
                        TimetableColumnClock(
                            stage: panelState.timetableStage,
                            board: board,
                            now: loadNow,
                            calendar: sessionManager.calendar
                        ) { entry in
                            sessionManager.toggleOpeningTimetableStop(entry)
                        }
                    },
                    runStatus: {
                        RunStatusColumnClock(
                            stage: panelState.timetableStage,
                            board: board,
                            calendar: sessionManager.calendar
                        )
                    },
                    nextStop: {
                        let _ = OpeningPanelSlotProbe.mark("nextStop")
                        TimetableNextSlotClock(
                            kind: .stop,
                            stage: panelState.timetableStage,
                            board: board
                        )
                    },
                    nextRide: {
                        let _ = OpeningPanelSlotProbe.mark("nextRide")
                        TimetableNextSlotClock(
                            kind: .ride,
                            stage: panelState.timetableStage,
                            board: board
                        )
                    },
                    timetableKey: {
                        TimetableConfirmKey(state: panelState) {
                            panelState.pressConfirm(.timetable)
                        }
                    },
                    nowLegend: {
                        let _ = OpeningPanelSlotProbe.mark("nowLegend")
                        TimetableSlotMark(
                            label: "ただいま",
                            value: timetableLit
                                ? OpeningPanelTimetableSpeech.runStatus(board.reading)
                                : ""
                        )
                    },
                    nowBoard: {
                        let _ = OpeningPanelSlotProbe.mark("nowBoard")
                        NowBoardClock(
                            stage: panelState.timetableStage,
                            board: board,
                            isLit: timetableLit,
                            calendar: sessionManager.calendar
                        )
                    },
                    sequenceKey: {
                        TicketsSequenceKey(state: panelState, phase: ticketsModel.sequencePhase) {
                            pressSequenceKey(panelState)
                        }
                    },
                    ticketsKey: {
                        TicketsConfirmKey(state: panelState) {
                            panelState.pressConfirm(.tickets)
                        }
                    },
                    // 段名は格子の OpeningPanelSlotNames が描く。先頭に足す計器はない。
                    ticketsLeading: {
                        let _ = OpeningPanelSlotProbe.mark("ticketsLeading")
                        EmptyView()
                    },
                    tickets: {
                        TicketsModule(
                            state: panelState,
                            model: ticketsModel,
                            calendar: sessionManager.calendar
                        )
                    },
                    load: {
                        LoadGauge(drawing: loadDrawing)
                    },
                    commTest: {
                        OpeningPanelCommButton(testing: commModel.testing) {
                            beginCommTest(panelState)
                        }
                    },
                    comm: {
                        OpeningPanelCommWindow(
                            text: commModel.display.text,
                            visible: commModel.display.visible && panelState.isPowered
                        )
                    },
                    // ロック行の灯は departLocks を格子の OpeningPanelLockRow が描く。重ねる計器はない。
                    departLock: {
                        let _ = OpeningPanelSlotProbe.mark("departLock")
                        EmptyView()
                    },
                    departStatus: {
                        let _ = OpeningPanelSlotProbe.mark("departStatus")
                        DepartStatusClock(
                            stage: panelState.timetableStage,
                            board: board,
                            isLit: timetableLit,
                            calendar: sessionManager.calendar
                        )
                    },
                    departFirst: {
                        DepartFirstLine(
                            row: ticketsModel.rows.first,
                            isLit: panelState.isPowered
                                && panelState.confirmation(of: .tickets) == .confirmed,
                            growthStep: panelState.ticketGrowthStep
                        )
                    },
                    departChevrons: {
                        DepartChevronField(state: panelState)
                    },
                    departBar: {
                        DepartModule(state: panelState) {
                            panelState.pressDepart()
                        }
                    },
                    departLocks: OpeningPanelLockPicture(state: panelState),
                    chevronsFlowing: panelState.chevronsFlowing,
                    departColumnLit: panelState.departColumnLit,
                    glowingModules: Set(panelState.glowingFaces.map(\.panelModule)),
                    lamps: lampField(state: panelState, phone: phone),
                    commTesting: commModel.testing && panelState.isPowered,
                    loadLit: loadDrawing.lit,
                    loadFrameTop: loadDrawing.frameTop,
                    sequenceLit: panelState.sequenceLampLit,
                    todayCut: ticketsModel.cut,
                    todayRows: ticketsModel.rows.count,
                    todayRailLit: panelState.isPowered
                        && panelState.confirmation(of: .tickets) == .confirmed,
                    onTodayRail: { y, began in
                        OpeningPanelTickets.perform(
                            OpeningPanelTickets.touchRail(
                                y: y,
                                began: began,
                                count: ticketsModel.rows.count,
                                cut: ticketsModel.cut,
                                sequencing: panelState.isSequencing,
                                confirmed: panelState.confirmation(of: .tickets) == .confirmed,
                                powered: panelState.isPowered,
                                departed: panelState.hasDeparted
                            ),
                            state: panelState,
                            model: ticketsModel
                        )
                    },
                    timetableTwentyFour: panelState.timetableTwentyFour,
                    sequenceMode: sequenceHitMode
                )
                // onChange は既定だと最初の値を渡さない。計器は出た瞬間の目標も受け取る。
                .onChange(of: loadTarget, initial: true) { _, target in
                    bindLoadSample()
                    loadPlayer.set(target)
                    loadDrawing = OpeningPanelLoadLogic.drawing(loadPlayer.sample)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            refreshPhone()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            refreshPhone()
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task {
            await sessionManager.refreshCalendarBoardIfAuthorized()
        }
        .task {
            guard panelState == nil else { return }
            paintTickets()
            let model = ticketsModel
            let context = modelContext
            panelState = OpeningPanelState.live(
                ticketCount: model.rows.count,
                reduceMotion: reduceMotion,
                serviceAlreadyRunning: serviceAlreadyRunning,
                onStartService: beginServiceFromMaster,
                onCommitSequence: { model.commitSequenceOrder(in: context) },
                onAbandonSequence: { model.abandonSequence() },
                onShowHub: { dismiss() }
            )
            await Task.yield()
            startReserve()
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { note in
            guard panelState != nil else { return }
            guard !ForecastReserveStore.savedByUs(note) else { return }
            startReserve()
        }
        .onChange(of: ticketsModel.cut) {
            guard panelState != nil, reserveGate.isActive else { return }
            startReserve()
        }
        .onChange(of: ticketsModel.rows.count) {
            guard let panelState else { return }
            if panelState.ticketsStage == .dark,
               panelState.confirmation(of: .tickets) == .unconfirmed {
                panelState.ticketCount = ticketsModel.rows.count
            }
        }
        .onChange(of: panelState?.isPowered) { _, powered in
            if powered == true {
                loadNow = Date()
                commModel.showIdle()
            } else {
                ticketsModel.abandonSequence()
                commModel.reset()
            }
            refreshPhone()
        }
        .onDisappear {
            commModel.reset()
            UIDevice.current.isBatteryMonitoringEnabled = false
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                loadNow = Date()
            }
        }
    }

    private func phoneReading(powered: Bool) -> OpeningPanelPhone.Reading {
        OpeningPanelPhone.reading(
            powered: powered,
            supply: phoneSupply,
            keepAwake: settings.keepAwakeWhileChargingInFocus
        )
    }

    private func lampField(
        state: OpeningPanelState,
        phone: OpeningPanelPhone.Reading
    ) -> OpeningPanelLampField {
        let powered = state.isPowered
        let comm = powered ? commModel.display : .hidden
        return OpeningPanelLampField(
            master: OpeningPanelSystem.checkLamp(powered: powered, lit: state.checkIsLit(.master)),
            clock: OpeningPanelSystem.checkLamp(powered: powered, lit: state.checkIsLit(.clock)),
            timetable: OpeningPanelSystem.checkLamp(powered: powered, lit: state.checkIsLit(.timetable)),
            tickets: OpeningPanelSystem.checkLamp(powered: powered, lit: state.checkIsLit(.tickets)),
            ext: phone.extLit ? .green : .off,
            awake: phone.awakeLit ? .green : .off,
            relay: comm.relay,
            mac: comm.mac
        )
    }

    private func liveBoard(
        for state: OpeningPanelState,
        now: Date
    ) -> (board: OpeningTimetableBoard, target: OpeningPanelLoadTarget) {
        let _ = OpeningPanelRedrawProbe.bump("loadTarget")
        let lit = OpeningPanelLoadLogic.isLit(
            powered: state.isPowered,
            timetableConfirmed: state.confirmation(of: .timetable) == .confirmed,
            ticketsConfirmed: state.confirmation(of: .tickets) == .confirmed
        )
        let above = Array(ticketsModel.rows.prefix(ticketsModel.cut))
        let tickets = above.map { ServiceLoadTicket(durationMinutes: $0.actualMinutes) }
        let board = sessionManager.openingTimetableBoard(
            now: now,
            isTwentyFourHour: state.timetableTwentyFour,
            ticketsAboveCutoff: tickets
        )
        let target = OpeningPanelLoadWire.target(
            lit: lit,
            now: now,
            rangeEndsAt: board.range.endsAt,
            freeMinutes: board.load.freeMinutes,
            ticketMinutes: above.map(\.actualMinutes)
        )
        return (board, target)
    }

    private func bindLoadSample() {
        guard loadPlayer.onSample == nil else { return }
        loadPlayer.onSample = { [weak loadPlayer] in
            guard let loadPlayer else { return }
            loadDrawing = OpeningPanelLoadLogic.drawing(loadPlayer.sample)
        }
    }

    private func beginCommTest(_ state: OpeningPanelState) {
        guard !commModel.testing else { return }
        guard state.pressCommTest() else { return }
        let presence = sessionManager.macPresenceKnown
        commModel.start(
            measure: { onRelay in
                await companion.measureComm(macPresenceKnown: presence, onRelay: onRelay)
            },
            onRelay: { state.noteCommLamp() },
            onMac: { state.noteCommLamp() },
            onFailure: { state.noteCommFailure() }
        )
    }

    private func refreshPhone() {
        let powered = panelState?.isPowered == true
        UIDevice.current.isBatteryMonitoringEnabled = OpeningPanelSystem.monitorsBattery(
            panelVisible: true,
            powered: powered
        )
        phoneSupply = OpeningPanelSystem.phoneSupply(
            state: UIDevice.current.batteryState,
            level: UIDevice.current.batteryLevel
        )
    }

    private var sequenceHitMode: OpeningPanelHitLayout.SequenceMode? {
        switch ticketsModel.sequencePhase {
        case .sorting: return .sorting
        case .comparing: return .comparing
        case .result: return .result
        case nil: return nil
        }
    }

    private func pressSequenceKey(_ state: OpeningPanelState) {
        guard state.isPowered, state.confirmation(of: .tickets) == .confirmed, !state.hasDeparted else {
            state.pressSequence()
            return
        }
        if !state.isSequencing {
            let sessions = (try? modelContext.fetch(FetchDescriptor<WorkSession>())) ?? []
            let free = sessionManager.openingTimetableBoard(
                now: loadNow,
                isTwentyFourHour: state.timetableTwentyFour
            ).load.freeMinutes
            guard OpeningPanelTickets.enterSequence(
                state: state,
                model: ticketsModel,
                sessions: sessions,
                freeMinutes: free,
                now: loadNow,
                calendar: sessionManager.calendar,
                in: modelContext
            ) else {
                state.rejectTouch()
                return
            }
            return
        }
        if ticketsModel.sequencePhase == .result {
            state.pressSequence()
            return
        }
        ticketsModel.finishSequenceEarly()
        state.noteSequenceRow(accepted: true)
    }

    private func paintTickets() {
        let tickets = (try? modelContext.fetch(
            FetchDescriptor<Ticket>(sortBy: [SortDescriptor(\.sortOrder)])
        )) ?? []
        ticketsModel.show(
            tickets: tickets,
            arrivals: ForecastReserveStore.tentativePlaces(in: modelContext, tickets: tickets)
        )
    }

    private func startReserve() {
        let generation = reserveGate.begin()
        let context = modelContext
        let model = ticketsModel
        let calendar = sessionManager.calendar
        let order = model.rows.map(\.id)
        let cut = model.cut
        Task { @MainActor in
            await ForecastReserveStore.refresh(
                in: context,
                rowOrder: order,
                cut: cut,
                calendar: calendar,
                onPlace: { id, place in
                    guard reserveGate.isCurrent(generation) else { return }
                    model.applyArrival(id: id, place: place)
                }
            )
            reserveGate.end(generation)
        }
    }

    private func beginServiceFromMaster() {
        switch OpeningPanelServiceStart.begin(sessionManager: sessionManager) {
        case .started, .alreadyActive:
            break
        case .needsEndPreviousDay:
            dismiss()
            onServiceDayNeedsEnd()
        case .failed:
            break
        }
    }
}

enum OpeningPanelSlotProbe {
    static var enabled = false
    static let names = [
        "nextStop", "nextRide", "nowLegend", "nowBoard",
        "departLock", "departStatus", "ticketsLeading",
    ]
    private static let lock = NSLock()
    private static var storage: Set<String> = []

    static func mark(_ name: String) {
        guard enabled else { return }
        lock.lock()
        storage.insert(name)
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        storage.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    static func snapshot() -> Set<String> {
        lock.lock()
        let copy = storage
        lock.unlock()
        return copy
    }
}

@MainActor
private final class OpeningPanelReserveGate {
    private var generation = 0
    private var active: Int?

    var isActive: Bool { active != nil }

    func begin() -> Int {
        generation += 1
        active = generation
        return generation
    }

    func isCurrent(_ generation: Int) -> Bool {
        self.generation == generation
    }

    func end(_ generation: Int) {
        if active == generation {
            active = nil
        }
    }
}
