//
//  OpeningPanelCover.swift
//  Todo train
//
//  盤の最小画面。MASTER、時計、DEPART の押し棒を載せる。
//

import SwiftUI

struct OpeningPanelCover: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var onServiceDayNeedsEnd: () -> Void

    @State private var panelState: OpeningPanelState?

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
                    departBar: {
                        DepartModule(state: panelState) {
                            panelState.pressDepart()
                        }
                    }
                )
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task {
            guard panelState == nil else { return }
            panelState = OpeningPanelState.live(
                ticketCount: 0,
                reduceMotion: reduceMotion,
                onStartService: beginServiceFromMaster,
                onShowHub: { dismiss() }
            )
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