import Foundation

/// Thresholds for 停車中の入力. The share is not stored.
public enum PauseInputThresholds {
    /// One look at the time since the last input.
    public static let sampleInterval: TimeInterval = 30
    /// The 30 second bucket counts as input when the last input is inside this window.
    public static let activeWithin: TimeInterval = 60
    /// A gap longer than this was not observed. It is not added.
    public static let maxSampleGap: TimeInterval = 60
    public static let promptAfter: TimeInterval = 5 * 60
    public static let hubGaugeAfter: TimeInterval = 15 * 60

    /// `active / sampled >= 4/5`. The ratio itself is not a stored value.
    public static func meetsInputShare(sampled: TimeInterval, active: TimeInterval) -> Bool {
        guard sampled > 0, active >= 0 else { return false }
        let capped = min(active, sampled)
        return capped * 5 >= sampled * 4
    }
}

/// Answer stored on the pause. `none` means the question was shown and not answered.
public enum PausePromptAnswer: Sendable, Equatable {
    case resume
    case keepPaused
    case none
    case unknown(String)

    public static let knownRawValues = ["resume", "keepPaused", "none"]

    public var rawValue: String {
        switch self {
        case .resume: "resume"
        case .keepPaused: "keepPaused"
        case .none: "none"
        case .unknown(let value): value
        }
    }

    public var isKnown: Bool {
        if case .unknown = self { return false }
        return true
    }

    public init(rawValue: String) {
        switch rawValue {
        case "resume": self = .resume
        case "keepPaused": self = .keepPaused
        case "none": self = .none
        default: self = .unknown(rawValue)
        }
    }
}

extension PausePromptAnswer: Codable {
    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Words for the pause question. Eight literals. The gauge is a clock, not the input share.
public enum PauseInputCopy {
    public static let questionBare = "停車のまま？"

    public static func question(title: String?) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return questionBare }
        return "『\(trimmed)』、停車のまま？"
    }

    public static let resume = "再乗車"
    public static let keepPaused = "停車のまま"
    public static let resumeHint = "停車を終えて、ここから走行を測ります。"
    public static let keepPausedHint = "この停車を続けます。"
    public static let questionHint = "停車が続いているときの問いです。"

    /// Hub clock once the pause has lasted 15 minutes. Nil before that.
    public static func gauge(elapsed: TimeInterval) -> String? {
        guard elapsed >= PauseInputThresholds.hubGaugeAfter else { return nil }
        let whole = Int(elapsed.rounded(.down))
        return "停車 \(ClockTime.mmss(whole))"
    }
}

public struct PauseInputReport: Equatable, Sendable {
    public var sessionId: UUID
    public var pauseId: UUID
    public var macSampledSeconds: Double
    public var macActiveSeconds: Double
    public var promptedAt: Int?
    public var promptAnswer: PausePromptAnswer?

    public init(
        sessionId: UUID,
        pauseId: UUID,
        macSampledSeconds: Double,
        macActiveSeconds: Double,
        promptedAt: Int?,
        promptAnswer: PausePromptAnswer?
    ) {
        self.sessionId = sessionId
        self.pauseId = pauseId
        self.macSampledSeconds = macSampledSeconds
        self.macActiveSeconds = macActiveSeconds
        self.promptedAt = promptedAt
        self.promptAnswer = promptAnswer
    }

    /// Nil when the payload cannot be stored. Unknown answers are refused.
    public static func make(
        sessionId: UUID?,
        pauseId: UUID?,
        macSampledSeconds: Double?,
        macActiveSeconds: Double?,
        promptedAt: Int?,
        promptAnswer: PausePromptAnswer?
    ) -> PauseInputReport? {
        guard let sessionId, let pauseId else { return nil }
        guard let sampled = macSampledSeconds, let active = macActiveSeconds else { return nil }
        guard sampled >= 0, active >= 0, active <= sampled else { return nil }
        if let promptedAt, promptedAt < 0 { return nil }
        if let promptAnswer, !promptAnswer.isKnown { return nil }
        return PauseInputReport(
            sessionId: sessionId,
            pauseId: pauseId,
            macSampledSeconds: sampled,
            macActiveSeconds: active,
            promptedAt: promptedAt,
            promptAnswer: promptAnswer
        )
    }
}

public enum PauseInputSampling {
    public struct Bucket: Equatable, Sendable {
        public var sampled: TimeInterval
        public var active: TimeInterval
        public var lastUptime: TimeInterval?

        public init(sampled: TimeInterval, active: TimeInterval, lastUptime: TimeInterval?) {
            self.sampled = sampled
            self.active = active
            self.lastUptime = lastUptime
        }
    }

    /// Counts awake uptime only. `counting` is false while asleep, locked, or disconnected.
    /// A bucket shorter than 30 seconds waits. A gap longer than 60 seconds is dropped.
    public static func advance(
        sampled: TimeInterval,
        active: TimeInterval,
        lastUptime: TimeInterval?,
        uptime: TimeInterval,
        secondsSinceLastInput: TimeInterval,
        counting: Bool
    ) -> Bucket {
        let cappedActive = min(active, sampled)
        guard counting else {
            return Bucket(sampled: sampled, active: cappedActive, lastUptime: uptime)
        }
        guard let lastUptime else {
            return Bucket(sampled: sampled, active: cappedActive, lastUptime: uptime)
        }
        let delta = uptime - lastUptime
        if delta < 0 || delta > PauseInputThresholds.maxSampleGap {
            return Bucket(sampled: sampled, active: cappedActive, lastUptime: uptime)
        }
        guard delta >= PauseInputThresholds.sampleInterval else {
            return Bucket(sampled: sampled, active: cappedActive, lastUptime: lastUptime)
        }
        let nextSampled = sampled + delta
        var nextActive = cappedActive
        if secondsSinceLastInput < PauseInputThresholds.activeWithin {
            nextActive += delta
        }
        if nextActive > nextSampled { nextActive = nextSampled }
        return Bucket(sampled: nextSampled, active: nextActive, lastUptime: uptime)
    }
}

public struct PauseInputWatch: Equatable, Sendable {
    public var pauseId: UUID
    public var sessionId: UUID
    public var sampled: TimeInterval
    public var active: TimeInterval
    public var lastUptime: TimeInterval?
    public var promptedAt: Int?
    public var answer: PausePromptAnswer?
    public var chimePlayed: Bool
    public var pausedAt: Int?
    public var heldBy: PauseHeldBy?
    public var title: String?

    public init(pauseId: UUID, sessionId: UUID) {
        self.pauseId = pauseId
        self.sessionId = sessionId
        sampled = 0
        active = 0
        lastUptime = nil
        promptedAt = nil
        answer = nil
        chimePlayed = false
        pausedAt = nil
        heldBy = nil
        title = nil
    }
}

public struct PauseInputObservation: Equatable, Sendable {
    public var uptime: TimeInterval
    public var unixNow: Int
    public var secondsSinceLastInput: TimeInterval
    /// False during sleep, screen lock, or a dropped relay.
    public var counting: Bool
    public var phase: WirePhase
    public var sessionId: UUID?
    public var pauseId: UUID?
    public var pausedAt: Int?
    public var heldBy: PauseHeldBy?
    public var title: String?

    public init(
        uptime: TimeInterval,
        unixNow: Int,
        secondsSinceLastInput: TimeInterval,
        counting: Bool,
        phase: WirePhase,
        sessionId: UUID? = nil,
        pauseId: UUID? = nil,
        pausedAt: Int? = nil,
        heldBy: PauseHeldBy? = nil,
        title: String? = nil
    ) {
        self.uptime = uptime
        self.unixNow = unixNow
        self.secondsSinceLastInput = secondsSinceLastInput
        self.counting = counting
        self.phase = phase
        self.sessionId = sessionId
        self.pauseId = pauseId
        self.pausedAt = pausedAt
        self.heldBy = heldBy
        self.title = title
    }
}

public struct PauseInputStep: Equatable, Sendable {
    public var reports: [PauseInputReport]
    public var chime: Bool
    public var prompt: String?

    public init(reports: [PauseInputReport], chime: Bool, prompt: String?) {
        self.reports = reports
        self.chime = chime
        self.prompt = prompt
    }
}

/// Mac-side ledger. Samples only the latest paused ride, and only while nothing is running.
public struct PauseInputEngine: Equatable, Sendable {
    public var current: PauseInputWatch?
    public var background: [PauseInputWatch]

    public init() {
        current = nil
        background = []
    }

    public var promptLine: String? {
        guard let current, current.promptedAt != nil, current.answer == nil else { return nil }
        return PauseInputCopy.question(title: current.title)
    }

    public mutating func step(_ observation: PauseInputObservation) -> PauseInputStep {
        var reports: [PauseInputReport] = []
        closeFinishedRides(observation, reports: &reports)

        if observation.phase == .paused, let pauseId = observation.pauseId, let sessionId = observation.sessionId {
            adopt(pauseId: pauseId, sessionId: sessionId, observation: observation)
        } else if observation.phase == .running || observation.phase == .overtime {
            parkIfAnotherRide(observation)
        }

        var chime = false
        if shouldOpenPrompt(observation), var watch = current {
            watch.promptedAt = observation.unixNow
            if !watch.chimePlayed {
                chime = true
                watch.chimePlayed = true
            }
            current = watch
        }

        return PauseInputStep(reports: reports, chime: chime, prompt: promptLine)
    }

    /// Records the answer and returns the report to send now. The pause stays open for 停車のまま.
    public mutating func answer(_ choice: PausePromptAnswer) -> PauseInputReport? {
        guard choice == .resume || choice == .keepPaused else { return nil }
        guard var watch = current, watch.promptedAt != nil, watch.answer == nil else { return nil }
        watch.answer = choice
        current = watch
        return report(for: watch)
    }

    private func shouldOpenPrompt(_ observation: PauseInputObservation) -> Bool {
        guard observation.phase == .paused, let watch = current, watch.pauseId == observation.pauseId else {
            return false
        }
        guard watch.answer == nil, watch.promptedAt == nil, watch.heldBy == .user else { return false }
        guard let pausedAt = watch.pausedAt else { return false }
        let age = TimeInterval(observation.unixNow - pausedAt)
        guard age >= PauseInputThresholds.promptAfter else { return false }
        return PauseInputThresholds.meetsInputShare(sampled: watch.sampled, active: watch.active)
    }

    private mutating func adopt(pauseId: UUID, sessionId: UUID, observation: PauseInputObservation) {
        if current?.pauseId != pauseId {
            if let watch = current {
                background.removeAll { $0.pauseId == watch.pauseId }
                background.append(watch)
            }
            if let index = background.firstIndex(where: { $0.pauseId == pauseId }) {
                current = background.remove(at: index)
                current?.lastUptime = nil
            } else {
                current = PauseInputWatch(pauseId: pauseId, sessionId: sessionId)
            }
        }
        current?.sessionId = sessionId
        current?.pausedAt = observation.pausedAt
        current?.heldBy = observation.heldBy
        current?.title = observation.title
        guard var watch = current else { return }
        let bucket = PauseInputSampling.advance(
            sampled: watch.sampled,
            active: watch.active,
            lastUptime: watch.lastUptime,
            uptime: observation.uptime,
            secondsSinceLastInput: observation.secondsSinceLastInput,
            counting: observation.counting
        )
        watch.sampled = bucket.sampled
        watch.active = bucket.active
        watch.lastUptime = bucket.lastUptime
        current = watch
    }

    private mutating func parkIfAnotherRide(_ observation: PauseInputObservation) {
        guard let watch = current, watch.sessionId != observation.sessionId else { return }
        background.removeAll { $0.pauseId == watch.pauseId }
        var parked = watch
        parked.lastUptime = nil
        background.append(parked)
        current = nil
    }

    private mutating func closeFinishedRides(
        _ observation: PauseInputObservation,
        reports: inout [PauseInputReport]
    ) {
        if observation.phase == .running || observation.phase == .overtime {
            if let watch = current, watch.sessionId == observation.sessionId {
                reports.append(report(for: watch))
                current = nil
            }
            let ended = background.filter { $0.sessionId == observation.sessionId }
            if !ended.isEmpty {
                reports.append(contentsOf: ended.map(report(for:)))
                background.removeAll { $0.sessionId == observation.sessionId }
            }
        }
        if observation.phase == .idle, let watch = current {
            reports.append(report(for: watch))
            current = nil
        }
    }

    private func report(for watch: PauseInputWatch) -> PauseInputReport {
        var answer = watch.answer
        if watch.promptedAt != nil, answer == nil {
            answer = PausePromptAnswer.none
        }
        if watch.promptedAt == nil {
            answer = nil
        }
        let active = min(watch.active, watch.sampled)
        return PauseInputReport(
            sessionId: watch.sessionId,
            pauseId: watch.pauseId,
            macSampledSeconds: watch.sampled,
            macActiveSeconds: active,
            promptedAt: watch.promptedAt,
            promptAnswer: answer
        )
    }
}
