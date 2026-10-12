import Foundation

extension NudgeStageWire {
    /// Ride stage number. Gaps stay nil until #108.
    public var rideStageNumber: Int? {
        switch self {
        case .checkIn: 1
        case .approach: 2
        case .estimate: 3
        case .handoff1: 4
        case .handoff2: 5
        case .handoff3: 6
        case .gap1, .gap2, .unknown: nil
        }
    }

    /// Stage 1 and stages 3...6 ask the same question. Stage 2 only colors the instruments.
    public var isRideQuestion: Bool {
        guard let rideStageNumber else { return false }
        return rideStageNumber == 1 || rideStageNumber >= 3
    }

    /// Stages that can ring. Stage 1 and approach do not.
    public var isRideRing: Bool {
        guard let rideStageNumber else { return false }
        return rideStageNumber >= 3
    }
}

/// What the Mac PiP shows for the nudge on a snap. Old snaps with no `nudge` stay on the cabin prompt.
public struct MacNudgeChrome: Equatable, Sendable {
    public var prompt: String?
    public var showsChoices: Bool
    public var holdLamp: Bool
    public var forcesApproach: Bool
    public var instrumentCaption: String?

    public static let empty = MacNudgeChrome(
        prompt: nil,
        showsChoices: false,
        holdLamp: false,
        forcesApproach: false,
        instrumentCaption: nil
    )

    public init(
        prompt: String?,
        showsChoices: Bool,
        holdLamp: Bool,
        forcesApproach: Bool,
        instrumentCaption: String?
    ) {
        self.prompt = prompt
        self.showsChoices = showsChoices
        self.holdLamp = holdLamp
        self.forcesApproach = forcesApproach
        self.instrumentCaption = instrumentCaption
    }

    public static func make(
        snap: SnapPlaintext?,
        now: Int,
        cabinEnabled: Bool,
        sendingExtendMinutes: Int?,
        winnerLine: String?
    ) -> MacNudgeChrome {
        guard cabinEnabled, let snap else { return .empty }
        let asking = snap.nudge?.stage.isRideQuestion == true
            && (snap.phase == .running || snap.phase == .overtime)
        let prompt = asking ? CabinCopy.question(title: snap.title ?? "") : nil
        let ownTurn = snap.nudge?.ringSurface == .mac
        let holdLamp = asking && (snap.nudge?.stage == .checkIn || ownTurn)
        let caption: String?
        if let sendingExtendMinutes {
            caption = CabinCopy.extendSending(minutes: sendingExtendMinutes)
        } else {
            caption = winnerLine
        }
        return MacNudgeChrome(
            prompt: prompt,
            showsChoices: asking,
            holdLamp: holdLamp,
            forcesApproach: isApproachWindow(snap: snap, now: now, asking: asking),
            instrumentCaption: caption
        )
    }

    /// Stage 2 colors the instruments. An open question keeps its own row.
    static func isApproachWindow(snap: SnapPlaintext, now: Int, asking: Bool) -> Bool {
        guard !asking, snap.phase == .running else { return false }
        guard let estimated = snap.estimatedSeconds, estimated > 0,
              let remaining = snap.remainingSeconds(at: now), remaining > 0 else { return false }
        let window = NudgePlanner.approachRemaining(estimatedSeconds: estimated)
        return TimeInterval(remaining) <= window
    }
}

/// One chime the Mac may play. Passed stages are recorded without sound.
public struct MacNudgeRingCue: Equatable, Sendable {
    public var key: String
    public var sound: Bool

    public init(key: String, sound: Bool) {
        self.key = key
        self.sound = sound
    }
}

/// Mac rings only its own turns. iPhone and Watch turns are skipped, so the two never chime together.
public enum MacNudgeRinging {
    /// A stage older than this, on the snap we just received, already passed. Do not replay it.
    public static let freshSeconds = 2

    public static func cues(
        sessionID: UUID?,
        nudge: WireNudge?,
        plan: [WireNudgePlanItem]?,
        now: Int,
        seen: Set<String>
    ) -> (fresh: [MacNudgeRingCue], seen: Set<String>) {
        var seen = seen
        var fresh: [MacNudgeRingCue] = []
        for candidate in candidates(sessionID: sessionID, nudge: nudge, plan: plan) {
            guard !seen.contains(candidate.key) else { continue }
            if candidate.fireAt > now { continue }
            let sound = now - candidate.fireAt <= freshSeconds
            seen.insert(candidate.key)
            fresh.append(MacNudgeRingCue(key: candidate.key, sound: sound))
        }
        return (fresh, seen)
    }

    /// Tucked PiP keeps the edge lamp and does not chime.
    public static func audible(_ cues: [MacNudgeRingCue], tucked: Bool) -> Bool {
        !tucked && cues.contains { $0.sound }
    }

    private struct Candidate {
        var key: String
        var fireAt: Int
    }

    private static func candidates(
        sessionID: UUID?,
        nudge: WireNudge?,
        plan: [WireNudgePlanItem]?
    ) -> [Candidate] {
        var rows: [Candidate] = []
        if let nudge, nudge.stage.isRideRing, nudge.ringSurface == .mac {
            rows.append(Candidate(key: key(sessionID: sessionID, stage: nudge.stage), fireAt: nudge.firedAt))
        }
        for item in plan ?? [] where item.stage.isRideRing && item.surface == .mac && item.rings {
            let key = key(sessionID: sessionID, stage: item.stage)
            if rows.contains(where: { $0.key == key }) { continue }
            rows.append(Candidate(key: key, fireAt: item.fireAt))
        }
        return rows
    }

    private static func key(sessionID: UUID?, stage: NudgeStageWire) -> String {
        let ride = sessionID?.uuidString.lowercased() ?? ""
        return "\(ride)|\(stage.rawValue)"
    }
}

/// What to show when Mac's answer lost. The snap already holds the winner.
public enum MacNudgeReceipt {
    public static func winnerLine(snap: SnapPlaintext, estimateBefore: Int?) -> String {
        if snap.phase == .paused {
            return CabinCopy.actionRecorded(CabinCopy.pause, on: CabinCopy.iphone)
        }
        if let before = estimateBefore, let estimate = snap.estimatedSeconds, estimate - before >= 60 {
            return CabinCopy.extendRecorded(minutes: (estimate - before) / 60, on: CabinCopy.iphone)
        }
        switch snap.phase {
        case .idle, .unknown:
            return CabinCopy.actionRecorded(CabinCopy.arrived, on: CabinCopy.iphone)
        case .running, .paused, .overtime:
            return CabinCopy.actionRecorded(CabinCopy.still, on: CabinCopy.iphone)
        }
    }
}
