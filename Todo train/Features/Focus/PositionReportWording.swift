//
//  PositionReportWording.swift
//  Todo train
//
//  指令（車内放送）の見込み文案。CabinKind の契約指紋とは分離する。
//

import Foundation

enum PositionReportWording {
    private static let arrivalFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "HH:mm"
        return f
    }()

    static func progressHeadline(tenth: Int) -> String {
        "\(tenth)割の地点"
    }

    static func projectionDetail(
        activeMinutes: Int,
        tenth: Int,
        projectedArrival: Date
    ) -> String {
        let clock = arrivalFormatter.string(from: projectedArrival)
        return "\(activeMinutes)分で\(tenth)割なので、このままなら \(clock)着の見込み"
    }

    static let onTimeProjectionSummary = "このままなら定時の見込み"

    static func recoveryCaption(arrival: Date) -> String {
        "\(arrivalFormatter.string(from: arrival))着を目指す"
    }

    static func adjustCaption(arrival: Date) -> String {
        "\(arrivalFormatter.string(from: arrival))着にする"
    }

}
