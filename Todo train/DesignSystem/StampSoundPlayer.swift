//
//  StampSoundPlayer.swift
//  Todo train
//

import AVFoundation

enum StampSoundPlayer {
    private static var configured = false
    private static var roundPlayer: AVAudioPlayer?
    private static var sealPlayer: AVAudioPlayer?

    /// 到着の画面が出た時点で呼ぶ。再生までの遅れを小さくする。
    static func prepareStampSounds() {
        prepareAmbientSession()
        roundPlayer = roundPlayer ?? loadPlayer(named: "round_stamp")
        sealPlayer = sealPlayer ?? loadPlayer(named: "seal_stamp")
        roundPlayer?.prepareToPlay()
        sealPlayer?.prepareToPlay()
    }

    /// 丸い印。軽い短い音。
    static func playRoundStamp() {
        play(player: roundPlayer ?? loadPlayer(named: "round_stamp"), store: { roundPlayer = $0 })
    }

    /// 角判。重い短い音。
    static func playSealStamp() {
        play(player: sealPlayer ?? loadPlayer(named: "seal_stamp"), store: { sealPlayer = $0 })
    }

    /// `.ambient` なのでマナーモードでは鳴らない。`.mixWithOthers` だけで、音楽は止めず音量も下げない。
    static func prepareAmbientSession() {
        guard !configured else { return }
        configured = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private static func play(player loaded: AVAudioPlayer?, store: (AVAudioPlayer?) -> Void) {
        prepareAmbientSession()
        store(loaded)
        guard let loaded else { return }
        loaded.currentTime = 0
        loaded.play()
    }

    private static func loadPlayer(named resource: String) -> AVAudioPlayer? {
        guard let url = soundURL(named: resource) else { return nil }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.volume = 1
        player.numberOfLoops = 0
        return player
    }

    private static func soundURL(named resource: String) -> URL? {
        let bundle = Bundle.main
        return bundle.url(forResource: resource, withExtension: "caf")
            ?? bundle.url(forResource: resource, withExtension: "caf", subdirectory: "Sounds")
            ?? bundle.url(forResource: resource, withExtension: "caf", subdirectory: "Resources/Sounds")
    }
}
