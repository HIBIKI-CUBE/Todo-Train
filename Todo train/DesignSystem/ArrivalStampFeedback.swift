//
//  ArrivalStampFeedback.swift
//  Todo train
//
//  到着の印を押したときの音と振動の順番。画面はこの列を順に出すだけ。
//

import Foundation

/// 丸い印と角判の間。実機では 100〜200ms の範囲でこの値だけを調整する。
enum StampFeedbackTiming {
    /// 丸い印を落としてから角判を落とすまでの間。250ms を超えると別々の出来事に見える。
    static let sealDelayMilliseconds = 150
    /// 角判の heavy から rigid までの間。
    static let sealSecondHapticMilliseconds = 70
}

enum ArrivalStampFeedback: Equatable, Sendable {
    enum Sound: Equatable, Sendable {
        /// 丸い印。軽い短い音。
        case roundStamp
        /// 角判。重い短い音。
        case seal
    }

    enum Haptic: Equatable, Sendable {
        /// 丸い印の一打。light、強度 `roundLightIntensity`。
        case roundLight
        /// 角判の 1 段目。heavy、強度 `sealHeavyIntensity`。
        case sealHeavy
        /// 角判の 2 段目。rigid、強度 `sealRigidIntensity`。
        case sealRigid
    }

    struct Event: Equatable, Sendable {
        /// 印を押した瞬間からのオフセット。
        var offsetMilliseconds: Int
        var sound: Sound?
        var haptic: Haptic?
    }

    /// 丸い印。light の 0.6 前後。
    static let roundLightIntensity = 0.6
    /// 角判が券面に当たる瞬間。
    static let sealHeavyIntensity = 1.0
    /// 角判の 2 段目。
    static let sealRigidIntensity = 0.75

    /// `hasCornerSeal` は定時で `sealLuxury` があるとき。豪華さの大小では変えない。
    /// 角判がないとき（遅刻など）は丸い印の一段だけ。
    static func sequence(hasCornerSeal: Bool) -> [Event] {
        var events = [
            Event(offsetMilliseconds: 0, sound: .roundStamp, haptic: .roundLight),
        ]
        guard hasCornerSeal else { return events }
        let seal = StampFeedbackTiming.sealDelayMilliseconds
        events.append(Event(offsetMilliseconds: seal, sound: .seal, haptic: .sealHeavy))
        events.append(
            Event(
                offsetMilliseconds: seal + StampFeedbackTiming.sealSecondHapticMilliseconds,
                sound: nil,
                haptic: .sealRigid
            )
        )
        return events
    }
}
