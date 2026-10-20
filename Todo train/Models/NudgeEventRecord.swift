//
//  NudgeEventRecord.swift
//  Todo train
//
//  段に達したときの記録。測り直さず、cancelledAt は空のとき一度だけ書く。
//

import Foundation
import SwiftData

struct NudgeEventRecord: Codable, Equatable, Sendable {
    var stage: String
    var firedAt: Date
    var surface: String
    var rang: Bool
    var skipped: Bool
    var cancelledAt: Date?

    static func decoded(from json: String) -> [NudgeEventRecord] {
        guard let data = json.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let records = try? decoder.decode([NudgeEventRecord].self, from: data) {
            return records
        }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return []
        }
        return raw.compactMap { element in
            guard JSONSerialization.isValidJSONObject(element),
                  let elementData = try? JSONSerialization.data(withJSONObject: element) else {
                return nil
            }
            return try? decoder.decode(NudgeEventRecord.self, from: elementData)
        }
    }

    static func encoded(_ records: [NudgeEventRecord]) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }
}

extension WorkSession {
    var nudgeEvents: [NudgeEventRecord] {
        get { NudgeEventRecord.decoded(from: nudgeEventsJSON) }
        set { nudgeEventsJSON = NudgeEventRecord.encoded(newValue) }
    }

    /// The same stage is kept as first written.
    func appendNudgeEvent(_ event: NudgeEventRecord) {
        var events = nudgeEvents
        guard !events.contains(where: { $0.stage == event.stage }) else { return }
        events.append(event)
        nudgeEvents = events
    }

    /// Fills `cancelledAt` once. Rang and the fire time stay.
    func cancelNudgeEvent(stage: String, at date: Date) {
        var events = nudgeEvents
        guard let index = events.lastIndex(where: { $0.stage == stage && $0.cancelledAt == nil }) else { return }
        events[index].cancelledAt = date
        nudgeEvents = events
    }
}
