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
    @Environment(ArrivalForecastStore.self) private var forecastStore
    @Environment(AppSettings.self) private var settings
    @Environment(CompanionSyncRuntime.self) private var companion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Ticket.sortOrder) private var allTickets: [Ticket]
    @Query private var allSessions: [WorkSession]

    var onServiceDayNeedsEnd: () -> Void

    @State private var panelState: OpeningPanelState?
    @State private var ticketsModel = OpeningPanelTicketsModel()
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
            syncTickets()
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
        }
        .onChange(of: ticketSyncKey) {
            syncTickets()
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

    private var ticketSyncKey: String {
        let _ = OpeningPanelRedrawProbe.bump("ticketSyncKey")
        return allTickets
            .filter(\.isOpen)
            .map { ticket in
                let refined: String
                if let entry = forecastStore.cachedEntry(for: ticket.id) {
                    refined = "\(entry.medianAtRun):\(entry.minutes.map(String.init) ?? "median"):\(entry.fingerprint.band.rawValue)"
                } else {
                    refined = "miss"
                }
                return "\(ticket.id.uuidString)|\(ticket.sortOrder)|\(ticket.estimatedSeconds)|\(ticket.title)|\(refined)"
            }
            .joined(separator: ";") + "#\(allSessions.count)"
    }

    private func syncTickets() {
        let sessions = Array(allSessions)
        ticketsModel.sync(tickets: Array(allTickets), sessions: sessions) { ticket in
            switch forecastStore.lookup(ticket: ticket, sessions: sessions) {
            case .hit(let minutes):
                return minutes
            case .miss:
                return nil
            }
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
