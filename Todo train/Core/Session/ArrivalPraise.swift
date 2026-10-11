//
//  ArrivalPraise.swift
//  Todo train
//
//  検札の褒めは足すだけ。超過で印を薄くしない。数は画面に出さない。
//

import Foundation

struct ArrivalPraise: Equatable, Sendable {
    var punctuality: ArrivalPunctuality
    var alreadyDone: Bool
    var nextWasReserved: Bool
    var continuedFromStamp: Bool

    static let plain = ArrivalPraise(
        punctuality: .late,
        alreadyDone: false,
        nextWasReserved: false,
        continuedFromStamp: false
    )

    /// 同時に起きているよいこと。定時と早着はどちらか一つ。
    var count: Int {
        var total = 0
        if punctuality == .onTime || punctuality == .early {
            total += 1
        }
        if alreadyDone { total += 1 }
        if nextWasReserved { total += 1 }
        if continuedFromStamp { total += 1 }
        return total
    }

    enum Spread: Equatable, Sendable {
        case none
        case stamp
        case paper
    }

    var spread: Spread {
        switch count {
        case 0: .none
        case 1: .stamp
        default: .paper
        }
    }

    /// 三つ重なったときだけ、印の内輪が実線になる。
    var innerRingSolid: Bool { count >= 3 }

    enum Ink: Equatable, Sendable {
        case arrival
        case onTime
        case early
    }

    var ink: Ink {
        switch punctuality {
        case .onTime: .onTime
        case .early: .early
        case .late, .notApplicable: .arrival
        }
    }
}
