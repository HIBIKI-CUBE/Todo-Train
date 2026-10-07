import CoreGraphics
import Foundation
import TodoTrainSync
import TodoTrainTicketUI

enum ImaYaruOffer {
    static func isAvailable(isPaired: Bool, serviceActive: Bool?) -> Bool {
        isPaired && serviceActive == true
    }

    /// Session the next interrupt must name. Idle snaps do not count, even with a leftover id.
    static func ridingSessionID(_ snap: SnapPlaintext?) -> UUID? {
        guard let snap else { return nil }
        switch snap.phase {
        case .running, .paused, .overtime:
            return snap.sessionId
        case .idle, .unknown:
            return nil
        }
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
        let actual = IssueAndBoardEvaluating.trimmedTitle(snap.title ?? "")
        guard actual == expected else { return false }
        if let priorSessionId, sessionId == priorSessionId { return false }
        return true
    }
}

enum ImaYaruStep: Equatable, Sendable {
    case wait
    case dispense
    case fail(WireError)
}

enum ImaYaruCommit {
    /// Ride confirmation wins over a failure ack. A second pull can ack mismatch after the board stuck.
    static func next(track: IssueBoardTrack, rideConfirmed: Bool) -> ImaYaruStep {
        if rideConfirmed { return .dispense }
        switch track {
        case .acked:
            return .dispense
        case .failed(let error):
            return .fail(error)
        case .idle, .sending:
            return .wait
        }
    }
}

enum ImaYaruWaitCue: Equatable, Sendable {
    case quiet
    case waiting
    case timedOut
}

enum ImaYaruWait {
    static let captionAfter: TimeInterval = 1.5
    static let limit: TimeInterval = 8

    static func cue(elapsed: TimeInterval) -> ImaYaruWaitCue {
        if elapsed >= limit { return .timedOut }
        if elapsed >= captionAfter { return .waiting }
        return .quiet
    }
}

/// Mars face centered on the future PiP, entering from the nearest screen edge.
enum TicketDispenseGeometry {
    static let edgeGap: CGFloat = 12

    static func restingFrame(pip: CGRect) -> CGRect {
        let width = pip.width
        let height = MarsTicketSpec.height(forWidth: width)
        return CGRect(
            x: pip.midX - width / 2,
            y: pip.midY - height / 2,
            width: width,
            height: height
        )
    }

    static func entryFrame(resting: CGRect, display: CGRect) -> CGRect {
        var frame = resting
        let distBottom = resting.midY - display.minY
        let distTop = display.maxY - resting.midY
        let distLeft = resting.midX - display.minX
        let distRight = display.maxX - resting.midX
        if min(distBottom, distTop) <= min(distLeft, distRight) {
            if distBottom <= distTop {
                frame.origin.y = display.minY - resting.height - edgeGap
            } else {
                frame.origin.y = display.maxY + edgeGap
            }
        } else if distLeft <= distRight {
            frame.origin.x = display.minX - resting.width - edgeGap
        } else {
            frame.origin.x = display.maxX + edgeGap
        }
        return frame
    }
}
