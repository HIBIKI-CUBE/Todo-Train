//
//  PassengerRide.swift
//  Todo train
//
//  乗客としての乗車。切符の WorkSession とは混ぜない。
//

import Foundation
import SwiftData

@Model
final class PassengerRide {
    var id: UUID = UUID()
    var intervalId: String = ""
    var title: String = ""
    var intervalStart: Date = Date.now
    var intervalEnd: Date = Date.now
    var boardedAt: Date = Date.now
    var endedAt: Date?
    var endReasonRaw: String?
    var sourceRaw: String = PassengerRideSource.manualInterval.rawValue
    var deviceId: String?

    var endReason: PassengerEndReason? {
        get { endReasonRaw.flatMap(PassengerEndReason.init(rawValue:)) }
        set { endReasonRaw = newValue?.rawValue }
    }

    var source: PassengerRideSource {
        get { PassengerRideSource(rawValue: sourceRaw) ?? .manualInterval }
        set { sourceRaw = newValue.rawValue }
    }

    var isOpen: Bool { endedAt == nil }

    init(
        id: UUID = UUID(),
        intervalId: String,
        title: String,
        intervalStart: Date,
        intervalEnd: Date,
        boardedAt: Date,
        source: PassengerRideSource,
        deviceId: String? = nil
    ) {
        self.id = id
        self.intervalId = intervalId
        self.title = title
        self.intervalStart = intervalStart
        self.intervalEnd = intervalEnd
        self.boardedAt = boardedAt
        self.endedAt = nil
        self.endReasonRaw = nil
        self.sourceRaw = source.rawValue
        self.deviceId = deviceId
    }

    convenience init(snapshot: PassengerRideSnapshot) {
        self.init(
            id: snapshot.id,
            intervalId: snapshot.intervalId,
            title: snapshot.title,
            intervalStart: snapshot.intervalStart,
            intervalEnd: snapshot.intervalEnd,
            boardedAt: snapshot.boardedAt,
            source: snapshot.source,
            deviceId: snapshot.deviceId
        )
        endedAt = snapshot.endedAt
        endReason = snapshot.endReason
    }

    var snapshot: PassengerRideSnapshot {
        PassengerRideSnapshot(
            id: id,
            intervalId: intervalId,
            title: title,
            intervalStart: intervalStart,
            intervalEnd: intervalEnd,
            boardedAt: boardedAt,
            endedAt: endedAt,
            endReason: endReason,
            source: source,
            deviceId: deviceId
        )
    }
}
