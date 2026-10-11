//
//  BoardingEligibility.swift
//  Todo train
//
//  One gate for Hub chrome and SessionManager.board. Pause-limit stays soft so a
//  tap can still open the pause sheet or resume an already-paused ticket.
//

import Foundation

enum BoardingEligibility: Equatable, Sendable {
    case allowed
    case blocked(SessionError)

    /// Hub may offer board gestures. Soft blocks still return true.
    var allowsInteraction: Bool {
        switch self {
        case .allowed, .blocked(.pauseLimitReached):
            return true
        case .blocked:
            return false
        }
    }

    /// Accessibility / disabled hint. Prefer `SessionError` copy so UI and throws match.
    var disabledReason: String {
        switch self {
        case .allowed:
            return "発車できません"
        case .blocked(let error):
            return error.errorDescription ?? "発車できません"
        }
    }

    /// Preconditions for starting a *new* ride (not resuming a paused ticket).
    func assertCanStartNewRide() throws {
        switch self {
        case .allowed:
            return
        case .blocked(let error):
            throw error
        }
    }

    /// Preconditions shared by resume and new board (pause limit is ignored).
    func assertCanBoardOrResume() throws {
        switch self {
        case .allowed, .blocked(.pauseLimitReached):
            return
        case .blocked(let error):
            throw error
        }
    }

    static func evaluate(
        isInService: Bool,
        needsServiceDayEnd: Bool,
        hasRunningRide: Bool,
        passengerLocksDriving: Bool,
        canBoardNewRide: Bool
    ) -> BoardingEligibility {
        if passengerLocksDriving {
            return .blocked(.passengerAboard)
        }
        if needsServiceDayEnd {
            return .blocked(.serviceDayNeedsEnd)
        }
        if !isInService {
            return .blocked(.noActiveService)
        }
        if hasRunningRide {
            return .blocked(.alreadyBoarding)
        }
        if !canBoardNewRide {
            return .blocked(.pauseLimitReached)
        }
        return .allowed
    }
}
