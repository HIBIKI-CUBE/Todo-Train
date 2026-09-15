//
//  TimetableBoardingOverlap.swift
//  Todo train
//
//  発車しようとした見積が、載せたダイヤ / いまの掲示とどう重なるか。
//  確認の材料。発車そのものは止めない。
//

import Foundation

nonisolated struct TimetableBoardInterval: Equatable, Sendable {
    var title: String
    var startsAt: Date
    var endsAt: Date
}

nonisolated enum TimetableBoardingConflict: Equatable, Sendable {
    /// いま載せた枠の中に発車しようとしている。
    case adoptedNow(title: String)
    /// 見積のあいだに載せた枠が始まる。
    case adoptedSoon(title: String)
    /// いま掲示があるが、載せていない。
    case noticeNow(title: String)
}

nonisolated enum TimetableBoardingOverlap {
    static func conflict(
        now: Date,
        rideEnd: Date,
        adopted: [TimetableBoardInterval],
        notices: [TimetableBoardInterval]
    ) -> TimetableBoardingConflict? {
        let rideEnd = max(rideEnd, now)
        let occupying = adopted
            .filter { $0.endsAt > $0.startsAt && $0.startsAt < rideEnd && $0.endsAt > now }
            .sorted { $0.startsAt < $1.startsAt }

        if let current = occupying.first(where: { $0.startsAt <= now && now < $0.endsAt }) {
            return .adoptedNow(title: current.title)
        }
        if let soon = occupying.first(where: { $0.startsAt > now }) {
            return .adoptedSoon(title: soon.title)
        }

        let noticeNow = notices.first { notice in
            notice.endsAt > notice.startsAt && notice.startsAt <= now && now < notice.endsAt
        }
        if let noticeNow {
            return .noticeNow(title: noticeNow.title)
        }
        return nil
    }
}
