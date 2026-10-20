//
//  TimetableStripLayout.swift
//  Todo train
//
//  Overlapping 掲示 / ダイヤ sit side by side so each strip stays tappable.
//

import Foundation

nonisolated enum TimetableStripLayout {
    struct Interval: Equatable, Sendable, Identifiable {
        var id: String
        var startsAt: Date
        var endsAt: Date
    }

    struct Placement: Equatable, Sendable {
        var lane: Int
        var laneCount: Int
    }

    static func placements(for intervals: [Interval]) -> [String: Placement] {
        let sorted = intervals.sorted {
            if $0.startsAt != $1.startsAt { return $0.startsAt < $1.startsAt }
            if $0.endsAt != $1.endsAt { return $0.endsAt < $1.endsAt }
            return $0.id < $1.id
        }
        var result: [String: Placement] = [:]
        var cluster: [Interval] = []
        var clusterEnd = Date.distantPast

        func flush() {
            guard !cluster.isEmpty else { return }
            let lanes = packLanes(cluster)
            let count = max(1, (lanes.values.max() ?? 0) + 1)
            for item in cluster {
                result[item.id] = Placement(lane: lanes[item.id] ?? 0, laneCount: count)
            }
            cluster.removeAll(keepingCapacity: true)
        }

        for item in sorted {
            if cluster.isEmpty || item.startsAt < clusterEnd {
                cluster.append(item)
                clusterEnd = max(clusterEnd, item.endsAt)
            } else {
                flush()
                cluster = [item]
                clusterEnd = item.endsAt
            }
        }
        flush()
        return result
    }

    private static func packLanes(_ items: [Interval]) -> [String: Int] {
        var laneEnds: [Date] = []
        var map: [String: Int] = [:]
        for item in items {
            if let index = laneEnds.firstIndex(where: { $0 <= item.startsAt }) {
                map[item.id] = index
                laneEnds[index] = item.endsAt
            } else {
                map[item.id] = laneEnds.count
                laneEnds.append(item.endsAt)
            }
        }
        return map
    }
}
