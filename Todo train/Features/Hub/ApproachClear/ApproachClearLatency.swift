//
//  ApproachClearLatency.swift
//  Todo train
//
//  The panel subtracts a learned input latency once, before touchDown.
//  The engine still judges the time it is given. Window widths stay put.
//  Until enough presses agree, the latency is zero.
//

import Foundation

nonisolated enum ApproachClearLatency {
    static let storageKey = "approachClear.inputLatencyMs"
    static let samplesKey = "approachClear.inputLatencySamples"

    /// Presses farther than this from the frame on screen are not a latency sample.
    static let admitMs = 80.0
    static let minSamples = 12
    static let maxSamples = 32
    /// Play-time sampling must not walk the compensation past this.
    static let limitMs = 40.0
    /// Trimmed spread above this means the presses have not settled.
    static let stableStdMs = 25.0

    /// Positive latency moves the touch into the past, which cancels a late arrival.
    static func judgementMs(touchMs: Double, inputLatencyMs: Double) -> Double {
        touchMs - inputLatencyMs
    }

    /// Same unit the needle uses while an approach is on screen.
    static func unit(timeMs: Double, approachStart: Double, approachMs: Double) -> Double {
        guard approachMs > 0 else { return 0 }
        let u = (timeMs - approachStart) / approachMs
        return min(1, max(0, u))
    }

    /// Positive when the press unit is later than the needle that was drawn.
    static func deltaMs(pressU: Double, visibleNeedleU: Double, approachMs: Double) -> Double {
        (pressU - visibleNeedleU) * approachMs
    }
}

nonisolated struct ApproachClearLatencyEstimate: Equatable, Sendable {
    var latencyMs = 0.0
    var samples: [Double] = []

    /// `rawDeltaMs` is the uncompensated `(touch − frame) ` gap. Compensation
    /// already applied to a press must not be folded back into this.
    mutating func record(rawDeltaMs: Double) {
        guard abs(rawDeltaMs) <= ApproachClearLatency.admitMs else { return }
        samples.append(rawDeltaMs)
        if samples.count > ApproachClearLatency.maxSamples {
            samples.removeFirst(samples.count - ApproachClearLatency.maxSamples)
        }
        guard let next = Self.stableLatency(samples) else { return }
        latencyMs = min(ApproachClearLatency.limitMs, max(-ApproachClearLatency.limitMs, next))
    }

    static func stableLatency(_ samples: [Double]) -> Double? {
        guard samples.count >= ApproachClearLatency.minSamples else { return nil }
        let sorted = samples.sorted()
        let drop = max(1, sorted.count / 5)
        let body = Array(sorted.dropFirst(drop).dropLast(drop))
        guard body.count >= 3 else { return nil }
        let mean = body.reduce(0, +) / Double(body.count)
        let variance = body.reduce(0.0) { partial, sample in
            let delta = sample - mean
            return partial + delta * delta
        } / Double(body.count)
        guard variance.squareRoot() <= ApproachClearLatency.stableStdMs else { return nil }
        return mean
    }
}

nonisolated enum ApproachClearLatencyStore {
    static func load(_ defaults: UserDefaults = .standard) -> ApproachClearLatencyEstimate {
        var estimate = ApproachClearLatencyEstimate()
        let storedLatency = defaults.double(forKey: ApproachClearLatency.storageKey)
        estimate.latencyMs = min(
            ApproachClearLatency.limitMs,
            max(-ApproachClearLatency.limitMs, storedLatency)
        )
        if let stored = defaults.array(forKey: ApproachClearLatency.samplesKey) {
            estimate.samples = stored.compactMap { ($0 as? NSNumber)?.doubleValue }
        }
        return estimate
    }

    static func save(_ estimate: ApproachClearLatencyEstimate, _ defaults: UserDefaults = .standard) {
        defaults.set(estimate.latencyMs, forKey: ApproachClearLatency.storageKey)
        defaults.set(estimate.samples, forKey: ApproachClearLatency.samplesKey)
    }
}
