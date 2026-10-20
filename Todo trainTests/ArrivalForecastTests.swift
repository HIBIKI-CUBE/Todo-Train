//
//  ArrivalForecastTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct ArrivalForecastTests {
    @Test func hourBand_splitsTheDay() {
        #expect(WorkHourBand.of(hour: 4) == .night)
        #expect(WorkHourBand.of(hour: 9) == .morning)
        #expect(WorkHourBand.of(hour: 14) == .afternoon)
        #expect(WorkHourBand.of(hour: 19) == .evening)
        #expect(WorkHourBand.of(hour: 23) == .night)
    }

    @Test func isCancellation_readsSwiftCancellationError() {
        #expect(ArrivalForecast.isCancellation(CancellationError()))
        #expect(!ArrivalForecast.isCancellation(NSError(domain: "test", code: 1)))
    }

    @Test func clampPredicted_staysNearMedian() {
        #expect(ArrivalForecast.clampPredicted(50, around: 20) == 32) // 20 + max(12, 8)
        #expect(ArrivalForecast.clampPredicted(5, around: 20) == 8)
        #expect(ArrivalForecast.clampPredicted(30, around: 30) == 30)
        #expect(ArrivalForecast.clampPredicted(80, around: 50) == 60)
        #expect(ArrivalForecast.clampPredicted(1, around: 50) == 30)
    }

    @Test func resolvedMinutes_usesWeightAndConfidence() {
        let heavier = ArrivalForecastDraft(
            thinking: "題名がレビューで過去も延びている",
            predictedMinutes: 40,
            weight: .heavier,
            confidence: .high
        )
        #expect(ArrivalForecast.resolvedMinutes(from: heavier, medianMinutes: 32) == 40)

        let similar = ArrivalForecastDraft(
            thinking: "題名も時間帯も中央値どおり",
            predictedMinutes: 40,
            weight: .similar,
            confidence: .high
        )
        #expect(ArrivalForecast.resolvedMinutes(from: similar, medianMinutes: 32) == nil)

        let low = ArrivalForecastDraft(
            thinking: "判断材料が足りない",
            predictedMinutes: 40,
            weight: .heavier,
            confidence: .low
        )
        #expect(ArrivalForecast.resolvedMinutes(from: low, medianMinutes: 32) == nil)

        let conflict = ArrivalForecastDraft(
            thinking: "重いはずだが分数が軽い",
            predictedMinutes: 20,
            weight: .heavier,
            confidence: .high
        )
        #expect(ArrivalForecast.resolvedMinutes(from: conflict, medianMinutes: 32) == nil)

        let lighter = ArrivalForecastDraft(
            thinking: "短い確認で早着が続いている",
            predictedMinutes: 18,
            weight: .lighter,
            confidence: .medium
        )
        #expect(ArrivalForecast.resolvedMinutes(from: lighter, medianMinutes: 32) == 19)
    }

    @Test func heuristicEngine_doesNotReplaceMedian() async {
        let minutes = await HeuristicArrivalForecastEngine().refine(sampleContext())
        #expect(minutes == nil)
    }

    @Test func clockLabel_usesJapaneseWeekday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 16, minute: 54))!
        #expect(ArrivalForecastPrompt.clockLabel(sunday, calendar: calendar) == "日 16:54")
        let monday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 9, minute: 5))!
        #expect(ArrivalForecastPrompt.clockLabel(monday, calendar: calendar) == "月 09:05")
    }

    @Test func rideLine_includesEstimateExtensionAndEarly() {
        let extended = ArrivalForecastContext.RideRecord(
            title: "週次レビュー",
            startedLabel: "火 10:15",
            estimatedMinutes: 30,
            actualMinutes: 38,
            budgetMinutes: 40,
            extensionMinutes: 10,
            extensionReasons: ["割り込みが入った"],
            punctuality: .late
        )
        let early = ArrivalForecastContext.RideRecord(
            title: "資料確認",
            startedLabel: "火 16:02",
            estimatedMinutes: 20,
            actualMinutes: 14,
            budgetMinutes: 20,
            extensionMinutes: 0,
            extensionReasons: [],
            punctuality: .early
        )
        #expect(
            ArrivalForecastPrompt.rideLine(extended)
                == "- 火 10:15 開始 「週次レビュー」 見積30分 → 実績38分 延長+10分（割り込みが入った） 予算40分 超過 8分"
        )
        #expect(
            ArrivalForecastPrompt.rideLine(early)
                == "- 火 16:02 開始 「資料確認」 見積20分 → 実績14分 早着 6分"
        )
    }

    @Test func userPrompt_includesRideHistory() {
        let context = sampleContext(
            title: "週次レビュー",
            recent: [
                ArrivalForecastContext.RideRecord(
                    title: "資料",
                    startedLabel: "土 13:00",
                    estimatedMinutes: 20,
                    actualMinutes: 28,
                    budgetMinutes: 30,
                    extensionMinutes: 10,
                    extensionReasons: ["範囲が増えた"],
                    punctuality: .late
                )
            ]
        )
        let prompt = ArrivalForecastPrompt.userPrompt(for: context)
        #expect(prompt.contains("週次レビュー"))
        #expect(prompt.contains("昼"))
        #expect(prompt.contains("32分"))
        #expect(prompt.contains("土 13:00 開始"))
        #expect(prompt.contains("見積20分 → 実績28分"))
        #expect(prompt.contains("延長+10分"))
        #expect(prompt.contains("範囲が増えた"))
        #expect(ArrivalForecastPrompt.instructions.contains("thinking"))
        #expect(!ArrivalForecastPrompt.instructions.contains("数字のみ"))
    }

    @Test func heuristicEngine_recordsTrace() async {
        let log = ArrivalForecastTraceLog()
        let engine = HeuristicArrivalForecastEngine(log: log)
        let minutes = await engine.refine(sampleContext(title: "レビュー", estimatedMinutes: 20, medianMinutes: 22))
        #expect(minutes == nil)
        #expect(log.traces.count == 1)
        #expect(log.traces.first?.outcome == .heuristicOnly)
        #expect(log.traces.first?.title == "レビュー")
        #expect(log.traces.first?.medianMinutes == 22)
    }

    @Test func context_carriesEstimateAndExtension() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let model = ModelContext(container)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let started = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 10, minute: 15))!
        let ticket = Ticket(title: "報告書", estimatedSeconds: 30 * 60)
        model.insert(ticket)
        let session = WorkSession(startedAt: started, estimatedSecondsAtStart: 30 * 60, ticket: ticket)
        session.endedAt = started.addingTimeInterval(50 * 60)
        session.accumulatedActiveSeconds = 38 * 60
        session.budgetSecondsAtStart = 40 * 60
        session.outcome = .arrived
        model.insert(session)
        model.insert(
            SessionExtension(
                addedSeconds: 10 * 60,
                reason: "割り込みが入った",
                createdAt: started.addingTimeInterval(30 * 60),
                session: session
            )
        )

        let rides = EstimateHeuristic.arrivedRides(from: [session], matchingAnyTagIDs: nil)
        #expect(rides.count == 1)
        #expect(rides.first?.estimatedSeconds == 30 * 60)
        #expect(rides.first?.extensionAddedSeconds == 10 * 60)
        #expect(rides.first?.extensionReasons == ["割り込みが入った"])
        #expect(rides.first?.punctuality == .late)

        let context = ArrivalForecast.context(
            ticket: ticket,
            rides: rides,
            pooled: rides,
            medianMinutes: 38,
            now: started,
            calendar: calendar
        )
        #expect(context.lateCount == 1)
        #expect(context.extendedCount == 1)
        #expect(context.recent.first?.startedLabel == "火 10:15")
        #expect(ArrivalForecastPrompt.userPrompt(for: context).contains("延長+10分（割り込みが入った）"))
    }

    @Test func traceLog_newestFirstAndCapped() {
        let log = ArrivalForecastTraceLog()
        for index in 0..<15 {
            log.record(.skipped(title: "t\(index)"))
        }
        #expect(log.traces.count == ArrivalForecastTraceLog.limit)
        #expect(log.traces.first?.title == "t14")
        #expect(log.latest(matchingTitle: "t10")?.title == "t10")
        log.clear()
        #expect(log.traces.isEmpty)
    }

    @Test func appliedMinutes_shiftsWithCurrentMedian() {
        #expect(
            ArrivalForecast.appliedMinutes(resolved: nil, medianAtRun: 32, currentMedian: 36) == nil
        )
        #expect(
            ArrivalForecast.appliedMinutes(resolved: 40, medianAtRun: 32, currentMedian: 32) == 40
        )
        #expect(
            ArrivalForecast.appliedMinutes(resolved: 40, medianAtRun: 32, currentMedian: 36) == 44
        )
        #expect(
            ArrivalForecast.appliedMinutes(resolved: 20, medianAtRun: 32, currentMedian: 50) == 38
        )
    }

    @Test func fingerprint_tracksTitleTagsEstimateAndBandNotArrivals() {
        let base = sampleContext()
        var later = sampleContext()
        later.nowLabel = "日 16:59"
        later.hour = 16
        #expect(base.fingerprint == later.fingerprint)

        var evening = sampleContext()
        evening.band = .evening
        #expect(base.fingerprint != evening.fingerprint)

        var renamed = sampleContext()
        renamed.title = "別件"
        #expect(base.fingerprint != renamed.fingerprint)

        var retagged = sampleContext()
        retagged.tagNames = ["別"]
        #expect(base.fingerprint != retagged.fingerprint)

        var longer = sampleContext()
        longer.estimatedMinutes = 45
        #expect(base.fingerprint != longer.fingerprint)

        var more = sampleContext()
        more.sampleCount = 8
        more.medianMinutes = 40
        #expect(base.fingerprint == more.fingerprint)

        var newRide = sampleContext(recent: [
            ArrivalForecastContext.RideRecord(
                title: "資料",
                startedLabel: "日 15:00",
                estimatedMinutes: 20,
                actualMinutes: 28,
                budgetMinutes: 30,
                extensionMinutes: 10,
                extensionReasons: ["範囲が増えた"],
                punctuality: .late
            )
        ])
        #expect(base.fingerprint == newRide.fingerprint)
    }

    private func sampleContext(
        title: String = "レビュー",
        estimatedMinutes: Int = 30,
        medianMinutes: Int = 32,
        recent: [ArrivalForecastContext.RideRecord] = []
    ) -> ArrivalForecastContext {
        ArrivalForecastContext(
            title: title,
            tagNames: ["仕事"],
            estimatedMinutes: estimatedMinutes,
            nowLabel: "日 16:54",
            hour: 14,
            band: .afternoon,
            medianMinutes: medianMinutes,
            sampleCount: 5,
            bandSampleCount: 3,
            earlyCount: 2,
            onTimeCount: 1,
            lateCount: 2,
            extendedCount: 1,
            recent: recent
        )
    }
}
