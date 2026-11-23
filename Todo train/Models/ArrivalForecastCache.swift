//
//  ArrivalForecastCache.swift
//  Todo train
//
//  到着予想の控え。元の切符・乗車・停車から作り直せる。
//

import Foundation
import SwiftData

@Model
final class ArrivalForecastCache {
    var ticketID: UUID = UUID()
    var payload: String = ""
    var sourceUpdatedAt: Date = Date.now
    var methodVersion: Int = 0

    init(
        ticketID: UUID,
        payload: String,
        sourceUpdatedAt: Date,
        methodVersion: Int
    ) {
        self.ticketID = ticketID
        self.payload = payload
        self.sourceUpdatedAt = sourceUpdatedAt
        self.methodVersion = methodVersion
    }
}
