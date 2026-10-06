//
//  PassengerCopy.swift
//  Todo train
//
//  乗客案内の文言。この面では切符語を出さない。
//

import Foundation

enum PassengerCopy {
    static let board = "乗る"
    static let boardLate = "途中から乗る"
    static let next = "次は"
    static let soon = "まもなく"
    static let now = "ただいま"
    static let nextEn = "Next"
    static let soonEn = "Soon"
    static let nowEn = "Now"
    static let doorCock = "非常用ドアコック"
    static let doorCockHint = "長押しでドアを開けます"
    static let doorOpened = "ドアを開けました"
    static let arrivedHistory = "終わり"
    static let emergencyHistory = "非常退出"
    static let cancelledHistory = "運休"
    static let drivingLocked = "案内のあいだは運転操作ができません"

    static func notificationBody(title: String) -> String {
        "『\(title)』のドアが開いています"
    }

    static func history(_ reason: PassengerEndReason) -> String {
        switch reason {
        case .arrived: arrivedHistory
        case .emergency: emergencyHistory
        case .cancelled: cancelledHistory
        }
    }

    static var surfaceLines: [String] {
        [
            board, boardLate, next, soon, now, nextEn, soonEn, nowEn,
            doorCock, doorCockHint, doorOpened,
            arrivedHistory, emergencyHistory, cancelledHistory, drivingLocked,
            notificationBody(title: "予定"),
        ]
    }
}
