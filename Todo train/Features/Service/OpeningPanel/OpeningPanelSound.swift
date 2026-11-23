//
//  OpeningPanelSound.swift
//  Todo train
//
//  盤の音はファイルを置かず、その場で合成する。
//  包絡は仕様に秒数がないので、参照モックの減衰に合わせる。
//

import AVFoundation
import CoreHaptics
import Foundation

enum OpeningPanelFilter: Equatable {
    case bandpass(Float)
    case lowpass(Float)

    func apply(to band: AVAudioUnitEQFilterParameters) {
        switch self {
        case .bandpass(let hz):
            band.filterType = .bandPass
            band.frequency = hz
            band.bandwidth = 1.4
            band.bypass = false
        case .lowpass(let hz):
            band.filterType = .lowPass
            band.frequency = hz
            band.bandwidth = 1
            band.bypass = false
        }
    }
}

struct OpeningPanelNoiseRecipe: Equatable {
    var duration: TimeInterval
    var decay: TimeInterval
    var amplitude: Float
    var filter: OpeningPanelFilter
}

struct OpeningPanelToneRecipe: Equatable {
    var startFrequency: Float
    var endFrequency: Float
    var glide: TimeInterval
    var duration: TimeInterval
    var peakGain: Float
    var fade: TimeInterval
}

enum OpeningPanelSoundRecipe {
    static let sampleRate: Double = 44_100
    /// 25ms の雑音、3200Hz 帯域。
    static let light = OpeningPanelNoiseRecipe(
        duration: 0.025,
        decay: 0.004,
        amplitude: 1,
        filter: .bandpass(3_200)
    )
    /// 180ms の雑音を 400Hz 以下に絞る。
    static let heavy = OpeningPanelNoiseRecipe(
        duration: 0.180,
        decay: 0.040,
        amplitude: 0.6,
        filter: .lowpass(400)
    )
    /// 90Hz から 55Hz へ。180ms のうち 140ms で消える。
    static let heavyBass = OpeningPanelToneRecipe(
        startFrequency: 90,
        endFrequency: 55,
        glide: 0.050,
        duration: 0.180,
        peakGain: 0.7,
        fade: 0.140
    )
    /// 140Hz、30ms。
    static let dull = OpeningPanelToneRecipe(
        startFrequency: 140,
        endFrequency: 140,
        glide: 0,
        duration: 0.030,
        peakGain: 0.25,
        fade: 0.030
    )
}

struct OpeningPanelHapticSpec: Equatable {
    var duration: TimeInterval
    var intensity: Float
    var sharpness: Float
    var includesTransient: Bool
    var includesContinuous: Bool

    static let operation = OpeningPanelHapticSpec(
        duration: 0.010,
        intensity: 0.55,
        sharpness: 0.75,
        includesTransient: true,
        includesContinuous: true
    )
    static let divider = OpeningPanelHapticSpec(
        duration: 0.008,
        intensity: 0.35,
        sharpness: 0.40,
        includesTransient: true,
        includesContinuous: true
    )
    static let depart = OpeningPanelHapticSpec(
        duration: 0.030,
        intensity: 1,
        sharpness: 0.30,
        includesTransient: true,
        includesContinuous: true
    )

    static func spec(for haptic: OpeningPanelHaptic) -> OpeningPanelHapticSpec {
        switch haptic {
        case .operation: .operation
        case .divider: .divider
        case .depart: .depart
        }
    }
}

enum OpeningPanelSynthesis {
    static func noise(
        _ recipe: OpeningPanelNoiseRecipe,
        sampleRate: Double = OpeningPanelSoundRecipe.sampleRate
    ) -> [Float] {
        let frames = frameCount(recipe.duration, sampleRate: sampleRate)
        var samples = [Float](repeating: 0, count: frames)
        guard recipe.decay > 0 else { return samples }
        for index in 0..<frames {
            let time = Double(index) / sampleRate
            let envelope = exp(-time / recipe.decay)
            let value = Float.random(in: -1...1) * recipe.amplitude * Float(envelope)
            samples[index] = min(1, max(-1, value))
        }
        return samples
    }

    static func tone(
        _ recipe: OpeningPanelToneRecipe,
        sampleRate: Double = OpeningPanelSoundRecipe.sampleRate
    ) -> [Float] {
        let frames = frameCount(recipe.duration, sampleRate: sampleRate)
        var samples = [Float](repeating: 0, count: frames)
        var phase = 0.0
        for index in 0..<frames {
            let time = Double(index) / sampleRate
            let frequency: Double
            if recipe.glide > 0, time < recipe.glide {
                let unit = time / recipe.glide
                frequency = Double(recipe.startFrequency)
                    + (Double(recipe.endFrequency) - Double(recipe.startFrequency)) * unit
            } else {
                frequency = Double(recipe.endFrequency)
            }
            phase += frequency / sampleRate
            let gain: Float
            if recipe.fade <= 0 || time >= recipe.fade {
                gain = 0
            } else {
                gain = recipe.peakGain * Float(1 - time / recipe.fade)
            }
            let wave = Float(sin(2 * Double.pi * phase))
            samples[index] = wave * gain
        }
        return samples
    }

    static func buffer(_ samples: [Float], sampleRate: Double = OpeningPanelSoundRecipe.sampleRate) -> AVAudioPCMBuffer? {
        guard
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        for (index, sample) in samples.enumerated() {
            channel[index] = sample
        }
        return buffer
    }

    static func frameCount(_ duration: TimeInterval, sampleRate: Double) -> Int {
        Int((duration * sampleRate).rounded())
    }
}

final class OpeningPanelHaptics {
    private var engine: CHHapticEngine?
    private let supports = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    func play(_ haptic: OpeningPanelHaptic) {
        guard supports else { return }
        let events = Self.events(for: OpeningPanelHapticSpec.spec(for: haptic))
        do {
            if engine == nil {
                let engine = try CHHapticEngine()
                engine.isAutoShutdownEnabled = true
                self.engine = engine
            }
            try engine?.start()
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: CHHapticTimeImmediate)
        } catch {
            engine = nil
        }
    }

    static func events(for spec: OpeningPanelHapticSpec) -> [CHHapticEvent] {
        let parameters = [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: spec.intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: spec.sharpness),
        ]
        var events: [CHHapticEvent] = []
        if spec.includesTransient {
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: parameters, relativeTime: 0))
        }
        if spec.includesContinuous {
            events.append(
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: parameters,
                    relativeTime: 0,
                    duration: spec.duration
                )
            )
        }
        return events
    }
}

final class OpeningPanelSound: OpeningPanelFeedback {
    private let engine = AVAudioEngine()
    private let noisePlayer = AVAudioPlayerNode()
    private let tonePlayer = AVAudioPlayerNode()
    private let noiseEQ = AVAudioUnitEQ(numberOfBands: 1)
    private let haptics = OpeningPanelHaptics()
    private var started = false
    private let sampleRate = OpeningPanelSoundRecipe.sampleRate

    func play(_ cue: OpeningPanelCue) {
        switch cue {
        case .light:
            playNoise(OpeningPanelSoundRecipe.light, tone: nil)
        case .heavy:
            playNoise(OpeningPanelSoundRecipe.heavy, tone: OpeningPanelSoundRecipe.heavyBass)
        case .dull:
            playNoise(nil, tone: OpeningPanelSoundRecipe.dull)
        case .haptic(let haptic):
            haptics.play(haptic)
        }
    }

    private func playNoise(_ noise: OpeningPanelNoiseRecipe?, tone: OpeningPanelToneRecipe?) {
        guard startEngine() else { return }
        if let noise {
            noise.filter.apply(to: noiseEQ.bands[0])
            if let buffer = OpeningPanelSynthesis.buffer(OpeningPanelSynthesis.noise(noise), sampleRate: sampleRate) {
                noisePlayer.scheduleBuffer(buffer, at: nil, options: .interrupts)
                noisePlayer.play()
            }
        }
        if let tone, let buffer = OpeningPanelSynthesis.buffer(OpeningPanelSynthesis.tone(tone), sampleRate: sampleRate) {
            tonePlayer.scheduleBuffer(buffer, at: nil, options: .interrupts)
            tonePlayer.play()
        }
    }

    private func startEngine() -> Bool {
        if started, engine.isRunning { return true }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
        if !started {
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
            engine.attach(noisePlayer)
            engine.attach(tonePlayer)
            engine.attach(noiseEQ)
            engine.connect(noisePlayer, to: noiseEQ, format: format)
            engine.connect(noiseEQ, to: engine.mainMixerNode, format: format)
            engine.connect(tonePlayer, to: engine.mainMixerNode, format: format)
            started = true
        }
        do {
            try engine.start()
            return true
        } catch {
            return false
        }
    }
}

extension OpeningPanelState {
    static func live(
        ticketCount: Int = 0,
        reduceMotion: Bool = false,
        serviceAlreadyRunning: Bool = false,
        onStartService: @escaping () -> Void = {},
        onCommitSequence: @escaping () -> Void = {},
        onAbandonSequence: @escaping () -> Void = {},
        onShowHub: @escaping () -> Void = {}
    ) -> OpeningPanelState {
        OpeningPanelState(
            scheduler: OpeningPanelDispatchScheduler(),
            feedback: OpeningPanelSound(),
            ticketCount: ticketCount,
            reduceMotion: reduceMotion,
            serviceAlreadyRunning: serviceAlreadyRunning,
            onStartService: onStartService,
            onCommitSequence: onCommitSequence,
            onAbandonSequence: onAbandonSequence,
            onShowHub: onShowHub
        )
    }
}
