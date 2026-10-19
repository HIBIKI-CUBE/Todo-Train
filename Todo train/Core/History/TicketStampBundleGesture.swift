//
//  TicketStampBundleGesture.swift
//  Todo train
//
//  束の指。触れた瞬間に開き、横になぞると枚をまたぐ。離す・取り消しは扇の状態機械へ。
//

import CoreGraphics
import Foundation

enum TicketStampBundleGesture {
    static let tapSlop: CGFloat = 10
    static let tapMaxDuration: Double = 0.3
    static let axisDecisionDistance: CGFloat = 10
    static let dragWidthRatio: CGFloat = 0.7
    static let minTravelPerCard: CGFloat = 18
    static let maxTravelPerCard: CGFloat = 40
    static let momentumProjection: Double = 0.2
    static let momentumSpringResponse: Double = 0.3
    static let momentumSpringDamping: Double = 0.75
    static let hapticMinInterval: Double = 0.03

    enum Classification: Equatable {
        case tap
        case pending
        case horizontal
        case vertical
    }

    /// 10pt 未満かつ 0.3 秒未満はタップ。初めて 10pt 動いた位置で、横が縦以上なら横。
    static func classify(dx: Double, dy: Double, duration: Double) -> Classification {
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance < Double(tapSlop) {
            return duration < tapMaxDuration ? .tap : .pending
        }
        if abs(dx) >= abs(dy) {
            return .horizontal
        }
        return .vertical
    }

    /// 右（正の速度）は focus を減らす。四捨五入して 0…count-1。
    static func projectedFocus(
        focus: Double,
        velocity: Double,
        travelPerCard: Double,
        count: Int
    ) -> Int {
        guard count > 0 else { return 0 }
        let travel = max(travelPerCard, 0.001)
        let projected = focus - (velocity / travel) * momentumProjection
        let rounded = Int(projected.rounded())
        return min(count - 1, max(0, rounded))
    }

    /// `start` から `end` へ進むあいだにまたいだ整数。向きの通りに並べる。
    static func crossings(from start: Double, to end: Double) -> [Int] {
        if end > start {
            let first = Int(floor(start)) + 1
            let last = Int(floor(end))
            guard last >= first else { return [] }
            return Array(first...last)
        }
        if end < start {
            let first = Int(ceil(start)) - 1
            let last = Int(ceil(end))
            guard first >= last else { return [] }
            return Array(stride(from: first, through: last, by: -1))
        }
        return []
    }

    /// 右（正）へは −1、左（負）へは +1。端のスクラバーが日の束を送る。
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
}

enum TicketStampBundleFanSession: Equatable {
    case closed
    case open(touching: Bool)

    enum Axis: Equatable {
        case horizontal
        case vertical
        case undecided
    }

    enum Event: Equatable {
        case touchBegan
        case moved
        case ended(Axis)
        case cancelled
        case bundleChanged
        case disappeared
        case sceneInactive
    }

    static func reduce(_ state: Self, _ event: Event) -> Self {
        switch event {
        case .touchBegan, .moved:
            return .open(touching: true)
        case .ended, .cancelled, .bundleChanged, .disappeared, .sceneInactive:
            return .closed
        }
    }
}
