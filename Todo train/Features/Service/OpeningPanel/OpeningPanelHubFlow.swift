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