//
//  OpeningPanelHubFlow.swift
//  Todo train
//
//  Hub から盤を出すときの分岐。`requestStartService()` は盤を出すだけ。
//

import Foundation

enum OpeningPanelHubFlow {
    enum StartIntent: Equatable {
        case showPanel
        case promptEndPreviousDay
    }

    static func startIntent(needsServiceDayEndPrompt: Bool) -> StartIntent {
        needsServiceDayEndPrompt ? .promptEndPreviousDay : .showPanel
    }

    struct PanelEntry: Equatable {
        /// 運行中に開く。MASTER は運行を始め直さない。
        var serviceAlreadyRunning: Bool
    }

    /// ハブの盤の入口。運行中も運行開始前も盤を出す。運行中は発車済みとして扱う。
    static func panelEntry(isInService: Bool) -> PanelEntry {
        PanelEntry(serviceAlreadyRunning: isInService)
    }
}

enum OpeningPanelServiceStart {
    enum Result: Equatable {
        case started
        case alreadyActive
        case needsEndPreviousDay
        case failed
    }

    static func begin(sessionManager: SessionManager) -> Result {
        do {
            try sessionManager.startService()
            return .started
        } catch SessionError.serviceDayNeedsEnd {
            return .needsEndPreviousDay
        } catch SessionError.serviceAlreadyActive {
            return .alreadyActive
        } catch {
            return .failed
        }
    }
}