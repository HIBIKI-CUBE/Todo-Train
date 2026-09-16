//
//  TimetableCopy.swift
//  Todo train
//

import Foundation

enum TimetableCopy {
    static let board = "ダイヤ"
    static let notice = "掲示"
    static let adopt = "載せる"
    static let unadopt = "外す"
    static let thisTime = "今回だけ"
    static let ongoing = "今後も"
    static let unadoptThisTime = "今回だけ外す"
    static let drawTime = "時刻を引く"
    static let pause = "停車"
    static let quiet = "会議中の時間は走行に入れていません"
    static let atsFooter = "載せた枠と走行が重なると、60秒後に停車します。アプリを開いていないときは、次に開いたときにその時刻へ遡ります。発車は確認しません。"
    static let calendarDenied = "カレンダーを読めません。設定から許可すると、掲示が図表に重なります。"
    static let emptyManualTitle = "枠"
    static let calendarFilter = "掲示するカレンダー"
    static let noCalendarsSelected = "掲示するカレンダーがありません。右上から選べます。"
    static let diagramLead = "今日の線路です。薄いスジは掲示。タップして載せると、その枠では停車します。"
    static let legendNotice = "薄い＝掲示（線路は空）"
    static let legendAdopted = "濃い＝ダイヤ"
    static let legendRide = "帯＝乗車"

    static func notificationBody(title: String) -> String {
        "『\(title)』のダイヤです。"
    }
}
