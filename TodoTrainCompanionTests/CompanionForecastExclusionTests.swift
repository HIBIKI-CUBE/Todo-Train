import Foundation
import Testing
@testable import TodoTrainCompanion

struct CompanionForecastExclusionTests {
    @Test func companionUsesTheSameThreshold() {
        #expect(CompanionForecastExclusion.excludes(pauseInputSeconds: 300, activeSeconds: 600))
        #expect(!CompanionForecastExclusion.excludes(pauseInputSeconds: 200, activeSeconds: 100))
    }
}
