import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Whole second")
struct WholeSecondTests {
    @Test func countdownCeilMatchesTimerText() {
        #expect(WholeSecond.countdownSeconds(0) == 0)
        #expect(WholeSecond.countdownSeconds(0.4) == 1)
        #expect(WholeSecond.countdownSeconds(0.5) == 1)
        #expect(WholeSecond.countdownSeconds(0.999) == 1)
        #expect(WholeSecond.countdownSeconds(59) == 59)
        #expect(WholeSecond.countdownSeconds(59.4) == 60)
        #expect(WholeSecond.countdownSeconds(60) == 60)
        #expect(WholeSecond.countdownSeconds(-0.4) == 0)
        #expect(WholeSecond.countdownSeconds(-1.4) == -1)
    }

    @Test func floorDropsTheFraction() {
        let fractional = Date(timeIntervalSince1970: 1_700_000_000.4)
        let whole = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(WholeSecond.floor(fractional) == whole)
        #expect(WholeSecond.floor(whole) == whole)
        #expect(WholeSecond.unix(fractional) == 1_700_000_000)
        #expect(WholeSecond.seconds(10.9) == 10)
        #expect(WholeSecond.floor(10.9) == 10)
    }

    @Test func scheduleFiresOnTheNextWholeSecond() {
        let date = Date(timeIntervalSince1970: 1_700_000_000.25)
        let start = WholeSecond.scheduleStart(date)
        #expect(start == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(start.addingTimeInterval(1) == Date(timeIntervalSince1970: 1_700_000_001))

        let nanos = WholeSecond.nanosecondsUntilNextBoundary(after: date)
        let wake = date.timeIntervalSince1970 + TimeInterval(nanos) / 1_000_000_000
        #expect(wake >= 1_700_000_001)
        #expect(wake < 1_700_000_001.002)

        let boundary = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(WholeSecond.nanosecondsUntilNextBoundary(after: boundary) == 1_000_000_000)
    }

    @Test func snapRemainingUsesTheSameCeiling() {
        let snap = SnapPlaintext(
            rev: 1,
            sessionId: nil,
            ticketId: nil,
            title: "週次",
            phase: .running,
            startedAt: 1_768_000_000,
            estimatedSeconds: 1_500,
            pausedAccumulated: 0,
            pausedAt: nil,
            boardedDeviceID: nil
        )
        #expect(snap.remainingSeconds(at: 1_768_000_120) == 1_380)
        #expect(snap.remainingSeconds(at: 1_768_000_120) == WholeSecond.countdownSeconds(1_380))
    }
}
