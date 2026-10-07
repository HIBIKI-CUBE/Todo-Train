import CoreGraphics
import Foundation
import TodoTrainSync
import TodoTrainTicketUI

/// Fixed frame for いまやる. Every phase reports the same size.
enum ImaYaruPhase: Equatable, Sendable {
    case composing
    case ejecting
    case holding
    case failed
}

enum ImaYaruCanvas {
    static let width: CGFloat = 440
    static let titleRail: CGFloat = 76
    static let gaugeRail: CGFloat = 120
    static let horizontalPad: CGFloat = 20
    static let verticalPad: CGFloat = 16
    static let stackSpacing: CGFloat = 12

    static var ticketSlotHeight: CGFloat {
        MarsTicketSpec.height(forWidth: width - horizontalPad * 2)
    }

    static var height: CGFloat {
        verticalPad * 2 + titleRail + stackSpacing + gaugeRail + stackSpacing + ticketSlotHeight
    }

    static var size: CGSize {
        CGSize(width: width, height: height)
    }

    static func size(for phase: ImaYaruPhase) -> CGSize {
        _ = phase
        return size
    }
}

enum ImaYaruOffer {
    static func isAvailable(isPaired: Bool, serviceActive: Bool?) -> Bool {
        isPaired && serviceActive == true
    }
}

enum IssueBoardTrack: Equatable, Sendable {
    case idle
    case sending(cmdId: UUID, title: String, priorSessionId: UUID?)
    case acked(cmdId: UUID, title: String, priorSessionId: UUID?)
    case failed(WireError)
}

enum IssueBoardTracking {
    static func begin(
        cmdId: UUID,
        title: String,
        priorSessionId: UUID?,
        current: IssueBoardTrack
    ) -> IssueBoardTrack? {
        if case .sending = current { return nil }
        return .sending(cmdId: cmdId, title: title, priorSessionId: priorSessionId)
    }

    static func applyAck(_ ack: AckPlaintext, current: IssueBoardTrack) -> IssueBoardTrack {
        guard case .sending(let cmdId, let title, let prior) = current, ack.cmdId == cmdId else {
            return current
        }
        if ack.ok {
            return .acked(cmdId: cmdId, title: title, priorSessionId: prior)
        }
        return .failed(ack.error ?? .decryptFailed)
    }

    static func failTransport(_ current: IssueBoardTrack) -> IssueBoardTrack {
        guard case .sending = current else { return current }
        return .failed(.decryptFailed)
    }
}

enum ImaYaruSnap {
    /// True when the snap is a new ride for this issue, not the ride we interrupted.
    static func confirms(snap: SnapPlaintext?, title: String, priorSessionId: UUID?) -> Bool {
        guard let snap, let sessionId = snap.sessionId else { return false }
        switch snap.phase {
        case .running, .paused, .overtime:
            break
        case .idle, .unknown:
            return false
        }
        let expected = IssueAndBoardEvaluating.trimmedTitle(title)
        guard snap.title == expected else { return false }
        if let priorSessionId, sessionId == priorSessionId { return false }
        return true
    }
}
