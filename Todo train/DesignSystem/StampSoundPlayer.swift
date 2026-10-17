//
//  StampSoundPlayer.swift
//  Todo train
//

import AVFoundation
import AudioToolbox

enum StampSoundPlayer {
    private static var configured = false

    static func playStampThud() {
        prepareAmbientSession()
        AudioServicesPlaySystemSound(1104)
    }

    static func prepareAmbientSession() {
        guard !configured else { return }
        configured = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
    }
}
