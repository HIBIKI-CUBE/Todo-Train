//
//  PositionReportWording.swift
//  Todo train
//
//  位置確認の一行目と、二択・取り消し帯の文。
//

import Foundation

enum PositionReportWording {
    private static let arrivalFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "HH:mm"
        return f
    }()

    static func clock(_ date: Date) -> String {
        arrivalFormatter.string(from: date)
    }

    static func scheduledLine(tenth: Int) -> String {
        "予定どおりなら \(tenth)割"
    }

    static func shareLine(tenth: Int) -> String {
        "\(tenth)割"
    }

    static func projectionLine(arrival: Date) -> String {
        "このままなら \(clock(arrival))着"
    }

    static let onTimeLine = "このままなら定時"

    static let arrivalPointLine = "到着の地点"

    static let unselectedValue = "未選択"

    static func gaugeValue(tenth: Int, phrase: String) -> String {
        "\(tenth)割、\(phrase)"
    }

    static func recoveryCaption(arrival: Date) -> String {
        "\(clock(arrival))着を目指す"
    }

    static func adjustCaption(arrival: Date) -> String {
        "\(clock(arrival))着にする"
    }

    static func recoveryBanner(arrival: Date) -> String {
        "\(clock(arrival))着を目指す回復運転"
    }

    static func adjustBanner(arrival: Date) -> String {
        "\(clock(arrival))着で運転調整"
    }
}
