//
//  CabinVoiceSpeaker.swift
//  Todo train
//

import AVFoundation

enum CabinVoiceSpeaker {
    private static let synthesizer = AVSpeechSynthesizer()

    static func speakDriverLine(_ text: String, enabled: Bool) {
        guard enabled, !text.isEmpty else { return }
        StampSoundPlayer.prepareAmbientSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
}
