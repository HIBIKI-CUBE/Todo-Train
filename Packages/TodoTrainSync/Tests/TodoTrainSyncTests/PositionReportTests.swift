import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Position report")
struct PositionReportTests {
    @Test func projection_sixTenthsOfTwentyOneMinutes() {
        let active = TimeInterval(21 * 60)
        let total = PositionReport.projection(activeSeconds: active, progress: 0.6)
        #expect(total == TimeInterval(35 * 60))
    }

    @Test func projection_fullProgressIsNil() {
        #expect(PositionReport.projection(activeSeconds: 600, progress: 1.0) == nil)
        #expect(PositionReport.projection(activeSeconds: 600, progress: 1.05) == nil)
    }

    @Test func projection_zeroActiveIsNil() {
        #expect(PositionReport.projection(activeSeconds: 0, progress: 0.5) == nil)
    }

    @Test func adjustLuxuryPreview_matchesSealLuxuryAtSameRatio() {
        let progress = 0.6
        let preview = PositionReport.adjustLuxuryPreview(progress: progress)
        let active = progress * 1_000
        let remaining = Int((1 - progress) * 1_000)
        let committed = PunctualityJudgment.sealLuxury(
            source: .reestimate(index: 1),
            reestimates: [
                PunctualityJudgment.ReestimateCommit(
                    reestimateIndex: 1,
                    activeSeconds: active,
                    committedRemainingSeconds: remaining
                ),
            ]
        )
        #expect(preview == committed)
        #expect(preview == 0.36)
    }

    @Test func showsRecoveryDeclaration_beforeOriginalScheduledArrival() {
        #expect(
            PositionReport.showsRecoveryDeclaration(
                activeSeconds: 21 * 60,
                plannedBudgetSeconds: 30 * 60
            )
        )
        #expect(
            PositionReport.showsRecoveryDeclaration(
                activeSeconds: 29 * 60 + 59,
                plannedBudgetSeconds: 30 * 60
            )
        )
    }

    @Test func projectedRemaining_overtimeSixTenthsOfSixtyEightMinutes() {
        let active = TimeInterval(68 * 60)
        let progress = 0.6
        let remaining = PositionReport.projectedRemainingSeconds(
            activeSeconds: active,
            progress: progress
        )
        #expect(remaining != nil)
        let minutes = (remaining! / 60)
        #expect(minutes > 44.5)
        #expect(minutes < 46.0)
        let total = PositionReport.projectedTotalSecondsInt(activeSeconds: active, progress: progress)
        #expect(total == Int((active / progress).rounded()))
        let committed = PositionReport.committedRemainingSeconds(activeSeconds: active, progress: progress)
        #expect(committed == total! - 68 * 60)
        let arrival = PositionReport.projectedArrival(
            now: Date(timeIntervalSince1970: 0),
            activeSeconds: active,
            progress: progress
        )
        #expect(arrival == Date(timeIntervalSince1970: remaining!))
    }

    @Test func showsRecoveryDeclaration_hidesAfterOriginalScheduledArrival() {
        #expect(
            !PositionReport.showsRecoveryDeclaration(
                activeSeconds: 30 * 60,
                plannedBudgetSeconds: 30 * 60
            )
        )
        #expect(
            !PositionReport.showsRecoveryDeclaration(
                activeSeconds: 34 * 60,
                plannedBudgetSeconds: 30 * 60
            )
        )
    }
}
