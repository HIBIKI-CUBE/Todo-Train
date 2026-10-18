//
//  TicketStampBundleSwipe.swift
//  Todo train
//
//  横になぞる向きと、長押しシャトルの速さ。正の向きは古い切符（−1）。
//

import Foundation

enum TicketStampBundleSwipe {
    /// 長押しでシャトルに入るまでの時間。
    static let shuttleArmDuration: Double = 0.35
    /// 押した位置からこの距離まではめくらない。
    static let shuttleDeadZone: Double = 20
    /// 不感帯の先、この距離で上限に達する。
    static let shuttleFullThrow: Double = 120
    static let shuttleMaxCardsPerSecond: Double = 12
    /// これ以上の速さでは、日の境目だけ振動する。
    static let shuttleFastCardsPerSecond: Double = 8

    /// 右（正）へは −1、左（負）へは +1。速さは移動量より先に見る。
    static func steps(
        translation: Double,
        velocity: Double,
        threshold: Double,
        flickVelocity: Double
    ) -> Int {
        if abs(velocity) > flickVelocity {
            return velocity > 0 ? -1 : 1
        }
        if translation > threshold {
            return -1
        }
        if translation < -threshold {
            return 1
        }
        return 0
    }

    /// 正の距離（右）は負の速さ（古い切符へ）。0〜deadZone は 0、上限は毎秒 12 枚。
    static func shuttleCardsPerSecond(distance: Double) -> Double {
        guard distance.isFinite else { return 0 }
        let sign: Double
        if distance > 0 {
            sign = -1
        } else if distance < 0 {
            sign = 1
        } else {
            return 0
        }
        let magnitude = abs(distance)
        guard magnitude > shuttleDeadZone else { return 0 }
        let span = max(shuttleFullThrow, 0.001)
        let t = min(1, (magnitude - shuttleDeadZone) / span)
        return sign * t * shuttleMaxCardsPerSecond
    }

    static func shuttleSuppressesPerCardHaptics(cardsPerSecond: Double) -> Bool {
        abs(cardsPerSecond) >= shuttleFastCardsPerSecond
    }

    /// 経過時間の端数を持ち越し、枚数の整数だけ進める。
    static func shuttleAdvance(
        rate: Double,
        elapsed: Double,
        carry: Double
    ) -> (steps: Int, carry: Double) {
        guard rate.isFinite, elapsed.isFinite, elapsed > 0, carry.isFinite else {
            return (0, carry.isFinite ? carry : 0)
        }
        let pending = carry + rate * elapsed
        guard pending.isFinite else { return (0, 0) }
        let steps = Int(pending.rounded(.towardZero))
        if steps == 0 {
            return (0, pending)
        }
        return (steps, pending - Double(steps))
    }
}
