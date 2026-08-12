//
//  Enums.swift
//  Todo train
//

import Foundation

enum SessionPhase: String, Codable, Sendable, Equatable {
    case idle
    case running
    case paused
    case overtime
}

enum ClosureKind: String, Codable, Sendable {
    case arrived
    case partialDisembark
    case abandoned
}

enum SessionOutcome: String, Codable, Sendable {
    case arrived
    case partialDisembark
    case abandoned
    case recoveryConflict
}

enum LineageKind: String, Codable, Sendable {
    case continuation
    case split
    case discovered
    case manual
}

enum SessionError: Error, Equatable, LocalizedError {
    case serviceAlreadyActive
    case noActiveService
    case serviceDayNeedsEnd
    case alreadyBoarding
    case noActiveSession
    case notPaused
    case notRunning
    case pauseLimitReached
    case cannotEndServiceWhileRunning
    case unresolvedPausedTickets
    case ticketAlreadyClosed

    var errorDescription: String? {
        switch self {
        case .serviceAlreadyActive:
            "運行はすでに開始されています"
        case .noActiveService:
            "運行を開始してください"
        case .serviceDayNeedsEnd:
            "昨日の運行を終了してください"
        case .alreadyBoarding:
            "すでに走行中の切符があります"
        case .noActiveSession:
            "アクティブなセッションがありません"
        case .notPaused:
            "停車中ではありません"
        case .notRunning:
            "走行中ではありません"
        case .pauseLimitReached:
            "停車中の切符が上限です"
        case .cannotEndServiceWhileRunning:
            "走行中は運行終了できません。先に停車または到着してください"
        case .unresolvedPausedTickets:
            "停車中の切符を途中下車または放棄してから運行終了してください"
        case .ticketAlreadyClosed:
            "この切符はすでに閉じられています"
        }
    }
}
