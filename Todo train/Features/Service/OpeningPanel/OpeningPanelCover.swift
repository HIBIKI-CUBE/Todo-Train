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

    var onServiceDayNeedsEnd: () -> Void

    @State private var panelState: OpeningPanelState?
    @State private var ticketsModel = OpeningPanelTicketsModel()
    @State private var reserveGate = OpeningPanelReserveGate()
    @State private var commModel = OpeningPanelCommModel()
    @State private var loadPlayer = OpeningPanelLoadPlayer(scheduler: OpeningPanelDispatchScheduler())
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
                let loadDrawing = OpeningPanelLoadLogic.drawing(loadPlayer.sample)
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
                            panelState.pressHourMode()
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
                    timetableKey: {
                        TimetableConfirmKey(state: panelState) {
                            panelState.pressConfirm(.timetable)
                        }
                    },
                    sequenceKey: {
                        TicketsSequenceKey(state: panelState) {
                            panelState.pressSequence()
                        }
                    },
                    ticketsKey: {
                        TicketsConfirmKey(state: panelState) {
                            panelState.pressConfirm(.tickets)
                        }
                    },
                    tickets: {
                        TicketsModule(state: panelState, model: ticketsModel)
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
                    timetableTwentyFour: panelState.hourCycle == .twentyFour
                )
                .onChange(of: loadTarget) { _, target in
                    loadPlayer.set(target)
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
                onStartService: beginServiceFromMaster,
                onCommitSequence: { model.commitSequenceOrder(in: context) },
                onAbandonSequence: { model.dropPicks() },
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
                ticketsModel.dropPicks()
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
            isTwentyFourHour: state.hourCycle == .twentyFour,
            ticketsAboveCutoff: tickets
        )
        let span = max(1, Int(board.range.endsAt.timeIntervalSince(now) / 60))
        let target = OpeningPanelLoadTarget(
            lit: lit,
            freeMinutes: Double(board.load.freeMinutes),
            spanMinutes: Double(span),
            tickets: lit ? above.map { Double($0.actualMinutes) } : []
        )
        return (board, target)
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
