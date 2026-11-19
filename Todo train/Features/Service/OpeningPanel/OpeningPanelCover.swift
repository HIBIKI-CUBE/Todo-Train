//
//  OpeningPanelCover.swift
//  Todo train
//
//  盤の最小画面。MASTER と DEPART の押し棒だけを載せる。
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
            OpeningPanelTokens.Palette.housing
                .ignoresSafeArea()
            if let panelState {
                OpeningPanelGrid(
                    master: {
                        MasterModule(state: panelState) {
                            panelState.pressMaster()
                        }
                    },
                    departChevrons: { EmptyView() },
                    departBar: {
                        DepartModule(state: panelState) {
                            panelState.pressDepart()
                        }
                    }
                )
            }
        }
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