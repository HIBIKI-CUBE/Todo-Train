import Foundation
import Testing
@testable import TodoTrainSync

struct ForecastExclusionTests {
    @Test func userSecondsStayRawAndIgnoreOtherReasons() {
        let seconds = ForecastExclusion.pauseInputSeconds([
            PauseInputReading(heldByRaw: "user", macActiveSeconds: 120),
            PauseInputReading(heldByRaw: "timetable", macActiveSeconds: 9_000),
            PauseInputReading(heldByRaw: "alarm", macActiveSeconds: 400),
            PauseInputReading(heldByRaw: "switch", macActiveSeconds: 400),
            PauseInputReading(heldByRaw: "passenger", macActiveSeconds: 400),
            PauseInputReading(heldByRaw: nil, macActiveSeconds: 400),
            PauseInputReading(heldByRaw: "user", macActiveSeconds: 180),
        ])
        #expect(seconds == 300)
    }

    @Test func fiveMinutesAndAQuarterExcludes() {
        #expect(ForecastExclusion.excludes(pauseInputSeconds: 300, activeSeconds: 1_200))
        #expect(ForecastExclusion.excludes(pauseInputSeconds: 300, activeSeconds: 300 * 4))
    }

    @Test func shortInputOrSmallShareStaysIn() {
        #expect(!ForecastExclusion.excludes(pauseInputSeconds: 299, activeSeconds: 400))
        #expect(!ForecastExclusion.excludes(pauseInputSeconds: 300, activeSeconds: 1_201))
        #expect(!ForecastExclusion.excludes(pauseInputSeconds: .nan, activeSeconds: 100))
        #expect(!ForecastExclusion.excludes(pauseInputSeconds: 400, activeSeconds: .infinity))
    }
}
