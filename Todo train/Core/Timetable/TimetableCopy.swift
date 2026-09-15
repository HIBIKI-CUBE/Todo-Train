//
//  TimetableCopy.swift
//  Todo train
//

import Foundation

enum TimetableCopy {
    static let board = "ダイヤ"
    static let notice = "掲示"
    static let adopt = "ダイヤに載せる"
    static let unadopt = "外す"
    static let thisOccurrence = "今回だけ"
    static let thisSeries = "今後も"
    static let manualAdd = "時刻を引く"
    static let pausedQuietly = "会議中の時間は走行に入れていません"
    static let nextNone = "次の枠はありません"
    static let calendarDenied = "カレンダーを参照できません。手動で時刻を引けます。"
    static let atsLimit = "iPhone を伏せたままでは、開始の通知に反応しないと次にアプリを開いたときに走行を切ります。Mac がつながっているときは、そちらから停車できます。"

    static func nextLine(kind: Kind, title: String, startsAt: Date) -> String {
        "\(kind.label) \(clockLine(title: title, startsAt: startsAt))"
    }

    static func clockLine(title: String, startsAt: Date) -> String {
        "\(BoardingForecast.timeString(from: startsAt)) \(title)"
    }

    enum Kind {
        case notice
        case board

        var label: String {
            switch self {
            case .notice: TimetableCopy.notice
            case .board: TimetableCopy.board
            }
        }
    }
}
