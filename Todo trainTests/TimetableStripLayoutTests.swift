//
//  TimetableStripLayoutTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

struct TimetableStripLayoutTests {
    private let day = Date(timeIntervalSince1970: 1_700_000_000)

    private func interval(
        _ id: String,
        from start: TimeInterval,
        duration: TimeInterval
    ) -> TimetableStripLayout.Interval {
        TimetableStripLayout.Interval(
            id: id,
            startsAt: day.addingTimeInterval(start),
            endsAt: day.addingTimeInterval(start + duration)
        )
    }

    @Test func isolated_keepsFullWidth() {
        let placements = TimetableStripLayout.placements(for: [
            interval("a", from: 0, duration: 1800),
            interval("b", from: 3600, duration: 1800)
        ])
        #expect(placements["a"]?.lane == 0)
        #expect(placements["a"]?.laneCount == 1)
        #expect(placements["b"]?.lane == 0)
        #expect(placements["b"]?.laneCount == 1)
    }

    @Test func overlap_splitsSideBySide() {
        let placements = TimetableStripLayout.placements(for: [
            interval("a", from: 0, duration: 3600),
            interval("b", from: 1800, duration: 3600)
        ])
        #expect(placements["a"]?.lane != placements["b"]?.lane)
        #expect(placements["a"]?.laneCount == 2)
        #expect(placements["b"]?.laneCount == 2)
    }

    @Test func laterCluster_doesNotInheritEarlierLanes() {
        let placements = TimetableStripLayout.placements(for: [
            interval("a", from: 0, duration: 3600),
            interval("b", from: 1800, duration: 3600),
            interval("c", from: 10_800, duration: 1800)
        ])
        #expect(placements["c"]?.lane == 0)
        #expect(placements["c"]?.laneCount == 1)
        #expect(placements["a"]?.laneCount == 2)
    }

    @Test func touchingEnds_doNotOverlap() {
        let placements = TimetableStripLayout.placements(for: [
            interval("a", from: 0, duration: 1800),
            interval("b", from: 1800, duration: 1800)
        ])
        #expect(placements["a"]?.laneCount == 1)
        #expect(placements["b"]?.laneCount == 1)
    }
}
