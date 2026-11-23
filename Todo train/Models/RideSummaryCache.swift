//
//  RideSummaryCache.swift
//  Todo train
//
//  似たきっぷ探しに使う過去の乗車の控え。元の乗車と停車から作り直せる。
//

import Foundation
import SwiftData

@Model
final class RideSummaryCache {
    var sessionID: UUID = UUID()
    var payload: String = ""
    var sourceUpdatedAt: Date = Date.now
    var methodVersion: Int = 0

    init(
        sessionID: UUID,
        payload: String,
        sourceUpdatedAt: Date,
        methodVersion: Int
    ) {
        self.sessionID = sessionID
        self.payload = payload
        self.sourceUpdatedAt = sourceUpdatedAt
        self.methodVersion = methodVersion
    }
}
