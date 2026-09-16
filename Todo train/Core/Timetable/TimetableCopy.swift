//
//  TimetableCopy.swift
//  Todo train
//

import Foundation

enum TimetableCopy {
    static let board = "ダイヤ"
    static let notice = "掲示"
    static let adopt = "着発"
    static let unadopt = "通過"
    static let thisTime = "今回だけ"
    static let adoptThisTime = "今回だけ着発"
    static let adoptOngoing = "今後も着発"
    static let unadoptOngoing = "今後も通過"
    static let unadoptThisTime = "今回だけ通過"
    static let drawTime = "時刻を引く"
    static let pause = "停車"
    static let quiet = "会議中は走っていません"
    static let atsFooter = "重なったら60秒で停車。閉じていても、次に開いたときその時刻へ戻す。"
    static let calendarDenied = "カレンダーを読めません。設定から許可すると掲示が出ます。"
    static let emptyManualTitle = "枠"
    static let calendarFilter = "掲示するカレンダー"
    static let noCalendarsSelected = "掲示するカレンダーがありません。"
    static let legendNotice = "掲示"
    static let legendAdopted = "ダイヤ"
    static let legendRide = "乗車"

    static func notificationBody(title: String) -> String {
        "『\(title)』のダイヤです。"
    }
}
