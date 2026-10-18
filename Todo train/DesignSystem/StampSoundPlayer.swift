//
//  StampSoundPlayer.swift
//  Todo train
//

import AVFoundation
import AudioToolbox

enum StampSoundPlayer {
    private static var configured = false
    private static var sealPlayer: AVAudioPlayer?

    /// 角判がない到着。システム音 1104。
    static func playStampThud() {
        prepareAmbientSession()
        AudioServicesPlaySystemSound(1104)
    }

    /// 到着の画面が出た時点で呼ぶ。再生までの遅れを小さくする。
    static func prepareSealSound() {
        prepareAmbientSession()
        let player = sealPlayer ?? loadSealPlayer()
        sealPlayer = player
        player?.prepareToPlay()
    }

    /// 角判がある到着。判専用の短い音だけを鳴らす。
    static func playSealStamp() {
        prepareAmbientSession()
        let player = sealPlayer ?? loadSealPlayer()
        sealPlayer = player
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }

    /// `.ambient` なのでマナーモードでは鳴らない。`.mixWithOthers` だけで、音楽は止めず音量も下げない。
    static func prepareAmbientSession() {
        guard !configured else { return }
        configured = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private static func loadSealPlayer() -> AVAudioPlayer? {
        guard let url = sealSoundURL() else { return nil }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.volume = 1
        player.numberOfLoops = 0
        return player
    }

    private static func sealSoundURL() -> URL? {
        let bundle = Bundle.main
        return bundle.url(forResource: "seal_stamp", withExtension: "caf")
            ?? bundle.url(forResource: "seal_stamp", withExtension: "caf", subdirectory: "Sounds")
            ?? bundle.url(forResource: "seal_stamp", withExtension: "caf", subdirectory: "Resources/Sounds")
    }
}
