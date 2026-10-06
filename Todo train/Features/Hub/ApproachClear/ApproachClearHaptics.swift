//
//  ApproachClearHaptics.swift
//  Todo train
//
//  Plays clearance cues in order. A later cue waits; it does not cut the hit.
//

import CoreHaptics
import UIKit

@MainActor
final class ApproachClearHaptics {
    private var engine: CHHapticEngine?
    private var queue: [Pulse] = []
    private var playing = false
    private var token = 0
    private let supportsCore = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)

    func prepare() {
        soft.prepare()
        light.prepare()
        medium.prepare()
        heavy.prepare()
        rigid.prepare()
        guard supportsCore, engine == nil else { return }
        engine = try? CHHapticEngine()
        engine?.isAutoShutdownEnabled = true
        try? engine?.start()
    }

    func play(_ cues: [ApproachClearCue]) {
        guard !cues.isEmpty else { return }
        queue.append(contentsOf: cues.map(Pulse.init))
        pump()
    }

    func stop() {
        token += 1
        queue.removeAll()
        playing = false
        engine?.stop(completionHandler: nil)
        engine = nil
    }

    private func pump() {
        guard !playing, !queue.isEmpty else { return }
        playing = true
        let pulse = queue.removeFirst()
        let current = token
        if supportsCore, let events = pulse.events {
            do {
                if engine == nil { prepare() }
                if let engine {
                    try engine.start()
                    let pattern = try CHHapticPattern(events: events, parameters: [])
                    let player = try engine.makePlayer(with: pattern)
                    try player.start(atTime: CHHapticTimeImmediate)
                } else {
                    fallback(pulse)
                }
            } catch {
                fallback(pulse)
            }
        } else {
            fallback(pulse)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(pulse.waitMs))
            guard current == self.token else { return }
            self.playing = false
            self.pump()
        }
    }

    private func fallback(_ pulse: Pulse) {
        switch pulse.fallback {
        case .soft: soft.impactOccurred(intensity: pulse.fallbackIntensity)
        case .light: light.impactOccurred(intensity: pulse.fallbackIntensity)
        case .medium: medium.impactOccurred(intensity: pulse.fallbackIntensity)
        case .heavy: heavy.impactOccurred(intensity: pulse.fallbackIntensity)
        case .rigid: rigid.impactOccurred(intensity: pulse.fallbackIntensity)
        }
    }
}

nonisolated private struct Pulse {
    var events: [CHHapticEvent]?
    var waitMs: Int
    var fallback: Fallback
    var fallbackIntensity: CGFloat

    enum Fallback {
        case soft, light, medium, heavy, rigid
    }

    init(_ cue: ApproachClearCue) {
        switch cue {
        case .approachPulse:
            self = Pulse(
                hits: [(0, 0.22, 0.25)],
                waitMs: 36,
                fallback: .soft,
                fallbackIntensity: 0.35
            )
        case .perfect(let tier):
            let weight = 0.74 + 0.08 * Float(tier)
            let hits: [(TimeInterval, Float, Float)] = tier >= 2
                ? [(0, weight, 0.55), (0.07, weight, 0.7), (0.15, min(1, weight + 0.08), 0.85)]
                : [(0, weight, 0.5), (0.08, min(1, weight + 0.06), 0.75)]
            self = Pulse(hits: hits, waitMs: tier >= 2 ? 230 : 170, fallback: .heavy, fallbackIntensity: 0.7 + 0.1 * CGFloat(tier))
        case .good(let tier):
            let weight = 0.32 + 0.07 * Float(tier)
            let hits: [(TimeInterval, Float, Float)] = tier >= 3
                ? [(0, weight, 0.35), (0.05, weight, 0.45), (0.11, weight + 0.05, 0.4)]
                : [(0, weight, 0.3), (0.06, weight + 0.04, 0.4)]
            self = Pulse(hits: hits, waitMs: 140, fallback: tier >= 2 ? .medium : .light, fallbackIntensity: 0.45 + 0.1 * CGFloat(tier))
        case .miss:
            self = Pulse(
                hits: [(0, 0.84, 0.9), (0.07, 0.8, 0.85), (0.15, 0.88, 1)],
                waitMs: 230,
                fallback: .rigid,
                fallbackIntensity: 0.95
            )
        case .pass:
            self = Pulse(
                hits: [(0, 0.48, 0.4), (0.06, 0.42, 0.35)],
                waitMs: 140,
                fallback: .light,
                fallbackIntensity: 0.6
            )
        case .jam:
            self = Pulse(
                hits: [(0, 0.78, 0.95), (0.07, 0.78, 0.95)],
                waitMs: 160,
                fallback: .rigid,
                fallbackIntensity: 0.9
            )
        case .heatUp:
            self = Pulse(
                hits: [(0, 0.4, 0.3), (0.05, 0.5, 0.45), (0.11, 0.58, 0.55)],
                waitMs: 160,
                fallback: .medium,
                fallbackIntensity: 0.7
            )
        case .easeDown:
            self = Pulse(
                hits: [(0, 0.34, 0.15), (0.08, 0.28, 0.1), (0.16, 0.22, 0.08)],
                waitMs: 220,
                fallback: .soft,
                fallbackIntensity: 0.45
            )
        case .interlockStep:
            self = Pulse(hits: [(0, 0.26, 0.35)], waitMs: 40, fallback: .soft, fallbackIntensity: 0.4)
        case .interlockDone:
            self = Pulse(
                hits: [(0, 0.3, 0.4), (0.04, 0.42, 0.5)],
                waitMs: 90,
                fallback: .light,
                fallbackIntensity: 0.55
            )
        case .interlockReject:
            self = Pulse(hits: [(0, 0.3, 0.2)], waitMs: 70, fallback: .soft, fallbackIntensity: 0.4)
        case .barrier:
            self = Pulse(
                hits: [(0, 0.36, 0.55), (0.04, 0.3, 0.4)],
                waitMs: 80,
                fallback: .light,
                fallbackIntensity: 0.5
            )
        case .sessionFull:
            self = Pulse(
                hits: [(0, 0.4, 0.3), (0.09, 0.48, 0.35)],
                waitMs: 180,
                fallback: .medium,
                fallbackIntensity: 0.55
            )
        }
    }

    init(
        hits: [(TimeInterval, Float, Float)],
        waitMs: Int,
        fallback: Fallback,
        fallbackIntensity: CGFloat
    ) {
        events = hits.map { time, intensity, sharpness in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                ],
                relativeTime: time
            )
        }
        self.waitMs = waitMs
        self.fallback = fallback
        self.fallbackIntensity = min(1, fallbackIntensity)
    }
}
