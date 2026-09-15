//
//  TimetableGuardLogic.swift
//  Todo train
//
//  ATS: overlap of an adopted ダイヤ and a running ride. Pause is the net;
//  driving stays with the person. Scores and "keep riding" are not here.
//

import Foundation

nonisolated struct TimetableGuardBlock: Equatable, Sendable, Identifiable {
    var id: UUID
    var startsAt: Date
    var endsAt: Date
    var isCancelled: Bool

    init(id: UUID = UUID(), startsAt: Date, endsAt: Date, isCancelled: Bool = false) {
        self.id = id
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.isCancelled = isCancelled
    }
}

nonisolated struct TimetableOpenGuard: Equatable, Sendable {
    var id: UUID
    var sessionID: UUID
    var blockID: UUID
    var notifiedAt: Date
    var protectionBoundary: Date
}

nonisolated enum TimetableRideState: Equatable, Sendable {
    case idle
    case running(sessionID: UUID, segmentStart: Date)
    case paused(sessionID: UUID)
    case arrived(sessionID: UUID)
}

nonisolated enum TimetableGuardEffect: Equatable, Sendable {
    case none
    case arm(blockID: UUID, notifiedAt: Date, protectionBoundary: Date)
    case pauseAt(Date)
    case resolve
    case invalidate
}

nonisolated enum TimetableGuardLogic {
    static let grace: TimeInterval = TimetableFit.protectionGrace

    static func overlappingEligibleBlock(
        blocks: [TimetableGuardBlock],
        now: Date
    ) -> TimetableGuardBlock? {
        blocks.first { block in
            !block.isCancelled
                && block.startsAt <= now
                && now < block.endsAt
        }
    }

    static func origin(blockStart: Date, segmentStart: Date) -> Date {
        max(blockStart, segmentStart)
    }

    static func protectionBoundary(blockStart: Date, segmentStart: Date) -> Date {
        origin(blockStart: blockStart, segmentStart: segmentStart).addingTimeInterval(grace)
    }

    static func evaluate(
        ride: TimetableRideState,
        blocks: [TimetableGuardBlock],
        openGuard: TimetableOpenGuard?,
        now: Date
    ) -> TimetableGuardEffect {
        switch ride {
        case .idle:
            return openGuard == nil ? .none : .invalidate
        case .arrived:
            return openGuard == nil ? .none : .invalidate
        case .paused:
            return openGuard == nil ? .none : .resolve
        case .running(let sessionID, let segmentStart):
            return evaluateRunning(
                sessionID: sessionID,
                segmentStart: segmentStart,
                blocks: blocks,
                openGuard: openGuard,
                now: now
            )
        }
    }

    private static func evaluateRunning(
        sessionID: UUID,
        segmentStart: Date,
        blocks: [TimetableGuardBlock],
        openGuard: TimetableOpenGuard?,
        now: Date
    ) -> TimetableGuardEffect {
        let overlapping = overlappingEligibleBlock(blocks: blocks, now: now)

        if let openGuard {
            if openGuard.sessionID != sessionID {
                return .invalidate
            }
            guard let overlapping, overlapping.id == openGuard.blockID else {
                return .invalidate
            }
            if now >= openGuard.protectionBoundary {
                return .pauseAt(openGuard.protectionBoundary)
            }
            return .none
        }

        guard let overlapping else { return .none }
        let boundary = protectionBoundary(blockStart: overlapping.startsAt, segmentStart: segmentStart)
        if now >= boundary {
            return .pauseAt(boundary)
        }
        return .arm(
            blockID: overlapping.id,
            notifiedAt: now,
            protectionBoundary: boundary
        )
    }
}
