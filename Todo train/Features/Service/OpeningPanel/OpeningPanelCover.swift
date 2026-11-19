//
//  OpeningPanelCover.swift
//  Todo train
//
//  盤の最小画面。MASTER、時計、TICKETS、DEPART の押し棒を載せる。
//

import SwiftData
import SwiftUI

struct OpeningPanelCover: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(ArrivalForecastStore.self) private var forecastStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Ticket.sortOrder) private var allTickets: [Ticket]
    @Query private var allSessions: [WorkSession]

    var onServiceDayNeedsEnd: () -> Void

    @State private var panelState: OpeningPanelState?
    @State private var ticketsModel = OpeningPanelTicketsModel()

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            if let panelState {
                OpeningPanelGrid(
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
                    departFirst: {
                        DepartFirstLine(
                            row: ticketsModel.rows.first,
                            isLit: panelState.isPowered
                                && panelState.confirmation(of: .tickets) == .confirmed,
                            growthStep: panelState.ticketGrowthStep
                        )
                    },
                    departBar: {
                        DepartModule(state: panelState) {
                            panelState.pressDepart()
                        }
                    },
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
                    }
                )
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
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
            if powered == false {
                ticketsModel.dropPicks()
            }
        }
    }

    private var ticketSyncKey: String {
        let sessions = Array(allSessions)
        return allTickets.map { ticket in
            let refined: String
            switch forecastStore.lookup(ticket: ticket, sessions: sessions) {
            case .hit(let minutes):
                refined = minutes.map(String.init) ?? "median"
            case .miss:
                refined = "miss"
            }
            return "\(ticket.id.uuidString)|\(ticket.sortOrder)|\(ticket.estimatedSeconds)|\(ticket.title)|\(ticket.closedAt?.timeIntervalSinceReferenceDate ?? -1)|\(refined)"
        }.joined(separator: ";") + "#\(sessions.count)"
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
