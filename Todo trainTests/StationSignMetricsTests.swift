//
//  StationSignMetricsTests.swift
//  Todo trainTests
//

import CoreGraphics
import Testing
@testable import Todo_train

struct StationSignMetricsTests {
    @Test func shortJapanese_opensOut() {
        #expect(StationSignMetrics.nameTracking("会議", compact: false) == 11)
        #expect(StationSignMetrics.nameTracking("会議", compact: true) == 5)
        #expect(StationSignMetrics.nameTracking("品川", compact: false) == 11)
        #expect(StationSignMetrics.nameTracking("大手町", compact: false) == 6)
        #expect(StationSignMetrics.nameTracking("しんばし", compact: false) == 3)
    }

    @Test func longOrLatin_staysTight() {
        #expect(StationSignMetrics.nameTracking("原稿を書く", compact: false) == 0)
        #expect(StationSignMetrics.nameTracking("Review PR", compact: false) == 0)
        #expect(StationSignMetrics.nameTracking("A", compact: false) == 0)
        #expect(StationSignMetrics.nameTracking("", compact: false) == 0)
    }
}
