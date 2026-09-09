import Foundation
import TodoTrainSync

enum CompanionSnapBuilding {
    static func wirePhase(_ phase: SessionPhase) -> WirePhase {
        switch phase {
        case .idle: .idle
        case .running: .running
        case .paused: .paused
        case .overtime: .overtime
        }
    }

    static func snap(
        rev: Int,
        phase: SessionPhase,
        session: WorkSession?,
        now: Date
    ) -> SnapPlaintext {
        guard let session, session.isOpen, phase != .idle else {
            return idle(rev: rev)
        }
        let started = Int(session.startedAt.timeIntervalSince1970)
        let elapsedActive = Int(session.elapsedSeconds(at: now).rounded(.towardZero))
        let pausedAtUnix: Int?
        let pausedAccumulated: Int
        if let pausedAt = session.pausedAt {
            let pausedUnix = Int(pausedAt.timeIntervalSince1970)
            pausedAtUnix = pausedUnix
            pausedAccumulated = max(0, (pausedUnix - started) - elapsedActive)
        } else {
            pausedAtUnix = nil
            let nowUnix = Int(now.timeIntervalSince1970)
            pausedAccumulated = max(0, (nowUnix - started) - elapsedActive)
        }
        return SnapPlaintext(
            rev: rev,
            sessionId: session.id,
            ticketId: session.ticket?.id,
            title: session.ticket?.title,
            phase: wirePhase(phase),
            startedAt: started,
            estimatedSeconds: session.budgetSecondsAtStart,
            pausedAccumulated: pausedAccumulated,
            pausedAt: pausedAtUnix,
            boardedDeviceID: session.boardedDeviceID
        )
    }

    static func idle(rev: Int) -> SnapPlaintext {
        SnapPlaintext(
            rev: rev,
            sessionId: nil,
            ticketId: nil,
            title: nil,
            phase: .idle,
            startedAt: nil,
            estimatedSeconds: nil,
            pausedAccumulated: nil,
            pausedAt: nil,
            boardedDeviceID: nil
        )
    }
}
