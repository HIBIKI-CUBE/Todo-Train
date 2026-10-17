import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Punctuality judgment")
struct PunctualityJudgmentTests {
    private func ride(
        active: TimeInterval,
        estimate: Int = 1_800,
        arrived: Bool = true,
        reestimates: [PunctualityJudgment.ReestimateCommit] = []
    ) -> PunctualityJudgment.RideInput {
        PunctualityJudgment.RideInput(
            arrived: arrived,
            activeSeconds: active,
            estimatedSecondsAtStart: estimate,
            reestimates: reestimates
        )
    }

    @Test func bandWidth_usesFifteenPercentOrOneMinute() {
        #expect(PunctualityJudgment.bandHalfWidth(bandBasisSeconds: 240) == 60)
        #expect(PunctualityJudgment.bandHalfWidth(bandBasisSeconds: 600) == 90)
        #expect(PunctualityJudgment.bandHalfWidth(bandBasisSeconds: 1_800) == 270)
    }

    @Test func reestimate_mustBeFiveRunningMinutesBeforeArrival() {
        let events = [
            PunctualityJudgment.ReestimateCommit(
                reestimateIndex: 1,
                activeSeconds: 1_200,
                committedRemainingSeconds: 900
            ),
        ]
        let justInside = PunctualityJudgment.judge(
            ride(active: 1_200 + 300, reestimates: events)
        )
        #expect(justInside.exportSource.kind == .reestimate)
        #expect(justInside.exportSource.reestimateIndex == 1)

        let tooLate = PunctualityJudgment.judge(
            ride(active: 1_200 + 299, reestimates: events)
        )
        #expect(tooLate.exportSource.kind == .original)
    }

    @Test func reestimate_usesLatestEligibleCommit() {
        let events = [
            PunctualityJudgment.ReestimateCommit(
                reestimateIndex: 1,
                activeSeconds: 300,
                committedRemainingSeconds: 1_200
            ),
            PunctualityJudgment.ReestimateCommit(
                reestimateIndex: 2,
                activeSeconds: 900,
                committedRemainingSeconds: 600
            ),
        ]
        let judgment = PunctualityJudgment.judge(ride(active: 1_600, reestimates: events))
        #expect(judgment.exportSource.reestimateIndex == 2)
        #expect(judgment.judgedTotalSeconds == 1_500)
    }

    @Test func onTime_withinSymmetricBandAroundJudgedTotal() {
        let judgment = PunctualityJudgment.judge(ride(active: 1_750, estimate: 1_800))
        #expect(judgment.outcome == .onTime)
        #expect(judgment.lowerBound == 1_800 - 270)
        #expect(judgment.upperBound == 1_800 + 270)
    }

    @Test func early_beforeLowerBound() {
        let judgment = PunctualityJudgment.judge(ride(active: 1_400, estimate: 1_800))
        #expect(judgment.outcome == .early)
        #expect(judgment.arrivalJudgement == .none)
        #expect(judgment.sealTier == nil)
    }

    @Test func late_pastUpperBound() {
        let judgment = PunctualityJudgment.judge(ride(active: 2_100, estimate: 1_800))
        #expect(judgment.outcome == .late)
    }

    @Test func sealTier_firstHalfVersusSecondHalf() {
        let earlyHalf = PunctualityJudgment.ReestimateCommit(
            reestimateIndex: 1,
            activeSeconds: 600,
            committedRemainingSeconds: 1_200
        )
        let onFirstHalf = PunctualityJudgment.judge(
            ride(active: 1_750, reestimates: [earlyHalf])
        )
        #expect(onFirstHalf.outcome == .onTime)
        #expect(onFirstHalf.sealTier == .earlyReestimate)

        let lateHalf = PunctualityJudgment.ReestimateCommit(
            reestimateIndex: 1,
            activeSeconds: 602,
            committedRemainingSeconds: 600
        )
        let onSecondHalf = PunctualityJudgment.judge(
            ride(active: 1_200, reestimates: [lateHalf])
        )
        #expect(onSecondHalf.outcome == .onTime)
        #expect(onSecondHalf.sealTier == .lateReestimate)

        let exactlyHalf = PunctualityJudgment.ReestimateCommit(
            reestimateIndex: 1,
            activeSeconds: 600,
            committedRemainingSeconds: 600
        )
        let atHalf = PunctualityJudgment.judge(
            ride(active: 1_200, reestimates: [exactlyHalf])
        )
        #expect(atHalf.outcome == .onTime)
        #expect(atHalf.sealTier == .earlyReestimate)
    }

    @Test func sealTier_ticketingForOriginalEstimate() {
        let judgment = PunctualityJudgment.judge(ride(active: 1_780, estimate: 1_800))
        #expect(judgment.sealTier == .ticketing)
    }

    @Test func overtimeResolution_canStillBeOnTimeAfterReestimate() {
        let events = [
            PunctualityJudgment.ReestimateCommit(
                reestimateIndex: 1,
                activeSeconds: 1_000,
                committedRemainingSeconds: 900
            ),
        ]
        let judgment = PunctualityJudgment.judge(
            ride(active: 1_850, estimate: 1_200, reestimates: events)
        )
        #expect(judgment.outcome == .onTime)
        #expect(judgment.exportSource.kind == .reestimate)
    }

    @Test func inRide_signalStates() {
        let judgment = PunctualityJudgment.judge(ride(active: 500, estimate: 1_800, arrived: false))
        #expect(judgment.signal == .green)
        let inside = PunctualityJudgment.judge(ride(active: 1_700, estimate: 1_800, arrived: false))
        #expect(inside.signal == .yellow)
        let past = PunctualityJudgment.judge(ride(active: 2_100, estimate: 1_800, arrived: false))
        #expect(past.signal == .off)
    }

    @Test func inRide_homeFreezesWithinFiveMinutesOfETA() {
        let events = [
            PunctualityJudgment.ReestimateCommit(
                reestimateIndex: 1,
                activeSeconds: 1_000,
                committedRemainingSeconds: 400
            ),
            PunctualityJudgment.ReestimateCommit(
                reestimateIndex: 2,
                activeSeconds: 1_200,
                committedRemainingSeconds: 200
            ),
        ]
        let frozen = PunctualityJudgment.judge(
            ride(active: 1_250, estimate: 1_800, arrived: false, reestimates: events)
        )
        if case .reestimate(let index) = frozen.source {
            #expect(index == 1)
        } else {
            Issue.record("expected frozen home source to stay on first reestimate")
        }
        #expect(frozen.judgedTotalSeconds == 1_400)
    }

    @Test func notArrived_isNotApplicable() {
        let judgment = PunctualityJudgment.judge(ride(active: 100, arrived: false))
        #expect(judgment.outcome == .notApplicable)
    }

    @Test func stampSeasonAndTimeOfDay_useTokyoCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = PunctualityJudgment.tokyoTimeZone
        let spring = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 12))!
        #expect(PunctualityJudgment.stampSeason(at: spring) == .spring)
        #expect(PunctualityJudgment.stampTimeOfDay(at: spring) == .afternoon)
    }

    @Test func reestimateBandBasis_usesCommittedRemaining() {
        let events = [
            PunctualityJudgment.ReestimateCommit(
                reestimateIndex: 1,
                activeSeconds: 600,
                committedRemainingSeconds: 400
            ),
        ]
        let judgment = PunctualityJudgment.judge(ride(active: 1_000, reestimates: events))
        #expect(judgment.bandHalfWidth == 60)
    }

    @Test func interruptedRide_sameRulesAsNormalRide() {
        let judgment = PunctualityJudgment.judge(ride(active: 1_790, estimate: 1_800))
        #expect(judgment.outcome == .onTime)
    }
}
