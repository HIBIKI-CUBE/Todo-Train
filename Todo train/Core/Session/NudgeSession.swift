//
//  NudgeSession.swift
//  Todo train
//
//  Pure nudge identity and answer rules. SessionManager applies them.
//

import Foundation
import TodoTrainSync

enum NudgeSession {
    struct Interval: Equatable, Sendable {
        var start: Date
        var end: Date
    }

    struct Stamp: Equatable, Sendable {
        var answer: CheckInAnswerKind
        var addSeconds: Int?
    }

    enum AnswerDecision: Equatable, Sendable {
        case apply(at: Date)
        case duplicate
        case stale
    }

    /// Stable id for one stage of one ride. No extra column.
    static func id(sessionID: UUID, stage: NudgeStage) -> UUID {
        var hash: UInt64 = 14_695_981_039_346_656_037
        let text = Data("\(sessionID.uuidString.lowercased())|\(stage.rawValue)".utf8)
        for byte in text {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        var mixed = hash
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<16 {
            bytes[index] = UInt8(truncatingIfNeeded: mixed)
            mixed = mixed &* 1_099_511_628_211 &+ UInt64(index) &+ hash
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    static func idString(sessionID: UUID, stage: NudgeStage) -> String {
        id(sessionID: sessionID, stage: stage).uuidString.lowercased()
    }

    /// Wall time when active seconds hit `offset`. Later pauses stay out of the sample.
    static func firedAt(startedAt: Date, offset: TimeInterval, exclusions: [Interval]) -> Date {
        let blocks = exclusions
            .map { Interval(start: $0.start, end: max($0.start, $0.end)) }
            .sorted { $0.start < $1.start }
        var wall = startedAt
        var remaining = max(0, offset)
        for block in blocks {
            if block.end <= wall { continue }
            let gap = block.start.timeIntervalSince(wall)
            if gap >= remaining {
                return wall.addingTimeInterval(remaining)
            }
            if gap > 0 {
                remaining -= gap
                wall = block.start
            }
            wall = max(wall, block.end)
        }
        return wall.addingTimeInterval(remaining)
    }

    /// The open question. An unanswered check-in stays until a ringing stage replaces it.
    static func visibleStage(fired: [NudgeStage], answered: Set<String>, sessionID: UUID) -> NudgeStage? {
        let ordered = fired.sorted { $0.number < $1.number }
        let ringing = ordered.filter { $0.number >= 3 }
        if ordered.contains(.checkIn), ringing.isEmpty {
            let checkInID = idString(sessionID: sessionID, stage: .checkIn)
            if !answered.contains(checkInID) { return .checkIn }
        }
        if let latest = ringing.last {
            let latestID = idString(sessionID: sessionID, stage: latest)
            if !answered.contains(latestID) { return latest }
        }
        return nil
    }

    /// Stage a command must name. Stays on the last answer so an identical retry is not stale.
    static func commandStage(fired: [NudgeStage], answered: Set<String>, sessionID: UUID) -> NudgeStage? {
        if let visible = visibleStage(fired: fired, answered: answered, sessionID: sessionID) {
            return visible
        }
        return fired
            .filter { $0 == .checkIn || $0.number >= 3 }
            .max { $0.number < $1.number }
    }

    static func decide(
        existing: Stamp?,
        choice: CheckInAnswerKind,
        addSeconds: Int?,
        firedAt: Date,
        commandAt: Date,
        now: Date
    ) -> AnswerDecision {
        if let existing {
            let sameChoice = existing.answer == choice
            let sameExtend = choice != .willExtend || existing.addSeconds == addSeconds
            return (sameChoice && sameExtend) ? .duplicate : .stale
        }
        let at = min(max(commandAt, firedAt), now)
        return .apply(at: at)
    }
}

extension CheckInAnswerKind {
    init?(_ choice: NudgeChoice) {
        switch choice {
        case .stillOnIt: self = .stillOnIt
        case .willExtend: self = .willExtend
        case .alreadyDone: self = .alreadyDone
        case .paused: self = .paused
        case .unknown: return nil
        }
    }
}
