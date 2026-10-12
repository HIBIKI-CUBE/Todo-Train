//
//  RideControlPerformer.swift
//  Todo train
//
//  コントロールは画面のボタンと同じメソッドを呼ぶ。記録の経路は増やさない。
//

import Foundation

extension SessionManager: RideControlPerforming {
    func boardReservedFromControl() -> RideControlEffect {
        adoptOpenRideIfNeeded()
        if reservedNextTicket() == nil, arrivalGapBanner?.ticketID == nil {
            return RideControlEffect(dialog: "予約の切符はありません。")
        }
        if phase == .running || phase == .overtime {
            return RideControlEffect(dialog: "走行中です。")
        }
        do {
            try refusePassengerDriving()
            if arrivalGapBanner?.ticketID != nil {
                try boardReservedFromHub()
            } else if let ticket = reservedNextTicket() {
                try board(ticket: ticket)
            }
        } catch let error as SessionError {
            return RideControlEffect(dialog: Self.controlDialog(for: error))
        } catch {
            return RideControlEffect(dialog: "この操作はできません。")
        }
        guard phase == .running || phase == .overtime else {
            return RideControlEffect(dialog: "予約の切符はありません。")
        }
        return RideControlEffect(dialog: "予約の切符で発車しました。")
    }

    func continueFromControl() -> RideControlEffect {
        adoptOpenRideIfNeeded()
        guard let session = activeSession, session.isOpen else {
            return RideControlEffect(dialog: "走行中ではありません。")
        }
        let before = session.checkInAnswersJSON
        do {
            try answerCheckIn(.stillOnIt)
        } catch let error as SessionError {
            return RideControlEffect(dialog: Self.controlDialog(for: error))
        } catch {
            return RideControlEffect(dialog: "この操作はできません。")
        }
        if session.checkInAnswersJSON != before {
            return RideControlEffect(dialog: "続行しました。")
        }
        return RideControlEffect(dialog: "問いは出ていません。")
    }

    func pauseFromControl() -> RideControlEffect {
        adoptOpenRideIfNeeded()
        guard let session = activeSession, session.isOpen else {
            return RideControlEffect(dialog: "走行中ではありません。")
        }
        if session.isPaused {
            return RideControlEffect(dialog: "停車中です。")
        }
        let beforeAnswers = session.checkInAnswersJSON
        let beforePauses = session.pauses.count
        do {
            if session.pendingCheckIn == .progress {
                try answerCheckIn(.paused)
            } else {
                try pause()
            }
        } catch let error as SessionError {
            return RideControlEffect(dialog: Self.controlDialog(for: error))
        } catch {
            return RideControlEffect(dialog: "この操作はできません。")
        }
        if session.isPaused || session.pauses.count != beforePauses || session.checkInAnswersJSON != beforeAnswers {
            return RideControlEffect(dialog: "停車しました。")
        }
        return RideControlEffect(dialog: "問いは出ていません。")
    }

    func resumeFromControl() -> RideControlEffect {
        adoptOpenRideIfNeeded()
        guard let session = activeSession, session.isOpen, session.isPaused, let ticket = session.ticket else {
            return RideControlEffect(dialog: "停車中ではありません。")
        }
        do {
            try board(ticket: ticket)
        } catch let error as SessionError {
            return RideControlEffect(dialog: Self.controlDialog(for: error))
        } catch {
            return RideControlEffect(dialog: "この操作はできません。")
        }
        return RideControlEffect(dialog: "再乗車しました。")
    }

    func arriveFromControl() -> RideControlEffect {
        adoptOpenRideIfNeeded()
        guard let session = activeSession, session.isOpen else {
            return RideControlEffect(dialog: "走行中ではありません。")
        }
        do {
            try arrive()
        } catch let error as SessionError {
            return RideControlEffect(dialog: Self.controlDialog(for: error))
        } catch {
            return RideControlEffect(dialog: "この操作はできません。")
        }
        return RideControlEffect(dialog: "到着しました。")
    }

    private func adoptOpenRideIfNeeded() {
        if let session = activeSession, session.isOpen { return }
        let open = fetchOpenSessions().sorted { $0.startedAt > $1.startedAt }
        if let running = open.first(where: { !$0.isPaused }) {
            activeSession = running
        } else if let paused = open.first {
            activeSession = paused
        }
        if activeSession != nil {
            reconcile()
        }
    }

    private static func controlDialog(for error: SessionError) -> String {
        switch error {
        case .noActiveService, .serviceDayNeedsEnd:
            "運行は始まっていません。"
        case .alreadyBoarding:
            "走行中です。"
        case .noActiveSession, .notRunning:
            "走行中ではありません。"
        case .notPaused:
            "停車中ではありません。"
        case .pauseLimitReached:
            "停車が上限に達しています。"
        case .passengerAboard:
            "乗客の移動中です。"
        case .ticketAlreadyClosed:
            "この切符は閉じています。"
        case .serviceAlreadyActive, .cannotEndServiceWhileRunning, .unresolvedPausedTickets,
             .cannotDeleteOpenSession, .cannotReserveCurrentRide, .emptyTicketTitle:
            "この操作はできません。"
        }
    }
}
