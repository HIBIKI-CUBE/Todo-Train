//
//  ArrivalStampFeedback.swift
//  Todo train
//
//  到着の印を押したときの音と振動の順番。画面はこの列を順に出すだけ。
//

import Foundation

enum ArrivalStampFeedback: Equatable, Sendable {
    enum Sound: Equatable, Sendable {
        /// 角判がない到着。システム音 1104。
        case roundStamp
        /// 角判がある到着。判専用の短い音。
        case seal
    }

    enum Haptic: Equatable, Sendable {
        /// 丸い印。praise がないとき。heavy、強度 `roundBaseIntensity`。
        case roundBase
        /// 丸い印。praise があるとき。rigid、強度 `roundPraiseIntensity`。
        case roundPraise
        /// 角判の 1 段目。heavy、強度 `sealHeavyIntensity`。
        case sealHeavy
        /// 角判の 2 段目。rigid、強度 `sealRigidIntensity`。
        case sealRigid
    }

    struct Event: Equatable, Sendable {
        var delayMilliseconds: Int
        var sound: Sound?
        var haptic: Haptic?
    }

    /// 丸い印だけの 1 段目。既存の設定のまま。
    static let roundBaseIntensity = 1.0
    /// 丸い印だけの praise。既存の設定のまま。
    static let roundPraiseIntensity = 1.0
    /// 角判が券面に当たる瞬間。
    static let sealHeavyIntensity = 1.0
    /// 角判の 2 段目。1 段目から `sealFollowUpMilliseconds` 後。
    static let sealRigidIntensity = 0.75
    static let sealFollowUpMilliseconds = 70

    /// `hasCornerSeal` は定時で `sealLuxury` があるとき。豪華さの大小では変えない。
    static func sequence(hasCornerSeal: Bool, praiseCount: Int) -> [Event] {
        if hasCornerSeal {
            return [
                Event(delayMilliseconds: 0, sound: .seal, haptic: .sealHeavy),
                Event(delayMilliseconds: sealFollowUpMilliseconds, sound: nil, haptic: .sealRigid),
            ]
        }
        let haptic: Haptic = praiseCount > 0 ? .roundPraise : .roundBase
        return [
            Event(delayMilliseconds: 0, sound: .roundStamp, haptic: haptic),
        ]
    }
}
